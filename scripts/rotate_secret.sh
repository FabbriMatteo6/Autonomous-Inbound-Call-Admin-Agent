#!/usr/bin/env bash
# ==============================================================================
# Rotate WEBHOOK_SECRET safely.
#
# Generates a new secret, writes it to .env (unquoted), recreates n8n so it
# reloads, and verifies the new secret is accepted (200) and the old one is
# rejected (401). Then prints the new value so you can paste it into the
# ElevenLabs shared secret.
#
# Usage:  ./scripts/rotate_secret.sh
#
# IMPORTANT: after running, update the ElevenLabs shared secret to the new
# value or every tool call will 401.
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONTAINER="n8n_inbound_admin"
ENV_FILE=".env"
PORT="${N8N_PORT:-5678}"
BASE="http://localhost:${PORT}"

command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl is required."; exit 1; }
command -v docker  >/dev/null 2>&1 || { echo "ERROR: docker is required.";  exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: .env not found. Run ./setup.sh first."; exit 1; }

OLD="$(grep -E '^WEBHOOK_SECRET=' "$ENV_FILE" | head -1 | sed -E 's/^WEBHOOK_SECRET=//; s/^"//; s/"$//' || true)"
NEW="$(openssl rand -hex 16)"

echo "==> Writing new WEBHOOK_SECRET to .env (unquoted)"
python3 - "$ENV_FILE" "$NEW" <<'PY'
import re, sys
path, new = sys.argv[1], sys.argv[2]
t = open(path, encoding="utf-8").read()
if re.search(r'^WEBHOOK_SECRET=.*$', t, flags=re.M):
    t = re.sub(r'^WEBHOOK_SECRET=.*$', f'WEBHOOK_SECRET={new}', t, flags=re.M)
else:
    if t and not t.endswith("\n"):
        t += "\n"
    t += f"WEBHOOK_SECRET={new}\n"
open(path, "w", encoding="utf-8").write(t)
PY

echo "==> Recreating n8n so it reloads the secret"
docker compose up -d --force-recreate >/dev/null

echo "==> Waiting for n8n to be healthy"
for i in $(seq 1 60); do
  if curl -sf "${BASE}/healthz" >/dev/null 2>&1; then break; fi
  sleep 1
done
sleep 2

echo "==> Verifying"
code_new="$(curl -s -o /dev/null -m 15 -w '%{http_code}' -X POST "${BASE}/webhook/sku-lookup" \
  -H "Content-Type: application/json" -H "X-Webhook-Secret: ${NEW}" --data '{"query":"oil"}')"
code_old="n/a"
if [ -n "${OLD}" ]; then
  code_old="$(curl -s -o /dev/null -m 15 -w '%{http_code}' -X POST "${BASE}/webhook/sku-lookup" \
    -H "Content-Type: application/json" -H "X-Webhook-Secret: ${OLD}" --data '{"query":"oil"}')"
fi

echo
echo "  new secret accepted (expect 200): HTTP ${code_new}"
echo "  old secret rejected (expect 401): HTTP ${code_old}"
echo
if [ "${code_new}" = "200" ]; then
  echo "✅ Rotation applied locally."
else
  echo "⚠️  New secret did not return 200 — ensure the workflows are imported and Active."
fi
echo
echo "NEW WEBHOOK_SECRET:"
echo "    ${NEW}"
echo
echo "NEXT (required): set the ElevenLabs shared secret (Settings → Secrets — the secret_id"
echo "your tools reference) to this exact value, or every tool call will 401."
