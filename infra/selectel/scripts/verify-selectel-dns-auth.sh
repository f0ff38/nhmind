#!/usr/bin/env bash
# Smoke-test Selectel DNS API auth (project IAM token + zones list).
set -euo pipefail

DNS_API="${SELECTEL_DNS_API:-https://api.selectel.ru/domains/v2}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(bash "${script_dir}/get-selectel-dns-token.sh")"

http_code="$(curl -sS -o dns-zones.json -w "%{http_code}" \
  -X GET "${DNS_API}/zones?limit=5" \
  -H "X-Auth-Token: ${token}" \
  -H "Accept: application/json")"

if [ "${http_code}" != "200" ]; then
  echo "::error::Selectel DNS API rejected token (HTTP ${http_code})"
  head -c 500 dns-zones.json || true
  echo ""
  echo "Checklist:"
  echo "  - SELECTEL_IAM_PROJECT_NAME override if auto-resolve from SELECTEL_PROJECT_ID fails"
  echo "  - Service user has IAM permission for the project that owns the zone"
  exit 1
fi

zone_count="$(jq -r 'if (.count? | type) == "number" then .count elif (.result? | type) == "array" then (.result | length) else 0 end' dns-zones.json 2>/dev/null || echo 0)"
sample_names="$(jq -r '(.result // [])[:5][]?.name // empty' dns-zones.json 2>/dev/null | paste -sd ', ' - || true)"

if [ "${zone_count}" = "0" ]; then
  echo "::error::Selectel DNS API OK but zero zones visible — wrong IAM project scope"
  echo "Set SELECTEL_IAM_PROJECT_NAME only if auto-resolve from SELECTEL_PROJECT_ID failed"
  exit 1
fi

echo "Selectel DNS API OK (HTTP 200, zones visible: ${zone_count}${sample_names:+, e.g. ${sample_names}})"
exit 0
