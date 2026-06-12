#!/usr/bin/env bash
# Ensure Selectel LE certificate (DNS-01, dnsv2) exists for RELAY_HOSTNAME.
# Prints knox_cert_id to stdout; sets knox_cert_id in GITHUB_OUTPUT when set.
set -euo pipefail

LE_API="${SELECTEL_LE_API:-https://api.selectel.ru/certs/le}"
POLL_INTERVAL="${RELAY_LE_POLL_INTERVAL:-15}"
POLL_TIMEOUT="${RELAY_LE_POLL_TIMEOUT:-600}"

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

relay_hostname="$(trim "${RELAY_HOSTNAME:-}" | tr '[:upper:]' '[:lower:]')"
knox_override="$(trim "${RELAY_TLS_KNOX_CERT_ID:-}")"

if [ -z "${relay_hostname}" ]; then
  echo "::error::RELAY_HOSTNAME is required"
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(bash "${script_dir}/get-selectel-dns-token.sh")"

le_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  local response_file http_code
  response_file="$(mktemp)"

  if [ -n "${body}" ]; then
    http_code="$(curl -sS -o "${response_file}" -w "%{http_code}" \
      -X "${method}" "${LE_API}${path}" \
      -H "X-Auth-Token: ${token}" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d "${body}")"
  else
    http_code="$(curl -sS -o "${response_file}" -w "%{http_code}" \
      -X "${method}" "${LE_API}${path}" \
      -H "X-Auth-Token: ${token}" \
      -H "Accept: application/json")"
  fi

  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
    cat "${response_file}"
    rm -f "${response_file}"
    return 0
  fi

  echo "::error::Selectel LE API ${method} ${path} failed (HTTP ${http_code})" >&2
  jq . "${response_file}" 2>/dev/null >&2 || cat "${response_file}" >&2
  rm -f "${response_file}"
  return 1
}

status_ready() {
  local status
  status="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${status}" in
    active | renewing) return 0 ;;
    *) return 1 ;;
  esac
}

status_failed() {
  local status
  status="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${status}" in
    error | invalid | failed) return 0 ;;
    *) return 1 ;;
  esac
}

pick_le_cert_for_host() {
  local list_json="$1"
  jq -c --arg host "${relay_hostname}" '
    [.items[]?
      | select((.deleted_at // null) == null)
      | select(.domains[]? == $host)
      | select((.status // "" | ascii_downcase) as $s | ($s != "error" and $s != "invalid" and $s != "failed"))
    ]
    | sort_by(.updated_at // .created_at // "")
    | last // empty
  ' <<< "${list_json}"
}

pick_le_cert_by_knox() {
  local list_json="$1"
  local knox_id="$2"
  jq -c --arg knox "${knox_id}" '
    [.items[]?
      | select((.deleted_at // null) == null)
      | select(.knox_cert_id == $knox)
    ]
    | last // empty
  ' <<< "${list_json}"
}

wait_for_ready() {
  local le_cert_id="$1"
  local deadline=$((SECONDS + POLL_TIMEOUT))
  local knox_cert_id=""

  while [ "${SECONDS}" -lt "${deadline}" ]; do
    list_json="$(le_request GET "/")"
    item="$(jq -c --arg id "${le_cert_id}" '
      [.items[]? | select(.id == $id)] | last // empty
    ' <<< "${list_json}")"

    if [ -z "${item}" ] || [ "${item}" = "null" ]; then
      echo "::error::LE certificate id=${le_cert_id} disappeared from list API" >&2
      exit 1
    fi

    status="$(jq -r '.status // "unknown"' <<< "${item}")"
    knox_cert_id="$(jq -r '.knox_cert_id // empty' <<< "${item}")"
    echo "LE cert id=${le_cert_id}: status=${status} knox_cert_id=${knox_cert_id:-pending}" >&2

    if status_failed "${status}"; then
      err="$(jq -r '.error_description // empty' <<< "${item}")"
      echo "::error::LE certificate id=${le_cert_id} status=${status} ${err}" >&2
      echo "Check NS delegation to Selectel (a/b/c/d.ns.selectel.ru) for DNS-01." >&2
      exit 1
    fi

    if [ -n "${knox_cert_id}" ] && [ "${knox_cert_id}" != "null" ] && status_ready "${status}"; then
      printf '%s' "${knox_cert_id}"
      return 0
    fi

    sleep "${POLL_INTERVAL}"
  done

  echo "::error::Timed out after ${POLL_TIMEOUT}s waiting for LE cert id=${le_cert_id} (DNS-01)" >&2
  exit 1
}

list_json="$(le_request GET "/")"
le_cert_id=""
knox_cert_id=""

if [ -n "${knox_override}" ]; then
  item="$(pick_le_cert_by_knox "${list_json}" "${knox_override}")"
  if [ -n "${item}" ] && [ "${item}" != "null" ]; then
    le_cert_id="$(jq -r '.id' <<< "${item}")"
    knox_cert_id="$(jq -r '.knox_cert_id // empty' <<< "${item}")"
    echo "Using LE certificate from RELAY_TLS_KNOX_CERT_ID: le_id=${le_cert_id}" >&2
  else
    echo "::warning::RELAY_TLS_KNOX_CERT_ID not in LE list; will poll Knox directly after issue lookup" >&2
    knox_cert_id="${knox_override}"
  fi
else
  item="$(pick_le_cert_for_host "${list_json}")"
  if [ -n "${item}" ] && [ "${item}" != "null" ]; then
    le_cert_id="$(jq -r '.id' <<< "${item}")"
    knox_cert_id="$(jq -r '.knox_cert_id // empty' <<< "${item}")"
    echo "Using existing LE certificate for ${relay_hostname}: le_id=${le_cert_id}" >&2
  fi
fi

if [ -z "${le_cert_id}" ]; then
  if [ -n "${knox_cert_id}" ]; then
    echo "Knox id provided without LE list match — cannot poll issue status" >&2
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "knox_cert_id=${knox_cert_id}" >> "${GITHUB_OUTPUT}"
    fi
    printf '%s' "${knox_cert_id}"
    exit 0
  fi

  cert_name="nhmind-relay-${relay_hostname}"
  echo "Issuing Selectel LE certificate for ${relay_hostname} (DNS-01, dnsv2)..." >&2
  issue_json="$(le_request POST "/issue?dnsv2=true" "$(jq -n \
    --arg name "${cert_name}" \
    --arg host "${relay_hostname}" \
    '{name: $name, domains: [$host]}')")"
  le_cert_id="$(jq -r '.id // empty' <<< "${issue_json}")"
  if [ -z "${le_cert_id}" ]; then
    echo "::error::LE issue response missing id" >&2
    jq . <<< "${issue_json}" >&2
    exit 1
  fi
  echo "LE issue started: id=${le_cert_id} (knox_cert_id pending)" >&2
fi

knox_cert_id="$(wait_for_ready "${le_cert_id}")"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "knox_cert_id=${knox_cert_id}"
    echo "le_cert_id=${le_cert_id}"
  } >> "${GITHUB_OUTPUT}"
fi

printf '%s' "${knox_cert_id}"
