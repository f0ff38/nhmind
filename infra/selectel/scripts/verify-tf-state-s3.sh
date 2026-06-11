#!/usr/bin/env bash
# List Terraform state bucket via Selectel S3-compatible API (same as terraform init backend).
set -euo pipefail

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

bucket="$(trim "${TF_STATE_S3_BUCKET:-}")"
access_key="$(trim "${TF_STATE_S3_ACCESS_KEY:-}")"
secret_key="$(trim "${TF_STATE_S3_SECRET_KEY:-}")"
s3_region="$(trim "${TF_STATE_S3_REGION:-}")"
selectel_region="$(trim "${SELECTEL_REGION:-}")"
az="$(trim "${SELECTEL_AVAILABILITY_ZONE:-}")"

if [ -z "${bucket}" ] || [ -z "${access_key}" ] || [ -z "${secret_key}" ]; then
  echo "::error::TF_STATE_S3_BUCKET, TF_STATE_S3_ACCESS_KEY, TF_STATE_S3_SECRET_KEY are required"
  exit 1
fi

if [ -z "${s3_region}" ]; then
  s3_region="${selectel_region}"
fi
if [ -z "${s3_region}" ] && [ -n "${az}" ]; then
  s3_region="${az%?}"
fi
if [ -z "${s3_region}" ]; then
  echo "::error::Set TF_STATE_S3_REGION (e.g. ru-3) or SELECTEL_REGION / SELECTEL_AVAILABILITY_ZONE"
  exit 1
fi

endpoint="https://s3.${s3_region}.storage.selcloud.ru"
export AWS_ACCESS_KEY_ID="${access_key}"
export AWS_SECRET_ACCESS_KEY="${secret_key}"
export AWS_DEFAULT_REGION="${s3_region}"

if aws s3 ls "s3://${bucket}/" --endpoint-url "${endpoint}" >/dev/null 2>&1; then
  echo "Terraform state S3 OK (bucket ${bucket}, pool ${s3_region})"
  exit 0
fi

echo "::error::Cannot list s3://${bucket}/ at ${endpoint}"
echo "Checklist:"
echo "  - TF_STATE_S3_REGION matches bucket pool (e.g. ru-3)"
echo "  - S3 access key has read/write on this bucket"
echo "  - TF_STATE_S3_BUCKET name is correct"
exit 1
