#!/usr/bin/env bash
# Confirm deploy SSH private/public keys are a matching pair.
set -euo pipefail

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

private_key="$(trim "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}")"
public_key="$(trim "${RELAY_DEPLOY_SSH_PUBLIC_KEY:-}")"

if [ -z "${private_key}" ] || [ -z "${public_key}" ]; then
  echo "::error::RELAY_DEPLOY_SSH_PRIVATE_KEY and RELAY_DEPLOY_SSH_PUBLIC_KEY are required"
  exit 1
fi

key_file="$(mktemp)"
trap 'rm -f "${key_file}"' EXIT
umask 077
printf '%s\n' "${private_key}" > "${key_file}"

if ! derived_pub="$(ssh-keygen -y -f "${key_file}" 2>/dev/null)"; then
  echo "::error::RELAY_DEPLOY_SSH_PRIVATE_KEY is not a valid SSH private key"
  exit 1
fi

pub_fp="$(printf '%s\n' "${public_key}" | ssh-keygen -lf - | awk '{print $2}')"
derived_fp="$(printf '%s\n' "${derived_pub}" | ssh-keygen -lf - | awk '{print $2}')"

if [ "${pub_fp}" != "${derived_fp}" ]; then
  echo "::error::SSH key mismatch: RELAY_DEPLOY_SSH_PUBLIC_KEY does not match RELAY_DEPLOY_SSH_PRIVATE_KEY"
  exit 1
fi

echo "SSH deploy keypair OK (fingerprint ${pub_fp})"
