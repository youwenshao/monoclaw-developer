#!/usr/bin/env bash
# Stage a reproducible CPython into bundle-inputs/vendor/python/current (macOS).
#
# Default source is astral-sh/python-build-standalone (same family Hatch vendor
# Python has historically used). Secretary bundles ship memo, which requires
# Python >= 3.13 per upstream requires-python; use this script before
# scripts/build_wheelhouse.sh and skill-deps prep when upgrading the bundle.
#
# Usage:
#   bash scripts/stage_vendor_python_macos.sh
#
# Override tarball URL entirely:
#   HATCH_VENDOR_PYTHON_URL='https://...install_only.tar.gz' bash scripts/stage_vendor_python_macos.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"

DEST="${HATCH_INPUT_ROOT}/vendor/python/current"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

log() {
  printf '[stage-vendor-python] %s\n' "$1"
}

die() {
  printf '[stage-vendor-python] fail: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

machine="$(uname -m)"
case "${machine}" in
  arm64) PBS_ARCH=aarch64 ;;
  x86_64) PBS_ARCH=x86_64 ;;
  *)
    die "unsupported machine ${machine}; run on Apple silicon or Intel macOS"
    ;;
esac

TAG="${HATCH_PYTHON_BUILD_STANDALONE_TAG:-20260510}"
VERSION="${HATCH_PYTHON_VERSION:-3.13.13}"

default_url="https://github.com/astral-sh/python-build-standalone/releases/download/${TAG}/cpython-${VERSION}%2B${TAG}-${PBS_ARCH}-apple-darwin-install_only.tar.gz"
URL="${HATCH_VENDOR_PYTHON_URL:-${default_url}}"

require_command curl
require_command tar

log "downloading ${URL}"
curl -fSL --retry 3 --retry-delay 2 -o "${TMP}/python.tgz" "${URL}"

log "extracting"
tar xzf "${TMP}/python.tgz" -C "${TMP}"

extracted="${TMP}/python"
[[ -x "${extracted}/bin/python3" ]] || die "extracted layout missing bin/python3 (${extracted})"

log "smoke test (venv + pip)"
smoke="${TMP}/smoke-venv"
"${extracted}/bin/python3" -m venv "${smoke}"
"${smoke}/bin/python" -m pip --version >/dev/null

stamp="$(date +%Y%m%d)"
backup="${DEST}.backup.${stamp}"
if [[ -d "${DEST}" ]]; then
  log "moving aside previous bundle to ${backup}"
  rm -rf "${backup}"
  mv "${DEST}" "${backup}"
fi

mkdir -p "$(dirname "${DEST}")"
mv "${extracted}" "${DEST}"

printf '%s\n' "${stamp}" > "${DEST}/BUILD"

log "staged ${DEST}/bin/python3 — $("${DEST}/bin/python3" -c 'import sys; print(sys.version.split()[0])')"
log "previous tree kept at ${backup} (delete manually when satisfied)"
