#!/usr/bin/env bash
# Upsert A record for RELAY_HOSTNAME in Selectel DNS (actual, API v2).
set -euo pipefail

DNS_API="${SELECTEL_DNS_API:-https://api.selectel.ru/domains/v2}"
TTL="${RELAY_DNS_TTL:-300}"

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

to_fqdn() {
  local name
  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g' | sed 's/\.$//')"
  printf '%s.' "${name}"
}

relay_hostname_raw="$(trim "${RELAY_HOSTNAME:-}")"
public_ip="$(trim "${PUBLIC_IP:-}")"
zone_override="$(trim "${RELAY_DNS_ZONE:-}")"

if [ -z "${relay_hostname_raw}" ] || [ -z "${public_ip}" ]; then
  echo "::error::RELAY_HOSTNAME and PUBLIC_IP are required"
  exit 1
fi

if ! printf '%s' "${public_ip}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "::error::PUBLIC_IP must be IPv4 (${public_ip})"
  exit 1
fi

rrset_fqdn="$(to_fqdn "${relay_hostname_raw}")"
hostname_no_dot="${rrset_fqdn%.}"

if [ -n "${zone_override}" ]; then
  zone_fqdn="$(to_fqdn "${zone_override}")"
else
  label_count="$(printf '%s' "${hostname_no_dot}" | tr -cd '.' | wc -c | tr -d ' ')"
  if [ "${label_count}" -le 1 ]; then
    zone_fqdn="${rrset_fqdn}"
  else
    zone_fqdn="$(to_fqdn "${hostname_no_dot#*.}")"
  fi
fi

case "${rrset_fqdn}" in
  *."${zone_fqdn}") ;;
  "${zone_fqdn}")
    rrset_fqdn="${zone_fqdn}"
    ;;
  *)
    echo "::error::RELAY_HOSTNAME ${rrset_fqdn} is not inside zone ${zone_fqdn} (set RELAY_DNS_ZONE if needed)"
    exit 1
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required"
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(bash "${script_dir}/get-openstack-project-token.sh")"

auth_header=(-H "X-Auth-Token: ${token}" -H "Content-Type: application/json")

echo "Selectel DNS: upsert A ${rrset_fqdn} -> ${public_ip} (zone ${zone_fqdn})"

zones_payload="$(curl -sS "${auth_header[@]}" "${DNS_API}/zones?filter=${zone_fqdn}")"
zone_id="$(printf '%s' "${zones_payload}" | jq -r --arg zone "${zone_fqdn}" '.result[]? | select(.name == $zone) | .id' | head -n 1)"

if [ -z "${zone_id}" ] || [ "${zone_id}" = "null" ]; then
  echo "::error::DNS zone ${zone_fqdn} not found in Selectel DNS for this project"
  echo "Checklist:"
  echo "  - Zone exists in panel → DNS (actual)"
  echo "  - Service user has access to the DNS project"
  echo "  - Set RELAY_DNS_ZONE if hostname uses a nested subdomain"
  exit 1
fi

list_url="${DNS_API}/zones/${zone_id}/rrset?name=$(printf '%s' "${rrset_fqdn}" | jq -sRr @uri)&rrset_types=A"
rrsets_payload="$(curl -sS "${auth_header[@]}" "${list_url}")"
rrset_id="$(printf '%s' "${rrsets_payload}" | jq -r '.result[0].id // empty')"
current_ip="$(printf '%s' "${rrsets_payload}" | jq -r '.result[0].records[0].content // empty')"

patch_body="$(jq -n \
  --argjson ttl "${TTL}" \
  --arg ip "${public_ip}" \
  '{
    ttl: $ttl,
    records: [{ content: $ip, disabled: false }],
    comment: "nhmind relay (managed by provision-relay-infra)"
  }')"

if [ -n "${rrset_id}" ]; then
  if [ "${current_ip}" = "${public_ip}" ]; then
    echo "DNS A record already points to ${public_ip}"
    exit 0
  fi
  http_code="$(curl -sS -o dns-response.json -w "%{http_code}" \
    -X PATCH \
    -H "X-Auth-Token: ${token}" \
    -H "Content-Type: application/json" \
    "${DNS_API}/zones/${zone_id}/rrset/${rrset_id}" \
    -d "${patch_body}")"
  if [ "${http_code}" = "204" ]; then
    echo "DNS A record updated: ${rrset_fqdn} -> ${public_ip}"
    exit 0
  fi
  echo "::error::DNS PATCH returned HTTP ${http_code}"
  cat dns-response.json || true
  exit 1
fi

create_body="$(jq -n \
  --arg name "${rrset_fqdn}" \
  --argjson ttl "${TTL}" \
  --arg ip "${public_ip}" \
  '{
    name: $name,
    type: "A",
    ttl: $ttl,
    records: [{ content: $ip, disabled: false }],
    comment: "nhmind relay (managed by provision-relay-infra)"
  }')"

http_code="$(curl -sS -o dns-response.json -w "%{http_code}" \
  -X POST \
  -H "X-Auth-Token: ${token}" \
  -H "Content-Type: application/json" \
  "${DNS_API}/zones/${zone_id}/rrset" \
  -d "${create_body}")"

if [ "${http_code}" = "200" ]; then
  echo "DNS A record created: ${rrset_fqdn} -> ${public_ip}"
  exit 0
fi

echo "::error::DNS POST returned HTTP ${http_code}"
cat dns-response.json || true
exit 1
