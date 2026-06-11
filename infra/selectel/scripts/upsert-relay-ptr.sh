#!/usr/bin/env bash
# Create or update PTR for relay floating IP (Selectel IPAM API v1).
set -euo pipefail

PTR_API_BASE="${SELECTEL_PTR_API_BASE:-https://api.selectel.ru/ipam/v1}"
TTL="${RELAY_PTR_TTL:-86400}"

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

normalize_ptr_hostname() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\.$//'
}

ptr_content_matches() {
  [ "$(normalize_ptr_hostname "$1")" = "$(normalize_ptr_hostname "$2")" ]
}

token="$(trim "${SELECTEL_STATIC_TOKEN:-}")"
public_ip="$(trim "${PUBLIC_IP:-}")"
hostname="$(normalize_ptr_hostname "$(trim "${RELAY_HOSTNAME:-}")")"

if [ -z "${token}" ] || [ -z "${public_ip}" ] || [ -z "${hostname}" ]; then
  echo "::error::SELECTEL_STATIC_TOKEN, PUBLIC_IP, and RELAY_HOSTNAME are required"
  exit 1
fi

if ! printf '%s' "${public_ip}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "::error::PUBLIC_IP must be IPv4"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required"
  exit 1
fi

api_base="${PTR_API_BASE%/}"
auth_header=(-H "X-Token: ${token}" -H "Content-Type: application/json" -H "Accept: application/json")

find_ptr_record_by_ip() {
  local offset=0
  local limit=1000
  while true; do
    local payload
    payload="$(curl -sS "${auth_header[@]}" "${api_base}/?limit=${limit}&offset=${offset}")"
    local record
    record="$(printf '%s' "${payload}" | jq -c --arg ip "${public_ip}" '
      if type == "array" then .
      elif (.result? | type) == "array" then .result
      else [] end
      | map(select(.ip == $ip)) | .[0] // empty
    ')"
    if [ -n "${record}" ] && [ "${record}" != "null" ]; then
      printf '%s' "${record}"
      return 0
    fi
    local count
    count="$(printf '%s' "${payload}" | jq -r 'if type == "array" then length elif (.result? | type) == "array" then (.result | length) else 0 end')"
    if [ "${count}" -lt "${limit}" ]; then
      return 1
    fi
    offset=$((offset + limit))
  done
}

get_ptr_record_by_id() {
  local ptr_id="$1"
  curl -sS "${auth_header[@]}" "${api_base}/${ptr_id}"
}

ptr_already_set_message() {
  echo "PTR already set (${public_ip} -> ${hostname})"
}

verify_ptr_state() {
  local record="$1"
  local current_content
  current_content="$(printf '%s' "${record}" | jq -r '.content // ""')"
  if ptr_content_matches "${current_content}" "${hostname}"; then
    ptr_already_set_message
    return 0
  fi
  return 1
}

update_ptr() {
  local ptr_id="$1"
  local body
  body="$(jq -n --arg content "${hostname}" '{ content: $content }')"
  local http_code
  http_code="$(curl -sS -o ptr-response.json -w "%{http_code}" \
    -X PUT "${auth_header[@]}" \
    "${api_base}/${ptr_id}" \
    -d "${body}")"
  case "${http_code}" in
    200)
      echo "PTR updated (${public_ip} -> ${hostname}, id=${ptr_id})"
      return 0
      ;;
    409)
      if verify_ptr_state "$(get_ptr_record_by_id "${ptr_id}")"; then
        return 0
      fi
      echo "::error::PTR PUT returned HTTP 409 (conflict)"
      cat ptr-response.json || true
      return 1
      ;;
    *)
      echo "::error::PTR PUT returned HTTP ${http_code}"
      cat ptr-response.json || true
      return 1
      ;;
  esac
}

create_ptr() {
  local body
  body="$(jq -n \
    --arg ip "${public_ip}" \
    --arg content "${hostname}" \
    --argjson ttl "${TTL}" \
    '{ ip: $ip, content: $content, ttl: $ttl }')"
  local http_code
  http_code="$(curl -sS -o ptr-response.json -w "%{http_code}" \
    -X POST "${auth_header[@]}" \
    "${api_base}/" \
    -d "${body}")"
  case "${http_code}" in
    200|201)
      echo "PTR created (${public_ip} -> ${hostname})"
      return 0
      ;;
    409)
      return 2
      ;;
    405)
      echo "::error::PTR POST returned HTTP 405 at ${api_base}/ — wrong API base URL"
      cat ptr-response.json || true
      return 1
      ;;
    *)
      echo "::error::PTR POST returned HTTP ${http_code}"
      cat ptr-response.json || true
      return 1
      ;;
  esac
}

echo "Selectel IPAM PTR: ${public_ip} -> ${hostname} (${api_base})"

if record="$(find_ptr_record_by_ip)"; then
  ptr_id="$(printf '%s' "${record}" | jq -r '.id')"
  if verify_ptr_state "${record}"; then
    exit 0
  fi
  update_ptr "${ptr_id}"
  exit $?
fi

if create_ptr; then
  exit 0
fi

create_status=$?
if [ "${create_status}" -eq 2 ]; then
  if record="$(find_ptr_record_by_ip)"; then
    ptr_id="$(printf '%s' "${record}" | jq -r '.id')"
    if verify_ptr_state "${record}"; then
      exit 0
    fi
    update_ptr "${ptr_id}"
    exit $?
  fi
  echo "::error::PTR exists (409) but could not resolve record for ${public_ip}"
  exit 1
fi

exit 1
