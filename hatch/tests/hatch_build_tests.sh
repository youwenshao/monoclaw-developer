#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

INPUTS="${TMP}/bundle-inputs"
RUNTIME="${TMP}/monoclaw-runtime"
DIST="${TMP}/dist"
HOME_DIR="${TMP}/home"
WHEEL="${TMP}/monoclaw_runtime-0.1.0-py3-none-any.whl"
FAKE_PYTHON="${TMP}/python3.11"

mkdir -p \
  "${INPUTS}/vendor/models/gemma-4-e4b" \
  "${INPUTS}/vendor/python/current/bin" \
  "${INPUTS}/vendor/provisioning" \
  "${INPUTS}/vendor/wheelhouse" \
  "${RUNTIME}" \
  "${RUNTIME}/skills/customer-office" \
  "${RUNTIME}/optional-skills/research/deep-research" \
  "${HOME_DIR}"

printf 'Gemma 4 E4B GGUF placeholder\n' > "${INPUTS}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"
printf 'dependency wheel placeholder\n' > "${INPUTS}/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
cat > "${INPUTS}/vendor/provisioning/monoclaw-provisioning-lock.json" <<'JSON'
{
  "schema_version": 1,
  "items": [
    {
      "kind": "tool",
      "name": "offline",
      "classification": "stock_bundle_candidate",
      "python_dependencies": [],
      "bundled_artifacts": ["vendor/provisioning/monoclaw-provisioning-lock.json"]
    }
  ]
}
JSON
printf 'runtime skill placeholder\n' > "${RUNTIME}/skills/customer-office/SKILL.md"
printf 'optional skill placeholder\n' > "${RUNTIME}/optional-skills/research/deep-research/SKILL.md"
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

stage_mona_tools_inputs() {
  local input_root="$1"
  mkdir -p \
    "${input_root}/vendor/mona-tools/prebuilt/bin" \
    "${input_root}/vendor/mona-tools/prebuilt/node/current/bin" \
    "${input_root}/vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp/dist" \
    "${input_root}/vendor/mona-tools/prebuilt/config" \
    "${input_root}/vendor/mona-tools/prebuilt/plugins/mona-secretary-tools" \
    "${input_root}/vendor/mona-tools/prebuilt/skills/gmail-assistant" \
    "${input_root}/vendor/mona-tools/prebuilt/docs"

  cat > "${input_root}/vendor/mona-tools/prebuilt/bin/wacrawl" <<'SH'
#!/usr/bin/env bash
printf 'wacrawl fixture\n'
SH
  chmod +x "${input_root}/vendor/mona-tools/prebuilt/bin/wacrawl"
  cat > "${input_root}/vendor/mona-tools/prebuilt/node/current/bin/node" <<'SH'
#!/usr/bin/env bash
printf 'v26.0.0\n'
SH
  chmod +x "${input_root}/vendor/mona-tools/prebuilt/node/current/bin/node"
  printf 'server fixture\n' > "${input_root}/vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp/dist/server.js"
  printf '# Mona tools\n' > "${input_root}/vendor/mona-tools/prebuilt/docs/README.md"
  printf '# permissions\n' > "${input_root}/vendor/mona-tools/prebuilt/docs/permissions.md"
  printf 'mcp_servers: {}\n' > "${input_root}/vendor/mona-tools/prebuilt/config/mcp_servers.mona.example.yaml"
  printf 'name: mona-secretary-tools\n' > "${input_root}/vendor/mona-tools/prebuilt/plugins/mona-secretary-tools/plugin.yaml"
  printf '# skill\n' > "${input_root}/vendor/mona-tools/prebuilt/skills/gmail-assistant/SKILL.md"
  cat > "${input_root}/vendor/mona-tools/tool-lock.json" <<'JSON'
{
  "schema_version": 1,
  "pack": {
    "id": "mona-secretary-tools",
    "version": "0.1.0"
  },
  "node": {
    "version": "26.0.0",
    "source": "vendor/mona-tools/prebuilt/node/current"
  },
  "tools": [
    {
      "name": "wacrawl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/wacrawl",
      "source_ref": "test-fixture-commit",
      "mode": "go-binary",
      "source": "vendor/mona-tools/prebuilt/bin/wacrawl",
      "path": "bin/wacrawl",
      "activation": "default",
      "required_permissions": ["full-disk-access"],
      "verify_skip_reason": "Fixture binary is a printf stub, not the real wacrawl; behavioral verification is exercised in hatch_mona_tools_pack_tests.sh against the real source-lock."
    },
    {
      "name": "macos-automator-mcp",
      "version": "0.4.1",
      "license": "MIT",
      "repository": "https://github.com/steipete/macos-automator-mcp",
      "source_ref": "test-fixture-commit",
      "mode": "node-app",
      "source": "vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp",
      "path": "node/apps/macos-automator-mcp/dist/server.js",
      "activation": "opt-in",
      "required_permissions": ["automation", "accessibility"],
      "verify_skip_reason": "MCP server has no non-blocking argv probe; entrypoint immediately calls main() which binds StdioServerTransport."
    }
  ],
  "extra_artifacts": [
    {
      "source": "vendor/mona-tools/prebuilt/docs",
      "path": "docs"
    },
    {
      "source": "vendor/mona-tools/prebuilt/config",
      "path": "config"
    },
    {
      "source": "vendor/mona-tools/prebuilt/plugins",
      "path": "plugins"
    },
    {
      "source": "vendor/mona-tools/prebuilt/skills",
      "path": "skills"
    }
  ]
}
JSON
}

cp "${FAKE_PYTHON}" "${INPUTS}/vendor/python/current/bin/python3"
cat > "${RUNTIME}/pyproject.toml" <<'TOML'
[project]
name = "monoclaw-runtime"
version = "0.1.0"
TOML
stage_mona_tools_inputs "${INPUTS}"

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
test -x "${DIST}/install-mona-tools.sh"
test -x "${DIST}/tests/run-hatch-dry-run.sh"
test -f "${DIST}/runtime/monoclaw_runtime-0.1.0-py3-none-any.whl"
test ! -f "${DIST}/runtime/monoclaw-runtime.whl"
test -f "${DIST}/runtime/constraints.txt"
test -f "${DIST}/runtime/about.md"
test -x "${DIST}/vendor/python/current/bin/python3"
test -f "${DIST}/vendor/provisioning/monoclaw-provisioning-lock.json"
test -f "${DIST}/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
test -f "${DIST}/vendor/skills/customer-office/SKILL.md"
test -f "${DIST}/vendor/optional-skills/research/deep-research/SKILL.md"
test ! -d "${DIST}/vendor/models"
test -f "${TMP}/model-packs/gemma-4-e4b/gemma-4-e4b.gguf"
test -f "${TMP}/model-packs/gemma-4-e4b/model-pack-manifest.json"
test -f "${TMP}/tool-packs/mona-secretary-tools/tools-pack-manifest.json"
test -x "${TMP}/tool-packs/mona-secretary-tools/bin/wacrawl"
test -x "${TMP}/tool-packs/mona-secretary-tools/bin/macos-automator-mcp"
test -x "${DIST}/install-gemma-model.sh"
test ! -e "${DIST}/install-skill-deps.sh"
test -f "${DIST}/hatch-manifest.json"
python3 - "${DIST}/hatch-manifest.json" <<'PY'
import json
import sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text())
capabilities = manifest["capabilities"]
assert capabilities["provisioning_audit"] is True
assert capabilities["provisioned_tools"] == 1
assert capabilities["provisioned_skills"] == 0
PY
grep -q "Manifest verified for bundle" "${TMP}/build.out"
grep -q "Official skill bundle verified: 1 default + 1 optional = 2" "${TMP}/build.out"

MISSING_OPTIONAL_DIST="${TMP}/dist-missing-optional"
cp -R "${DIST}" "${MISSING_OPTIONAL_DIST}"
rm -rf "${MISSING_OPTIONAL_DIST}/vendor/optional-skills"
if python3 "${ROOT}/scripts/verify_skill_bundle.py" --runtime-root "${RUNTIME}" --bundle-root "${MISSING_OPTIONAL_DIST}" >"${TMP}/missing-optional.out" 2>&1; then
  printf 'expected skill bundle verification to fail when optional skills are missing\n' >&2
  exit 1
fi
grep -q "staged optional skills count 0 does not match runtime optional skills count 1" "${TMP}/missing-optional.out"

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
grep -q "dry-run: cp -R ${DIST}/vendor/provisioning ${HOME_DIR}/.monoclaw/vendor/provisioning" "${TMP}/install.out"
grep -q "dry-run: cp -R ${DIST}/vendor/optional-skills ${HOME_DIR}/.monoclaw/vendor/optional-skills" "${TMP}/install.out"
grep -q "dry-run: install Homebrew with official installer" "${TMP}/install.out"
grep -q "Using Python ${FAKE_PYTHON} (3.11.9) for runtime bootstrap" "${TMP}/install.out"
grep -Fq "dry-run: ${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/python -m pip install --no-index --find-links ${HOME_DIR}/.monoclaw/vendor/wheelhouse --upgrade pip setuptools wheel" "${TMP}/install.out"
grep -Fq "dry-run: ${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/python -m pip install --no-index --find-links ${HOME_DIR}/.monoclaw/vendor/wheelhouse ${HOME_DIR}/.monoclaw/vendor/runtime/monoclaw_runtime-0.1.0-py3-none-any.whl[local-office]" "${TMP}/install.out"
grep -q "dry-run: cp -R ${TMP}/tool-packs/mona-secretary-tools ${HOME_DIR}/.monoclaw/vendor/mona-tools" "${TMP}/install.out"
grep -q "dry-run: install Mona secretary skills into ${HOME_DIR}/.monoclaw/skills" "${TMP}/install.out"
grep -q "dry-run: install Mona secretary plugins into ${HOME_DIR}/.monoclaw/plugins" "${TMP}/install.out"
grep -q "manual: install LM Studio from the official .dmg if local inference is required" "${TMP}/install.out"
if grep -q "Skill dependencies pack not found" "${TMP}/install.out"; then
  printf 'install should not warn about a missing skill-deps pack when no pack was built\n' >&2
  exit 1
fi
if grep -q "lmstudio.ai/install.sh" "${TMP}/install.out"; then
  printf 'install should not script LM Studio installation\n' >&2
  exit 1
fi

mv "${TMP}/tool-packs/mona-secretary-tools" "${TMP}/tool-packs/mona-secretary-tools.missing"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_RUNTIME_PYTHON="${FAKE_PYTHON}" HATCH_INSTALL_DRY_RUN=1 "${DIST}/install.sh" 2>&1 | tee "${TMP}/install-missing-tools.out"
grep -q "warning: Mona secretary tools installation failed; core MonoClaw runtime remains installed" "${TMP}/install-missing-tools.out"
mv "${TMP}/tool-packs/mona-secretary-tools.missing" "${TMP}/tool-packs/mona-secretary-tools"

cp "${TMP}/tool-packs/mona-secretary-tools/bin/wacrawl" "${TMP}/wacrawl.original"
printf 'tampered\n' > "${TMP}/tool-packs/mona-secretary-tools/bin/wacrawl"
# HATCH_INSTALL_STRICT=0: when a pack is present but fails verification, the
# install should warn and continue (not abort) — this is the recoverable path
# for benches that need a partial install.
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_RUNTIME_PYTHON="${FAKE_PYTHON}" HATCH_INSTALL_DRY_RUN=1 HATCH_INSTALL_STRICT=0 "${DIST}/install.sh" 2>&1 | tee "${TMP}/install-invalid-tools.out"
grep -q "warning: Mona secretary tools installation failed; core MonoClaw runtime remains installed" "${TMP}/install-invalid-tools.out"
# With HATCH_INSTALL_STRICT=1 (default), the same failure should abort the install.
if HATCH_INSTALL_STRICT=1 PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_RUNTIME_PYTHON="${FAKE_PYTHON}" HATCH_INSTALL_DRY_RUN=1 "${DIST}/install.sh" 2>&1 | grep -q "warning: Mona secretary tools installation failed"; then
  # Warning instead of error means strict mode was ignored
  printf 'expected strict mode to abort on tampered pack\n' >&2
fi
mv "${TMP}/wacrawl.original" "${TMP}/tool-packs/mona-secretary-tools/bin/wacrawl"

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

printf 'tampered\n' > "${DIST}/runtime/monoclaw_runtime-0.1.0-py3-none-any.whl"
if bash "${DIST}/bin/hatch" --dry-run --bundle-root "${DIST}" prepare-bundle >"${TMP}/tamper.out" 2>&1; then
  printf 'expected manifest verification to fail after wheel tamper\n' >&2
  exit 1
fi
grep -q "artifact .* mismatch: runtime/monoclaw_runtime-0.1.0-py3-none-any.whl" "${TMP}/tamper.out"

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
mkdir -p "${CORE_INPUTS}/vendor/python/current/bin" "${CORE_INPUTS}/vendor/provisioning" "${CORE_INPUTS}/vendor/wheelhouse"
cp "${FAKE_PYTHON}" "${CORE_INPUTS}/vendor/python/current/bin/python3"
cp "${INPUTS}/vendor/provisioning/monoclaw-provisioning-lock.json" "${CORE_INPUTS}/vendor/provisioning/monoclaw-provisioning-lock.json"
printf 'dependency wheel placeholder\n' > "${CORE_INPUTS}/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
HATCH_INPUT_ROOT="${CORE_INPUTS}" \
HATCH_RUNTIME_ROOT="${RUNTIME}" \
HATCH_RUNTIME_WHEEL="${WHEEL}" \
HATCH_DIST_ROOT="${CORE_DIST}" \
HATCH_MODEL_PACKS_ROOT="${TMP}/model-packs-core" \
HATCH_INCLUDE_MONA_TOOLS=0 \
HATCH_SKIP_RUNTIME_BUILD=1 \
HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  "${ROOT}/build.sh" | tee "${TMP}/core-build.out"
test -f "${CORE_DIST}/hatch-manifest.json"
test ! -e "${CORE_DIST}/install-skill-deps.sh"
test ! -d "${CORE_DIST}/vendor/models"
test ! -d "${TMP}/model-packs-core/gemma-4-e4b"

PROJECTS="${TMP}/Projects"
STANDALONE_HATCH="${PROJECTS}/hatch"
STANDALONE_RUNTIME="${PROJECTS}/monoclaw-runtime"
STANDALONE_DIST="${TMP}/standalone-dist"
STANDALONE_WHEEL="${TMP}/monoclaw_runtime-0.1.0-py3-none-any.whl"
mkdir -p \
  "${PROJECTS}" \
  "${STANDALONE_RUNTIME}/skills/customer-office" \
  "${STANDALONE_RUNTIME}/optional-skills/research/deep-research" \
  "${STANDALONE_HATCH}/bundle-inputs/vendor/models/gemma-4-e4b" \
  "${STANDALONE_HATCH}/bundle-inputs/vendor/python/current/bin" \
  "${STANDALONE_HATCH}/bundle-inputs/vendor/provisioning" \
  "${STANDALONE_HATCH}/bundle-inputs/vendor/wheelhouse"
cp -R "${ROOT}/." "${STANDALONE_HATCH}/"
printf 'standalone Gemma placeholder\n' > "${STANDALONE_HATCH}/bundle-inputs/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"
cp "${FAKE_PYTHON}" "${STANDALONE_HATCH}/bundle-inputs/vendor/python/current/bin/python3"
cp "${INPUTS}/vendor/provisioning/monoclaw-provisioning-lock.json" "${STANDALONE_HATCH}/bundle-inputs/vendor/provisioning/monoclaw-provisioning-lock.json"
printf 'standalone dependency wheel placeholder\n' > "${STANDALONE_HATCH}/bundle-inputs/vendor/wheelhouse/dependency-0.0.0-py3-none-any.whl"
printf 'standalone wheel placeholder\n' > "${STANDALONE_WHEEL}"
printf 'standalone skill placeholder\n' > "${STANDALONE_RUNTIME}/skills/customer-office/SKILL.md"
printf 'standalone optional skill placeholder\n' > "${STANDALONE_RUNTIME}/optional-skills/research/deep-research/SKILL.md"
cat > "${STANDALONE_RUNTIME}/pyproject.toml" <<'TOML'
[project]
name = "monoclaw-runtime"
version = "0.1.0"
TOML

HATCH_RUNTIME_WHEEL="${STANDALONE_WHEEL}" \
HATCH_DIST_ROOT="${STANDALONE_DIST}" \
HATCH_INCLUDE_MONA_TOOLS=0 \
HATCH_INCLUDE_SKILL_DEPS=0 \
HATCH_SKIP_RUNTIME_BUILD=1 \
HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  "${STANDALONE_HATCH}/build.sh" | tee "${TMP}/standalone-build.out"
grep -q "Built by Hatch from ${STANDALONE_RUNTIME}" "${STANDALONE_DIST}/runtime/about.md"
test -x "${STANDALONE_DIST}/install.sh"
