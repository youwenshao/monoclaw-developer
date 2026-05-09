#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"

if [[ -z "${HATCH_RUNTIME_ROOT:-}" ]]; then
  if [[ -d "${HATCH_ROOT}/../monoclaw-runtime" ]]; then
    HATCH_RUNTIME_ROOT="$(cd "${HATCH_ROOT}/../monoclaw-runtime" && pwd)"
  elif [[ -d "${HATCH_ROOT}/../../monoclaw-runtime" ]]; then
    HATCH_RUNTIME_ROOT="$(cd "${HATCH_ROOT}/../../monoclaw-runtime" && pwd)"
  else
    HATCH_RUNTIME_ROOT="$(cd "${HATCH_ROOT}/.." && pwd)/monoclaw-runtime"
  fi
fi

HATCH_WHEELHOUSE_ROOT="${HATCH_WHEELHOUSE_ROOT:-${HATCH_INPUT_ROOT}/vendor/wheelhouse}"
HATCH_WHEELHOUSE_PYTHON="${HATCH_WHEELHOUSE_PYTHON:-${HATCH_INPUT_ROOT}/vendor/python/current/bin/python3}"

log() {
  printf '[hatch-wheelhouse] %s\n' "$1"
}

die() {
  printf '[hatch-wheelhouse] fail: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || die "$2: $1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

build_wheelhouse() {
  require_file "${HATCH_RUNTIME_ROOT}/pyproject.toml" "runtime pyproject is missing"

  if [[ "${HATCH_WHEELHOUSE_PYTHON}" == */* ]]; then
    [[ -x "${HATCH_WHEELHOUSE_PYTHON}" ]] || die "wheelhouse Python is not executable: ${HATCH_WHEELHOUSE_PYTHON}; stage bundle-inputs/vendor/python/current/bin/python3 or set HATCH_WHEELHOUSE_PYTHON"
  else
    require_command "${HATCH_WHEELHOUSE_PYTHON}"
  fi

  if [[ "${HATCH_CLEAN_WHEELHOUSE:-0}" == "1" ]]; then
    log "Cleaning ${HATCH_WHEELHOUSE_ROOT}"
    rm -rf "${HATCH_WHEELHOUSE_ROOT}"
  fi

  mkdir -p "${HATCH_WHEELHOUSE_ROOT}"
  log "Using wheelhouse Python ${HATCH_WHEELHOUSE_PYTHON}"

  log "Building bootstrap tool wheels"
  "${HATCH_WHEELHOUSE_PYTHON}" -m pip wheel \
    --wheel-dir "${HATCH_WHEELHOUSE_ROOT}" \
    pip setuptools wheel

  log "Building monoclaw-runtime[local-office] wheelhouse"
  "${HATCH_WHEELHOUSE_PYTHON}" -m pip wheel \
    --wheel-dir "${HATCH_WHEELHOUSE_ROOT}" \
    "${HATCH_RUNTIME_ROOT}[local-office]"

  log "Wheelhouse ready at ${HATCH_WHEELHOUSE_ROOT}"
}

build_wheelhouse
