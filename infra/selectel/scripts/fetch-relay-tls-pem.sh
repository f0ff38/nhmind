#!/usr/bin/env bash
# Download TLS PEM files from Selectel Certificate Manager (Knox) into output_dir.
# Usage: fetch-relay-tls-pem.sh <output_dir> [knox_cert_id]
set -euo pipefail

output_dir="${1:?usage: fetch-relay-tls-pem.sh <output_dir> [knox_cert_id]}"
knox_cert_id="${2:-${RELAY_TLS_KNOX_CERT_ID:-}}"

if [ -z "${knox_cert_id}" ]; then
  echo "::error::knox_cert_id is required (arg or RELAY_TLS_KNOX_CERT_ID)"
  exit 1
fi

CERT_API="${SELECTEL_CERT_API:-https://cloud.api.selcloud.ru/certificate-manager/v1}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(bash "${script_dir}/get-selectel-dns-token.sh")"

mkdir -p "${output_dir}"
chmod 700 "${output_dir}"

cert_request() {
  local path="$1"
  local out_file="$2"

  local response_file headers_file http_code content_type
  response_file="$(mktemp)"
  headers_file="$(mktemp)"

  http_code="$(curl -sS -o "${response_file}" -D "${headers_file}" -w "%{http_code}" \
    -X GET "${CERT_API}${path}" \
    -H "X-Auth-Token: ${token}" \
    -H "Accept: application/json, text/plain")"

  if [ "${http_code}" -lt 200 ] || [ "${http_code}" -ge 300 ]; then
    echo "::error::Certificate Manager GET ${path} failed (HTTP ${http_code})" >&2
    cat "${response_file}" >&2
    rm -f "${response_file}" "${headers_file}"
    return 1
  fi

  content_type="$(awk 'BEGIN { IGNORECASE=1 } /^content-type:/ { sub(/^[^:]*:[ \t]*/, ""); gsub(/\r$/, ""); print; exit }' "${headers_file}")"
  if printf '%s' "${content_type}" | grep -qi 'application/json'; then
    jq -r '
      if type == "string" then .
      elif .private_key? then .private_key
      elif .pem?.private_key? then .pem.private_key
      elif .certificates? then (.certificates | join("\n"))
      elif .pem?.certificates? then (.pem.certificates | join("\n"))
      elif .ca_chain? then (.ca_chain | if type == "array" then join("\n") else . end)
      else empty end
    ' "${response_file}" > "${out_file}"
  else
    cp "${response_file}" "${out_file}"
  fi

  rm -f "${response_file}" "${headers_file}"
}

privkey_file="${output_dir}/privkey.pem"
chain_file="${output_dir}/fullchain.pem"
tmp_chain="$(mktemp)"

cert_request "/cert/${knox_cert_id}/private_key" "${privkey_file}"
cert_request "/cert/${knox_cert_id}/ca_chain" "${tmp_chain}"

if [ ! -s "${privkey_file}" ] || ! grep -q 'BEGIN.*PRIVATE KEY' "${privkey_file}"; then
  echo "::error::Downloaded private key is empty or not PEM"
  exit 1
fi

if [ -s "${tmp_chain}" ] && grep -q 'BEGIN CERTIFICATE' "${tmp_chain}"; then
  cp "${tmp_chain}" "${chain_file}"
else
  cert_meta="$(mktemp)"
  http_code="$(curl -sS -o "${cert_meta}" -w "%{http_code}" \
    -X GET "${CERT_API}/cert/${knox_cert_id}" \
    -H "X-Auth-Token: ${token}" \
    -H "Accept: application/json")"
  if [ "${http_code}" -lt 200 ] || [ "${http_code}" -ge 300 ]; then
    echo "::error::Certificate Manager GET /cert/${knox_cert_id} failed (HTTP ${http_code})" >&2
    exit 1
  fi
  jq -r '
    if .pem?.certificates? then (.pem.certificates | join("\n"))
    elif .certificates? then (.certificates | join("\n"))
    else empty end
  ' "${cert_meta}" > "${chain_file}"
  rm -f "${cert_meta}"
fi
rm -f "${tmp_chain}"

if [ ! -s "${chain_file}" ] || ! grep -q 'BEGIN CERTIFICATE' "${chain_file}"; then
  echo "::error::Downloaded certificate chain is empty or not PEM"
  exit 1
fi

chmod 600 "${privkey_file}" "${chain_file}"
echo "TLS PEM written to ${output_dir} (privkey + fullchain)" >&2
