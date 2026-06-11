#!/usr/bin/env bash
# Normalize Selectel/OpenStack env for Terraform and Keystone verify (CI or local).
set -euo pipefail

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

normalize_project_id() {
  local raw="$1"
  local hex
  hex="$(printf '%s' "$raw" | tr 'A-Z' 'a-z' | tr -d '-' | sed 's/[^0-9a-f]//g')"
  if [ "${#hex}" -eq 32 ]; then
    printf '%s' "${hex}"
    return
  fi
  printf '%s' "$(trim "$raw")"
}

out="${GITHUB_ENV:-}"
export_mode="${PREPARE_OPENSTACK_EXPORT:-}"

account_id="$(trim "${SELECTEL_ACCOUNT_ID:-}")"
project_id="$(normalize_project_id "${SELECTEL_PROJECT_ID:-}")"
service_user="$(trim "${SELECTEL_SERVICE_USER:-}")"
service_password="$(trim "${SELECTEL_SERVICE_PASSWORD:-}")"
region="$(trim "${SELECTEL_REGION:-}")"
az="$(trim "${SELECTEL_AVAILABILITY_ZONE:-}")"

if [ -z "${region}" ] && [ -n "${az}" ]; then
  region="${az%?}"
fi

if [ -z "${account_id}" ]; then
  echo "::error::SELECTEL_ACCOUNT_ID is empty (account number, panel top-right)"
  exit 1
fi

if [ -z "${project_id}" ]; then
  echo "::error::SELECTEL_PROJECT_ID is empty"
  exit 1
fi

if [ -z "${service_user}" ] || [ -z "${service_password}" ]; then
  echo "::error::SELECTEL_SERVICE_USER or SELECTEL_SERVICE_PASSWORD is empty"
  exit 1
fi

emit() {
  local key="$1"
  local value="$2"
  if [ "${export_mode}" = "1" ]; then
    printf -v "$key" '%s' "$value"
    export "$key"
  elif [ -n "${out}" ]; then
    {
      echo "${key}<<EOF"
      printf '%s\n' "${value}"
      echo "EOF"
    } >> "${out}"
  fi
}

emit "TF_VAR_selectel_account_id" "${account_id}"
emit "TF_VAR_selectel_project_id" "${project_id}"
emit "TF_VAR_selectel_service_user" "${service_user}"
emit "TF_VAR_selectel_service_password" "${service_password}"
emit "TF_VAR_selectel_region" "${region}"
emit "TF_VAR_availability_zone" "${az}"
emit "OS_DOMAIN_NAME" "${account_id}"
emit "OS_USERNAME" "${service_user}"
emit "OS_PASSWORD" "${service_password}"
emit "OS_PROJECT_ID" "${project_id}"
emit "OS_REGION_NAME" "${region}"

if [ -n "${RELAY_DEPLOY_SSH_PUBLIC_KEY:-}" ]; then
  emit "TF_VAR_deploy_ssh_public_key" "$(trim "${RELAY_DEPLOY_SSH_PUBLIC_KEY}")"
fi

if [ -n "${TF_VAR_flavor_id:-}" ]; then
  emit "TF_VAR_flavor_id" "$(trim "${TF_VAR_flavor_id}")"
fi

echo "OpenStack pool (region): ${region:-<empty>}"
echo "Availability zone (segment): ${az:-<empty>}"
echo "Project id (32 hex): ${project_id:0:8}...${project_id: -4}"
