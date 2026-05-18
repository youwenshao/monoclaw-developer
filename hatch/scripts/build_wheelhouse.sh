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

# Verify that the wheelhouse is self-sufficient: simulate an offline install
# of monoclaw-runtime[local-office] against the wheelhouse with no network
# access.  If any declared dependency is absent the resolver fails here,
# on the assembly machine, rather than on the target Mac during install.sh.
verify_wheelhouse() {
  log "Verifying wheelhouse is self-sufficient (offline resolve smoke test)"
  local tmpdir
  tmpdir="$(mktemp -d)"

  # Create a minimal venv so pip has an isolated site-packages to resolve
  # against; this avoids pollution from whatever is installed in the bundled
  # Python's base environment.
  "${HATCH_WHEELHOUSE_PYTHON}" -m venv "${tmpdir}/verify-venv" 2>/dev/null

  # Upgrade pip inside the venv from the wheelhouse (avoids any network hit).
  "${tmpdir}/verify-venv/bin/python" -m pip install \
    --quiet \
    --no-index --find-links "${HATCH_WHEELHOUSE_ROOT}" \
    --upgrade pip setuptools wheel

  # Dry-run install: resolves the full dependency tree from the wheelhouse
  # only.  Exits non-zero if any package is missing — same error the target
  # Mac would see — so this catches stale wheelhouses before a bundle ships.
  local resolve_ok=0
  "${tmpdir}/verify-venv/bin/python" -m pip install \
      --quiet \
      --no-index --find-links "${HATCH_WHEELHOUSE_ROOT}" \
      --dry-run \
      "${HATCH_RUNTIME_ROOT}[local-office]" 2>&1 || resolve_ok=$?

  rm -rf "${tmpdir}"

  if [[ "${resolve_ok}" -ne 0 ]]; then
    die "Wheelhouse offline resolve failed — run HATCH_CLEAN_WHEELHOUSE=1 bash scripts/build_wheelhouse.sh to rebuild"
  fi

  log "Wheelhouse offline resolve: ok"
}

build_wheelhouse
if [[ "${HATCH_SKIP_WHEELHOUSE_VERIFY:-0}" == "1" ]]; then
  log "Skipping wheelhouse offline resolve smoke test (HATCH_SKIP_WHEELHOUSE_VERIFY=1)"
else
  verify_wheelhouse
fi
