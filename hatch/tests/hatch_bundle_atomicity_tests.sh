#!/usr/bin/env bash
set -euo pipefail

# Regression tests: atomic dist publishing, optional pack strict mode, and build diagnostics.
# Uses test-only hooks documented in hatch/build.sh (HATCH_TEST_* variables).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

INPUTS="${TMP}/bundle-inputs"
RUNTIME="${TMP}/monoclaw-runtime"
DIST="${TMP}/dist"
WHEEL="${TMP}/monoclaw_runtime-0.1.0-py3-none-any.whl"
FAKE_PYTHON="${TMP}/python3.11"

mkdir -p \
  "${INPUTS}/vendor/python/current/bin" \
  "${INPUTS}/vendor/provisioning" \
  "${INPUTS}/vendor/wheelhouse" \
  "${RUNTIME}/skills/customer-office" \
  "${RUNTIME}/optional-skills/research/deep-research"

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
cp "${FAKE_PYTHON}" "${INPUTS}/vendor/python/current/bin/python3"
cat > "${RUNTIME}/pyproject.toml" <<'TOML'
[project]
name = "monoclaw-runtime"
version = "0.1.0"
TOML

# Phase 1 verify_node_subsystems.py refuses bundles missing vendor/tui or
# vendor/whatsapp-bridge. Seed the minimum source files so the staging
# steps produce what the verifier requires.  See hatch_build_tests.sh
# for the full helper rationale.
mkdir -p \
  "${RUNTIME}/ui-tui/dist" \
  "${RUNTIME}/ui-tui/packages/monoclaw-ink/dist" \
  "${RUNTIME}/scripts/whatsapp-bridge"
printf '{"name":"monoclaw-tui","version":"0.0.1"}\n' > "${RUNTIME}/ui-tui/package.json"
printf 'console.log("entry")\n' > "${RUNTIME}/ui-tui/dist/entry.js"
printf 'export {}\n' > "${RUNTIME}/ui-tui/packages/monoclaw-ink/dist/entry-exports.js"
printf '// bridge\n' > "${RUNTIME}/scripts/whatsapp-bridge/bridge.js"
printf '{"name":"whatsapp-bridge"}\n' > "${RUNTIME}/scripts/whatsapp-bridge/package.json"
printf '{"lockfileVersion":3}\n' > "${RUNTIME}/scripts/whatsapp-bridge/package-lock.json"

mkdir -p "${DIST}"
printf 'prior_bundle_marker\n' > "${DIST}/.prior_bundle_marker"

if HATCH_INPUT_ROOT="${INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_RUNTIME_WHEEL="${WHEEL}" \
  HATCH_DIST_ROOT="${DIST}" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
  HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  HATCH_INCLUDE_MONA_TOOLS=0 \
  HATCH_INCLUDE_SKILL_DEPS=0 \
  HATCH_TEST_FAIL_AFTER_STEP=after_templates \
  "${ROOT}/build.sh" >"${TMP}/atomic-fail.out" 2>&1; then
  printf 'expected build to fail at HATCH_TEST_FAIL_AFTER_STEP hook\n' >&2
  exit 1
fi

test -f "${DIST}/.prior_bundle_marker"
test ! -x "${DIST}/bin/hatch"
test ! -f "${DIST}/hatch-manifest.json"
grep -q "HATCH_TEST_FAIL_AFTER_STEP=after_templates" "${TMP}/atomic-fail.out"
grep -q '\[hatch-build\] fail: exit' "${TMP}/atomic-fail.out"

FRESH_DIST_PARENT="${TMP}/fresh-dist-parent"
mkdir -p "${FRESH_DIST_PARENT}"
FRESH_DIST="${FRESH_DIST_PARENT}/dist-output"

if HATCH_INPUT_ROOT="${INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_RUNTIME_WHEEL="${WHEEL}" \
  HATCH_DIST_ROOT="${FRESH_DIST}" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
  HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  HATCH_INCLUDE_MONA_TOOLS=0 \
  HATCH_INCLUDE_SKILL_DEPS=0 \
  HATCH_TEST_FAIL_AFTER_STEP=after_wheel \
  "${ROOT}/build.sh" >"${TMP}/fresh-fail.out" 2>&1; then
  printf 'expected fresh-dist build to fail at hook\n' >&2
  exit 1
fi

test ! -e "${FRESH_DIST}"

DIST_STRICT="${TMP}/dist-strict"
if HATCH_INPUT_ROOT="${INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_RUNTIME_WHEEL="${WHEEL}" \
  HATCH_DIST_ROOT="${DIST_STRICT}" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
  HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  HATCH_INCLUDE_MONA_TOOLS=0 \
  HATCH_INCLUDE_SKILL_DEPS=1 \
  HATCH_OPTIONAL_PACKS_STRICT=1 \
  HATCH_TEST_FORCE_SKILL_DEPS_PACK_FAIL=1 \
  "${ROOT}/build.sh" >"${TMP}/strict-fail.out" 2>&1; then
  printf 'expected strict skill-deps failure to abort build\n' >&2
  exit 1
fi
grep -q "HATCH_TEST_FORCE_SKILL_DEPS_PACK_FAIL" "${TMP}/strict-fail.out"
grep -q "skill-deps pack step aborted" "${TMP}/strict-fail.out"

DIST_LOOSE="${TMP}/dist-loose"
HATCH_INPUT_ROOT="${INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_RUNTIME_WHEEL="${WHEEL}" \
  HATCH_DIST_ROOT="${DIST_LOOSE}" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
  HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
  HATCH_INCLUDE_MONA_TOOLS=0 \
  HATCH_INCLUDE_SKILL_DEPS=1 \
  HATCH_OPTIONAL_PACKS_STRICT=0 \
  HATCH_TEST_FORCE_SKILL_DEPS_PACK_FAIL=1 \
  "${ROOT}/build.sh" >"${TMP}/loose-ok.out"

test -f "${DIST_LOOSE}/hatch-manifest.json"
grep -q "continuing without skill-deps pack" "${TMP}/loose-ok.out"

printf 'bundle atomicity + optional strict tests ok\n'
