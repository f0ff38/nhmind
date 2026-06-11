#!/usr/bin/env bash
# Project IAM token for Selectel DNS API v2 (stdout).
# DNS requires Keystone scope by IAM project *name*; cloud hex id often returns zero zones.
set -euo pipefail

AUTH_URL="${OS_AUTH_URL:-https://cloud.api.selcloud.ru/identity/v3}"
DNS_API="${SELECTEL_DNS_API:-https://api.selectel.ru/domains/v2}"

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} (run prepare-openstack-env.sh first)" >&2
    exit 1
  fi
done

project_hex="$(printf '%s' "${OS_PROJECT_ID}" | tr 'A-Z' 'a-z' | tr -d '-' | sed 's/[^0-9a-f]//g')"
project_uuid="${OS_PROJECT_ID}"
if [ "${#project_hex}" -eq 32 ]; then
  project_uuid="$(printf '%s-%s-%s-%s-%s' \
    "${project_hex:0:8}" "${project_hex:8:4}" "${project_hex:16:4}" \
    "${project_hex:20:4}" "${project_hex:24:12}")"
fi

iam_project_name="$(printf '%s' "${SELECTEL_IAM_PROJECT_NAME:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
zone_id_probe="$(printf '%s' "${RELAY_DNS_ZONE_ID:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

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

  local payload zone_count
  payload="$(curl -sS \
    -X GET "${DNS_API}/zones?limit=1" \
    -H "X-Auth-Token: ${token}" \
    -H "Accept: application/json")"
  zone_count="$(printf '%s' "${payload}" | jq -r 'if (.count? | type) == "number" then .count elif (.result? | type) == "array" then (.result | length) else 0 end')"
  if [ "${zone_count:-0}" -gt 0 ] 2>/dev/null; then
    return 0
  fi
  return 1
}

declare -a scope_modes=()
declare -a scope_refs=()
declare -a scope_labels=()

if [ -n "${iam_project_name}" ]; then
  scope_modes+=("name")
  scope_refs+=("${iam_project_name}")
  scope_labels+=("IAM project name")
fi
if [ "${#project_hex}" -eq 32 ]; then
  scope_modes+=("id")
  scope_refs+=("${project_hex}")
  scope_labels+=("cloud project hex id")
fi
if [ "${project_uuid}" != "${project_hex}" ]; then
  scope_modes+=("id")
  scope_refs+=("${project_uuid}")
  scope_labels+=("cloud project uuid id")
fi

keystone_ok=0
for i in "${!scope_modes[@]}"; do
  mode="${scope_modes[$i]}"
  ref="${scope_refs[$i]}"
  label="${scope_labels[$i]}"
  token="$(request_project_token "${label}" "${mode}" "${ref}")" || continue
  keystone_ok=1
  if dns_token_can_manage_zones "${token}"; then
    if [ "${mode}" != "name" ]; then
      echo "::warning::DNS API works with ${label}; prefer secret SELECTEL_IAM_PROJECT_NAME (IAM → Projects → name)" >&2
    else
      echo "Selectel DNS token scope: IAM project name" >&2
    fi
    printf '%s' "${token}"
    exit 0
  fi
  echo "::warning::Keystone OK (${label}) but DNS API sees zero zones for this scope" >&2
done

if [ "${keystone_ok}" -eq 0 ]; then
  echo "::error::Keystone project token failed for DNS (no scope accepted credentials)" >&2
else
  echo "::error::Keystone token obtained but Selectel DNS API returned zero zones for every scope" >&2
fi

echo "Checklist:" >&2
echo "  - Set SELECTEL_IAM_PROJECT_NAME = IAM → Projects → project *name* (not 32 hex cloud id)" >&2
echo "  - Service user permission: Projects scope must include the DNS project" >&2
echo "  - Optional: RELAY_DNS_ZONE_ID = zone UUID from panel .../registrar/<uuid>/" >&2
echo "  - SELECTEL_PROJECT_ID (cloud hex) is for Terraform; DNS scope uses IAM project name" >&2
exit 1
