#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ROOT="${HATCH_RUNTIME_ROOT:-$(cd "${ROOT}/../.." && pwd)/monoclaw-runtime}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

HOME_DIR="${TMP}/home"
LOCK="${TMP}/monoclaw-provisioning-lock.json"
INSTALLED_LOCK="${HOME_DIR}/.monoclaw/vendor/provisioning/monoclaw-provisioning-lock.json"

mkdir -p "${HOME_DIR}/.monoclaw/vendor/provisioning"

PYTHONPATH="${RUNTIME_ROOT}" \
MONOCLAW_HOME="${HOME_DIR}/.monoclaw" \
  python3 -m monoclaw_cli.provisioning_audit \
    --no-skills \
    --lock-out "${LOCK}"

cp "${LOCK}" "${INSTALLED_LOCK}"

PYTHONPATH="${RUNTIME_ROOT}" \
MONOCLAW_HOME="${HOME_DIR}/.monoclaw" \
  python3 -m monoclaw_cli.provisioning_audit \
    --no-skills \
    --allow-unknown \
    --assert-lock "${INSTALLED_LOCK}" | tee "${TMP}/assert.out"

grep -q '"schema_version": 1' "${TMP}/assert.out"
