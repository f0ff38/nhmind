#!/usr/bin/env bash
# Read-only check that SELECTEL_STATIC_TOKEN works (Balance API accepts X-Token).
set -euo pipefail

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

token="$(trim "${SELECTEL_STATIC_TOKEN:-}")"

if [ -z "${token}" ]; then
  echo "::error::SELECTEL_STATIC_TOKEN is required"
  exit 1
fi

response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT

http_code="$(curl -sS -o "${response_file}" -w "%{http_code}" \
  -X GET "https://api.selectel.ru/v3/balances" \
  -H "X-Token: ${token}" \
  -H "Accept: application/json")"

if [ "${http_code}" = "200" ]; then
  echo "SELECTEL_STATIC_TOKEN OK (Balance API HTTP 200)"
  exit 0
fi

echo "::error::SELECTEL_STATIC_TOKEN rejected (HTTP ${http_code})"
head -c 500 "${response_file}" || true
echo ""
echo "Checklist:"
echo "  - Token from Profile → API Keys (X-Token), not service user password"
echo "  - Token not revoked; copy without trailing whitespace"
exit 1
