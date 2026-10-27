// popup.js — UI logic for the Felix extension popup. All network/auth work is
// delegated to background.js via chrome.runtime messaging.

const SUPPORTED_SERVICES = [
  { id: "gmail",    glyph: "GM", name: "Gmail browser",  sub: "Signed-in web session" },
  { id: "sheets",   glyph: "SH", name: "Sheets browser", sub: "Signed-in web session" },
  { id: "notion",   glyph: "N",  name: "Notion",         sub: "Create and edit pages" },
  { id: "linkedin", glyph: "IN", name: "LinkedIn",       sub: "Search and post updates" },
  { id: "slack",    glyph: "S",  name: "Slack",          sub: "Send messages" },
  { id: "airtable", glyph: "A",  name: "Airtable",       sub: "Manage records" },
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
  question: `<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <circle cx="10" cy="10" r="8" stroke="currentColor" stroke-width="1.6"/>
    <path d="M7.8 8a2.2 2.2 0 1 1 3.1 2c-.6.35-.9.7-.9 1.4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
    <circle cx="10" cy="14" r="0.9" fill="currentColor"/>
  </svg>`,
};

function sendMessage(type, payload = {}) {
  return chrome.runtime.sendMessage({ type, ...payload });
}

async function init() {
  try {
    const auth = await sendMessage("GET_AUTH");
    if (auth.token) {
      await showConnectedView(auth.user);
      return;
    }
    showLoginView();
  } catch {
    showLoginView();
    document.getElementById("login-error").textContent =
      "Felix couldn’t start. Close this popup and try again.";
  }
}

function showLoginView() {
  document.getElementById("login-view").classList.remove("hidden");
  document.getElementById("connected-view").classList.add("hidden");
}

async function showConnectedView(user) {
  document.getElementById("login-view").classList.add("hidden");
  document.getElementById("connected-view").classList.remove("hidden");
  document.getElementById("user-email").textContent = user?.email || "Signed in";

  setSyncBanner("unknown", "Checking status…", "Asking the Felix server which accounts are linked.");
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

function setSyncBanner(kind, title, detail) {
  const iconEl = document.getElementById("sync-banner-icon");
  const icons = { never: ICONS.dashedCircle, recent: ICONS.checkFilled,
                  stale: ICONS.clock, unknown: ICONS.question };
  iconEl.innerHTML = icons[kind];
  iconEl.className = `status-icon status-${kind}`;
  document.getElementById("sync-banner-title").textContent = title;
  document.getElementById("sync-banner-detail").textContent = detail;
}

function renderSyncBanner(status) {
  const everSynced = status.ever_synced && status.last_synced_at;
  if (!status.ever_synced) {
    setSyncBanner("never", "No accounts connected yet",
      "Connect an account below so Felix on your phone can use it.");
    return;
  }
  if (!everSynced) {
    // Connected, but this backend doesn't report sync times — still connected.
    setSyncBanner("recent", "Connected to your phone",
      "Your accounts are linked and ready.");
    return;
  }
  const fresh = Date.now() - status.last_synced_at * 1000 < STALE_AFTER_MS;
  if (fresh) {
    setSyncBanner("recent", "Connected to your phone",
      `Last synced ${relativeTime(status.last_synced_at)}.`);
  } else {
    setSyncBanner("stale", "Connected — sync is old",
      `Last synced ${relativeTime(status.last_synced_at)}. ` +
      "Re-connect your accounts below so your sessions stay fresh.");
  }
}

// ── Services list ──────────────────────────────────────────────────────────

async function renderServicesList() {
  const res = await sendMessage("GET_CONNECTED_SERVICES");
  const status = res.status || { ok: false };

  if (status.ok === false) {
    // The check failed — say so; never pretend nothing is connected.
    setSyncBanner("unknown", "Can't check right now",
      "The Felix server didn't answer. Your accounts may still be connected — try again in a moment.");
  } else {
    renderSyncBanner(status);
  }

  const connected = status.connected || [];
  const syncTimes = {};
  for (const s of status.services || []) {
    if (s.last_synced_at) syncTimes[s.service] = s.last_synced_at;
  }

  const container = document.getElementById("services-list");
  container.innerHTML = "";

  // Google APIs row — the OAuth grant that Gmail/Sheets/Calendar tools run on.
  // Distinct from the cookie rows below: cookies sign the cloud browser in,
  // this signs the Google REST API layer in.
  const googleRow = document.createElement("div");
  googleRow.className = "service-row";
  googleRow.innerHTML = `
    <span class="service-glyph" aria-hidden="true">G</span>
    <span class="service-copy">
      <span class="row-title">Google workspace</span>
      <span class="row-subtitle">Gmail, Calendar, Docs, Drive</span>
    </span>
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
    const syncedAt = syncTimes[service.id];
    const sub = isConnected && syncedAt
      ? `Synced ${relativeTime(syncedAt)}`
      : service.sub;
    const row = document.createElement("div");
    row.className = "service-row";
    row.innerHTML = `
      <span class="service-glyph" aria-hidden="true">${service.glyph}</span>
      <span class="service-copy">
        <span class="row-title">${service.name}</span>
        <span class="row-subtitle">${sub}</span>
      </span>
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
  const nameEl = document.getElementById("current-site-name");
  const btn = document.getElementById("sync-current-tab-btn");
  let domain = null;
  try {
    const url = new URL(activeTab?.url || "");
    if (url.protocol === "http:" || url.protocol === "https:") domain = url.hostname;
  } catch { /* not a web page */ }
  nameEl.textContent = domain || "Not a website";
  btn.disabled = !domain;
}

function showSyncStatus(message, isError = false) {
  const el = document.getElementById("sync-status");
  el.textContent = message;
  el.className = isError ? "message sync-status error" : "message sync-status success";
  setTimeout(() => { el.textContent = ""; el.className = "message sync-status"; }, 6000);
}

async function withPending(button, pendingLabel, action) {
  const original = button.textContent;
  button.textContent = pendingLabel;
  button.disabled = true;
  button.setAttribute("aria-busy", "true");
  try {
    return await action();
  } finally {
    button.textContent = original;
    button.disabled = false;
    button.removeAttribute("aria-busy");
  }
}

// ── Event listeners ─────────────────────────────────────────────────────

document.getElementById("email-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!e.currentTarget.reportValidity()) return;
  const email = document.getElementById("email-input").value;
  const password = document.getElementById("password-input").value;
  const errorEl = document.getElementById("login-error");
  errorEl.textContent = "";
  const button = e.currentTarget.querySelector("button[type='submit']");
  const result = await withPending(button, "Signing in…", () =>
    sendMessage("LOGIN_EMAIL", { email, password })
  );
  if (result.success) {
    showConnectedView(result.user);
  } else {
    errorEl.textContent = result.error || "Sign in failed";
  }
});

document.getElementById("google-signin-btn").addEventListener("click", async () => {
  const button = document.getElementById("google-signin-btn");
  document.getElementById("login-error").textContent = "";
  const result = await withPending(button, "Opening Google…", () => sendMessage("LOGIN_GOOGLE"));
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
  const button = e.currentTarget;
  const result = await withPending(button, "Connecting…", () => sendMessage("SYNC_CURRENT_TAB"));
  if (result.success) {
    showSyncStatus(`Connected ${result.domain}`);
    await renderServicesList();   // refresh the sync banner timestamp
  } else {
    showSyncStatus(result.error, true);
  }
});

init();
