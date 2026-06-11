#!/usr/bin/env bash
# Resolve IAM/cloud project display name from SELECTEL_PROJECT_ID (stdout).
# DNS API v2 Keystone token must use scope.project.name; id scope returns zero zones.
set -euo pipefail

AUTH_URL="${OS_AUTH_URL:-https://cloud.api.selcloud.ru/identity/v3}"
VPC_API="${SELECTEL_VPC_API:-https://api.selectel.ru/vpc/resell/v2}"

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} (run prepare-openstack-env.sh first)" >&2
    exit 1
  fi
done

override="$(trim "${SELECTEL_IAM_PROJECT_NAME:-}")"
if [ -n "${override}" ]; then
  printf '%s' "${override}"
  exit 0
fi

project_hex="$(printf '%s' "${OS_PROJECT_ID}" | tr 'A-Z' 'a-z' | tr -d '-' | sed 's/[^0-9a-f]//g')"
project_uuid="${OS_PROJECT_ID}"
if [ "${#project_hex}" -eq 32 ]; then
  project_uuid="$(printf '%s-%s-%s-%s-%s' \
    "${project_hex:0:8}" "${project_hex:8:4}" "${project_hex:16:4}" \
    "${project_hex:20:4}" "${project_hex:24:12}")"
fi

request_account_token() {
  local body http_code token headers_file response_file
  body="$(jq -n \
    --arg user "$OS_USERNAME" \
    --arg domain "$OS_DOMAIN_NAME" \
    --arg password "$OS_PASSWORD" \
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
          domain: { name: $domain }
        }
      }
    }')"

  headers_file="$(mktemp)"
  response_file="$(mktemp)"

  http_code="$(curl -sS -o "${response_file}" -D "${headers_file}" -w "%{http_code}" \
    -X POST "${AUTH_URL}/auth/tokens" \
    -H "Content-Type: application/json" \
    -d "${body}")"

  if [ "${http_code}" != "201" ]; then
    rm -f "${headers_file}" "${response_file}"
    return 1
  fi

  token="$(awk 'BEGIN { IGNORECASE=1 } /^x-subject-token:/ { sub(/^[^:]*:[ \t]*/, ""); gsub(/\r$/, ""); print; exit }' "${headers_file}")"
  rm -f "${headers_file}" "${response_file}"
  if [ -z "${token}" ]; then
    return 1
  fi
  printf '%s' "${token}"
}

fetch_project_name() {
  local token="$1"
  local ref="$2"
  local response_file http_code name
  response_file="$(mktemp)"
  http_code="$(curl -sS -o "${response_file}" -w "%{http_code}" \
    -X GET "${VPC_API}/projects/${ref}?exclude_quotas=true" \
    -H "X-Auth-Token: ${token}" \
    -H "Accept: application/json")"
  if [ "${http_code}" != "200" ]; then
    rm -f "${response_file}"
    return 1
  fi
  name="$(jq -r '.project.name // empty' "${response_file}")"
  rm -f "${response_file}"
  if [ -n "${name}" ] && [ "${name}" != "null" ]; then
    printf '%s' "${name}"
    return 0
  fi
  return 1
}

account_token="$(request_account_token)" || account_token=""
if [ -n "${account_token}" ]; then
  for ref in "${project_uuid}" "${project_hex}"; do
    if name="$(fetch_project_name "${account_token}" "${ref}")"; then
      echo "Resolved project name from SELECTEL_PROJECT_ID: ${name}" >&2
      printf '%s' "${name}"
      exit 0
    fi
  done
fi

echo "::error::Could not resolve IAM project name from SELECTEL_PROJECT_ID (${project_hex:0:8}...${project_hex: -4})" >&2
echo "Checklist:" >&2
echo "  - SELECTEL_PROJECT_ID is correct (same id in IAM → Projects and Cloud)" >&2
echo "  - Service user needs account-scoped IAM permission to read project metadata, OR" >&2
echo "  - Set SELECTEL_IAM_PROJECT_NAME = project name from IAM → Projects (override)" >&2
exit 1
