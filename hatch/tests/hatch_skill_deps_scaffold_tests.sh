#!/usr/bin/env bash
# Phase 5 of the skill readiness uplift program lands an empty
# `tool-packs/skill-deps-pack/` scaffolding pattern that mirrors the
# Mona secretary tools pack.  This test pins the safety contract:
#
#   * `bin/hatch verify-skill-deps` and `install-skill-deps` are wired and
#     accept the `--skill-deps-pack-root` flag.
#   * `scripts/build_skill_deps_pack.sh` is a no-op when the pack input is
#     missing (default scaffolding state) and refuses to ship an empty
#     pack when input is partial.
#   * `templates/install-skill-deps.sh` exits cleanly with no pack on the
#     provisioning medium.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Verify hatch CLI usage text mentions the new verbs.
HELP="$(bash "${ROOT}/bin/hatch" --help 2>&1 || true)"
case "${HELP}" in
  *install-skill-deps*) ;;
  *) printf 'fail: bin/hatch help missing install-skill-deps verb\n' >&2; exit 1;;
esac
case "${HELP}" in
  *verify-skill-deps*) ;;
  *) printf 'fail: bin/hatch help missing verify-skill-deps verb\n' >&2; exit 1;;
esac

# Verify hatch accepts --skill-deps-pack-root flag without erroring.
EMPTY_PACK="${TMP}/skill-deps-pack"
mkdir -p "${EMPTY_PACK}"
mkdir -p "${TMP}/dist"
OUT="$(bash "${ROOT}/bin/hatch" --dry-run --bundle-root "${TMP}/dist" --skill-deps-pack-root "${EMPTY_PACK}" verify-skill-deps 2>&1)"
case "${OUT}" in
  *"missing tools-pack-manifest.json"*) ;;
  *) printf 'fail: verify-skill-deps did not warn about missing manifest. got: %s\n' "${OUT}" >&2; exit 1;;
esac

# Build script must skip when explicitly disabled.
DISABLED_OUT="$(HATCH_INCLUDE_SKILL_DEPS=0 bash "${ROOT}/scripts/build_skill_deps_pack.sh" 2>&1)"
case "${DISABLED_OUT}" in
  *"disabled"*) ;;
  *) printf 'fail: build_skill_deps_pack.sh did not skip when disabled. got: %s\n' "${DISABLED_OUT}" >&2; exit 1;;
esac

# Legacy spelling HATCH_INCLUDE_SKILLS_DEPS=0 must also disable.
DISABLED_SPELL_OUT="$(HATCH_INCLUDE_SKILLS_DEPS=0 bash "${ROOT}/scripts/build_skill_deps_pack.sh" 2>&1)"
case "${DISABLED_SPELL_OUT}" in
  *"disabled"*) ;;
  *) printf 'fail: build_skill_deps_pack.sh did not skip when legacy SKILLS var disabled. got: %s\n' "${DISABLED_SPELL_OUT}" >&2; exit 1;;
esac

# Build script must skip cleanly when enabled but no tool-lock.json yet.
INPUT_ROOT="${TMP}/inputs"
mkdir -p "${INPUT_ROOT}/vendor/skill-deps"
TOOLS_PACKS="${TMP}/tool-packs"
mkdir -p "${TOOLS_PACKS}"
HATCH_INCLUDE_SKILL_DEPS=1 \
HATCH_INPUT_ROOT="${INPUT_ROOT}" \
HATCH_TOOLS_PACKS_ROOT="${TOOLS_PACKS}" \
  bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/build.out" 2>&1
case "$(cat "${TMP}/build.out")" in
  *"nothing to build"*) ;;
  *) printf 'fail: build_skill_deps_pack.sh did not log "nothing to build" when lock is absent. got: %s\n' "$(cat "${TMP}/build.out")" >&2; exit 1;;
esac
if [[ -e "${TOOLS_PACKS}/skill-deps-pack" ]]; then
  printf 'fail: build script created an empty pack when no tool-lock.json was provided\n' >&2
  exit 1
fi

# Build script must remove a stale skill-deps pack when enabled but no lock exists.
mkdir -p "${TOOLS_PACKS}/skill-deps-pack"
printf 'stale pack\n' > "${TOOLS_PACKS}/skill-deps-pack/stale.txt"
HATCH_INPUT_ROOT="${INPUT_ROOT}" \
HATCH_TOOLS_PACKS_ROOT="${TOOLS_PACKS}" \
  bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/stale-build.out" 2>&1
if [[ -e "${TOOLS_PACKS}/skill-deps-pack" ]]; then
  printf 'fail: build script left a stale pack when no tool-lock.json was provided\n' >&2
  exit 1
fi

# Populated lock should build a binary-only pack, verify it, and install it.
POPULATED_INPUT="${TMP}/populated-inputs"
POPULATED_PACKS="${TMP}/populated-tool-packs"
POPULATED_DIST="${TMP}/populated-dist"
POPULATED_HOME="${TMP}/populated-home"
mkdir -p \
  "${POPULATED_INPUT}/vendor/skill-deps/prebuilt/bin" \
  "${POPULATED_PACKS}" \
  "${POPULATED_DIST}/bin" \
  "${POPULATED_DIST}/lib" \
  "${POPULATED_DIST}/vendor/python/current/bin" \
  "${POPULATED_HOME}"
cat > "${POPULATED_INPUT}/vendor/skill-deps/prebuilt/bin/fake-remindctl" <<'SH'
#!/usr/bin/env sh
printf 'fake remindctl\n'
SH
chmod +x "${POPULATED_INPUT}/vendor/skill-deps/prebuilt/bin/fake-remindctl"
FAKE_SHA="$(python3 - "${POPULATED_INPUT}/vendor/skill-deps/prebuilt/bin/fake-remindctl" <<'PY'
import hashlib
import sys
from pathlib import Path
print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
cat > "${POPULATED_INPUT}/vendor/skill-deps/tool-lock.json" <<JSON
{
  "schema_version": 1,
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "tools": [
    {
      "name": "fake-remindctl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://example.invalid/fake-remindctl",
      "source_ref": "fixture",
      "activation": "opt-in",
      "required_permissions": ["reminders"],
      "source": "prebuilt/bin/fake-remindctl",
      "path": "bin/fake-remindctl",
      "sha256": "${FAKE_SHA}"
    }
  ]
}
JSON
HATCH_INPUT_ROOT="${POPULATED_INPUT}" \
HATCH_TOOLS_PACKS_ROOT="${POPULATED_PACKS}" \
HATCH_TARGET_ARCH="$(uname -m)" \
  bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/populated-build.out" 2>&1
test -x "${POPULATED_PACKS}/skill-deps-pack/bin/fake-remindctl"
test -f "${POPULATED_PACKS}/skill-deps-pack/tools-pack-manifest.json"
cp "${ROOT}/bin/hatch" "${POPULATED_DIST}/bin/hatch"
cp "${ROOT}/lib/common.sh" "${POPULATED_DIST}/lib/common.sh"
cp "$(command -v python3)" "${POPULATED_DIST}/vendor/python/current/bin/python3"
chmod +x "${POPULATED_DIST}/bin/hatch" "${POPULATED_DIST}/vendor/python/current/bin/python3"
bash "${POPULATED_DIST}/bin/hatch" --dry-run --bundle-root "${POPULATED_DIST}" --skill-deps-pack-root "${POPULATED_PACKS}/skill-deps-pack" verify-skill-deps >"${TMP}/populated-verify.out" 2>&1
case "$(cat "${TMP}/populated-verify.out")" in
  *"Tools pack verified for skill-deps-pack"*) ;;
  *) printf 'fail: verify-skill-deps did not verify populated pack. got: %s\n' "$(cat "${TMP}/populated-verify.out")" >&2; exit 1;;
esac
SYMLINK_PACK="${TMP}/external-symlink-pack"
mkdir -p "${SYMLINK_PACK}/python/memo/bin"
ln -s "/opt/homebrew/Cellar/python@3.13/missing/bin/python3.13" "${SYMLINK_PACK}/python/memo/bin/python"
cat > "${SYMLINK_PACK}/tools-pack-manifest.json" <<JSON
{
  "schema_version": 1,
  "created_at": "2026-01-01T00:00:00Z",
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "target": {
    "platform": "darwin",
    "arch": "$(uname -m)"
  },
  "runtime": {},
  "tools": [
    {
      "name": "memo",
      "version": "0.5.3",
      "path": "python/memo/bin/python",
      "activation": "opt-in",
      "required_permissions": ["notes"]
    }
  ],
  "artifacts": [
    {
      "path": "python/memo/bin/python",
      "kind": "file",
      "sha256": "replace-with-sha",
      "bytes": 1
    }
  ]
}
JSON
if bash "${POPULATED_DIST}/bin/hatch" --dry-run --bundle-root "${POPULATED_DIST}" --skill-deps-pack-root "${SYMLINK_PACK}" verify-skill-deps >"${TMP}/external-symlink.out" 2>&1; then
  printf 'fail: verify-skill-deps accepted an out-of-pack symlink\n' >&2
  exit 1
fi
grep -q "tools pack path escapes pack root: python/memo/bin/python" "${TMP}/external-symlink.out"

IN_PACK_SYMLINK="${TMP}/in-pack-symlink-pack"
mkdir -p "${IN_PACK_SYMLINK}/bin"
cat > "${IN_PACK_SYMLINK}/bin/real-tool" <<'SH'
#!/usr/bin/env sh
printf 'real tool\n'
SH
chmod +x "${IN_PACK_SYMLINK}/bin/real-tool"
ln -s "real-tool" "${IN_PACK_SYMLINK}/bin/link-tool"
REAL_SHA="$(python3 - "${IN_PACK_SYMLINK}/bin/real-tool" <<'PY'
import hashlib
import sys
from pathlib import Path
print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
REAL_BYTES="$(python3 - "${IN_PACK_SYMLINK}/bin/real-tool" <<'PY'
import sys
from pathlib import Path
print(Path(sys.argv[1]).stat().st_size)
PY
)"
cat > "${IN_PACK_SYMLINK}/tools-pack-manifest.json" <<JSON
{
  "schema_version": 1,
  "created_at": "2026-01-01T00:00:00Z",
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "target": {
    "platform": "darwin",
    "arch": "$(uname -m)"
  },
  "runtime": {},
  "tools": [
    {
      "name": "link-tool",
      "version": "0.1.0",
      "path": "bin/link-tool",
      "activation": "opt-in",
      "required_permissions": []
    }
  ],
  "artifacts": [
    {
      "path": "bin/link-tool",
      "kind": "file",
      "sha256": "${REAL_SHA}",
      "bytes": ${REAL_BYTES}
    },
    {
      "path": "bin/real-tool",
      "kind": "file",
      "sha256": "${REAL_SHA}",
      "bytes": ${REAL_BYTES}
    }
  ]
}
JSON
bash "${POPULATED_DIST}/bin/hatch" --dry-run --bundle-root "${POPULATED_DIST}" --skill-deps-pack-root "${IN_PACK_SYMLINK}" verify-skill-deps >"${TMP}/in-pack-symlink.out" 2>&1
grep -q "Tools pack verified for skill-deps-pack" "${TMP}/in-pack-symlink.out"
cp "${ROOT}/templates/install-skill-deps.sh" "${POPULATED_DIST}/install-skill-deps.sh"
chmod +x "${POPULATED_DIST}/install-skill-deps.sh"
mkdir -p "${TMP}/tool-packs"
rm -rf "${TMP}/tool-packs/skill-deps-pack"
cp -R "${POPULATED_PACKS}/skill-deps-pack" "${TMP}/tool-packs/skill-deps-pack"
HOME="${POPULATED_HOME}" MONOCLAW_HOME="${POPULATED_HOME}/.monoclaw" \
  bash "${POPULATED_DIST}/install-skill-deps.sh" >"${TMP}/populated-install.out" 2>&1
test -x "${POPULATED_HOME}/.monoclaw/vendor/skill-deps/bin/fake-remindctl"

# Placeholder lock should trigger auto-prep from source-lock before strict verify.
AUTO_INPUT="${TMP}/auto-inputs"
AUTO_PACKS="${TMP}/auto-tool-packs"
mkdir -p "${AUTO_INPUT}/vendor/skill-deps/fixtures" "${AUTO_PACKS}"
cat > "${AUTO_INPUT}/vendor/skill-deps/fixtures/fake-remindctl" <<'SH'
#!/usr/bin/env sh
printf 'auto-prepped remindctl\n'
SH
chmod +x "${AUTO_INPUT}/vendor/skill-deps/fixtures/fake-remindctl"
cat > "${AUTO_INPUT}/vendor/skill-deps/source-lock.json" <<'JSON'
{
  "schema_version": 1,
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "tools": [
    {
      "name": "fake-remindctl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://example.invalid/fake-remindctl",
      "source_ref": "fixture",
      "activation": "opt-in",
      "required_permissions": ["reminders"],
      "source": "prebuilt/bin/fake-remindctl",
      "path": "bin/fake-remindctl",
      "methods": [
        {
          "type": "local_binary",
          "path": "fixtures/fake-remindctl"
        }
      ]
    }
  ]
}
JSON
cat > "${AUTO_INPUT}/vendor/skill-deps/tool-lock.json" <<'JSON'
{
  "schema_version": 1,
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "tools": [
    {
      "name": "fake-remindctl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://example.invalid/fake-remindctl",
      "source_ref": "replace-with-reviewed-release-or-commit",
      "activation": "opt-in",
      "required_permissions": ["reminders"],
      "source": "prebuilt/bin/fake-remindctl",
      "path": "bin/fake-remindctl",
      "sha256": "replace-with-sha256"
    }
  ]
}
JSON
HATCH_INPUT_ROOT="${AUTO_INPUT}" \
HATCH_TOOLS_PACKS_ROOT="${AUTO_PACKS}" \
HATCH_TARGET_ARCH="$(uname -m)" \
  bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/auto-build.out" 2>&1
grep -q "running prepare_skill_deps_inputs.sh" "${TMP}/auto-build.out"
test -x "${AUTO_PACKS}/skill-deps-pack/bin/fake-remindctl"
python3 - "${AUTO_INPUT}/vendor/skill-deps/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
sha = data["tools"][0]["sha256"]
assert sha and not sha.startswith("replace"), sha
PY

cat > "${AUTO_INPUT}/vendor/skill-deps/tool-lock.json" <<'JSON'
{
  "schema_version": 1,
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "tools": [
    {
      "name": "fake-remindctl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://example.invalid/fake-remindctl",
      "source_ref": "replace-with-reviewed-release-or-commit",
      "activation": "opt-in",
      "required_permissions": ["reminders"],
      "source": "prebuilt/bin/fake-remindctl",
      "path": "bin/fake-remindctl",
      "sha256": "replace-with-sha256"
    }
  ]
}
JSON
if HATCH_SKILL_DEPS_AUTO_PREP=0 \
  HATCH_INPUT_ROOT="${AUTO_INPUT}" \
  HATCH_TOOLS_PACKS_ROOT="${TMP}/auto-disabled-packs" \
    bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/auto-disabled.out" 2>&1; then
  printf 'fail: build_skill_deps_pack.sh should fail when placeholders remain and auto-prep is disabled\n' >&2
  exit 1
fi
grep -q "placeholders or missing sources" "${TMP}/auto-disabled.out"

# Python-backed tools should use staged bundle Python and ship wheelhouse artifacts.
PY_INPUT="${TMP}/python-inputs"
PY_PACKS="${TMP}/python-tool-packs"
PY_PACKAGE="${TMP}/fake-memo-package"
PY_MARKER="${TMP}/staged-python-used.log"
PY_HOME="${TMP}/python-home"
PY_DIST="${TMP}/python-dist"
mkdir -p \
  "${PY_INPUT}/vendor/skill-deps" \
  "${PY_INPUT}/vendor/python/current/bin" \
  "${PY_PACKS}" \
  "${PY_PACKAGE}/fake_memo" \
  "${PY_DIST}/bin" \
  "${PY_DIST}/lib" \
  "${PY_DIST}/vendor/python/current/bin" \
  "${PY_HOME}/.monoclaw/vendor/python/current/bin"
cat > "${PY_INPUT}/vendor/python/current/bin/python3" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${PY_MARKER}"
if [[ "\$1" == "-c" ]]; then
  printf '3.13.0\n'
  exit 0
fi
if [[ "\$1" == "-m" && "\$2" == "venv" ]]; then
  venv_dir="\$3"
  mkdir -p "\${venv_dir}/bin"
  cat > "\${venv_dir}/bin/python" <<'PYSH'
#!/usr/bin/env bash
if [[ "\$1" == "-m" && "\$2" == "pip" && "\$3" == "--version" ]]; then
  printf 'pip 0.0 fixture\n'
  exit 0
fi
exit 0
PYSH
  cat > "\${venv_dir}/bin/pip" <<'PIPSH'
#!/usr/bin/env bash
script_dir="\$(cd "\$(dirname "\$0")" && pwd)"
cat > "\${script_dir}/fake-memo" <<'MEMOSH'
#!/usr/bin/env bash
printf 'fake memo\n'
MEMOSH
chmod +x "\${script_dir}/fake-memo"
exit 0
PIPSH
  chmod +x "\${venv_dir}/bin/python" "\${venv_dir}/bin/pip"
  exit 0
fi
if [[ "\$1" == "-m" && "\$2" == "pip" && "\$3" == "wheel" ]]; then
  wheel_dir=""
  while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--wheel-dir" ]]; then
      wheel_dir="\$2"
      shift 2
      continue
    fi
    shift
  done
  mkdir -p "\${wheel_dir}"
  printf 'fake wheel\n' > "\${wheel_dir}/fake_memo-0.1.0-py3-none-any.whl"
  exit 0
fi
exit 1
SH
chmod +x "${PY_INPUT}/vendor/python/current/bin/python3"
cat > "${PY_PACKAGE}/pyproject.toml" <<'TOML'
[build-system]
requires = ["setuptools", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "fake-memo"
version = "0.1.0"

[project.scripts]
fake-memo = "fake_memo:main"
TOML
cat > "${PY_PACKAGE}/fake_memo/__init__.py" <<'PY'
def main():
    print("fake memo")
PY
cat > "${PY_INPUT}/vendor/skill-deps/source-lock.json" <<JSON
{
  "schema_version": 1,
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "tools": [
    {
      "name": "fake-memo",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://example.invalid/fake-memo",
      "source_ref": "fixture",
      "activation": "opt-in",
      "required_permissions": ["notes"],
      "source": "prebuilt/python/fake-memo/.install-marker",
      "path": "python/fake-memo/.install-marker",
      "methods": [
        {
          "type": "python_wheelhouse",
          "package": "${PY_PACKAGE}",
          "entrypoint": "fake-memo",
          "min_python": "3.13",
          "support_source": "prebuilt/python/fake-memo",
          "support_path": "python/fake-memo"
        }
      ]
    }
  ]
}
JSON
HATCH_INPUT_ROOT="${PY_INPUT}" \
HATCH_TOOLS_PACKS_ROOT="${PY_PACKS}" \
HATCH_TARGET_ARCH="$(uname -m)" \
  bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/python-build.out" 2>&1
grep -q "using bundled Python" "${TMP}/python-build.out"
grep -q -- "-m pip wheel" "${PY_MARKER}"
test -f "${PY_PACKS}/skill-deps-pack/python/fake-memo/.install-marker"
test -f "${PY_PACKS}/skill-deps-pack/python/fake-memo/package-spec.json"
test -f "${PY_PACKS}/skill-deps-pack/python/fake-memo/wheelhouse/fake_memo-0.1.0-py3-none-any.whl"
test ! -e "${PY_PACKS}/skill-deps-pack/bin/fake-memo"
test ! -e "${PY_PACKS}/skill-deps-pack/python/fake-memo/bin/python"
python3 - "${PY_INPUT}/vendor/skill-deps/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
tool = data["tools"][0]
assert tool["source"] == "prebuilt/python/fake-memo/.install-marker"
assert tool["path"] == "python/fake-memo/.install-marker"
assert tool["extra_artifacts"] == [
    {"source": "prebuilt/python/fake-memo", "path": "python/fake-memo"}
]
PY
cp "${ROOT}/bin/hatch" "${PY_DIST}/bin/hatch"
cp "${ROOT}/lib/common.sh" "${PY_DIST}/lib/common.sh"
cp "$(command -v python3)" "${PY_DIST}/vendor/python/current/bin/python3"
cp "${ROOT}/templates/install-skill-deps.sh" "${PY_DIST}/install-skill-deps.sh"
chmod +x "${PY_DIST}/bin/hatch" "${PY_DIST}/vendor/python/current/bin/python3" "${PY_DIST}/install-skill-deps.sh"
cat > "${PY_HOME}/.monoclaw/vendor/python/current/bin/python3" <<'PYRT'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]]; then
  printf '3.13.0\n'
  exit 0
fi
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  venv_dir="$3"
  mkdir -p "${venv_dir}/bin"
  cat > "${venv_dir}/bin/python" <<'VENVPY'
#!/usr/bin/env bash
if [[ "$1" == "-m" && "$2" == "pip" && "$3" == "install" ]]; then
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  cat > "${script_dir}/fake-memo" <<'FAKEMEMO'
#!/usr/bin/env bash
printf 'installed fake memo\n'
FAKEMEMO
  chmod +x "${script_dir}/fake-memo"
  exit 0
fi
exit 1
VENVPY
  chmod +x "${venv_dir}/bin/python"
  exit 0
fi
exit 1
PYRT
chmod +x "${PY_HOME}/.monoclaw/vendor/python/current/bin/python3"
rm -rf "${TMP}/tool-packs/skill-deps-pack"
mkdir -p "${TMP}/tool-packs"
cp -R "${PY_PACKS}/skill-deps-pack" "${TMP}/tool-packs/skill-deps-pack"
HOME="${PY_HOME}" MONOCLAW_HOME="${PY_HOME}/.monoclaw" \
  bash "${PY_DIST}/install-skill-deps.sh" >"${TMP}/python-install.out" 2>&1
test -x "${PY_HOME}/.monoclaw/vendor/skill-deps/bin/fake-memo"
"${PY_HOME}/.monoclaw/vendor/skill-deps/bin/fake-memo" >"${TMP}/fake-memo-run.out"
grep -q "installed fake memo" "${TMP}/fake-memo-run.out"

STRICT_INPUT="${TMP}/strict-python-inputs"
STRICT_PACKAGE="${TMP}/strict-python-package"
mkdir -p "${STRICT_INPUT}/vendor/skill-deps" "${STRICT_PACKAGE}"
cat > "${STRICT_INPUT}/vendor/skill-deps/source-lock.json" <<JSON
{
  "schema_version": 1,
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "tools": [
    {
      "name": "strict-memo",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://example.invalid/strict-memo",
      "source_ref": "fixture",
      "activation": "opt-in",
      "required_permissions": ["notes"],
      "source": "prebuilt/python/strict-memo/.install-marker",
      "path": "python/strict-memo/.install-marker",
      "methods": [
        {
          "type": "python_wheelhouse",
          "package": "${STRICT_PACKAGE}",
          "entrypoint": "strict-memo",
          "min_python": "3.13",
          "support_source": "prebuilt/python/strict-memo",
          "support_path": "python/strict-memo"
        }
      ]
    }
  ]
}
JSON
if HATCH_INPUT_ROOT="${STRICT_INPUT}" \
  HATCH_SKILL_DEPS_SOURCE_LOCK="${STRICT_INPUT}/vendor/skill-deps/source-lock.json" \
  HATCH_SKILL_DEPS_BUILD_ROOT="${TMP}/strict-build" \
    bash "${ROOT}/scripts/prepare_skill_deps_inputs.sh" >"${TMP}/strict-python.out" 2>&1; then
  printf 'fail: prepare_skill_deps_inputs.sh used system/Homebrew Python when bundled Python was missing\n' >&2
  exit 1
fi
grep -q "stage bundle-inputs/vendor/python/current/bin/python3" "${TMP}/strict-python.out"

# Install template should exit cleanly when no pack exists alongside dist/.
rm -rf "${TMP}/tool-packs/skill-deps-pack"
DIST="${TMP}/install-test-dist"
mkdir -p "${DIST}/bin"
cp "${ROOT}/bin/hatch" "${DIST}/bin/hatch"
chmod +x "${DIST}/bin/hatch"
cp "${ROOT}/templates/install-skill-deps.sh" "${DIST}/install-skill-deps.sh"
chmod +x "${DIST}/install-skill-deps.sh"
INSTALL_OUT="$(bash "${DIST}/install-skill-deps.sh" 2>&1)"
case "${INSTALL_OUT}" in
  *"Skill dependencies pack not found"*) ;;
  *) printf 'fail: install-skill-deps.sh did not warn that the pack was missing. got: %s\n' "${INSTALL_OUT}" >&2; exit 1;;
esac
case "${INSTALL_OUT}" in
  *"The pack is optional and only built when"*)
    printf 'fail: install-skill-deps.sh printed stale opt-in wording. got: %s\n' "${INSTALL_OUT}" >&2
    exit 1
    ;;
esac
case "${INSTALL_OUT}" in
  *"skills-deps-pack"*)
    printf 'fail: install-skill-deps.sh used pluralized skills-deps-pack path. got: %s\n' "${INSTALL_OUT}" >&2
    exit 1
    ;;
esac

printf 'ok: skill-deps scaffold\n'
