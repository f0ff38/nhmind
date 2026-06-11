#!/usr/bin/env bash
# Keystone password auth smoke test — unscoped then project-scoped (matches OpenStack provider).
set -euo pipefail

AUTH_URL="${OS_AUTH_URL:-https://cloud.api.selcloud.ru/identity/v3}"

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} (run prepare-openstack-env.sh first)"
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

echo "Keystone target: ${AUTH_URL}" >&2
echo "Auth domain (SELECTEL_ACCOUNT_ID): ${OS_DOMAIN_NAME}" >&2
echo "User (SELECTEL_SERVICE_USER): ${OS_USERNAME}" >&2
echo "Password length: ${#OS_PASSWORD} chars" >&2
echo "Project id attempts: uuid=${project_uuid}, hex=${project_hex}" >&2

keystone_post() {
  local label="$1"
  local scope_mode="$2"
  local project_ref="$3"

  local body
  if [ "${scope_mode}" = "none" ]; then
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

  local response_file headers_file
  response_file="$(mktemp)"
  headers_file="$(mktemp)"

  local http_code
  http_code="$(curl -sS -o "${response_file}" -D "${headers_file}" -w "%{http_code}" \
    -X POST "${AUTH_URL}/auth/tokens" \
    -H "Content-Type: application/json" \
    -d "${body}")"

  echo "" >&2
  echo "--- ${label} (HTTP ${http_code}) ---" >&2
  if [ -s "${response_file}" ]; then
    jq . "${response_file}" 2>/dev/null >&2 || cat "${response_file}" >&2
  else
    echo "(empty response body)" >&2
  fi
  if grep -qi 'x-openstack-request-id' "${headers_file}" 2>/dev/null; then
    grep -i 'x-openstack-request-id' "${headers_file}" >&2 || true
  fi

  rm -f "${response_file}" "${headers_file}"
  printf '%s' "${http_code}"
}

echo "" >&2
echo "Step 1: identity only (no project scope)" >&2
code_identity="$(keystone_post "Identity (unscoped)" "none" "")"

if [ "${code_identity}" != "201" ]; then
  echo "" >&2
  echo "::error::Keystone identity failed (HTTP ${code_identity}) — user, password, or SELECTEL_ACCOUNT_ID"
  echo "Checklist:" >&2
  echo "  - SELECTEL_ACCOUNT_ID = account number (panel top-right)" >&2
  echo "  - SELECTEL_SERVICE_USER = exact IAM service user name" >&2
  echo "  - SELECTEL_SERVICE_PASSWORD = current password (re-save secret, no trailing newline)" >&2
  exit 1
fi

echo "Identity OK — credentials accepted by Keystone" >&2

echo "" >&2
echo "Step 2: project scope (UUID with hyphens)" >&2
code_uuid="$(keystone_post "Project scope (uuid)" "project" "${project_uuid}")"
if [ "${code_uuid}" = "201" ]; then
  echo "Keystone authentication OK (project scoped, uuid id)"
  exit 0
fi

echo "" >&2
echo "Step 3: project scope (32 hex, no hyphens)" >&2
code_hex="skipped"
if [ "${project_hex}" != "${project_uuid}" ] && [ "${#project_hex}" -eq 32 ]; then
  code_hex="$(keystone_post "Project scope (hex)" "project" "${project_hex}")"
  if [ "${code_hex}" = "201" ]; then
    echo "::warning::Project scope works with 32-hex id but not UUID — keep SELECTEL_PROJECT_ID as panel hex"
    echo "Keystone authentication OK (project scoped, hex id)"
    exit 0
  fi
fi

echo "" >&2
echo "::error::Keystone identity OK but project scope failed (uuid HTTP ${code_uuid}, hex HTTP ${code_hex})"
echo "Checklist:" >&2
echo "  - SELECTEL_PROJECT_ID = Cloud servers → nhmind (not IAM user UID)" >&2
echo "  - Service user: member role on THIS cloud project" >&2
exit 1
