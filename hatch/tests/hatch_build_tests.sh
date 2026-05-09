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
FAKE_PYTHON="${TMP}/python3.11"

mkdir -p \
  "${INPUTS}/vendor/models/gemma-4-e4b" \
  "${INPUTS}/vendor/python/current/bin" \
  "${INPUTS}/vendor/wheelhouse" \
  "${RUNTIME}" \
  "${RUNTIME}/skills/customer-office" \
  "${HOME_DIR}"

printf 'Gemma 4 E4B GGUF placeholder\n' > "${INPUTS}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"
printf 'dependency wheel placeholder\n' > "${INPUTS}/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
printf 'runtime skill placeholder\n' > "${RUNTIME}/skills/customer-office/SKILL.md"
printf 'wheel placeholder\n' > "${WHEEL}"
cat > "${FAKE_PYTHON}" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "-c" ]; then
  printf '3.11.9\n'
  exit 0
fi
exec /usr/bin/python3 "$@"
SH
chmod +x "${FAKE_PYTHON}"
cp "${FAKE_PYTHON}" "${INPUTS}/vendor/python/current/bin/python3"
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
HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  "${ROOT}/build.sh" | tee "${TMP}/build.out"

test -x "${DIST}/install.sh"
test -x "${DIST}/bin/hatch"
test -f "${DIST}/lib/common.sh"
test -x "${DIST}/tests/run-hatch-dry-run.sh"
test -f "${DIST}/runtime/monoclaw_runtime-0.13.0-py3-none-any.whl"
test ! -f "${DIST}/runtime/monoclaw-runtime.whl"
test -f "${DIST}/runtime/constraints.txt"
test -f "${DIST}/runtime/about.md"
test -x "${DIST}/vendor/python/current/bin/python3"
test -f "${DIST}/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
test -f "${DIST}/vendor/skills/customer-office/SKILL.md"
test ! -d "${DIST}/vendor/models"
test -f "${TMP}/model-packs/gemma-4-e4b/gemma-4-e4b.gguf"
test -f "${TMP}/model-packs/gemma-4-e4b/model-pack-manifest.json"
test -x "${DIST}/install-gemma-model.sh"
test -f "${DIST}/hatch-manifest.json"
grep -q "Manifest verified for bundle" "${TMP}/build.out"

bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle | tee "${TMP}/prepare.out"
grep -q "Manifest verified for bundle" "${TMP}/prepare.out"

printf 'finder metadata\n' > "${DIST}/.DS_Store"
printf 'appledouble metadata\n' > "${DIST}/._hatch"
mkdir -p "${DIST}/__MACOSX" "${DIST}/.Spotlight-V100" "${DIST}/.fseventsd" "${DIST}/.Trashes"
printf 'archive metadata\n' > "${DIST}/__MACOSX/._hatch"
printf 'spotlight metadata\n' > "${DIST}/.Spotlight-V100/store"
printf 'fsevents metadata\n' > "${DIST}/.fseventsd/events"
printf 'trash metadata\n' > "${DIST}/.Trashes/501"
bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle | tee "${TMP}/prepare-metadata.out"
grep -q "Manifest verified for bundle" "${TMP}/prepare-metadata.out"

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" preflight | tee "${TMP}/preflight-bundle-python.out"
grep -q "Python 3.11+ runtime interpreter available at ${DIST}/vendor/python/current/bin/python3" "${TMP}/preflight-bundle-python.out"
bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle | tee "${TMP}/prepare-after-preflight.out"
grep -q "Manifest verified for bundle" "${TMP}/prepare-after-preflight.out"

printf 'extra file\n' > "${DIST}/runtime/unlisted.txt"
if bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle >"${TMP}/unlisted.out" 2>&1; then
  printf 'expected manifest verification to fail for an unlisted file\n' >&2
  exit 1
fi
grep -q "bundle file is not listed in manifest artifacts: runtime/unlisted.txt" "${TMP}/unlisted.out"
rm "${DIST}/runtime/unlisted.txt"

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_RUNTIME_PYTHON="${FAKE_PYTHON}" HATCH_INSTALL_DRY_RUN=1 "${DIST}/install.sh" | tee "${TMP}/install.out"
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/install.out"
grep -q "dry-run: cp ${DIST}/hatch-manifest.json ${HOME_DIR}/.monoclaw/vendor/hatch-manifest.json" "${TMP}/install.out"
grep -q "dry-run: cp -R ${DIST}/vendor/wheelhouse ${HOME_DIR}/.monoclaw/vendor/wheelhouse" "${TMP}/install.out"
grep -q "dry-run: install Homebrew with official installer" "${TMP}/install.out"
grep -q "Using Python ${FAKE_PYTHON} (3.11.9) for runtime bootstrap" "${TMP}/install.out"
grep -Fq "dry-run: ${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/python -m pip install --no-index --find-links ${HOME_DIR}/.monoclaw/vendor/wheelhouse --upgrade pip setuptools wheel" "${TMP}/install.out"
grep -Fq "dry-run: ${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/python -m pip install --no-index --find-links ${HOME_DIR}/.monoclaw/vendor/wheelhouse ${HOME_DIR}/.monoclaw/vendor/runtime/monoclaw_runtime-0.13.0-py3-none-any.whl[local-office]" "${TMP}/install.out"
grep -q "manual: install LM Studio from the official .dmg if local inference is required" "${TMP}/install.out"
if grep -q "lmstudio.ai/install.sh" "${TMP}/install.out"; then
  printf 'install should not script LM Studio installation\n' >&2
  exit 1
fi

APPLY_HOME="${TMP}/apply-home"
mkdir -p "${APPLY_HOME}/.monoclaw/skills/customer-office"
printf 'customer skill override\n' > "${APPLY_HOME}/.monoclaw/skills/customer-office/SKILL.md"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${APPLY_HOME}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_SKIP_HOMEBREW_INSTALL=1 HATCH_SKIP_RUNTIME_BOOTSTRAP=1 "${DIST}/install.sh" | tee "${TMP}/apply.out"
grep -q "run: mkdir -p ${APPLY_HOME}/.monoclaw/vendor" "${TMP}/apply.out"
grep -q "Skipping Homebrew installation because HATCH_SKIP_HOMEBREW_INSTALL=1" "${TMP}/apply.out"
grep -q "Skipping runtime bootstrap because HATCH_SKIP_RUNTIME_BOOTSTRAP=1" "${TMP}/apply.out"
test ! -f "${APPLY_HOME}/.monoclaw/.env"
test ! -f "${APPLY_HOME}/.monoclaw/config.yaml"
test -f "${APPLY_HOME}/.monoclaw/skills/customer-office/SKILL.md"
grep -q "customer skill override" "${APPLY_HOME}/.monoclaw/skills/customer-office/SKILL.md"

printf 'tampered\n' > "${DIST}/runtime/monoclaw_runtime-0.13.0-py3-none-any.whl"
if bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle >"${TMP}/tamper.out" 2>&1; then
  printf 'expected manifest verification to fail after wheel tamper\n' >&2
  exit 1
fi
grep -q "artifact .* mismatch: runtime/monoclaw_runtime-0.13.0-py3-none-any.whl" "${TMP}/tamper.out"

if HATCH_INPUT_ROOT="${INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_RUNTIME_WHEEL="${WHEEL}" \
  HATCH_DIST_ROOT="${INPUTS}" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
  HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
    "${ROOT}/build.sh" >"${TMP}/unsafe-dist.out" 2>&1; then
  printf 'expected build to reject unsafe HATCH_DIST_ROOT\n' >&2
  exit 1
fi
grep -q "unsafe dist root" "${TMP}/unsafe-dist.out"
test -f "${INPUTS}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"

CORE_INPUTS="${TMP}/bundle-inputs-core"
CORE_DIST="${TMP}/core-dist"
mkdir -p "${CORE_INPUTS}/vendor/python/current/bin" "${CORE_INPUTS}/vendor/wheelhouse"
cp "${FAKE_PYTHON}" "${CORE_INPUTS}/vendor/python/current/bin/python3"
printf 'dependency wheel placeholder\n' > "${CORE_INPUTS}/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
HATCH_INPUT_ROOT="${CORE_INPUTS}" \
HATCH_RUNTIME_ROOT="${RUNTIME}" \
HATCH_RUNTIME_WHEEL="${WHEEL}" \
HATCH_DIST_ROOT="${CORE_DIST}" \
HATCH_MODEL_PACKS_ROOT="${TMP}/model-packs-core" \
HATCH_SKIP_RUNTIME_BUILD=1 \
HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  "${ROOT}/build.sh" | tee "${TMP}/core-build.out"
test -f "${CORE_DIST}/hatch-manifest.json"
test ! -d "${CORE_DIST}/vendor/models"
test ! -d "${TMP}/model-packs-core/gemma-4-e4b"

PROJECTS="${TMP}/Projects"
STANDALONE_HATCH="${PROJECTS}/hatch"
STANDALONE_RUNTIME="${PROJECTS}/monoclaw-runtime"
STANDALONE_DIST="${TMP}/standalone-dist"
STANDALONE_WHEEL="${TMP}/monoclaw_runtime-0.13.0-py3-none-any.whl"
mkdir -p "${PROJECTS}" "${STANDALONE_RUNTIME}" "${STANDALONE_HATCH}/bundle-inputs/vendor/models/gemma-4-e4b" "${STANDALONE_HATCH}/bundle-inputs/vendor/python/current/bin" "${STANDALONE_HATCH}/bundle-inputs/vendor/wheelhouse"
cp -R "${ROOT}/." "${STANDALONE_HATCH}/"
printf 'standalone Gemma placeholder\n' > "${STANDALONE_HATCH}/bundle-inputs/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"
cp "${FAKE_PYTHON}" "${STANDALONE_HATCH}/bundle-inputs/vendor/python/current/bin/python3"
printf 'standalone dependency wheel placeholder\n' > "${STANDALONE_HATCH}/bundle-inputs/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
printf 'standalone wheel placeholder\n' > "${STANDALONE_WHEEL}"
cat > "${STANDALONE_RUNTIME}/pyproject.toml" <<'TOML'
[project]
name = "monoclaw-runtime"
version = "0.13.0"
TOML

HATCH_RUNTIME_WHEEL="${STANDALONE_WHEEL}" \
HATCH_DIST_ROOT="${STANDALONE_DIST}" \
HATCH_SKIP_RUNTIME_BUILD=1 \
HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  "${STANDALONE_HATCH}/build.sh" | tee "${TMP}/standalone-build.out"
grep -q "Built by Hatch from ${STANDALONE_RUNTIME}" "${STANDALONE_DIST}/runtime/about.md"
test -x "${STANDALONE_DIST}/install.sh"
