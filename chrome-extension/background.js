// background.js — Lumis Chrome extension service worker.
// Handles auth (email + Google), reading cookies for chosen services, and
// syncing them to the user's Lumis account on the backend. Reuses the same
// /auth/* endpoints the iPhone app uses — no new auth logic.

const API_BASE = "https://lumis-production-b878.up.railway.app";

// Web application OAuth Client ID (not "Chrome Extension" type). Used by the
// launchWebAuthFlow id_token flow below so the backend's /auth/google can verify
// a real signed JWT. Its authorized redirect URI must be
// chrome.identity.getRedirectURL() → https://<ext-id>.chromiumapp.org/
const GOOGLE_CLIENT_ID = "955535830862-sg3mge88iqmk3q835i83hpqod0db25mn.apps.googleusercontent.com";

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

async function getStoredAuth() {
  const { lumis_token, lumis_user } = await chrome.storage.local.get(["lumis_token", "lumis_user"]);
  return { token: lumis_token, user: lumis_user };
}

async function logout() {
  await chrome.storage.local.remove(["lumis_token", "lumis_user"]);
}

// ── Service connection status ────────────────────────────────────────────

async function fetchConnectStatus() {
  // `ok:false` means "couldn't check", which the popup shows honestly —
  // a failed request must never be reported as "nothing connected".
  const { token } = await getStoredAuth();
  if (!token) {
    return { ok: true, connected: [], services: [], ever_synced: false, last_synced_at: null };
  }
  try {
    const res = await fetch(`${API_BASE}/connect/status`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (!res.ok) return { ok: false };
    const data = await res.json();
    return {
      ok: true,
      connected: data.connected || [],
      services: data.services || [],
      ever_synced: data.ever_synced ?? (data.connected || []).length > 0,
      last_synced_at: data.last_synced_at ?? null,
      google_api: data.google_api ?? false,
    };
  } catch {
    return { ok: false };
  }
}

// Start the Google OAuth consent flow (the credential Gmail/Sheets/Calendar
// tools actually run on — separate from cookie sync). Opens Google's consent
// page in a new tab; the backend's callback stores the tokens.
async function connectGoogleAPI() {
  const { token } = await getStoredAuth();
  if (!token) throw new Error("Not signed into Lumis");
  const res = await fetch(`${API_BASE}/connect/google/start`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` }
  });
  if (!res.ok) throw new Error(await errorDetail(res, "Couldn't start Google connect"));
  const { url } = await res.json();
  await chrome.tabs.create({ url });
  return true;
}

// Pull the backend's specific error detail out of a failed response so the
// user sees "Those cookies don't look like…" instead of a generic message.
async function errorDetail(res, fallback) {
  try {
    const body = await res.json();
    if (body && body.detail) return String(body.detail);
  } catch (_) { /* not JSON */ }
  return fallback;
}

// ── Cookie sync ───────────────────────────────────────────────────────────

// The domain whose cookies actually carry the service's login session.
// IMPORTANT: chrome.cookies.getAll({domain}) matches that domain and its
// SUBDOMAINS only — passing "mail.google.com" would miss the real Google
// session cookies (SID, HSID, SAPISID, …), which are set on ".google.com".
// Always use the registrable domain here.
const SERVICE_DOMAINS = {
  gmail:     "google.com",
  sheets:    "google.com",
  spotify:   "spotify.com",
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

  if (!res.ok) throw new Error(await errorDetail(res, "Failed to sync — try again"));
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

  if (!res.ok) throw new Error(await errorDetail(res, "Failed to sync — try again"));
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
        case "GET_CONNECTED_SERVICES": {
          const status = await fetchConnectStatus();
          sendResponse({ success: true, services: status.connected || [], status });
          break;
        }
        case "CONNECT_GOOGLE_API":
          sendResponse({ success: true, opened: await connectGoogleAPI() });
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
