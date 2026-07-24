#!/usr/bin/env bash
# After `railway login` + `railway link`, pull production env vars into backend/.env
# without printing secret values.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
export PATH="${HOME}/.railway/bin:${PATH}"

command -v railway >/dev/null || { echo "Railway CLI missing"; exit 1; }
railway whoami >/dev/null || { echo "Run: railway login"; exit 1; }

cd "$BACKEND"
if [[ ! -f .railway/config.json ]] && [[ ! -d ../.railway ]]; then
  echo "No linked Railway project. From backend/: railway link"
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
# railway variables outputs KEY=VALUE for the linked service
railway variables --kv > "$TMP"

python3 - "$TMP" "$BACKEND/.env" <<'PY'
import sys
from pathlib import Path
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
wanted = {
  "GROQ_API_KEY","GROQ_MODEL","LUMIS_JWT_SECRET",
  "BROWSERBASE_API_KEY","BROWSERBASE_PROJECT_ID",
  "GOOGLE_OAUTH_CLIENT_ID","GOOGLE_OAUTH_CLIENT_SECRET",
  "LUMIS_GOOGLE_CLIENT_ID","LUMIS_APPLE_BUNDLE_ID",
  "PUBLIC_BASE_URL","AGENT_MAX_STEPS","AGENT_THINK_TIMEOUT",
  "BROWSER_SESSION_IDLE_S",
}
incoming={}
for line in src.read_text().splitlines():
  if "=" not in line: continue
  k,v=line.split("=",1)
  if k in wanted and v:
    incoming[k]=v
if not dest.exists():
  dest.write_text("")
lines=dest.read_text().splitlines()
seen=set(); out=[]
for line in lines:
  if not line.strip() or line.strip().startswith("#") or "=" not in line:
    out.append(line); continue
  k,v=line.split("=",1)
  if k in incoming:
    out.append(f"{k}={incoming[k]}"); seen.add(k)
  else:
    out.append(line)
for k,v in incoming.items():
  if k not in seen:
    out.append(f"{k}={v}")
dest.write_text("\n".join(out)+"\n")
print(f"Updated {dest} with {len(incoming)} Railway variables (values not printed).")
for k in sorted(incoming):
  print(f"  {k}: SET len={len(incoming[k])}")
PY
