#!/usr/bin/env bash
# Verify IAM token can list Selectel LE certificates (no values logged).
set -euo pipefail

LE_API="${SELECTEL_LE_API:-https://api.selectel.ru/certs/le}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(bash "${script_dir}/get-selectel-dns-token.sh")"

http_code="$(curl -sS -o /dev/null -w "%{http_code}" \
  -X GET "${LE_API}/" \
  -H "X-Auth-Token: ${token}" \
  -H "Accept: application/json")"

if [ "${http_code}" = "200" ]; then
  echo "Selectel LE API: OK (HTTP 200)"
  exit 0
fi

echo "::error::Selectel LE API list failed (HTTP ${http_code})"
echo "Service user needs Certificate Manager / Let's Encrypt permissions on the project."
exit 1
