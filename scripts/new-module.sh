#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

usage() {
  cat <<'EOF'
Create a new Acurast module from modules/module-template.

Usage: ./scripts/new-module.sh <module-name>

Rules:
  - lowercase letters, digits, hyphens
  - must start with a letter
  - must not exist under modules/

Example:
  ./scripts/new-module.sh oracle-feed
  NHIND_MODULE_DIR=modules/oracle-feed ./scripts/dev install
EOF
}

NAME="${1:-}"
if [[ -z "${NAME}" ]] || [[ "${NAME}" == "-h" ]] || [[ "${NAME}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! "${NAME}" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "Invalid module name: ${NAME}" >&2
  echo "Use lowercase letters, digits, hyphens; start with a letter." >&2
  exit 1
fi

SOURCE="modules/module-template"
TARGET="modules/${NAME}"

if [[ ! -d "${SOURCE}" ]]; then
  echo "Template not found: ${SOURCE}" >&2
  exit 1
fi

if [[ -e "${TARGET}" ]]; then
  echo "Target already exists: ${TARGET}" >&2
  exit 1
fi

echo ">> Creating ${TARGET} from ${SOURCE}..."
cp -r "${SOURCE}" "${TARGET}"

# Rename scaffold identifiers (word-boundary safe).
while IFS= read -r -d '' file; do
  sed -i "s/\\btemplate\\b/${NAME}/g" "${file}"
  sed -i "s/@nhmind\\/template/@nhmind\\/${NAME}/g" "${file}"
done < <(find "${TARGET}" -type f \( \
  -name '*.ts' -o -name '*.json' -o -name '*.md' -o -name 'package.json' \
\) -print0)

rm -rf "${TARGET}/node_modules" "${TARGET}/dist" 2>/dev/null || true

cat <<EOF

Created ${TARGET}

Next steps:
  NHIND_MODULE_DIR=${TARGET} ./scripts/dev install
  NHIND_MODULE_DIR=${TARGET} ./scripts/dev test
  NHIND_MODULE_DIR=${TARGET} ./scripts/dev bundle

Optional:
  NHIND_MODULE_DIR=${TARGET} ./scripts/dev acurast init
EOF
