#!/usr/bin/env bash
# ==============================================================================
# One-command setup for the Inbound Call Admin Agent (local dev).
# Automates the mechanical steps: .env, secret generation, config render,
# Docker boot, and n8n workflow import + activation. The genuinely external
# steps (Supabase SQL, Google OAuth, ElevenLabs, ngrok) are printed as a
# checklist at the end.
#
# Usage:  ./setup.sh
# Re-runnable (idempotent): safe to run again after editing config.
# ==============================================================================
set -euo pipefail

CONTAINER="n8n_inbound_admin"
cd "$(dirname "$0")"

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m!!\033[0m %s\n" "$1"; }

# --- 1. Prerequisites -------------------------------------------------------
command -v docker >/dev/null 2>&1 || { warn "Docker is not installed. Install Docker Desktop, then re-run."; exit 1; }
docker compose version >/dev/null 2>&1 || { warn "The 'docker compose' plugin is required."; exit 1; }
command -v python3 >/dev/null 2>&1 || { warn "python3 is required (used to render config and edit .env)."; exit 1; }

# --- 2. .env + webhook secret ----------------------------------------------
if [ ! -f .env ]; then
  info "Creating .env from .env.example"
  cp .env.example .env
fi

info "Ensuring a strong WEBHOOK_SECRET (unquoted)"
python3 - <<'PY'
import re, secrets, pathlib
p = pathlib.Path(".env")
txt = p.read_text()
def current(t):
    m = re.search(r'^WEBHOOK_SECRET=(.*)$', t, re.M)
    return m.group(1).strip().strip('"').strip("'") if m else ""
val = current(txt)
placeholder = (not val) or val == "generate_a_random_32_character_secret_here"
if placeholder:
    new = secrets.token_hex(16)
    txt = re.sub(r'^WEBHOOK_SECRET=.*$', f'WEBHOOK_SECRET={new}', txt, flags=re.M)
    p.write_text(txt)
    print("  generated a new WEBHOOK_SECRET")
else:
    # normalise: strip surrounding quotes if present
    txt = re.sub(r'^WEBHOOK_SECRET=.*$', f'WEBHOOK_SECRET={val}', txt, flags=re.M)
    p.write_text(txt)
    print("  kept existing WEBHOOK_SECRET (quotes normalised)")
PY

# --- 3. Render white-label config from business-profile.yaml ----------------
if [ -f config/business-profile.yaml ]; then
  info "Rendering ElevenLabs config from config/business-profile.yaml"
  python3 scripts/render_config.py || warn "Config render failed (continuing)."
fi

# --- 4. Boot the stack ------------------------------------------------------
info "Starting n8n via docker compose"
docker compose up -d

info "Waiting for n8n to become healthy"
for i in $(seq 1 60); do
  if curl -sf http://localhost:5678/healthz >/dev/null 2>&1; then info "n8n is up (${i}s)"; break; fi
  sleep 1
done

# --- 5. Import + activate workflows ----------------------------------------
info "Importing workflows into n8n"
for f in workflows/*.json; do
  docker cp "$f" "$CONTAINER:/tmp/$(basename "$f")" >/dev/null
  docker exec "$CONTAINER" n8n import:workflow --input="/tmp/$(basename "$f")" 2>&1 \
    | grep -viE "error tracking|punycode|deprecation" || true
done

info "Activating all imported workflows"
docker exec "$CONTAINER" n8n list:workflow 2>/dev/null \
  | grep -E '^[A-Za-z0-9]+\|' \
  | cut -d'|' -f1 \
  | while read -r id; do
      docker exec "$CONTAINER" n8n update:workflow --id="$id" --active=true >/dev/null 2>&1 || true
    done

info "Restarting n8n so webhook routes register"
docker compose restart n8n >/dev/null 2>&1
for i in $(seq 1 60); do
  curl -sf http://localhost:5678/healthz >/dev/null 2>&1 && break; sleep 1
done

# --- 6. Manual checklist ----------------------------------------------------
cat <<'DONE'

------------------------------------------------------------------------------
 Local stack is running at http://localhost:5678
------------------------------------------------------------------------------
 Remaining manual steps (external services):

 1. n8n owner account: open http://localhost:5678 and create the admin login.
 2. Supabase: create a free project, run database/schema.sql then seed.sql in
    the SQL editor, and paste SUPABASE_URL / keys into .env. Re-run ./setup.sh.
 3. ngrok: `ngrok http 5678`, copy the https URL into WEBHOOK_URL in .env,
    then `docker compose up -d --force-recreate`.
 4. Google Calendar: create an OAuth client, add the ngrok callback URL, and
    connect the credential in n8n *via the ngrok URL* (not localhost).
 5. ElevenLabs: create the agent, paste elevenlabs/agent-prompt.md, upload the
    FAQ, and set each tool URL to https://<ngrok>/webhook/<name> with the
    X-Webhook-Secret header = your WEBHOOK_SECRET.
------------------------------------------------------------------------------
DONE
