#!/usr/bin/env bash
# Verify local Lumis backend setup is healthy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
cd "$BACKEND"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK  $*"; }

[[ -d venv ]] || fail "backend/venv missing — run scripts/setup_backend.sh"
# shellcheck disable=SC1091
source venv/bin/activate

python - <<'PY' || fail "import check"
mods = ["fastapi","uvicorn","groq","google.auth","googleapiclient","dotenv",
        "websockets","dateparser","requests","bs4","playwright","browserbase",
        "cryptography"]
for m in mods:
    __import__(m)
print("imports ok")
PY
ok "Python packages import"

[[ -f .env ]] || fail "backend/.env missing — run scripts/setup_backend.sh"
# shellcheck disable=SC1091
set -a; source .env; set +a
[[ -n "${LUMIS_JWT_SECRET:-}" ]] || fail "LUMIS_JWT_SECRET empty in .env"
ok "LUMIS_JWT_SECRET set"
if [[ -z "${GROQ_API_KEY:-}" ]]; then
  echo "WARN GROQ_API_KEY empty — local AI calls will return a friendly error"
else
  ok "GROQ_API_KEY set"
fi
if [[ -z "${BROWSERBASE_API_KEY:-}" || -z "${BROWSERBASE_PROJECT_ID:-}" ]]; then
  echo "WARN Browserbase not configured — cloud browser tools return 503"
else
  ok "Browserbase configured"
fi
if [[ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" || -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
  echo "WARN Google OAuth not configured — google_api tools need connect Google"
else
  ok "Google OAuth configured"
fi

# Live health if server is up
if curl -fsS -m 2 http://127.0.0.1:8000/health >/dev/null 2>&1; then
  ok "Local server /health"
else
  echo "INFO local server not running (start: uvicorn main:app --port 8000)"
fi

if curl -fsS -m 8 https://lumis-production-b878.up.railway.app/health >/dev/null 2>&1; then
  ok "Railway production /health"
else
  echo "WARN Railway production /health unreachable"
fi

echo
echo "Verification finished."
