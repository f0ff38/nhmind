#!/usr/bin/env bash
# Shared helpers for Selectel DNS API v2 scripts. Source from infra/selectel/scripts.

DNS_API="${SELECTEL_DNS_API:-https://api.selectel.ru/domains/v2}"
TTL="${RELAY_DNS_TTL:-300}"
TOTAL_ZONES_REPORT="${TOTAL_ZONES_REPORT:-}"

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

default_zone_for_hostname() {
  local hostname_no_dot
  hostname_no_dot="$(normalize_zone_label "$1")"
  local label_count
  label_count="$(printf '%s' "${hostname_no_dot}" | tr -cd '.' | wc -c | tr -d ' ')"
  if [ "${label_count}" -le 1 ]; then
    to_fqdn "${hostname_no_dot}"
  else
    to_fqdn "${hostname_no_dot#*.}"
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required"
    exit 1
  fi
}

init_dns_token() {
  local scripts_dir="${1:?scripts dir required}"
  SELECTEL_DNS_TOKEN="$(bash "${scripts_dir}/get-selectel-dns-token.sh" | tr -d '\r\n')"
  SELECTEL_DNS_TOKEN="$(trim "${SELECTEL_DNS_TOKEN}")"
  export SELECTEL_DNS_TOKEN
  if [ -z "${SELECTEL_DNS_TOKEN}" ]; then
    echo "::error::Selectel DNS token is empty"
    exit 1
  fi
}

dns_curl() {
  curl -sS \
    -H "X-Auth-Token: ${SELECTEL_DNS_TOKEN:?init_dns_token first}" \
    -H "Accept: application/json" \
    "$@"
}

dns_json_curl() {
  curl -sS \
    -H "X-Auth-Token: ${SELECTEL_DNS_TOKEN:?init_dns_token first}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$@"
}

list_zones_page() {
  local offset="$1"
  local limit="$2"
  local filter="${3:-}"
  local -a args=(
    -G "${DNS_API}/zones"
    --data-urlencode "limit=${limit}"
    --data-urlencode "offset=${offset}"
  )
  if [ -n "${filter}" ]; then
    args+=(--data-urlencode "filter=${filter}")
  fi
  dns_curl "${args[@]}"
}

count_visible_zones() {
  local payload
  payload="$(list_zones_page 0 1)"
  printf '%s' "${payload}" | jq -r 'if (.count? | type) == "number" then .count elif (.result? | type) == "array" then (.result | length) else 0 end'
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
