#!/usr/bin/env bash
# Create or update PTR for relay floating IP (Selectel IPAM API v1).
set -euo pipefail

PTR_API_BASE="${SELECTEL_PTR_API_BASE:-https://api.selectel.ru/ipam/v1}"
TTL="${RELAY_PTR_TTL:-86400}"

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

token="$(trim "${SELECTEL_STATIC_TOKEN:-}")"
public_ip="$(trim "${PUBLIC_IP:-}")"
hostname="$(trim "${RELAY_HOSTNAME:-}")"

if [ -z "${token}" ] || [ -z "${public_ip}" ] || [ -z "${hostname}" ]; then
  echo "::error::SELECTEL_STATIC_TOKEN, PUBLIC_IP, and RELAY_HOSTNAME are required"
  exit 1
fi

if ! printf '%s' "${public_ip}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "::error::PUBLIC_IP must be IPv4"
  exit 1
fi

hostname="$(printf '%s' "${hostname}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\.$//')"
if [ -z "${hostname}" ]; then
  echo "::error::RELAY_HOSTNAME is empty after normalization"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required"
  exit 1
fi

api_base="${PTR_API_BASE%/}"
auth_header=(-H "X-Token: ${token}" -H "Content-Type: application/json" -H "Accept: application/json")

find_ptr_id_by_ip() {
  local offset=0
  local limit=1000
  while true; do
    local payload
    payload="$(curl -sS "${auth_header[@]}" "${api_base}/?limit=${limit}&offset=${offset}")"
    local ptr_id
    ptr_id="$(printf '%s' "${payload}" | jq -r --arg ip "${public_ip}" '
      if type == "array" then .
      elif (.result? | type) == "array" then .result
      else [] end
      | map(select(.ip == $ip)) | .[0].id // empty
    ')"
    if [ -n "${ptr_id}" ] && [ "${ptr_id}" != "null" ]; then
      printf '%s' "${ptr_id}"
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

update_ptr() {
  local ptr_id="$1"
  local body
  body="$(jq -n --arg ip "${public_ip}" --arg content "${hostname}" '{ ip: $ip, content: $content }')"
  local http_code
  http_code="$(curl -sS -o ptr-response.json -w "%{http_code}" \
    -X PUT "${auth_header[@]}" \
    "${api_base}/${ptr_id}" \
    -d "${body}")"
  if [ "${http_code}" = "200" ]; then
    echo "PTR updated (${public_ip} -> ${hostname}, id=${ptr_id})"
    return 0
  fi
  echo "::error::PTR PUT returned HTTP ${http_code}"
  cat ptr-response.json || true
  return 1
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
      echo "PTR already exists for ${public_ip}; updating..."
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

if ptr_id="$(find_ptr_id_by_ip)"; then
  update_ptr "${ptr_id}"
  exit 0
fi

if create_ptr; then
  exit 0
fi

create_status=$?
if [ "${create_status}" -eq 2 ]; then
  ptr_id="$(find_ptr_id_by_ip)" || true
  if [ -n "${ptr_id:-}" ]; then
    update_ptr "${ptr_id}"
    exit 0
  fi
  echo "::error::PTR exists (409) but could not resolve ptr_id for ${public_ip}"
  exit 1
fi

exit 1
