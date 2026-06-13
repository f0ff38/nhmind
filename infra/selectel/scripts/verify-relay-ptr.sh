#!/usr/bin/env bash
# Verify relay floating IP PTR matches RELAY_HOSTNAME (Acurast reverse whitelist).
# When PTR = RELAY_HOSTNAME, forward _acu.<host> TXT also satisfies reverse lookup.
set -euo pipefail

normalize_hostname() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\.$//'
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

expected="$(normalize_hostname "$(trim "${RELAY_HOSTNAME:-}")")"
public_ip="$(trim "${PUBLIC_IP:-}")"
retries="${VERIFY_PTR_RETRIES:-18}"
sleep_sec="${VERIFY_PTR_SLEEP_SEC:-10}"

if [ -z "${expected}" ]; then
  echo "::error::RELAY_HOSTNAME is required"
  exit 1
fi

if [ -z "${public_ip}" ]; then
  echo "::error::PUBLIC_IP is required (set explicitly or via read-relay-public-ip.sh)"
  exit 1
fi

if ! printf '%s' "${public_ip}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "::error::PUBLIC_IP must be IPv4"
  exit 1
fi

if ! command -v dig >/dev/null 2>&1; then
  echo "::error::dig is required (install dnsutils)"
  exit 1
fi

lookup_ptr() {
  dig +short -x "${public_ip}" 2>/dev/null | head -n 1 | sed 's/\.$//'
}

attempt=1
ptr_host=""
while [ "${attempt}" -le "${retries}" ]; do
  ptr_host="$(lookup_ptr || true)"
  ptr_host="$(normalize_hostname "${ptr_host}")"
  if [ -n "${ptr_host}" ]; then
    break
  fi
  echo "PTR for ${public_ip} not visible yet (attempt ${attempt}/${retries}); sleeping ${sleep_sec}s..."
  sleep "${sleep_sec}"
  attempt=$((attempt + 1))
done

if [ -z "${ptr_host}" ]; then
  echo "::error::No PTR record for ${public_ip} after ${retries} attempts — run Provision Relay Infra apply with set_ptr=true"
  exit 1
fi

if [ "${ptr_host}" != "${expected}" ]; then
  echo "::error::PTR mismatch: ${public_ip} -> ${ptr_host} (expected ${expected})"
  echo "::error::Fix PTR via upsert-relay-ptr.sh or Provision Relay Infra (set_ptr=true); reverse _acu TXT must use PTR hostname in hash"
  exit 1
fi

echo "PTR OK: ${public_ip} -> ${ptr_host}"
