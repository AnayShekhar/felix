# Fix — Chrome Extension Google Sign-In (ID Token Flow)

## The problem

`chrome.identity.getAuthToken()` returns a Google **access token**, which is meant
for calling Google APIs (Gmail, Calendar, etc.) on the user's behalf. It is NOT a
signed identity credential.

The backend's `/auth/google` endpoint expects an **ID token** — a signed JWT that
proves who the user is, which is what `google-auth`'s `verify_oauth2_token` (used
in `_verify_google`) is built to validate. An access token will fail that
verification because it's not even a JWT — it's an opaque bearer string.

## The fix

Replace `chrome.identity.getAuthToken()` with `chrome.identity.launchWebAuthFlow()`,
manually building the Google OAuth URL to request an `id_token` via the implicit
flow. This gives us the actual JWT the backend already knows how to verify.

---

## Step 1 — Google Cloud Console setup

Go to Google Cloud Console → APIs & Services → Credentials.

You need a **Web application** OAuth Client ID (NOT "Chrome Extension" type this
time) because `launchWebAuthFlow` uses a standard web redirect flow.

1. Create Credentials → OAuth Client ID → Application type: **Web application**
2. Under "Authorized redirect URIs" add:
   ```
   https://<YOUR_EXTENSION_ID>.chromiumapp.org/
   ```
   You get `YOUR_EXTENSION_ID` from `chrome://extensions` after loading the
   unpacked extension once (it's a random string like `abcdefghijklmnopabcdefghijklmnop`).
3. Copy the generated **Client ID** — you'll paste it into `background.js` below.

This is a different Client ID than any "Chrome Extension" type credential — do not
reuse the iOS/backend Web Client ID either; create a fresh one scoped to this
extension's redirect URI, since the redirect URI must match exactly.

---

## Step 2 — Remove the old OAuth block from manifest.json

Delete this section entirely if present:
```json
"oauth2": {
  "client_id": "...",
  "scopes": ["openid", "email", "profile"]
}
```

It's not used by `launchWebAuthFlow` — that flow builds the URL manually instead
of relying on the manifest's `oauth2` key.

Ensure `"identity"` remains in the `permissions` array in `manifest.json` — it's
still required for `launchWebAuthFlow`.

---

## Step 3 — Replace the Google login function in background.js

Replace the existing `loginWithGoogle()` function entirely with:

```javascript
// background.js

const GOOGLE_CLIENT_ID = "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"; // paste from Step 1

function buildGoogleAuthUrl(redirectUri) {
  const params = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    response_type: "id_token",
    redirect_uri: redirectUri,
    scope: "openid email profile",
    nonce: crypto.randomUUID(),
    prompt: "select_account"
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

async function loginWithGoogle() {
  const redirectUri = chrome.identity.getRedirectURL(); // https://<ext-id>.chromiumapp.org/
  const authUrl = buildGoogleAuthUrl(redirectUri);

  const responseUrl = await new Promise((resolve, reject) => {
    chrome.identity.launchWebAuthFlow(
      { url: authUrl, interactive: true },
      (redirectedTo) => {
        if (chrome.runtime.lastError || !redirectedTo) {
          reject(new Error(chrome.runtime.lastError?.message || "Google sign-in was cancelled"));
          return;
        }
        resolve(redirectedTo);
      }
    );
  });

  // Google returns the token in the URL fragment, e.g.:
  // https://<ext-id>.chromiumapp.org/#id_token=eyJ...&...
  const fragment = new URL(responseUrl).hash.substring(1);
  const fragmentParams = new URLSearchParams(fragment);
  const idToken = fragmentParams.get("id_token");

  if (!idToken) {
    throw new Error("Google did not return an ID token");
  }

  const res = await fetch(`${API_BASE}/auth/google`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken })
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Google sign-in failed: ${errText}`);
  }

  const data = await res.json();
  await chrome.storage.local.set({
    lumis_token: data.token,
    lumis_user: data.user
  });
  return data.user;
}
```

Everything else in `background.js` (the message listener, `loginWithEmail`,
`syncServiceCookies`, etc.) stays exactly as-is — only `loginWithGoogle()` changes.

---

## Step 4 — No changes needed to popup.js or popup.html

The `LOGIN_GOOGLE` message type and the "Sign in with Google" button already call
`sendMessage("LOGIN_GOOGLE")`, which triggers `loginWithGoogle()` in the background
script. Since the function signature and return shape (`{ success, user }` or
`{ success: false, error }`) are unchanged, the popup code needs no modification.

---

## Step 5 — Re-load and test

1. Go to `chrome://extensions`, click the refresh icon on the Lumis extension card
2. Note the extension ID shown on the card — confirm it matches what you registered
   in Google Cloud Console's redirect URI in Step 1 (if you loaded a fresh unpacked
   copy, the ID may have changed — extension IDs from unpacked loads can be
   inconsistent across machines/reloads unless you pin it with a `key` field in
   `manifest.json`; see note below if this happens)
3. Open the popup, click "Sign in with Google"
4. A Google account picker should appear in a popup window
5. After choosing an account, the window closes automatically and the popup should
   show the connected/signed-in view

### Note on stable extension ID during development

If the extension ID changes every time you reload unpacked (common), your redirect
URI in Google Cloud Console will stop matching. To fix this, generate a stable ID:

1. Pack the extension once (`chrome://extensions` → "Pack extension") to generate
   a `.pem` key file
2. Extract the public key and add a `"key"` field to `manifest.json` with that value
3. This pins the extension ID permanently for unpacked loads too, so the redirect
   URI stays valid across reloads

This is optional for pure local testing (you can just re-copy the new ID into
Google Cloud Console each time it changes) but recommended if you're testing
Google sign-in repeatedly during development.

---

## Verification

- [ ] `manifest.json` no longer has an `oauth2` block
- [ ] `GOOGLE_CLIENT_ID` in `background.js` is a **Web application** type Client ID, not Chrome Extension type
- [ ] Google Cloud Console redirect URI exactly matches `chrome.identity.getRedirectURL()` output
- [ ] Clicking "Sign in with Google" opens a real Google account picker
- [ ] After choosing an account, the extension shows the signed-in state
- [ ] Signing in with Google in the extension using the same Google account as the
      iPhone app lands on the same Lumis account (same connected services list appears)
- [ ] Backend logs show a successful `/auth/google` call, not a token verification error