#!/usr/bin/env bash
# Print project-scoped Keystone X-Auth-Token (stdout). Requires prepare-openstack-env.sh.
set -euo pipefail

AUTH_URL="${OS_AUTH_URL:-https://cloud.api.selcloud.ru/identity/v3}"

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

body="$(jq -n \
  --arg user "$OS_USERNAME" \
  --arg domain "$OS_DOMAIN_NAME" \
  --arg password "$OS_PASSWORD" \
  --arg project "$project_uuid" \
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

headers_file="$(mktemp)"
response_file="$(mktemp)"
trap 'rm -f "${headers_file}" "${response_file}"' EXIT

http_code="$(curl -sS -o "${response_file}" -D "${headers_file}" -w "%{http_code}" \
  -X POST "${AUTH_URL}/auth/tokens" \
  -H "Content-Type: application/json" \
  -d "${body}")"

if [ "${http_code}" != "201" ]; then
  echo "::error::Keystone project token failed (HTTP ${http_code})" >&2
  jq . "${response_file}" 2>/dev/null >&2 || cat "${response_file}" >&2
  exit 1
fi

token="$(awk 'BEGIN { IGNORECASE=1 } /^x-subject-token:/ { sub(/^[^:]*:[ \t]*/, ""); gsub(/\r$/, ""); print; exit }' "${headers_file}")"
if [ -z "${token}" ]; then
  echo "::error::Keystone response missing X-Subject-Token header" >&2
  exit 1
fi

printf '%s' "${token}"
