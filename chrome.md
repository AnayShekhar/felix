# Lumis Chrome Extension — Build Prompt

A lightweight Chrome extension whose only job is: let the user sign into their
existing Lumis account, then sync their logged-in sessions (cookies) for chosen
services into their Browserbase cloud browser context on Railway. No automation,
no content scripts controlling pages, no visible backend — just auth + cookie sync.

This is a companion to the cloud browser architecture already built. Do not
duplicate auth logic — reuse the existing `/auth/*` endpoints exactly as the
iPhone app uses them.

---

## Part 1 — Project structure

Create a new top-level folder: `chrome-extension/`

```
chrome-extension/
├── manifest.json
├── background.js
├── popup.html
├── popup.js
├── popup.css
├── icons/
│   ├── icon16.png
│   ├── icon48.png
│   └── icon128.png
└── README.md
```

Use the existing Lumis petal icon (from the iOS app assets) exported at the three
required sizes for `icons/`.

---

## Part 2 — manifest.json

```json
{
  "manifest_version": 3,
  "name": "Lumis",
  "version": "1.0.0",
  "description": "Connect your accounts to Lumis so it can act on your behalf.",
  "icons": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  },
  "action": {
    "default_popup": "popup.html",
    "default_icon": {
      "16": "icons/icon16.png",
      "48": "icons/icon48.png",
      "128": "icons/icon128.png"
    }
  },
  "background": {
    "service_worker": "background.js"
  },
  "permissions": [
    "cookies",
    "storage",
    "tabs",
    "identity"
  ],
  "host_permissions": [
    "https://*/*"
  ],
  "oauth2": {
    "client_id": "YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com",
    "scopes": ["openid", "email", "profile"]
  }
}
```

Note: `host_permissions: ["https://*/*"]` is required to read cookies from any
domain the user chooses to connect. Chrome will show this as a permission request
on install — this is expected and necessary.

---

## Part 3 — background.js

Handles: token storage, cookie reading, sending synced cookies to Railway, Google
OAuth flow via `chrome.identity`.

```javascript
// background.js

const API_BASE = "https://lumis-production-b878.up.railway.app";

// ── Auth ──────────────────────────────────────────────────────────────────

async function loginWithEmail(email, password) {
  const res = await fetch(`${API_BASE}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password })
  });
  if (!res.ok) throw new Error("Invalid email or password");
  const data = await res.json();
  await chrome.storage.local.set({
    lumis_token: data.token,
    lumis_user: data.user
  });
  return data.user;
}

async function loginWithGoogle() {
  return new Promise((resolve, reject) => {
    chrome.identity.getAuthToken({ interactive: true }, async (googleToken) => {
      if (chrome.runtime.lastError || !googleToken) {
        reject(new Error("Google sign-in failed"));
        return;
      }
      try {
        const res = await fetch(`${API_BASE}/auth/google`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ idToken: googleToken })
        });
        if (!res.ok) throw new Error("Google sign-in failed");
        const data = await res.json();
        await chrome.storage.local.set({
          lumis_token: data.token,
          lumis_user: data.user
        });
        resolve(data.user);
      } catch (err) {
        reject(err);
      }
    });
  });
}

async function getStoredAuth() {
  const { lumis_token, lumis_user } = await chrome.storage.local.get(["lumis_token", "lumis_user"]);
  return { token: lumis_token, user: lumis_user };
}

async function logout() {
  await chrome.storage.local.remove(["lumis_token", "lumis_user"]);
}

// ── Service connection status ────────────────────────────────────────────

async function fetchConnectedServices() {
  const { token } = await getStoredAuth();
  if (!token) return [];
  const res = await fetch(`${API_BASE}/connect/status`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  if (!res.ok) return [];
  const data = await res.json();
  return data.connected || [];
}

// ── Cookie sync ───────────────────────────────────────────────────────────

const SERVICE_DOMAINS = {
  gmail:     "mail.google.com",
  sheets:    "docs.google.com",
  notion:    "notion.so",
  linkedin:  "linkedin.com",
  slack:     "slack.com",
  airtable:  "airtable.com",
  twitter:   "twitter.com",
  reddit:    "reddit.com",
  github:    "github.com",
};

async function syncServiceCookies(serviceName) {
  const domain = SERVICE_DOMAINS[serviceName];
  if (!domain) throw new Error(`Unknown service: ${serviceName}`);

  const cookies = await chrome.cookies.getAll({ domain });
  if (cookies.length === 0) {
    throw new Error(`Not logged into ${serviceName} in this browser. Open ${domain} and log in first.`);
  }

  const { token } = await getStoredAuth();
  if (!token) throw new Error("Not signed into Lumis");

  const res = await fetch(`${API_BASE}/connect/cookies/sync`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({
      service: serviceName,
      domain: domain,
      cookies: cookies.map(c => ({
        name: c.name,
        value: c.value,
        domain: c.domain,
        path: c.path,
        secure: c.secure,
        httpOnly: c.httpOnly,
        sameSite: c.sameSite,
        expirationDate: c.expirationDate
      }))
    })
  });

  if (!res.ok) throw new Error("Failed to sync — try again");
  return await res.json();
}

async function syncCurrentTabCookies() {
  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!activeTab?.url) throw new Error("No active tab");

  const url = new URL(activeTab.url);
  const domain = url.hostname;

  const cookies = await chrome.cookies.getAll({ domain });
  if (cookies.length === 0) {
    throw new Error("No cookies found for this site. Make sure you're logged in.");
  }

  const { token } = await getStoredAuth();
  if (!token) throw new Error("Not signed into Lumis");

  const res = await fetch(`${API_BASE}/connect/cookies/sync`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({
      service: domain,          // use the raw domain as the service identifier
      domain: domain,
      cookies: cookies.map(c => ({
        name: c.name, value: c.value, domain: c.domain, path: c.path,
        secure: c.secure, httpOnly: c.httpOnly, sameSite: c.sameSite,
        expirationDate: c.expirationDate
      }))
    })
  });

  if (!res.ok) throw new Error("Failed to sync — try again");
  return { domain, result: await res.json() };
}

// ── Message handling from popup.js ───────────────────────────────────────

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    try {
      switch (message.type) {
        case "LOGIN_EMAIL":
          sendResponse({ success: true, user: await loginWithEmail(message.email, message.password) });
          break;
        case "LOGIN_GOOGLE":
          sendResponse({ success: true, user: await loginWithGoogle() });
          break;
        case "LOGOUT":
          await logout();
          sendResponse({ success: true });
          break;
        case "GET_AUTH":
          sendResponse({ success: true, ...(await getStoredAuth()) });
          break;
        case "GET_CONNECTED_SERVICES":
          sendResponse({ success: true, services: await fetchConnectedServices() });
          break;
        case "SYNC_SERVICE":
          sendResponse({ success: true, result: await syncServiceCookies(message.service) });
          break;
        case "SYNC_CURRENT_TAB":
          sendResponse({ success: true, ...(await syncCurrentTabCookies()) });
          break;
        default:
          sendResponse({ success: false, error: "Unknown message type" });
      }
    } catch (err) {
      sendResponse({ success: false, error: err.message });
    }
  })();
  return true; // keep message channel open for async response
});
```

---

## Part 4 — popup.html

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <link rel="stylesheet" href="popup.css">
</head>
<body>
  <div id="app">

    <!-- Logged out state -->
    <div id="login-view" class="view">
      <div class="header">
        <div class="logo-mark"></div>
        <h1>Lumis</h1>
      </div>
      <p class="subtitle">Sign in to connect your accounts to Lumis on your phone.</p>

      <form id="email-form">
        <input type="email" id="email-input" placeholder="Email" required />
        <input type="password" id="password-input" placeholder="Password" required />
        <button type="submit" class="btn-primary">Sign In</button>
      </form>

      <div class="divider"><span>or</span></div>

      <button id="google-signin-btn" class="btn-outline">
        <img src="icons/google-logo.svg" width="16" height="16" />
        Sign in with Google
      </button>

      <p id="login-error" class="error-text"></p>
    </div>

    <!-- Logged in state -->
    <div id="connected-view" class="view hidden">
      <div class="header-row">
        <div class="header">
          <div class="logo-mark small"></div>
          <span class="app-name">Lumis</span>
        </div>
        <button id="logout-btn" class="btn-text">Sign Out</button>
      </div>
      <p id="user-email" class="user-email"></p>

      <div class="section">
        <p class="section-label">Connect your accounts</p>
        <div id="services-list"></div>
      </div>

      <div class="section current-site-section">
        <p class="section-label">Current site</p>
        <div class="current-site-row">
          <span id="current-site-name">—</span>
          <button id="sync-current-tab-btn" class="btn-small">Connect current site</button>
        </div>
      </div>

      <p id="sync-status" class="sync-status"></p>
    </div>

  </div>
  <script src="popup.js"></script>
</body>
</html>
```

---

## Part 5 — popup.js

```javascript
// popup.js

const SUPPORTED_SERVICES = [
  { id: "gmail",    name: "Gmail" },
  { id: "sheets",   name: "Google Sheets" },
  { id: "notion",   name: "Notion" },
  { id: "linkedin", name: "LinkedIn" },
  { id: "slack",    name: "Slack" },
  { id: "airtable", name: "Airtable" },
];

function sendMessage(type, payload = {}) {
  return chrome.runtime.sendMessage({ type, ...payload });
}

async function init() {
  const auth = await sendMessage("GET_AUTH");
  if (auth.token) {
    showConnectedView(auth.user);
  } else {
    showLoginView();
  }
}

function showLoginView() {
  document.getElementById("login-view").classList.remove("hidden");
  document.getElementById("connected-view").classList.add("hidden");
}

async function showConnectedView(user) {
  document.getElementById("login-view").classList.add("hidden");
  document.getElementById("connected-view").classList.remove("hidden");
  document.getElementById("user-email").textContent = user.email;

  await renderServicesList();
  await renderCurrentSite();
}

async function renderServicesList() {
  const { services: connected } = await sendMessage("GET_CONNECTED_SERVICES");
  const container = document.getElementById("services-list");
  container.innerHTML = "";

  SUPPORTED_SERVICES.forEach(service => {
    const isConnected = connected.includes(service.id);
    const row = document.createElement("div");
    row.className = "service-row";
    row.innerHTML = `
      <span class="service-name">${service.name}</span>
      ${isConnected
        ? `<span class="connected-badge">✓ Connected</span>`
        : `<button class="btn-small connect-btn" data-service="${service.id}">Connect</button>`}
    `;
    container.appendChild(row);
  });

  container.querySelectorAll(".connect-btn").forEach(btn => {
    btn.addEventListener("click", async () => {
      const serviceId = btn.dataset.service;
      btn.textContent = "Connecting…";
      btn.disabled = true;
      const result = await sendMessage("SYNC_SERVICE", { service: serviceId });
      if (result.success) {
        await renderServicesList();
      } else {
        showSyncStatus(result.error, true);
        btn.textContent = "Connect";
        btn.disabled = false;
      }
    });
  });
}

async function renderCurrentSite() {
  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const domain = activeTab?.url ? new URL(activeTab.url).hostname : "—";
  document.getElementById("current-site-name").textContent = domain;
}

function showSyncStatus(message, isError = false) {
  const el = document.getElementById("sync-status");
  el.textContent = message;
  el.className = isError ? "sync-status error" : "sync-status success";
  setTimeout(() => { el.textContent = ""; el.className = "sync-status"; }, 4000);
}

// ── Event listeners ─────────────────────────────────────────────────────

document.getElementById("email-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const email = document.getElementById("email-input").value;
  const password = document.getElementById("password-input").value;
  const errorEl = document.getElementById("login-error");
  errorEl.textContent = "";

  const result = await sendMessage("LOGIN_EMAIL", { email, password });
  if (result.success) {
    showConnectedView(result.user);
  } else {
    errorEl.textContent = result.error || "Sign in failed";
  }
});

document.getElementById("google-signin-btn").addEventListener("click", async () => {
  const result = await sendMessage("LOGIN_GOOGLE");
  if (result.success) {
    showConnectedView(result.user);
  } else {
    document.getElementById("login-error").textContent = result.error || "Google sign-in failed";
  }
});

document.getElementById("logout-btn").addEventListener("click", async () => {
  await sendMessage("LOGOUT");
  showLoginView();
});

document.getElementById("sync-current-tab-btn").addEventListener("click", async (e) => {
  e.target.textContent = "Connecting…";
  e.target.disabled = true;
  const result = await sendMessage("SYNC_CURRENT_TAB");
  if (result.success) {
    showSyncStatus(`Connected ${result.domain}`);
  } else {
    showSyncStatus(result.error, true);
  }
  e.target.textContent = "Connect current site";
  e.target.disabled = false;
});

init();
```

---

## Part 6 — popup.css

```css
body {
  width: 320px;
  margin: 0;
  font-family: -apple-system, "SF Pro Text", sans-serif;
  background: #F8F3EE;
  color: #212222;
}

.view { padding: 20px; }
.hidden { display: none !important; }

.header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}

.logo-mark {
  width: 28px;
  height: 28px;
  background: #B0BFD1;
  border-radius: 50%;
  /* replace with actual Lumis petal SVG mask */
}
.logo-mark.small { width: 20px; height: 20px; }

h1 { font-size: 20px; font-weight: 600; margin: 0; }
.app-name { font-size: 15px; font-weight: 600; }

.subtitle {
  font-size: 13px;
  color: #21222299;
  margin: 8px 0 20px 0;
  line-height: 1.4;
}

form { display: flex; flex-direction: column; gap: 10px; }

input {
  height: 40px;
  border: 1px solid #21222215;
  border-radius: 10px;
  padding: 0 12px;
  font-size: 14px;
  background: white;
  outline: none;
}
input:focus { border-color: #B0BFD1; }

.btn-primary {
  height: 42px;
  background: #212222;
  color: #F8F3EE;
  border: none;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  margin-top: 4px;
}
.btn-primary:hover { opacity: 0.9; }

.btn-outline {
  height: 42px;
  background: white;
  color: #212222;
  border: 1px solid #21222220;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
}

.divider {
  text-align: center;
  margin: 16px 0;
  position: relative;
  color: #21222260;
  font-size: 12px;
}
.divider::before, .divider::after {
  content: "";
  position: absolute;
  top: 50%;
  width: 40%;
  height: 1px;
  background: #21222215;
}
.divider::before { left: 0; }
.divider::after { right: 0; }

.error-text {
  color: #E05252;
  font-size: 12px;
  margin-top: 8px;
  min-height: 16px;
}

.header-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 4px;
}

.btn-text {
  background: none;
  border: none;
  color: #21222299;
  font-size: 12px;
  cursor: pointer;
}

.user-email {
  font-size: 12px;
  color: #21222260;
  margin: 0 0 20px 0;
}

.section { margin-bottom: 20px; }

.section-label {
  font-size: 11px;
  font-weight: 600;
  color: #21222260;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 10px;
}

.service-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  height: 40px;
  border-bottom: 1px solid #21222210;
}
.service-row:last-child { border-bottom: none; }

.service-name { font-size: 14px; }

.connected-badge {
  font-size: 12px;
  color: #4CAF7D;
  font-weight: 500;
}

.btn-small {
  height: 28px;
  padding: 0 12px;
  background: #B0BFD1;
  color: white;
  border: none;
  border-radius: 14px;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}
.btn-small:disabled { opacity: 0.5; cursor: default; }

.current-site-section {
  background: white;
  border-radius: 10px;
  padding: 12px;
  border: 1px solid #21222210;
}

.current-site-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

#current-site-name {
  font-size: 13px;
  font-weight: 500;
  color: #212222;
}

.sync-status {
  font-size: 12px;
  text-align: center;
  min-height: 16px;
  margin-top: 8px;
}
.sync-status.success { color: #4CAF7D; }
.sync-status.error { color: #E05252; }
```

---

## Part 7 — Backend endpoint to receive synced cookies

Add to `backend/routes.py`:

```python
@app.post("/connect/cookies/sync")
async def sync_cookies(request: CookieSyncRequest, user=Depends(get_current_user)):
    """
    Receives cookies captured by the Chrome extension and injects them
    into the user's persistent Browserbase context.
    """
    from cloud_browser import get_or_create_user_context, inject_cookies_into_context

    context_id = await get_or_create_user_context(user.id)
    await inject_cookies_into_context(context_id, request.cookies)

    add_connected_service(user.id, request.service)

    return {"success": True, "service": request.service}
```

Add to `backend/cloud_browser.py`:

```python
async def inject_cookies_into_context(context_id: str, cookies: list[dict]):
    """
    Opens a temporary session on the user's persistent context and adds
    the given cookies to it, then closes — the context (with cookies) persists
    for all future sessions.
    """
    session = bb.sessions.create(
        project_id=PROJECT_ID,
        browser_settings={"context": {"id": context_id, "persist": True}}
    )
    playwright = await async_playwright().start()
    browser = await playwright.chromium.connect_over_cdp(session.connect_url)
    context = browser.contexts[0] if browser.contexts else await browser.new_context()

    playwright_cookies = [
        {
            "name": c["name"],
            "value": c["value"],
            "domain": c["domain"],
            "path": c["path"],
            "secure": c.get("secure", True),
            "httpOnly": c.get("httpOnly", False),
            "sameSite": c.get("sameSite", "Lax").capitalize()
                if c.get("sameSite") in ["lax", "strict", "none"] else "Lax",
            "expires": c.get("expirationDate", -1)
        }
        for c in cookies
    ]
    await context.add_cookies(playwright_cookies)
    await bb.sessions.update(session.id, status="REQUEST_RELEASE")
```

Add request model to `backend/routes.py` or a shared schema file:

```python
class CookieSyncRequest(BaseModel):
    service: str
    domain: str
    cookies: list[dict]
```

Add `GET /connect/status` if not already present from the earlier cloud browser doc:

```python
@app.get("/connect/status")
async def connection_status(user=Depends(get_current_user)):
    return {"connected": get_connected_services(user.id)}
```

---

## Part 8 — Google OAuth Client ID for the extension

The `chrome.identity.getAuthToken` flow requires a Google OAuth Client ID
registered as a **Chrome App** type in Google Cloud Console (different from the
Web application type used for the iOS/backend Google Sign-In).

Steps:
1. Google Cloud Console → Credentials → Create Credentials → OAuth Client ID
2. Application type: **Chrome Extension**
3. Item ID: the extension's ID (visible in `chrome://extensions` after loading unpacked)
4. Copy the generated Client ID into `manifest.json`'s `oauth2.client_id`

---

## Part 9 — Installing for testing (unpacked, one week timeline)

No Chrome Web Store submission needed for now:

1. Open `chrome://extensions`
2. Enable "Developer mode" (top right toggle)
3. Click "Load unpacked"
4. Select the `chrome-extension/` folder
5. Extension icon appears in the toolbar — pin it for easy access

Document this in `chrome-extension/README.md` so it's easy to reinstall after
code changes (click the refresh icon on the extension card in `chrome://extensions`
after editing any file).

---

## Part 10 — Verification

- [ ] Extension loads without errors in `chrome://extensions`
- [ ] Popup shows login view when signed out
- [ ] Email/password login works — same credentials as the iPhone app log into
      the same account
- [ ] Google sign-in works and matches the same account if the user originally
      signed up with Google on the phone
- [ ] After login, services list renders with correct connected/not-connected state
- [ ] Clicking "Connect" on a service with existing browser cookies succeeds and
      updates the account's connected services in the database
- [ ] Clicking "Connect" on a service with NO existing cookies shows a clear
      error telling the user to log in first
- [ ] "Connect current site" correctly detects the active tab's domain and syncs
      its cookies under that domain name
- [ ] Cookies synced from the extension are usable by Browserbase — verify by
      running an agent command that uses that service and confirming it doesn't
      need to log in again
- [ ] Logout clears local storage and returns to the login view
- [ ] No Railway URL, backend terminology, or technical jargon is ever shown to
      the user in the popup UI