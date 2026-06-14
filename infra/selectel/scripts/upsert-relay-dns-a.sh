#!/usr/bin/env bash
# Upsert A record for RELAY_HOSTNAME in Selectel DNS (actual, API v2).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/dns-common.sh"

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
  zone_fqdn="$(default_zone_for_hostname "${hostname_no_dot}")"
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

require_jq
init_dns_token "${script_dir}"

echo "Selectel DNS: upsert A ${rrset_fqdn} -> ${public_ip} (zone ${zone_fqdn})"

create_zone_if_missing() {
  local want_zone="$1"
  local create_body http_code zone_id

  echo "Selectel DNS: creating zone ${want_zone} (DNS hosting actual)"
  create_body="$(jq -n --arg name "${want_zone}" '{ name: $name }')"
  http_code="$(dns_json_curl -o dns-zone-create.json -w "%{http_code}" \
    -X POST \
    "${DNS_API}/zones" \
    -d "${create_body}")"

  case "${http_code}" in
    200)
      zone_id="$(jq -r '.id // empty' dns-zone-create.json)"
      if [ -n "${zone_id}" ] && [ "${zone_id}" != "null" ]; then
        echo "DNS zone created: ${want_zone} (id=${zone_id})"
        printf '%s' "${zone_id}"
        return 0
      fi
      echo "::error::DNS zone POST returned 200 but response missing id"
      cat dns-zone-create.json || true
      return 1
      ;;
    409)
      echo "DNS zone already exists (409); resolving by name"
      find_zone_id_by_name "${want_zone}"
      return $?
      ;;
    *)
      echo "::error::DNS zone POST returned HTTP ${http_code}"
      cat dns-zone-create.json || true
      return 1
      ;;
  esac
}

resolve_zone_id() {
  if [ -n "${zone_id_override}" ]; then
    local payload http_code
    http_code="$(dns_curl -o dns-zone.json -w "%{http_code}" "${DNS_API}/zones/${zone_id_override}")"
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
  echo "  - SELECTEL_IAM_PROJECT_NAME override if auto-resolve from SELECTEL_PROJECT_ID fails"
  echo "  - Registrar Домены != DNS hosting Доменные зоны; script auto-creates zone via POST /zones"
  echo "  - Service user IAM permission must include DNS hosting on this project"
  if [ -n "${TOTAL_ZONES_REPORT:-}" ]; then
    echo "  - Token sees ${TOTAL_ZONES_REPORT} zone(s) in API; none matched ${zone_fqdn}"
  fi
  local sample_payload sample_names
  sample_payload="$(list_zones_page 0 5)"
  sample_names="$(printf '%s' "${sample_payload}" | jq -r '(.result // [])[:5][]?.name // empty' | paste -sd ', ' -)"
  if [ -n "${sample_names}" ]; then
    echo "  - Sample zone names from API: ${sample_names}"
  else
    echo "  - Доменные зоны = 0: will attempt POST /zones (same API as A record upsert)"
  fi
}

TOTAL_ZONES_REPORT=""
zone_id=""
if [ -n "${zone_id_override}" ]; then
  zone_id="$(resolve_zone_id || true)"
else
  TOTAL_ZONES_REPORT="$(count_visible_zones || echo 0)"
  if [ "${TOTAL_ZONES_REPORT}" = "0" ]; then
    echo "Selectel DNS: zone list empty (count=0); creating ${zone_fqdn}"
    zone_id="$(create_zone_if_missing "${zone_fqdn}" || true)"
  else
    zone_id="$(resolve_zone_id || true)"
    if [ -z "${zone_id}" ] || [ "${zone_id}" = "null" ]; then
      zone_id="$(create_zone_if_missing "${zone_fqdn}" || true)"
    fi
  fi
fi
if [ -z "${zone_id}" ] || [ "${zone_id}" = "null" ]; then
  echo "::error::DNS zone ${zone_fqdn} not found and could not be created in Selectel DNS"
  print_zone_lookup_help
  exit 1
fi

rrsets_payload="$(dns_curl -G "${DNS_API}/zones/${zone_id}/rrset" \
  --data-urlencode "name=${rrset_fqdn}" \
  --data-urlencode "rrset_types=A")"
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
  http_code="$(dns_json_curl -o dns-response.json -w "%{http_code}" \
    -X PATCH \
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

http_code="$(dns_json_curl -o dns-response.json -w "%{http_code}" \
  -X POST \
  "${DNS_API}/zones/${zone_id}/rrset" \
  -d "${create_body}")"

if [ "${http_code}" = "200" ]; then
  echo "DNS A record created: ${rrset_fqdn} -> ${public_ip}"
  exit 0
fi

echo "::error::DNS POST returned HTTP ${http_code}"
cat dns-response.json || true
exit 1
