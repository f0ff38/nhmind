#!/usr/bin/env bash
# Smoke-test Selectel DNS API auth (project IAM token + zones list).
set -euo pipefail

DNS_API="${SELECTEL_DNS_API:-https://api.selectel.ru/domains/v2}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(bash "${script_dir}/get-openstack-project-token.sh")"

http_code="$(curl -sS -o dns-zones.json -w "%{http_code}" \
  -X GET "${DNS_API}/zones?limit=1" \
  -H "X-Auth-Token: ${token}" \
  -H "Accept: application/json")"

if [ "${http_code}" = "200" ]; then
  echo "Selectel DNS API OK (HTTP 200, project-scoped IAM token)"
  exit 0
fi

echo "::error::Selectel DNS API rejected token (HTTP ${http_code})"
head -c 500 dns-zones.json || true
echo ""
echo "Checklist:"
echo "  - DNS zone exists in panel → DNS (actual)"
echo "  - Service user has IAM permission for the project that owns the zone"
echo "  - If Keystone scope-by-id fails for DNS: set SELECTEL_IAM_PROJECT_NAME (IAM → Projects → name)"
exit 1
