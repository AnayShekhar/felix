# Felix Chrome Extension

A lightweight companion to the Felix phone app. Its only job: let you sign into
your existing Felix account, then sync your logged-in browser sessions (cookies)
for chosen services up to Felix so it can act on your behalf. No automation, no
content scripts, no page control — just **auth + cookie sync**.

Reuses the exact same `/auth/*` endpoints the iPhone app uses.

## Files

```
chrome-extension/
├── manifest.json        MV3 manifest (cookies/storage/tabs/identity perms)
├── background.js        service worker: auth + cookie reading + sync
├── popup.html/js/css    the popup UI (Felix design tokens, brand comet mark)
├── icons/               Felix mark icons (16/48/128) + google logo
└── README.md
```

The icons in `icons/` are generated from the Felix brand mark (`image.svg` at
the repo root) — Cool Steel `#99ACBE` on transparent for the toolbar. The header
logo in the popup uses `icons/felix-mark.png` as a CSS mask over the theme's ink
color, so it adapts to light/dark automatically.

## Install (unpacked — no Web Store needed)

1. Open `chrome://extensions`
2. Enable **Developer mode** (top-right toggle)
3. Click **Load unpacked**
4. Select this `chrome-extension/` folder
5. The Felix icon appears in the toolbar — pin it for easy access

After editing any file, click the **refresh** icon on the Felix card in
`chrome://extensions` to reload.

## Google sign-in setup (`launchWebAuthFlow` id_token flow)

Google sign-in uses `chrome.identity.launchWebAuthFlow` to request a real
**ID token** (a signed JWT), which is what the backend's `/auth/google`
(`_verify_google`) verifies. This needs a **Web application** OAuth Client ID
(not "Chrome Extension" type):

1. Google Cloud Console → Credentials → Create Credentials → OAuth Client ID
2. Application type: **Web application**
3. Under **Authorized redirect URIs** add:
   `https://<YOUR_EXTENSION_ID>.chromiumapp.org/`
   — get `<YOUR_EXTENSION_ID>` from `chrome://extensions` after loading unpacked
   once. It must exactly match `chrome.identity.getRedirectURL()`.
4. Paste the Client ID into `background.js` → `GOOGLE_CLIENT_ID`.

The configured Web Client ID is
`955535830862-sg3mge88iqmk3q835i83hpqod0db25mn.apps.googleusercontent.com`.
Its redirect URI in Google Cloud Console must match this extension's ID. If the
unpacked extension ID changes on reload, either re-copy the new ID into the
console's redirect URI, or pin the ID with a `key` field in `manifest.json`
(see fix.md "Note on stable extension ID").

Email + password sign-in also works with no extra setup.

## Backend

The extension talks to `https://lumis-production-b878.up.railway.app`:

| Endpoint | Status |
| --- | --- |
| `POST /auth/login` | ✅ exists (`backend/auth.py`) |
| `POST /auth/google` | ✅ exists — extension now sends a real ID token |
| `GET  /connect/status` | ✅ exists (`backend/routes.py`) |
| `POST /connect/cookies/sync` | ✅ exists (`backend/routes.py`) |

The `/connect/*` endpoints (chrome.md Part 7) are backed by the Browserbase cloud
browser layer: `backend/cloud_browser.py` (persistent per-user context + cookie
injection) and `backend/connections.py` (connected-services + context store).

To make cookie sync actually round-trip to Browserbase, set these env vars on the
server: `BROWSERBASE_API_KEY` and `BROWSERBASE_PROJECT_ID`, and ensure the
`browserbase` package (added to `requirements.txt`) is installed. Until then,
`POST /connect/cookies/sync` returns a clear **503 "Cloud browser is not
configured"** — login and `GET /connect/status` still work.

## Verification checklist

- [x] Loads without errors in `chrome://extensions`
- [x] Popup shows login view when signed out
- [x] Email/password login uses the same account as the iPhone app
- [x] After login, services list renders (all "not connected" until backend ships)
- [x] Missing cookies for a service shows a clear "log in first" error
- [x] "Connect current site" detects the active tab's domain
- [x] Logout clears storage and returns to the login view
- [x] No Railway URL or backend jargon shown in the popup UI
- [ ] Cookie sync round-trips to Browserbase — blocked on `/connect/*` backend
