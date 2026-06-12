#!/usr/bin/env bash
# Upsert TXT records on _acu.<RELAY_HOSTNAME> for Acurast processor whitelist.
# Each ACURAST_TXT_V value is v=base64(sha256(deployment_source || host)).
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
zone_override="$(trim "${RELAY_DNS_ZONE:-}")"
zone_id_override="$(trim "${RELAY_DNS_ZONE_ID:-}")"
txt_values_raw="$(trim "${ACURAST_TXT_V:-}")"

if [ -z "${relay_hostname_raw}" ]; then
  echo "::error::RELAY_HOSTNAME is required"
  exit 1
fi

if [ -z "${txt_values_raw}" ]; then
  echo "::error::ACURAST_TXT_V is required (space-separated v=... values)"
  exit 1
fi

relay_host="$(normalize_zone_label "${relay_hostname_raw}")"
rrset_fqdn="$(to_fqdn "_acu.${relay_host}")"

if [ -n "${zone_override}" ]; then
  zone_fqdn="$(to_fqdn "${zone_override}")"
else
  label_count="$(printf '%s' "${relay_host}" | tr -cd '.' | wc -c | tr -d ' ')"
  if [ "${label_count}" -le 1 ]; then
    zone_fqdn="$(to_fqdn "${relay_host}")"
  else
    zone_fqdn="$(to_fqdn "${relay_host#*.}")"
  fi
fi

case "${rrset_fqdn}" in
  *."${zone_fqdn}") ;;
  *)
    echo "::error::_acu.${relay_host} is not inside zone ${zone_fqdn} (set RELAY_DNS_ZONE if needed)"
    exit 1
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required"
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(bash "${script_dir}/get-selectel-dns-token.sh" | tr -d '\r\n')"
token="$(trim "${token}")"

if [ -z "${token}" ]; then
  echo "::error::Selectel DNS token is empty"
  exit 1
fi

dns_curl() {
  curl -sS \
    -H "X-Auth-Token: ${token}" \
    -H "Accept: application/json" \
    "$@"
}

dns_json_curl() {
  curl -sS \
    -H "X-Auth-Token: ${token}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$@"
}

find_zone_id_by_name() {
  local want_zone="$1"
  local offset=0
  local limit=100
  while true; do
    local payload
    payload="$(dns_curl -G "${DNS_API}/zones" \
      --data-urlencode "limit=${limit}" \
      --data-urlencode "offset=${offset}")"
    local id
    id="$(printf '%s' "${payload}" | jq -r --arg z "${want_zone}" '
      (.result // [])[] | select((.name // "") | ascii_downcase == ($z | ascii_downcase)) | .id
    ' | head -n 1)"
    if [ -n "${id}" ]; then
      printf '%s' "${id}"
      return 0
    fi
    local count
    count="$(printf '%s' "${payload}" | jq -r '(.result // []) | length')"
    if [ "${count}" -lt "${limit}" ]; then
      return 1
    fi
    offset=$((offset + limit))
  done
}

resolve_zone_id() {
  if [ -n "${zone_id_override}" ]; then
    printf '%s' "${zone_id_override}"
    return 0
  fi
  find_zone_id_by_name "${zone_fqdn}"
}

zone_id="$(resolve_zone_id || true)"
if [ -z "${zone_id}" ] || [ "${zone_id}" = "null" ]; then
  echo "::error::DNS zone ${zone_fqdn} not found for _acu TXT upsert"
  exit 1
fi

declare -a desired_values=()
while IFS= read -r line; do
  value="$(trim "${line}")"
  if [ -n "${value}" ]; then
    desired_values+=("${value}")
  fi
done <<EOF
$(printf '%s' "${txt_values_raw}" | tr ' ' '\n')
EOF

if [ "${#desired_values[@]}" -eq 0 ]; then
  echo "::error::No valid v= values in ACURAST_TXT_V"
  exit 1
fi

records_json="$(printf '%s\n' "${desired_values[@]}" | jq -R -s '
  split("\n")
  | map(select(length > 0))
  | map({ content: ., disabled: false })
')"

patch_body="$(jq -n \
  --argjson ttl "${TTL}" \
  --argjson records "${records_json}" \
  '{
    ttl: $ttl,
    records: $records,
    comment: "nhmind Acurast whitelist (managed by deploy-canary / relay ops)"
  }')"

echo "Selectel DNS: upsert TXT ${rrset_fqdn} (${#desired_values[@]} record(s)) in zone ${zone_fqdn}"

rrsets_payload="$(dns_curl -G "${DNS_API}/zones/${zone_id}/rrset" \
  --data-urlencode "name=${rrset_fqdn}" \
  --data-urlencode "rrset_types=TXT")"
rrset_id="$(printf '%s' "${rrsets_payload}" | jq -r '.result[0].id // empty')"

if [ -n "${rrset_id}" ]; then
  http_code="$(dns_json_curl -o dns-response.json -w "%{http_code}" \
    -X PATCH \
    "${DNS_API}/zones/${zone_id}/rrset/${rrset_id}" \
    -d "${patch_body}")"
  if [ "${http_code}" = "204" ]; then
    echo "DNS TXT updated: ${rrset_fqdn}"
    exit 0
  fi
  echo "::error::DNS TXT PATCH returned HTTP ${http_code}"
  cat dns-response.json || true
  exit 1
fi

create_body="$(jq -n \
  --arg name "${rrset_fqdn}" \
  --argjson ttl "${TTL}" \
  --argjson records "${records_json}" \
  '{
    name: $name,
    type: "TXT",
    ttl: $ttl,
    records: $records,
    comment: "nhmind Acurast whitelist (managed by deploy-canary / relay ops)"
  }')"

http_code="$(dns_json_curl -o dns-response.json -w "%{http_code}" \
  -X POST \
  "${DNS_API}/zones/${zone_id}/rrset" \
  -d "${create_body}")"

if [ "${http_code}" = "200" ]; then
  echo "DNS TXT created: ${rrset_fqdn}"
  exit 0
fi

echo "::error::DNS TXT POST returned HTTP ${http_code}"
cat dns-response.json || true
exit 1
