#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

INPUTS="${TMP}/bundle-inputs"
RUNTIME="${TMP}/monoclaw-runtime"
DIST="${TMP}/dist"
HOME_DIR="${TMP}/home"
WHEEL="${TMP}/monoclaw_runtime-0.13.0-py3-none-any.whl"

mkdir -p \
  "${INPUTS}/vendor/lm-studio/LM Studio.app/Contents" \
  "${INPUTS}/vendor/models/gemma-4-e4b" \
  "${RUNTIME}" \
  "${HOME_DIR}"

printf 'LM Studio app placeholder\n' > "${INPUTS}/vendor/lm-studio/LM Studio.app/Contents/Info.plist"
printf 'Gemma 4 E4B GGUF placeholder\n' > "${INPUTS}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"
printf 'wheel placeholder\n' > "${WHEEL}"
cat > "${RUNTIME}/pyproject.toml" <<'TOML'
[project]
name = "monoclaw-runtime"
version = "0.13.0"
TOML

HATCH_INPUT_ROOT="${INPUTS}" \
HATCH_RUNTIME_ROOT="${RUNTIME}" \
HATCH_RUNTIME_WHEEL="${WHEEL}" \
HATCH_DIST_ROOT="${DIST}" \
HATCH_SKIP_RUNTIME_BUILD=1 \
  "${ROOT}/build.sh" | tee "${TMP}/build.out"

test -x "${DIST}/install.sh"
test -x "${DIST}/bin/hatch"
test -f "${DIST}/lib/common.sh"
test -x "${DIST}/tests/run-hatch-dry-run.sh"
test -f "${DIST}/runtime/monoclaw-runtime.whl"
test -f "${DIST}/runtime/constraints.txt"
test -f "${DIST}/runtime/about.md"
test -f "${DIST}/hatch-manifest.json"
grep -q "Manifest verified for bundle" "${TMP}/build.out"

bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle | tee "${TMP}/prepare.out"
grep -q "Manifest verified for bundle" "${TMP}/prepare.out"

printf 'extra file\n' > "${DIST}/runtime/unlisted.txt"
if bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle >"${TMP}/unlisted.out" 2>&1; then
  printf 'expected manifest verification to fail for an unlisted file\n' >&2
  exit 1
fi
grep -q "bundle file is not listed in manifest artifacts: runtime/unlisted.txt" "${TMP}/unlisted.out"
rm "${DIST}/runtime/unlisted.txt"

HOME="${HOME_DIR}" HATCH_INSTALL_DRY_RUN=1 "${DIST}/install.sh" | tee "${TMP}/install.out"
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/install.out"
grep -q "dry-run: cp ${DIST}/hatch-manifest.json ${HOME_DIR}/.monoclaw/vendor/hatch-manifest.json" "${TMP}/install.out"

APPLY_HOME="${TMP}/apply-home"
mkdir -p "${APPLY_HOME}"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${APPLY_HOME}" "${DIST}/install.sh" | tee "${TMP}/apply.out"
grep -q "run: mkdir -p ${APPLY_HOME}/.monoclaw/vendor" "${TMP}/apply.out"
test -f "${APPLY_HOME}/.monoclaw/.env"
test -f "${APPLY_HOME}/.monoclaw/config.yaml"

printf 'tampered\n' > "${DIST}/runtime/monoclaw-runtime.whl"
if bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle >"${TMP}/tamper.out" 2>&1; then
  printf 'expected manifest verification to fail after wheel tamper\n' >&2
  exit 1
fi
grep -q "artifact .* mismatch: runtime/monoclaw-runtime.whl" "${TMP}/tamper.out"

if HATCH_INPUT_ROOT="${INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_RUNTIME_WHEEL="${WHEEL}" \
  HATCH_DIST_ROOT="${INPUTS}" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
    "${ROOT}/build.sh" >"${TMP}/unsafe-dist.out" 2>&1; then
  printf 'expected build to reject unsafe HATCH_DIST_ROOT\n' >&2
  exit 1
fi
grep -q "unsafe dist root" "${TMP}/unsafe-dist.out"
test -f "${INPUTS}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"

PROJECTS="${TMP}/Projects"
STANDALONE_HATCH="${PROJECTS}/hatch"
STANDALONE_RUNTIME="${PROJECTS}/monoclaw-runtime"
STANDALONE_DIST="${TMP}/standalone-dist"
STANDALONE_WHEEL="${TMP}/standalone-wheel.whl"
mkdir -p "${PROJECTS}" "${STANDALONE_RUNTIME}" "${STANDALONE_HATCH}/bundle-inputs/vendor/lm-studio/LM Studio.app/Contents" "${STANDALONE_HATCH}/bundle-inputs/vendor/models/gemma-4-e4b"
cp -R "${ROOT}/." "${STANDALONE_HATCH}/"
printf 'standalone LM Studio placeholder\n' > "${STANDALONE_HATCH}/bundle-inputs/vendor/lm-studio/LM Studio.app/Contents/Info.plist"
printf 'standalone Gemma placeholder\n' > "${STANDALONE_HATCH}/bundle-inputs/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"
printf 'standalone wheel placeholder\n' > "${STANDALONE_WHEEL}"
cat > "${STANDALONE_RUNTIME}/pyproject.toml" <<'TOML'
[project]
name = "monoclaw-runtime"
version = "0.13.0"
TOML

HATCH_RUNTIME_WHEEL="${STANDALONE_WHEEL}" \
HATCH_DIST_ROOT="${STANDALONE_DIST}" \
HATCH_SKIP_RUNTIME_BUILD=1 \
  "${STANDALONE_HATCH}/build.sh" | tee "${TMP}/standalone-build.out"
grep -q "Built by Hatch from ${STANDALONE_RUNTIME}" "${STANDALONE_DIST}/runtime/about.md"
test -x "${STANDALONE_DIST}/install.sh"
