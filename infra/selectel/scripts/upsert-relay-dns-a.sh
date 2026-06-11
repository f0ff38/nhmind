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

normalize_zone_label() {
  printf '%s' "$(to_fqdn "$1")" | sed 's/\.$//'
}

zone_names_match() {
  [ "$(normalize_zone_label "$1")" = "$(normalize_zone_label "$2")" ]
}

relay_hostname_raw="$(trim "${RELAY_HOSTNAME:-}")"
public_ip="$(trim "${PUBLIC_IP:-}")"
zone_override="$(trim "${RELAY_DNS_ZONE:-}")"
zone_id_override="$(trim "${RELAY_DNS_ZONE_ID:-}")"

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

auth_header=(-H "X-Auth-Token: ${token}" -H "Content-Type: application/json" -H "Accept: application/json")

echo "Selectel DNS: upsert A ${rrset_fqdn} -> ${public_ip} (zone ${zone_fqdn})"

dns_curl() {
  curl -sS "${auth_header[@]}" "$@"
}

list_zones_page() {
  local offset="$1"
  local limit="$2"
  local filter="${3:-}"
  local url="${DNS_API}/zones?limit=${limit}&offset=${offset}"
  if [ -n "${filter}" ]; then
    local encoded
    encoded="$(printf '%s' "${filter}" | jq -sRr @uri)"
    url="${url}&filter=${encoded}"
  fi
  dns_curl "${url}"
}

extract_zone_id_from_payload() {
  local payload="$1"
  local want_zone="$2"
  printf '%s' "${payload}" | jq -r --arg zone "${want_zone}" --arg zone_plain "${want_zone%.}" '
    def norm: ascii_downcase | sub("\\.$"; "");
    (.result // [])[]
    | select(
        (.name // "") as $n
        | ($n | norm) == ($zone | norm)
        or ($n | norm) == ($zone_plain | norm)
      )
    | .id
  ' | head -n 1
}

find_zone_id_by_name() {
  local want_zone="$1"
  local offset=0
  local limit=1000
  local filter

  for filter in "${want_zone}" "${want_zone%.}"; do
    offset=0
    while true; do
      local payload
      payload="$(list_zones_page "${offset}" "${limit}" "${filter}")"
      local zone_id
      zone_id="$(extract_zone_id_from_payload "${payload}" "${want_zone}")"
      if [ -n "${zone_id}" ] && [ "${zone_id}" != "null" ]; then
        printf '%s' "${zone_id}"
        return 0
      fi
      local page_count next_offset total_count
      page_count="$(printf '%s' "${payload}" | jq -r '(.result // []) | length')"
      next_offset="$(printf '%s' "${payload}" | jq -r '.next_offset // empty')"
      total_count="$(printf '%s' "${payload}" | jq -r '.count // empty')"
      if [ -n "${total_count}" ] && [ "${total_count}" != "null" ]; then
        TOTAL_ZONES_REPORT="${total_count}"
      fi
      if [ -z "${page_count}" ] || [ "${page_count}" -lt "${limit}" ]; then
        break
      fi
      if [ -n "${next_offset}" ] && [ "${next_offset}" != "null" ]; then
        offset="${next_offset}"
      else
        offset=$((offset + limit))
      fi
    done
  done

  offset=0
  while true; do
    local payload
    payload="$(list_zones_page "${offset}" "${limit}")"
    local zone_id
    zone_id="$(extract_zone_id_from_payload "${payload}" "${want_zone}")"
    if [ -n "${zone_id}" ] && [ "${zone_id}" != "null" ]; then
      printf '%s' "${zone_id}"
      return 0
    fi
    local page_count next_offset
    page_count="$(printf '%s' "${payload}" | jq -r '(.result // []) | length')"
    next_offset="$(printf '%s' "${payload}" | jq -r '.next_offset // empty')"
    if [ -z "${page_count}" ] || [ "${page_count}" -lt "${limit}" ]; then
      return 1
    fi
    if [ -n "${next_offset}" ] && [ "${next_offset}" != "null" ]; then
      offset="${next_offset}"
    else
      offset=$((offset + limit))
    fi
  done
}

resolve_zone_id() {
  if [ -n "${zone_id_override}" ]; then
    local payload http_code
    http_code="$(curl -sS -o dns-zone.json -w "%{http_code}" "${auth_header[@]}" "${DNS_API}/zones/${zone_id_override}")"
    if [ "${http_code}" != "200" ]; then
      echo "::error::RELAY_DNS_ZONE_ID ${zone_id_override} not found (HTTP ${http_code})"
      cat dns-zone.json || true
      exit 1
    fi
    local api_zone_name
    api_zone_name="$(jq -r '.name // empty' dns-zone.json)"
    if [ -n "${api_zone_name}" ] && ! zone_names_match "${api_zone_name}" "${zone_fqdn}"; then
      echo "::warning::RELAY_DNS_ZONE_ID name ${api_zone_name} differs from derived zone ${zone_fqdn}; using zone id from secret"
    fi
    printf '%s' "${zone_id_override}"
    return 0
  fi

  find_zone_id_by_name "${zone_fqdn}"
}

print_zone_lookup_help() {
  echo "Checklist:"
  echo "  - Zone exists in panel → DNS (actual/registrar) for project ${OS_PROJECT_ID:-<unknown>}"
  echo "  - Set RELAY_DNS_ZONE if hostname uses a nested subdomain"
  echo "  - Set RELAY_DNS_ZONE_ID from panel URL: .../dns/<project>/registrar/<zone-uuid>/"
  echo "  - Service user IAM permission must include this DNS project"
  echo "  - Optional: SELECTEL_IAM_PROJECT_NAME (IAM → Projects → name) for token scope"
  if [ -n "${TOTAL_ZONES_REPORT:-}" ]; then
    echo "  - Token sees ${TOTAL_ZONES_REPORT} zone(s) in API; none matched ${zone_fqdn}"
  fi
  local sample_payload sample_names
  sample_payload="$(list_zones_page 0 5)"
  sample_names="$(printf '%s' "${sample_payload}" | jq -r '(.result // [])[:5][]?.name // empty' | paste -sd ', ' -)"
  if [ -n "${sample_names}" ]; then
    echo "  - Sample zone names from API: ${sample_names}"
  else
    echo "  - API returned zero zones for this project token (wrong scope or empty project)"
  fi
}

TOTAL_ZONES_REPORT=""
zone_id="$(resolve_zone_id || true)"
if [ -z "${zone_id}" ] || [ "${zone_id}" = "null" ]; then
  echo "::error::DNS zone ${zone_fqdn} not found in Selectel DNS for this project"
  print_zone_lookup_help
  exit 1
fi

list_url="${DNS_API}/zones/${zone_id}/rrset?name=$(printf '%s' "${rrset_fqdn}" | jq -sRr @uri)&rrset_types=A"
rrsets_payload="$(dns_curl "${list_url}")"
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
