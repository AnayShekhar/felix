// popup.js — UI logic for the Lumis extension popup. All network/auth work is
// delegated to background.js via chrome.runtime messaging.

const SUPPORTED_SERVICES = [
  { id: "gmail",    name: "Gmail" },
  { id: "sheets",   name: "Google Sheets" },
  { id: "notion",   name: "Notion" },
  { id: "linkedin", name: "LinkedIn" },
  { id: "slack",    name: "Slack" },
  { id: "airtable", name: "Airtable" },
];

// Inline vector icons (no emoji anywhere in this UI).
const ICONS = {
  check: `<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <circle cx="8" cy="8" r="7" fill="currentColor" opacity="0.15"/>
    <path d="M4.8 8.2l2.1 2.1 4.3-4.6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`,
  checkFilled: `<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <circle cx="10" cy="10" r="9" fill="currentColor"/>
    <path d="M6.2 10.3l2.5 2.5 5.1-5.6" stroke="var(--background)" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`,
  clock: `<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <circle cx="10" cy="10" r="8" stroke="currentColor" stroke-width="1.6"/>
    <path d="M10 5.5V10l3 2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`,
  dashedCircle: `<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <circle cx="10" cy="10" r="8" stroke="currentColor" stroke-width="1.6" stroke-dasharray="3 3"/>
  </svg>`,
};

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

// ── Sync status banner (mirrors the iOS tri-state + wording) ──────────────

const STALE_AFTER_MS = 24 * 60 * 60 * 1000;

function relativeTime(tsSeconds) {
  const diff = Date.now() - tsSeconds * 1000;
  const mins = Math.round(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} minute${mins === 1 ? "" : "s"} ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

function renderSyncBanner(status) {
  const icon = document.getElementById("sync-banner-icon");
  const title = document.getElementById("sync-banner-title");
  const detail = document.getElementById("sync-banner-detail");

  const everSynced = status.ever_synced && status.last_synced_at;
  if (!everSynced) {
    icon.innerHTML = ICONS.dashedCircle;
    icon.className = "status-icon status-never";
    title.textContent = "Extension not connected";
    detail.textContent = "Connect an account below so Lumis on your phone can use it.";
    return;
  }
  const fresh = Date.now() - status.last_synced_at * 1000 < STALE_AFTER_MS;
  if (fresh) {
    icon.innerHTML = ICONS.checkFilled;
    icon.className = "status-icon status-recent";
    title.textContent = "Extension connected";
    detail.textContent = `Last synced ${relativeTime(status.last_synced_at)}.`;
  } else {
    icon.innerHTML = ICONS.clock;
    icon.className = "status-icon status-stale";
    title.textContent = "Extension needs a refresh";
    detail.textContent =
      `Last synced ${relativeTime(status.last_synced_at)}. ` +
      "Re-connect your accounts below so your sessions stay fresh.";
  }
}

// ── Services list ──────────────────────────────────────────────────────────

async function renderServicesList() {
  const res = await sendMessage("GET_CONNECTED_SERVICES");
  const connected = res.services || [];
  const status = res.status || { ever_synced: connected.length > 0, last_synced_at: null };
  renderSyncBanner(status);

  const container = document.getElementById("services-list");
  container.innerHTML = "";

  // Google APIs row — the OAuth grant that Gmail/Sheets/Calendar tools run on.
  // Distinct from the cookie rows below: cookies sign the cloud browser in,
  // this signs the Google REST API layer in.
  const googleRow = document.createElement("div");
  googleRow.className = "service-row";
  googleRow.innerHTML = `
    <span class="service-name">Google account<br>
      <small style="opacity:.6">Gmail, Sheets, Calendar, Docs, Drive</small></span>
    ${status.google_api
      ? `<span class="connected-badge">${ICONS.check} Connected</span>`
      : `<button class="btn-small" id="connect-google-api-btn">Connect</button>`}
  `;
  container.appendChild(googleRow);
  const gBtn = googleRow.querySelector("#connect-google-api-btn");
  if (gBtn) {
    gBtn.addEventListener("click", async () => {
      gBtn.textContent = "Opening…";
      gBtn.disabled = true;
      const result = await sendMessage("CONNECT_GOOGLE_API");
      if (!result.success) {
        showSyncStatus(result.error, true);
        gBtn.textContent = "Connect";
        gBtn.disabled = false;
      } else {
        showSyncStatus("Finish signing in on the Google tab, then reopen this popup.");
      }
    });
  }

  SUPPORTED_SERVICES.forEach(service => {
    const isConnected = connected.includes(service.id);
    const row = document.createElement("div");
    row.className = "service-row";
    row.innerHTML = `
      <span class="service-name">${service.name}</span>
      ${isConnected
        ? `<span class="connected-badge">${ICONS.check} Connected</span>`
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
  setTimeout(() => { el.textContent = ""; el.className = "sync-status"; }, 6000);
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
    await renderServicesList();   // refresh the sync banner timestamp
  } else {
    showSyncStatus(result.error, true);
  }
  e.target.textContent = "Connect";
  e.target.disabled = false;
});

init();
