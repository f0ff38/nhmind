#!/usr/bin/env bash
# Read relay floating IP from Terraform remote state (single source of truth).
# stdout: IPv4 only (for GITHUB_OUTPUT / command substitution).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

bash "${SCRIPT_DIR}/write-terraform-backend-ci.sh" >&2

cd "${TF_DIR}"
init_log="$(mktemp)"
trap 'rm -f backend.ci.hcl "${init_log}"' EXIT
if ! terraform init -backend-config=backend.ci.hcl -input=false -no-color >"${init_log}" 2>&1; then
  cat "${init_log}" >&2
  exit 1
fi

public_ip="$(terraform output -raw public_ip 2>/dev/null || true)"
if [ -z "${public_ip}" ] || ! printf '%s' "${public_ip}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "::error::terraform output public_ip is missing or invalid — run Provision Relay Infra apply first" >&2
  exit 1
fi

printf '%s' "${public_ip}"
