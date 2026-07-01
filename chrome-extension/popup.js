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
