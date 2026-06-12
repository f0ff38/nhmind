#!/usr/bin/env bash
# Wait for coordinator registry (30092) + scorecard (30091) on production relay.
# Usage: smoke-coordinator-relay.sh <relay-hostname> [watch-module]
set -euo pipefail

relay_hostname="${1:?usage: smoke-coordinator-relay.sh <relay-hostname> [watch-module]}"
watch_module="${2:-hello}"

relay_hostname="$(printf '%s' "${relay_hostname}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s|/$||')"
export RELAY_URL="wss://${relay_hostname}/"
export SMOKE_MODULE="${watch_module}"
export SMOKE_TIMEOUT_MS="${SMOKE_TIMEOUT_MS:-120000}"
export SMOKE_MAX_AGE_SEC="${SMOKE_MAX_AGE_SEC:-180}"
if [ -n "${COORDINATOR_PUBKEY:-}" ]; then
  export COORDINATOR_PUBKEY
fi

echo "Smoke coordinator relay: RELAY_URL=${RELAY_URL} module=${SMOKE_MODULE} timeout=${SMOKE_TIMEOUT_MS}ms"

compose_env=(
  -e "RELAY_URL=${RELAY_URL}"
  -e "SMOKE_MODULE=${SMOKE_MODULE}"
  -e "SMOKE_TIMEOUT_MS=${SMOKE_TIMEOUT_MS}"
  -e "SMOKE_MAX_AGE_SEC=${SMOKE_MAX_AGE_SEC}"
)
if [ -n "${COORDINATOR_PUBKEY:-}" ]; then
  compose_env+=(-e "COORDINATOR_PUBKEY=${COORDINATOR_PUBKEY}")
fi

docker compose run --rm "${compose_env[@]}" dev bash -lc '
  set -euo pipefail
  npm ci --prefix packages/nostr-client
  npm run build --prefix packages/nostr-client
  npm run test:integration --prefix packages/nostr-client -- -t "coordinator-relay"
'

echo "Coordinator relay smoke passed (registry + scorecard on ${RELAY_URL})"
