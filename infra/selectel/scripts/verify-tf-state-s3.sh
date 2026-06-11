#!/usr/bin/env bash
# Verify Terraform state bucket via Selectel S3-compatible API (path-style, same as backend).
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
state_key="${TF_STATE_KEY:-nhmind-relay/terraform.tfstate}"

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
export AWS_EC2_METADATA_DISABLED=true

aws configure set default.s3.addressing_style path >/dev/null 2>&1 || true

aws_cmd=(aws --endpoint-url "${endpoint}" --region "${s3_region}")

echo "S3 endpoint: ${endpoint} (path-style)"
echo "Bucket: ${bucket}"
echo "State key: ${state_key}"

run_check() {
  local label="$1"
  shift
  echo ""
  echo "--- ${label} ---"
  set +e
  local out rc
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [ -n "${out}" ]; then
    printf '%s\n' "${out}"
  fi
  return "${rc}"
}

if run_check "ListBucket" "${aws_cmd[@]}" s3 ls "s3://${bucket}/"; then
  echo ""
  echo "Terraform state S3 OK (ListBucket, pool ${s3_region})"
  exit 0
fi

set +e
head_out="$("${aws_cmd[@]}" s3api head-object --bucket "${bucket}" --key "${state_key}" 2>&1)"
head_rc=$?
set -e

echo ""
echo "--- HeadObject state key ---"
if [ -n "${head_out}" ]; then
  printf '%s\n' "${head_out}"
fi

if [ "${head_rc}" -eq 0 ]; then
  echo ""
  echo "Terraform state S3 OK (HeadObject on state key, pool ${s3_region})"
  exit 0
fi

if printf '%s' "${head_out}" | grep -Eqi '404|Not Found|NoSuchKey'; then
  echo ""
  echo "Terraform state S3 OK (bucket reachable; state file not created yet)"
  exit 0
fi

echo ""
echo "::error::S3 access failed for bucket ${bucket} at ${endpoint}"
echo "Checklist:"
echo "  - TF_STATE_S3_REGION matches bucket pool (e.g. ru-3)"
echo "  - TF_STATE_S3_* keys are S3 Access Key / Secret from Object Storage (not IAM password)"
echo "  - Key has read/write on container ${bucket}"
exit 1
