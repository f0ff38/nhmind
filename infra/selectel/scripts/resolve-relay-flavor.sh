#!/usr/bin/env bash
# Resolve pool-specific flavor_id when workflow input is empty (Nova API; avoids ambiguous TF data source).
set -euo pipefail

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

emit() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "${key}<<EOF"
      printf '%s\n' "${value}"
      echo "EOF"
    } >> "${GITHUB_ENV}"
  else
    printf -v "$key" '%s' "$value"
    export "$key"
  fi
}

VCPUS="${RELAY_FLAVOR_VCPUS:-2}"
RAM_MB="${RELAY_FLAVOR_RAM_MB:-4096}"
DISK_GB="${RELAY_FLAVOR_DISK_GB:-0}"

existing="$(trim "${TF_VAR_flavor_id:-}")"
if [ -n "${existing}" ]; then
  echo "Using flavor_id override: ${existing}"
  emit "TF_VAR_flavor_id" "${existing}"
  exit 0
fi

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID OS_REGION_NAME; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} (run prepare-openstack-env.sh first)"
    exit 1
  fi
done

AUTH_URL="${OS_AUTH_URL:-https://cloud.api.selcloud.ru/identity/v3}"
project_id="$(trim "${OS_PROJECT_ID}")"

auth_body="$(jq -n \
  --arg user "$OS_USERNAME" \
  --arg domain "$OS_DOMAIN_NAME" \
  --arg password "$OS_PASSWORD" \
  --arg project "$project_id" \
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
body_file="$(mktemp)"
trap 'rm -f "${headers_file}" "${body_file}"' EXIT

http_code="$(curl -sS -o "${body_file}" -D "${headers_file}" -w "%{http_code}" \
  -X POST "${AUTH_URL}/auth/tokens" \
  -H "Content-Type: application/json" \
  -d "${auth_body}")"

if [ "${http_code}" != "201" ]; then
  echo "::error::Keystone project scope failed (HTTP ${http_code}) while resolving flavor"
  jq . "${body_file}" 2>/dev/null || cat "${body_file}"
  exit 1
fi

token="$(awk 'tolower($1)=="x-subject-token:" {print $2; exit}' "${headers_file}" | tr -d '\r')"
if [ -z "${token}" ]; then
  echo "::error::Keystone token missing from response headers"
  exit 1
fi

compute_url="$(jq -r --arg region "${OS_REGION_NAME}" '
  .token.catalog[]
  | select(.type == "compute")
  | .endpoints[]
  | select(.interface == "public" and .region_id == $region)
  | .url
' "${body_file}" | head -n 1)"

if [ -z "${compute_url}" ] || [ "${compute_url}" = "null" ]; then
  compute_url="https://${OS_REGION_NAME}.cloud.api.selcloud.ru/compute/v2.1"
fi

compute_url="${compute_url%/}"
flavors_file="$(mktemp)"
trap 'rm -f "${headers_file}" "${body_file}" "${flavors_file}"' EXIT

flavors_code="$(curl -sS -o "${flavors_file}" -w "%{http_code}" \
  -H "X-Auth-Token: ${token}" \
  "${compute_url}/flavors/detail")"

if [ "${flavors_code}" != "200" ]; then
  echo "::error::Nova flavors/detail failed (HTTP ${flavors_code})"
  cat "${flavors_file}" || true
  exit 1
fi

picked="$(jq -r --argjson vcpus "${VCPUS}" --argjson ram "${RAM_MB}" --argjson disk "${DISK_GB}" '
  [.flavors[]
    | select(.vcpus == $vcpus and .ram == $ram and .disk == $disk)
  ]
  | sort_by(.name)
  | .[0]
' "${flavors_file}")"

if [ -z "${picked}" ] || [ "${picked}" = "null" ]; then
  match_count="$(jq -r --argjson vcpus "${VCPUS}" --argjson ram "${RAM_MB}" --argjson disk "${DISK_GB}" '
    [.flavors[] | select(.vcpus == $vcpus and .ram == $ram and .disk == $disk)] | length
  ' "${flavors_file}")"
  echo "::error::No flavor matches ${VCPUS} vCPU / ${RAM_MB} MB / disk ${DISK_GB} (matches: ${match_count}). Set workflow input flavor_id from Selectel panel."
  exit 1
fi

flavor_id="$(jq -r '.id' <<< "${picked}")"
flavor_name="$(jq -r '.name' <<< "${picked}")"

echo "Auto-picked flavor: ${flavor_name} (${flavor_id}) — ${VCPUS} vCPU / ${RAM_MB} MB / disk ${DISK_GB}"
emit "TF_VAR_flavor_id" "${flavor_id}"
