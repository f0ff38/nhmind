#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${NHIND_MODULE_DIR:-/workspace/modules/hello}"

if [[ -f "${MODULE_DIR}/package.json" && ! -d "${MODULE_DIR}/node_modules" ]]; then
  echo ">> Installing dependencies in ${MODULE_DIR}..."
  npm ci --prefix "${MODULE_DIR}"
fi

exec "$@"
