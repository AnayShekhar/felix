#!/usr/bin/env bash
# One-shot local backend setup for Lumis.
# Usage: bash scripts/setup_backend.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
cd "$BACKEND"

if ! python3 -c "import venv" 2>/dev/null; then
  echo "python3-venv is required (e.g. apt install python3.12-venv)" >&2
  exit 1
fi

if [[ ! -d venv ]]; then
  python3 -m venv venv
fi
# shellcheck disable=SC1091
source venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m playwright install chromium

if [[ ! -f .env ]]; then
  JWT="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')"
  cp .env.example .env
  # Fill a local JWT so auth works without Railway.
  if grep -q '^LUMIS_JWT_SECRET=' .env; then
    sed -i "s|^LUMIS_JWT_SECRET=.*|LUMIS_JWT_SECRET=${JWT}|" .env
  else
    echo "LUMIS_JWT_SECRET=${JWT}" >> .env
  fi
  # Sensible local defaults
  if grep -q '^PUBLIC_BASE_URL=' .env; then
    sed -i 's|^PUBLIC_BASE_URL=.*|PUBLIC_BASE_URL=http://127.0.0.1:8000|' .env
  else
    echo "PUBLIC_BASE_URL=http://127.0.0.1:8000" >> .env
  fi
  echo "Created backend/.env — set GROQ_API_KEY (and optional Browserbase/Google keys)."
else
  echo "backend/.env already exists — leaving it untouched."
fi

echo
echo "Setup complete. Start the backend with:"
echo "  cd backend && source venv/bin/activate && uvicorn main:app --port 8000"
echo
echo "Required for AI:     GROQ_API_KEY"
echo "Required on Railway: LUMIS_JWT_SECRET"
echo "Optional cloud:      BROWSERBASE_API_KEY, BROWSERBASE_PROJECT_ID,"
echo "                     GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET"
