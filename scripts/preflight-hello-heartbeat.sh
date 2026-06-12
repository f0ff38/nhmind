#!/usr/bin/env bash
# Fail fast when hello heartbeat is missing on production relay (coordinator deploy prerequisite).
set -euo pipefail

relay_hostname="${1:?usage: preflight-hello-heartbeat.sh <relay-hostname> [watch-module]}"
watch_module="${2:-hello}"
timeout_ms="${PREFLIGHT_TIMEOUT_MS:-30000}"

relay_hostname="$(printf '%s' "${relay_hostname}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s|/$||')"
export RELAY_URL="wss://${relay_hostname}/"
export SMOKE_COORDINATOR_RELAY=1
export SMOKE_MODULE="${watch_module}"
export SMOKE_TIMEOUT_MS="${timeout_ms}"
export SMOKE_PREFLIGHT_HEARTBEAT=1

echo "Preflight: hello heartbeat (30090) on ${RELAY_URL} (timeout ${timeout_ms}ms)"

docker compose run --rm \
  -e "RELAY_URL=${RELAY_URL}" \
  -e "SMOKE_COORDINATOR_RELAY=${SMOKE_COORDINATOR_RELAY}" \
  -e "SMOKE_MODULE=${SMOKE_MODULE}" \
  -e "SMOKE_TIMEOUT_MS=${SMOKE_TIMEOUT_MS}" \
  -e "SMOKE_PREFLIGHT_HEARTBEAT=${SMOKE_PREFLIGHT_HEARTBEAT}" \
  dev bash -lc '
    set -euo pipefail
    npm ci --prefix packages/nostr-client --silent
    npm run build --prefix packages/nostr-client --silent
    npm run test:integration --prefix packages/nostr-client -- -t "preflight finds hello heartbeat"
  '

echo "Preflight passed: heartbeat present for module=${watch_module}"
