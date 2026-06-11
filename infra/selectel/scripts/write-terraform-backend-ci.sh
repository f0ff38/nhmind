#!/usr/bin/env bash
# Write backend.ci.hcl for Terraform init in GitHub Actions (Selectel S3 state).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

S3_REGION="${TF_STATE_S3_REGION:-}"
if [ -z "${S3_REGION}" ]; then
  S3_REGION="${SELECTEL_REGION:-}"
fi
if [ -z "${S3_REGION}" ] && [ -n "${SELECTEL_AVAILABILITY_ZONE:-}" ]; then
  S3_REGION="${SELECTEL_AVAILABILITY_ZONE%?}"
fi
if [ -z "${S3_REGION}" ]; then
  echo "::error::Set TF_STATE_S3_REGION (e.g. ru-3) or SELECTEL_REGION / SELECTEL_AVAILABILITY_ZONE"
  exit 1
fi

if [ -z "${TF_STATE_S3_BUCKET:-}" ] || [ -z "${TF_STATE_S3_ACCESS_KEY:-}" ] || [ -z "${TF_STATE_S3_SECRET_KEY:-}" ]; then
  echo "::error::TF_STATE_S3_BUCKET, TF_STATE_S3_ACCESS_KEY, and TF_STATE_S3_SECRET_KEY are required"
  exit 1
fi

S3_ENDPOINT="https://s3.${S3_REGION}.storage.selcloud.ru"
echo "Terraform state S3 pool: ${S3_REGION} (${S3_ENDPOINT})"
umask 077
cat > "${TF_DIR}/backend.ci.hcl" <<EOF
bucket     = "${TF_STATE_S3_BUCKET}"
access_key = "${TF_STATE_S3_ACCESS_KEY}"
secret_key = "${TF_STATE_S3_SECRET_KEY}"
region     = "${S3_REGION}"
endpoints = {
  s3 = "${S3_ENDPOINT}"
}
EOF
