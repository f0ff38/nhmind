#!/usr/bin/env bash
# Project IAM token for Selectel DNS API v2 (stdout).
# Same SELECTEL_PROJECT_ID as Terraform; DNS Keystone scope uses project *name* (auto-resolved).
set -euo pipefail

AUTH_URL="${OS_AUTH_URL:-https://cloud.api.selcloud.ru/identity/v3}"
DNS_API="${SELECTEL_DNS_API:-https://api.selectel.ru/domains/v2}"

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} (run prepare-openstack-env.sh first)" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zone_id_probe="$(printf '%s' "${RELAY_DNS_ZONE_ID:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

project_hex="$(printf '%s' "${OS_PROJECT_ID}" | tr 'A-Z' 'a-z' | tr -d '-' | sed 's/[^0-9a-f]//g')"
project_uuid="${OS_PROJECT_ID}"
if [ "${#project_hex}" -eq 32 ]; then
  project_uuid="$(printf '%s-%s-%s-%s-%s' \
    "${project_hex:0:8}" "${project_hex:8:4}" "${project_hex:16:4}" \
    "${project_hex:20:4}" "${project_hex:24:12}")"
fi

iam_project_name="$(bash "${script_dir}/resolve-selectel-project-name.sh")"

request_project_token() {
  local label="$1"
  local scope_mode="$2"
  local project_ref="$3"

  local body
  if [ "${scope_mode}" = "name" ]; then
    body="$(jq -n \
      --arg user "$OS_USERNAME" \
      --arg domain "$OS_DOMAIN_NAME" \
      --arg password "$OS_PASSWORD" \
      --arg project "$project_ref" \
      '{
        auth: {
          identity: {
            methods: ["password"],
            password: {
              user: {
                name: $user,
                domain: { name: $domain },
                password: $password
              }
            }
          },
          scope: {
            project: {
              name: $project,
              domain: { name: $domain }
            }
          }
        }
      }')"
  else
    body="$(jq -n \
      --arg user "$OS_USERNAME" \
      --arg domain "$OS_DOMAIN_NAME" \
      --arg password "$OS_PASSWORD" \
      --arg project "$project_ref" \
      '{
        auth: {
          identity: {
            methods: ["password"],
            password: {
              user: {
                name: $user,
                domain: { name: $domain },
                password: $password
              }
            }
          },
          scope: {
            project: { id: $project }
          }
        }
      }')"
  fi

  local headers_file response_file http_code token
  headers_file="$(mktemp)"
  response_file="$(mktemp)"

  http_code="$(curl -sS -o "${response_file}" -D "${headers_file}" -w "%{http_code}" \
    -X POST "${AUTH_URL}/auth/tokens" \
    -H "Content-Type: application/json" \
    -d "${body}")"

  if [ "${http_code}" = "201" ]; then
    token="$(awk 'BEGIN { IGNORECASE=1 } /^x-subject-token:/ { sub(/^[^:]*:[ \t]*/, ""); gsub(/\r$/, ""); print; exit }' "${headers_file}")"
    rm -f "${headers_file}" "${response_file}"
    if [ -n "${token}" ]; then
      printf '%s' "${token}"
      return 0
    fi
    echo "::error::Keystone ${label}: response missing X-Subject-Token header" >&2
    return 1
  fi

  echo "::warning::Keystone ${label} failed (HTTP ${http_code})" >&2
  jq . "${response_file}" 2>/dev/null >&2 || cat "${response_file}" >&2
  rm -f "${headers_file}" "${response_file}"
  return 1
}

dns_token_can_manage_zones() {
  local token="$1"

  if [ -n "${zone_id_probe}" ]; then
    local http_code
    http_code="$(curl -sS -o /dev/null -w "%{http_code}" \
      -X GET "${DNS_API}/zones/${zone_id_probe}" \
      -H "X-Auth-Token: ${token}" \
      -H "Accept: application/json")"
    if [ "${http_code}" = "200" ]; then
      return 0
    fi
  fi

  local http_code
  http_code="$(curl -sS -o /dev/null -w "%{http_code}" \
    -X GET "${DNS_API}/zones?limit=1" \
    -H "X-Auth-Token: ${token}" \
    -H "Accept: application/json")"
  [ "${http_code}" = "200" ]
}

declare -a scope_modes=("name")
declare -a scope_refs=("${iam_project_name}")
declare -a scope_labels=("IAM project name (from SELECTEL_PROJECT_ID)")

if [ "${#project_hex}" -eq 32 ]; then
  scope_modes+=("id")
  scope_refs+=("${project_hex}")
  scope_labels+=("project hex id")
fi
if [ "${project_uuid}" != "${project_hex}" ]; then
  scope_modes+=("id")
  scope_refs+=("${project_uuid}")
  scope_labels+=("project uuid id")
fi

keystone_ok=0
for i in "${!scope_modes[@]}"; do
  mode="${scope_modes[$i]}"
  ref="${scope_refs[$i]}"
  label="${scope_labels[$i]}"
  token="$(request_project_token "${label}" "${mode}" "${ref}")" || continue
  keystone_ok=1
  if dns_token_can_manage_zones "${token}"; then
    echo "Selectel DNS token scope: ${label}" >&2
    if [ -z "${zone_id_probe}" ]; then
      echo "::warning::DNS zone list may be empty — upsert-relay-dns-a.sh will POST /zones if needed" >&2
    fi
    printf '%s' "${token}"
    exit 0
  fi
  echo "::warning::Keystone OK (${label}) but DNS API rejected token (non-200)" >&2
done

if [ "${keystone_ok}" -eq 0 ]; then
  echo "::error::Keystone project token failed for DNS (no scope accepted credentials)" >&2
else
  echo "::error::Keystone token obtained but Selectel DNS API rejected every scope" >&2
fi

echo "Checklist:" >&2
echo "  - SELECTEL_PROJECT_ID is the same project id as IAM → Projects (correct)" >&2
echo "  - Empty zone list is OK — provision creates DNS hosting zone via POST /zones" >&2
echo "  - Service user IAM permission must include DNS hosting on this project" >&2
exit 1
