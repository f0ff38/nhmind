#!/usr/bin/env bash
# Keystone password auth smoke test (same scope as Terraform OpenStack provider).
set -euo pipefail

AUTH_URL="${OS_AUTH_URL:-https://cloud.api.selcloud.ru/identity/v3}"

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} (run prepare-openstack-env.sh first)"
    exit 1
  fi
done

body="$(jq -n \
  --arg user "$OS_USERNAME" \
  --arg domain "$OS_DOMAIN_NAME" \
  --arg password "$OS_PASSWORD" \
  --arg project "$OS_PROJECT_ID" \
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

response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT

http_code="$(curl -sS -o "${response_file}" -w "%{http_code}" \
  -X POST "${AUTH_URL}/auth/tokens" \
  -H "Content-Type: application/json" \
  -d "${body}")"

if [ "${http_code}" = "201" ]; then
  echo "Keystone authentication OK (HTTP 201, project scoped)"
  exit 0
fi

echo "::error::OpenStack authentication failed (HTTP ${http_code})"
jq -r '.error.message // .error // .' "${response_file}" 2>/dev/null || cat "${response_file}"
echo ""
echo "Checklist:"
echo "  - SELECTEL_ACCOUNT_ID: account number (panel top-right), not project name"
echo "  - SELECTEL_PROJECT_ID: Cloud servers → nhmind → 32 hex id (NOT IAM → Projects)"
echo "  - Service user: role member scoped to THIS cloud project"
echo "  - SELECTEL_SERVICE_PASSWORD: re-save secret without trailing newline/spaces"
exit 1
