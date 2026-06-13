#!/usr/bin/env bash
# Smoke-check relay after deploy: DNS (optional), TLS, NIP-11, WebSocket upgrade.
set -euo pipefail

relay_hostname="${1:?usage: smoke-relay.sh <relay-hostname>}"
expected_ip="${2:-}"

relay_hostname="$(printf '%s' "${relay_hostname}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [ -n "${expected_ip}" ]; then
  echo "Checking DNS A record for ${relay_hostname}..."
  resolved="$(getent ahostsv4 "${relay_hostname}" | awk '{print $1; exit}' || true)"
  if [ -z "${resolved}" ]; then
    echo "::warning::Could not resolve ${relay_hostname} — ensure A record points to ${expected_ip}"
  elif [ "${resolved}" != "${expected_ip}" ]; then
    echo "::warning::${relay_hostname} resolves to ${resolved}, expected ${expected_ip} (DNS may still be propagating)"
  else
    echo "DNS OK: ${relay_hostname} -> ${resolved}"
  fi
fi

echo "Checking HTTPS / NIP-11..."
http_code=""
attempt=1
max_attempts=12
while [ "${attempt}" -le "${max_attempts}" ]; do
  http_code="$(curl -4fsS -o /tmp/nhmind-relay-nip11.json -w '%{http_code}' "https://${relay_hostname}/" 2>/dev/null || true)"
  if [ "${http_code}" = "200" ]; then
    break
  fi
  echo "HTTPS not ready (HTTP ${http_code:-000}), retry ${attempt}/${max_attempts}..."
  sleep 5
  attempt=$((attempt + 1))
done
if [ "${http_code}" != "200" ]; then
  echo "::error::HTTPS GET https://${relay_hostname}/ returned HTTP ${http_code:-000}"
  exit 1
fi

if ! grep -q '"name"' /tmp/nhmind-relay-nip11.json 2>/dev/null; then
  echo "::warning::Response may not be NIP-11 JSON — check relay diagnostics"
fi
echo "HTTPS OK"

echo "Checking WebSocket upgrade..."
ws_headers="$(mktemp)"
trap 'rm -f "${ws_headers}" /tmp/nhmind-relay-nip11.json /tmp/nhmind-relay-bridge.json' EXIT
ws_status="$(curl -4sS -D "${ws_headers}" -o /dev/null --http1.1 --max-time 15 \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  "https://${relay_hostname}/" -w '%{http_code}' 2>/dev/null || true)"
ws_first_line="$(head -n 1 "${ws_headers}" 2>/dev/null || true)"
if ! printf '%s\n%s' "${ws_first_line}" "${ws_status}" | grep -q '101'; then
  echo "::error::WebSocket upgrade to wss://${relay_hostname}/ failed (${ws_first_line:-no response}, code=${ws_status:-?})"
  exit 1
fi
echo "WebSocket upgrade OK"

echo "Checking Acurast HTTP POST bridge (REQ)..."
bridge_body='["REQ","nhmind-smoke",{"limit":0}]'
bridge_code=""
attempt=1
while [ "${attempt}" -le "${max_attempts}" ]; do
  bridge_code="$(curl -4fsS -o /tmp/nhmind-relay-bridge.json -w '%{http_code}' \
    -X POST "https://${relay_hostname}/" \
    -H "Content-Type: application/json" \
    --data "${bridge_body}" 2>/dev/null || true)"
  if [ "${bridge_code}" = "200" ] && grep -q 'EOSE' /tmp/nhmind-relay-bridge.json 2>/dev/null; then
    break
  fi
  echo "HTTP POST bridge not ready (HTTP ${bridge_code:-000}), retry ${attempt}/${max_attempts}..."
  sleep 5
  attempt=$((attempt + 1))
done
if [ "${bridge_code}" != "200" ] || ! grep -q 'EOSE' /tmp/nhmind-relay-bridge.json 2>/dev/null; then
  echo "::error::HTTP POST https://${relay_hostname}/ (Acurast bridge) failed (HTTP ${bridge_code:-000})"
  exit 1
fi
echo "HTTP POST bridge OK"

echo "Smoke passed for wss://${relay_hostname}/"
