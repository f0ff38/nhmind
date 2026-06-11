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

iam_project_name="$(printf '%s' "${SELECTEL_IAM_PROJECT_NAME:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

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

if [ "${#project_hex}" -eq 32 ]; then
  if token="$(request_project_token "project scope (hex id)" "id" "${project_hex}")"; then
    printf '%s' "${token}"
    exit 0
  fi
fi

if [ "${project_uuid}" != "${project_hex}" ]; then
  if token="$(request_project_token "project scope (uuid id)" "id" "${project_uuid}")"; then
    printf '%s' "${token}"
    exit 0
  fi
fi

if [ -n "${iam_project_name}" ]; then
  if token="$(request_project_token "project scope (IAM name)" "name" "${iam_project_name}")"; then
    printf '%s' "${token}"
    exit 0
  fi
fi

echo "::error::Keystone project token failed (hex, uuid${iam_project_name:+, IAM project name})" >&2
echo "Checklist:" >&2
echo "  - SELECTEL_PROJECT_ID = Cloud servers project ID (32 hex)" >&2
echo "  - For DNS API: set SELECTEL_IAM_PROJECT_NAME if zone is under IAM project name scope" >&2
echo "  - Service user: member on cloud project + IAM permission for DNS project" >&2
exit 1
