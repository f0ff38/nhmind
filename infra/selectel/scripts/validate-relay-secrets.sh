#!/usr/bin/env bash
# Validate relay GitHub environment secret presence and format without printing values.
set -euo pipefail

STAGE="${STAGE:-${1:-}}"

if [ -z "${STAGE}" ]; then
  echo "::error::STAGE is required (provision, deploy, all)"
  exit 1
fi

case "${STAGE}" in
  provision|deploy|all) ;;
  *)
    echo "::error::Invalid STAGE: ${STAGE}"
    exit 1
    ;;
esac

require() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "::error::Missing or empty secret: $name"
    return 1
  fi
  return 0
}

fail_format() {
  local name="$1"
  local hint="$2"
  echo "::error::Invalid format for $name ($hint)"
  return 1
}

errors=0

check_required() {
  local name="$1"
  local value="$2"
  if ! require "$name" "$value"; then
    errors=$((errors + 1))
  fi
}

if [ "$STAGE" = provision ] || [ "$STAGE" = all ]; then
  echo "Checking provision secrets (format)..."
  check_required SELECTEL_SERVICE_USER "${SELECTEL_SERVICE_USER:-}"
  check_required SELECTEL_SERVICE_PASSWORD "${SELECTEL_SERVICE_PASSWORD:-}"
  check_required SELECTEL_ACCOUNT_ID "${SELECTEL_ACCOUNT_ID:-}"
  check_required SELECTEL_PROJECT_ID "${SELECTEL_PROJECT_ID:-}"
  check_required RELAY_DEPLOY_SSH_PRIVATE_KEY "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}"
  check_required RELAY_DEPLOY_SSH_PUBLIC_KEY "${RELAY_DEPLOY_SSH_PUBLIC_KEY:-}"
  check_required TF_STATE_S3_BUCKET "${TF_STATE_S3_BUCKET:-}"
  check_required TF_STATE_S3_ACCESS_KEY "${TF_STATE_S3_ACCESS_KEY:-}"
  check_required TF_STATE_S3_SECRET_KEY "${TF_STATE_S3_SECRET_KEY:-}"
  check_required RELAY_HOSTNAME "${RELAY_HOSTNAME:-}"
  check_required SELECTEL_STATIC_TOKEN "${SELECTEL_STATIC_TOKEN:-}"

  check_required SELECTEL_AVAILABILITY_ZONE "${SELECTEL_AVAILABILITY_ZONE:-}"
  if [ -n "${SELECTEL_AVAILABILITY_ZONE:-}" ]; then
    if printf '%s' "$SELECTEL_AVAILABILITY_ZONE" | grep -Eq '^[a-z]{2,4}-[0-9]+[a-z]$'; then
      echo "SELECTEL_AVAILABILITY_ZONE: OK - pool AZ, e.g. ru-3a"
    elif printf '%s' "$SELECTEL_AVAILABILITY_ZONE" | grep -Eq '^[a-z]{2,4}-[0-9]+$'; then
      echo "::warning::SELECTEL_AVAILABILITY_ZONE is a pool (e.g. ru-3), not an AZ. For VM creation use ru-3a / ru-3b from the server wizard."
    else
      fail_format SELECTEL_AVAILABILITY_ZONE "expected pool (ru-3) or AZ (ru-3a)" || errors=$((errors + 1))
    fi
  fi

  if [ -n "${SELECTEL_ACCOUNT_ID:-}" ] && ! printf '%s' "$SELECTEL_ACCOUNT_ID" | grep -Eq '^[0-9]+$'; then
    fail_format SELECTEL_ACCOUNT_ID "expected numeric account id" || errors=$((errors + 1))
  fi

  if [ -n "${SELECTEL_PROJECT_ID:-}" ]; then
    pid_hex="$(printf '%s' "$SELECTEL_PROJECT_ID" | tr 'A-Z' 'a-z' | sed 's/[^0-9a-f]//g')"
    pid_len="${#pid_hex}"
    if [ "$pid_len" -eq 32 ]; then
      echo "SELECTEL_PROJECT_ID: OK - 32 hex chars, cloud project id"
    else
      echo "::error::SELECTEL_PROJECT_ID: after cleanup got ${pid_len} hex chars, need 32. Use Cloud servers project id, not IAM Projects."
      errors=$((errors + 1))
    fi
  fi

  if [ -n "${RELAY_HOSTNAME:-}" ] && ! printf '%s' "$RELAY_HOSTNAME" | grep -Eq '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$'; then
    fail_format RELAY_HOSTNAME "expected lowercase FQDN without scheme" || errors=$((errors + 1))
  fi

  if [ -n "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}" ] && ! printf '%s' "$RELAY_DEPLOY_SSH_PRIVATE_KEY" | grep -q 'BEGIN.*PRIVATE KEY'; then
    fail_format RELAY_DEPLOY_SSH_PRIVATE_KEY "expected PEM private key" || errors=$((errors + 1))
  fi

  if [ -n "${RELAY_DEPLOY_SSH_PUBLIC_KEY:-}" ] && ! printf '%s' "$RELAY_DEPLOY_SSH_PUBLIC_KEY" | grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-)'; then
    fail_format RELAY_DEPLOY_SSH_PUBLIC_KEY "expected OpenSSH public key line" || errors=$((errors + 1))
  fi
fi

if [ "$STAGE" = deploy ] || [ "$STAGE" = all ]; then
  echo "Checking deploy secrets (format)..."
  check_required TF_STATE_S3_BUCKET "${TF_STATE_S3_BUCKET:-}"
  check_required TF_STATE_S3_ACCESS_KEY "${TF_STATE_S3_ACCESS_KEY:-}"
  check_required TF_STATE_S3_SECRET_KEY "${TF_STATE_S3_SECRET_KEY:-}"
  check_required RELAY_DEPLOY_SSH_PRIVATE_KEY "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}"
  check_required RELAY_HOSTNAME "${RELAY_HOSTNAME:-}"
  check_required SELECTEL_SERVICE_USER "${SELECTEL_SERVICE_USER:-}"
  check_required SELECTEL_SERVICE_PASSWORD "${SELECTEL_SERVICE_PASSWORD:-}"
  check_required SELECTEL_ACCOUNT_ID "${SELECTEL_ACCOUNT_ID:-}"
  check_required SELECTEL_PROJECT_ID "${SELECTEL_PROJECT_ID:-}"
  if [ -n "${RELAY_TLS_KNOX_CERT_ID:-}" ] && ! printf '%s' "$RELAY_TLS_KNOX_CERT_ID" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    fail_format RELAY_TLS_KNOX_CERT_ID "expected UUID (optional; auto-resolved from RELAY_HOSTNAME if empty)" || errors=$((errors + 1))
  fi
  echo "RELAY_SSH_HOST: resolved at runtime from terraform output public_ip (not a GitHub secret)"
  echo "TLS: Selectel LE DNS-01 (pull-on-deploy); RELAY_TLS_KNOX_CERT_ID optional"
fi

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "Fix secrets in GitHub -> Settings -> Environments -> relay"
  exit 1
fi

echo "Format checks passed for stage: $STAGE"
