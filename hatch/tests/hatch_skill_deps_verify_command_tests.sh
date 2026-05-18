#!/usr/bin/env bash
# End-to-end tests for the verify_command contract on the skill-deps pack.
#
# Covers:
#   - source-lock declared verify_command propagates through
#     prepare_skill_deps_inputs.sh -> tool-lock.json
#   - tool-lock.json fields propagate through build_skill_deps_pack.sh ->
#     tools-pack-manifest.json
#   - build_skill_deps_pack.sh now runs `verify-skill-deps` at the end and
#     respects HATCH_TOOLS_PACK_STRICT_VERIFY=1
#   - probes that exit 0 are silent
#   - verify_skip_reason silences the "no verify_command" warn honestly
#   - probes that exit 1 with verify_strict: true fail the build
#
# Mirrors the structure of hatch_tools_pack_verify_command_tests.sh but
# scoped to the skill-deps pack pipeline.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

HOME_DIR="${TMP}/home"
mkdir -p "${HOME_DIR}"
HATCH_BIN="${ROOT}/bin/hatch"

# scaffold_skill_deps_source <input_root> <fixture_root>
#   Writes vendor/skill-deps/source-lock.json that points at fixture binaries
#   and an .install-marker placeholder for a wheelhouse-style tool. Uses the
#   local_binary preparation path so we don't need network access.
scaffold_skill_deps_source() {
  local input_root="$1"
  local fixtures="$2"
  mkdir -p \
    "${input_root}/vendor/skill-deps" \
    "${input_root}/vendor/python/current/bin" \
    "${fixtures}/bin" \
    "${fixtures}/python/marker"

  # Bundled Python: needed because prepare_skill_deps_inputs.sh probes
  # vendor/python/current/bin/python3 for venv/pip readiness.
  ln -sf "$(command -v python3)" "${input_root}/vendor/python/current/bin/python3"

  cat > "${fixtures}/bin/exit-zero-binary" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "${fixtures}/bin/exit-one-binary" <<'SH'
#!/usr/bin/env bash
echo "fixture intentional failure" >&2
exit 1
SH
  chmod +x "${fixtures}/bin/exit-zero-binary" "${fixtures}/bin/exit-one-binary"

  # Wheelhouse-style fixture: just an .install-marker placeholder so prep
  # treats it like the real memo path. Use the local_binary method pointed
  # at the marker file.
  cat > "${fixtures}/python/marker/.install-marker" <<'TXT'
fixture wheelhouse marker
TXT

  cat > "${input_root}/vendor/skill-deps/source-lock.json" <<JSON
{
  "schema_version": 1,
  "pack": {
    "id": "skill-deps-pack",
    "version": "0.1.0"
  },
  "tools": [
    {
      "name": "good-tool",
      "version": "1.0.0",
      "license": "MIT",
      "repository": "https://example.com/good-tool",
      "source_ref": "v1.0.0",
      "activation": "opt-in",
      "required_permissions": ["network"],
      "source": "prebuilt/bin/good-tool",
      "path": "bin/good-tool",
      "verify_command": ["{bin}", "--version"],
      "verify_strict": true,
      "methods": [
        {
          "type": "local_binary",
          "path": "${fixtures}/bin/exit-zero-binary"
        }
      ]
    },
    {
      "name": "wheel-tool",
      "version": "1.0.0",
      "license": "MIT",
      "repository": "https://example.com/wheel-tool",
      "source_ref": "v1.0.0",
      "activation": "opt-in",
      "required_permissions": ["notes"],
      "source": "prebuilt/python/marker/.install-marker",
      "path": "python/marker/.install-marker",
      "verify_skip_reason": "Wheelhouse fixture; entrypoint is installed at install time.",
      "methods": [
        {
          "type": "local_binary",
          "path": "${fixtures}/python/marker/.install-marker"
        }
      ]
    }
  ]
}
JSON
}

# CASE 1 — successful build: probes pass, manifest carries fields, verifier
# reports verified.
CASE1_INPUTS="${TMP}/case1-inputs"
CASE1_FIXTURES="${TMP}/case1-fixtures"
CASE1_PACKS="${TMP}/case1-packs"
scaffold_skill_deps_source "${CASE1_INPUTS}" "${CASE1_FIXTURES}"

HATCH_INPUT_ROOT="${CASE1_INPUTS}" \
HATCH_SKILL_DEPS_FORCE=1 \
  bash "${ROOT}/scripts/prepare_skill_deps_inputs.sh" >"${TMP}/case1-prep.out" 2>&1

# tool-lock.json carries the verify fields from source-lock.
python3 - "${CASE1_INPUTS}/vendor/skill-deps/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text())
tools = {tool["name"]: tool for tool in lock["tools"]}
good = tools["good-tool"]
assert good["verify_command"] == ["{bin}", "--version"], good
assert good["verify_strict"] is True, good
wheel = tools["wheel-tool"]
assert wheel["verify_skip_reason"].startswith("Wheelhouse fixture;"), wheel
PY

HATCH_INPUT_ROOT="${CASE1_INPUTS}" \
HATCH_TOOLS_PACKS_ROOT="${CASE1_PACKS}" \
  bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/case1-build.out" 2>"${TMP}/case1-build.err"

# Manifest carries the verify fields end-to-end.
python3 - "${CASE1_PACKS}/skill-deps-pack/tools-pack-manifest.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tools = {tool["name"]: tool for tool in data["tools"]}
good = tools["good-tool"]
assert good["verify_command"] == ["{bin}", "--version"], good
assert good["verify_strict"] is True, good
assert "verify_skip_reason" not in good, good
wheel = tools["wheel-tool"]
assert wheel["verify_skip_reason"].startswith("Wheelhouse fixture;"), wheel
assert "verify_command" not in wheel, wheel
PY

# The verifier ran inside build_skill_deps_pack.sh:
#   - good-tool probe ran (exit 0): no warn
#   - wheel-tool skipped: prints info (to stderr)
#   - overall pack verified (printed to stdout by lib/common.sh)
grep -q "Tools pack verified for skill-deps-pack" "${TMP}/case1-build.out"
grep -q "info: wheel-tool verify skipped: Wheelhouse fixture" "${TMP}/case1-build.err"
if grep -E "warn: (good-tool|wheel-tool) " "${TMP}/case1-build.err"; then
  printf 'unexpected warn line from skill-deps verify\n' >&2
  exit 1
fi

# CASE 2 — strict-true probe fails: build should abort under
# HATCH_TOOLS_PACK_STRICT_VERIFY=1.
CASE2_INPUTS="${TMP}/case2-inputs"
CASE2_FIXTURES="${TMP}/case2-fixtures"
CASE2_PACKS="${TMP}/case2-packs"
scaffold_skill_deps_source "${CASE2_INPUTS}" "${CASE2_FIXTURES}"
# Swap good-tool to point at the failing fixture binary.
python3 - "${CASE2_INPUTS}/vendor/skill-deps/source-lock.json" "${CASE2_FIXTURES}/bin/exit-one-binary" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
target = sys.argv[2]
data = json.loads(path.read_text())
for tool in data["tools"]:
    if tool["name"] == "good-tool":
        tool["methods"] = [{"type": "local_binary", "path": target}]
path.write_text(json.dumps(data, indent=2) + "\n")
PY

HATCH_INPUT_ROOT="${CASE2_INPUTS}" \
HATCH_SKILL_DEPS_FORCE=1 \
  bash "${ROOT}/scripts/prepare_skill_deps_inputs.sh" >"${TMP}/case2-prep.out" 2>&1

if HATCH_TOOLS_PACK_STRICT_VERIFY=1 \
  HATCH_INPUT_ROOT="${CASE2_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${CASE2_PACKS}" \
    bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/case2-build.out" 2>"${TMP}/case2-build.err"; then
  printf 'expected strict skill-deps build to fail when good-tool probe exits 1\n' >&2
  cat "${TMP}/case2-build.err" >&2
  exit 1
fi
grep -q "strict probe" "${TMP}/case2-build.err"

# CASE 3 — without strict env, strict-true still fails on non-zero exit (the
# per-tool flag is the user's contract regardless of host env). Mirrors
# CASE 3 of the Mona-pack tests.
HATCH_INPUT_ROOT="${CASE2_INPUTS}" \
HATCH_TOOLS_PACKS_ROOT="${CASE2_PACKS}" \
  HATCH_TOOLS_PACK_STRICT_VERIFY=0 \
  bash "${ROOT}/scripts/build_skill_deps_pack.sh" >"${TMP}/case3-build.out" 2>"${TMP}/case3-build.err" && {
  printf 'expected per-tool verify_strict to fail even with HATCH_TOOLS_PACK_STRICT_VERIFY=0\n' >&2
  cat "${TMP}/case3-build.err" >&2
  exit 1
}
grep -q "strict probe" "${TMP}/case3-build.err"

printf 'skill-deps verify_command tests passed\n'
