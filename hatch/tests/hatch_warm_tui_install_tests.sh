#!/usr/bin/env bash
# Tests for ``warm_tui_install`` added in 2026-05 (Phase 2 of
# plans/tui-npm-install-error-handling.md).
#
# The TUI is now warmed at Hatch install time so the customer's first
# ``monoclaw --tui`` invocation isn't where install failures first
# surface. Same shape as ``warm_whatsapp_bridge_install``: non-fatal by
# default with ``HATCH_REQUIRE_TUI_INSTALL=1`` for lab provisioning, plus
# a ``HATCH_SKIP_TUI_WARMUP=1`` escape hatch for tight provisioning
# windows.
#
# Also exercises the shared ``_run_warm_npm_install`` helper that the
# WhatsApp bridge warmer now also uses — the May 2026 lazy-error fix
# replaced the previous ``>/dev/null 2>&1`` swallow with proper stderr
# capture + log-path surfacing.
#
# Cases:
#   1. HATCH_SKIP_TUI_WARMUP=1 short-circuits before any check.
#   2. TUI not staged → soft-skip warning, exit 0.
#   3. node_modules already present → idempotent no-op (no npm exec).
#   4. npm missing + default mode → warn but return 0.
#   5. npm missing + HATCH_REQUIRE_TUI_INSTALL=1 → die (exit non-zero).
#   6. Dry-run prints the planned command without executing it.
#   7. npm install failure surfaces stderr tail + log-path hint.
#   8. (regression) warm_whatsapp_bridge_install with my _run_warm_npm_install
#      refactor still surfaces stderr (was >/dev/null 2>&1 before).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# All harnesses inline ``_run_warm_npm_install`` (the shared diagnostic
# helper) plus whichever warmer is under test. ``awk`` extracts each
# function from bin/hatch in-place so we test exactly what bin/hatch
# would execute.
_RUN_WARM_HELPER_AWK='/^_run_warm_npm_install\(\) \{$/,/^\}$/'
_WARM_TUI_AWK='/^warm_tui_install\(\) \{$/,/^\}$/'
_WARM_BRIDGE_AWK='/^warm_whatsapp_bridge_install\(\) \{$/,/^\}$/'


# ─────────────────────────────────────────────────────────────────────────
# Case 1: HATCH_SKIP_TUI_WARMUP=1 short-circuits.
# Must happen BEFORE the package.json existence check so an opt-out
# customer with no staged TUI gets the "skipped" message, not the
# "not staged" warning.
# ─────────────────────────────────────────────────────────────────────────
SKIP_HOME="${TMP}/skip-home/.monoclaw"
mkdir -p "${SKIP_HOME}/vendor"  # no tui subtree

SKIP_HARNESS="${TMP}/skip_harness.sh"
cat > "${SKIP_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
HATCH_SKIP_TUI_WARMUP="1"
export HATCH_DRY_RUN HATCH_SKIP_TUI_WARMUP
monoclaw_home() { printf '%s' "${SKIP_HOME}"; }
have_command() { return 0; }
$(awk "${_RUN_WARM_HELPER_AWK}" "${ROOT}/bin/hatch")
$(awk "${_WARM_TUI_AWK}" "${ROOT}/bin/hatch")
warm_tui_install
HARNESS_EOF
chmod +x "${SKIP_HARNESS}"

SKIP_OUT="$(bash "${SKIP_HARNESS}" 2>&1)"
case "${SKIP_OUT}" in
  *"HATCH_SKIP_TUI_WARMUP=1"*) ;;
  *)
    printf 'fail: warm_tui_install did not honor HATCH_SKIP_TUI_WARMUP=1. got:\n%s\n' "${SKIP_OUT}" >&2
    exit 1
    ;;
esac
case "${SKIP_OUT}" in
  *"not staged"*)
    printf 'fail: warm_tui_install fell through to staging check despite HATCH_SKIP_TUI_WARMUP=1. got:\n%s\n' "${SKIP_OUT}" >&2
    exit 1
    ;;
esac


# ─────────────────────────────────────────────────────────────────────────
# Case 2: TUI not staged → soft-skip warning.
# A bundle that omits the TUI (--no-tui future flag, partial install,
# etc.) must NOT fail provisioning.
# ─────────────────────────────────────────────────────────────────────────
MISS_HOME="${TMP}/miss-home/.monoclaw"
mkdir -p "${MISS_HOME}/vendor"

MISS_HARNESS="${TMP}/miss_harness.sh"
cat > "${MISS_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${MISS_HOME}"; }
have_command() { return 0; }
$(awk "${_RUN_WARM_HELPER_AWK}" "${ROOT}/bin/hatch")
$(awk "${_WARM_TUI_AWK}" "${ROOT}/bin/hatch")
warm_tui_install
HARNESS_EOF
chmod +x "${MISS_HARNESS}"

MISS_OUT="$(bash "${MISS_HARNESS}" 2>&1)"
case "${MISS_OUT}" in
  *"TUI not staged"*) ;;
  *)
    printf 'fail: warm_tui_install did not log skip when TUI absent. got:\n%s\n' "${MISS_OUT}" >&2
    exit 1
    ;;
esac


# ─────────────────────────────────────────────────────────────────────────
# Case 3: node_modules already present → idempotent no-op.
# A re-run of bin/hatch install must NOT re-invoke npm.
# ─────────────────────────────────────────────────────────────────────────
IDEM_HOME="${TMP}/idem-home/.monoclaw"
mkdir -p "${IDEM_HOME}/vendor/tui/node_modules"
printf '{}' > "${IDEM_HOME}/vendor/tui/package.json"

IDEM_HARNESS="${TMP}/idem_harness.sh"
cat > "${IDEM_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${IDEM_HOME}"; }
have_command() { return 0; }
# Booby-trap: if warm_tui_install actually invokes npm, fail loudly.
npm() { printf 'fail: npm was invoked despite existing node_modules\n' >&2; exit 99; }
$(awk "${_RUN_WARM_HELPER_AWK}" "${ROOT}/bin/hatch")
$(awk "${_WARM_TUI_AWK}" "${ROOT}/bin/hatch")
warm_tui_install
HARNESS_EOF
chmod +x "${IDEM_HARNESS}"

IDEM_OUT="$(bash "${IDEM_HARNESS}" 2>&1)"
case "${IDEM_OUT}" in
  *"TUI node_modules already present"*) ;;
  *)
    printf 'fail: warm_tui_install did not detect existing node_modules. got:\n%s\n' "${IDEM_OUT}" >&2
    exit 1
    ;;
esac


# ─────────────────────────────────────────────────────────────────────────
# Case 4: npm missing + default mode → warn but return 0.
# Customer Mac without Node installed yet must NOT block provisioning;
# the runtime's _make_tui_argv will reprompt them at first --tui run.
# ─────────────────────────────────────────────────────────────────────────
NO_NPM_HOME="${TMP}/no-npm-home/.monoclaw"
mkdir -p "${NO_NPM_HOME}/vendor/tui"
printf '{}' > "${NO_NPM_HOME}/vendor/tui/package.json"

NO_NPM_HARNESS="${TMP}/no_npm_harness.sh"
cat > "${NO_NPM_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${NO_NPM_HOME}"; }
have_command() { return 1; }  # pretend npm is NOT present
$(awk "${_RUN_WARM_HELPER_AWK}" "${ROOT}/bin/hatch")
$(awk "${_WARM_TUI_AWK}" "${ROOT}/bin/hatch")
warm_tui_install
HARNESS_EOF
chmod +x "${NO_NPM_HARNESS}"

NO_NPM_OUT="$(bash "${NO_NPM_HARNESS}" 2>&1)"
case "${NO_NPM_OUT}" in
  *"npm not on PATH"*) ;;
  *)
    printf 'fail: warm_tui_install did not warn about missing npm. got:\n%s\n' "${NO_NPM_OUT}" >&2
    exit 1
    ;;
esac
# Hint must reference monoclaw --tui so the operator knows the runtime
# will retry on first invocation.
case "${NO_NPM_OUT}" in
  *"monoclaw --tui"*) ;;
  *)
    printf 'fail: warm_tui_install missing remediation hint. got:\n%s\n' "${NO_NPM_OUT}" >&2
    exit 1
    ;;
esac


# ─────────────────────────────────────────────────────────────────────────
# Case 5: strict mode + npm missing → die.
# HATCH_REQUIRE_TUI_INSTALL=1 upgrades the warning to a hard fail for
# lab provisioning where the operator wants an install-time guarantee.
# ─────────────────────────────────────────────────────────────────────────
if HATCH_REQUIRE_TUI_INSTALL=1 bash "${NO_NPM_HARNESS}" 2>/dev/null; then
  printf 'fail: warm_tui_install exited 0 in strict mode without npm\n' >&2
  exit 1
fi


# ─────────────────────────────────────────────────────────────────────────
# Case 6: dry-run prints the planned command without executing it.
# bin/hatch's preflight + technician dry-run path must surface what
# would happen.
# ─────────────────────────────────────────────────────────────────────────
DRY_HARNESS="${TMP}/dry_harness.sh"
cat > "${DRY_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="true"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${NO_NPM_HOME}"; }
have_command() { return 0; }  # pretend npm IS present so we hit the dry-run line
# Booby-trap: dry-run must NOT actually shell out to npm.
npm() { printf 'fail: dry-run invoked npm\n' >&2; exit 99; }
$(awk "${_RUN_WARM_HELPER_AWK}" "${ROOT}/bin/hatch")
$(awk "${_WARM_TUI_AWK}" "${ROOT}/bin/hatch")
warm_tui_install
HARNESS_EOF
chmod +x "${DRY_HARNESS}"

DRY_OUT="$(bash "${DRY_HARNESS}" 2>&1)"
case "${DRY_OUT}" in
  *"dry-run: npm install --loglevel=error"*) ;;
  *)
    printf 'fail: warm_tui_install dry-run did not plan the npm command. got:\n%s\n' "${DRY_OUT}" >&2
    exit 1
    ;;
esac
case "${DRY_OUT}" in
  *"${NO_NPM_HOME}/vendor/tui"*) ;;
  *)
    printf 'fail: warm_tui_install dry-run did not name the cwd. got:\n%s\n' "${DRY_OUT}" >&2
    exit 1
    ;;
esac


# ─────────────────────────────────────────────────────────────────────────
# Case 7: npm install failure surfaces stderr tail + log-path hint.
# Locks the Phase 1 contract for _run_warm_npm_install: the May 2026
# >/dev/null 2>&1 swallow MUST NOT regress.
# ─────────────────────────────────────────────────────────────────────────
FAIL_HOME="${TMP}/fail-home/.monoclaw"
mkdir -p "${FAIL_HOME}/vendor/tui"
printf '{}' > "${FAIL_HOME}/vendor/tui/package.json"

FAIL_HARNESS="${TMP}/fail_harness.sh"
cat > "${FAIL_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${FAIL_HOME}"; }
have_command() { return 0; }
# Stub npm: exit non-zero with a realistic-shape stderr error.
npm() {
  printf 'npm error code ENOTFOUND\n' >&2
  printf 'npm error errno ENOTFOUND\n' >&2
  printf 'npm error network request to https://registry.npmjs.org/ink failed\n' >&2
  return 1
}
export -f npm  # subshells inside _run_warm_npm_install need to see it
$(awk "${_RUN_WARM_HELPER_AWK}" "${ROOT}/bin/hatch")
$(awk "${_WARM_TUI_AWK}" "${ROOT}/bin/hatch")
warm_tui_install
HARNESS_EOF
chmod +x "${FAIL_HARNESS}"

FAIL_OUT="$(bash "${FAIL_HARNESS}" 2>&1)"
# npm's actual error must survive — this is the heart of the Phase 1 fix.
case "${FAIL_OUT}" in
  *"ENOTFOUND"*) ;;
  *)
    printf 'fail: warm_tui_install swallowed npm stderr (May 2026 lazy-error regression). got:\n%s\n' "${FAIL_OUT}" >&2
    exit 1
    ;;
esac
case "${FAIL_OUT}" in
  *"retry manually"*) ;;
  *)
    printf 'fail: warm_tui_install missing manual-retry hint. got:\n%s\n' "${FAIL_OUT}" >&2
    exit 1
    ;;
esac
case "${FAIL_OUT}" in
  *"npm install --loglevel=verbose"*) ;;
  *)
    printf 'fail: warm_tui_install retry hint does not point at --loglevel=verbose. got:\n%s\n' "${FAIL_OUT}" >&2
    exit 1
    ;;
esac
# Default mode is non-fatal: even after the npm failure, warm_tui_install
# returns 0 and install.sh continues.
if ! bash "${FAIL_HARNESS}" >/dev/null 2>&1; then
  printf 'fail: warm_tui_install exited non-zero on npm failure in default (non-strict) mode\n' >&2
  exit 1
fi
# Strict mode escalates the same failure to a die.
if HATCH_REQUIRE_TUI_INSTALL=1 bash "${FAIL_HARNESS}" >/dev/null 2>&1; then
  printf 'fail: warm_tui_install did not die under HATCH_REQUIRE_TUI_INSTALL=1\n' >&2
  exit 1
fi


# ─────────────────────────────────────────────────────────────────────────
# Case 8: regression for warm_whatsapp_bridge_install.
# The shared _run_warm_npm_install refactor replaced the previous
# >/dev/null 2>&1 swallow; verify the bridge warmer now surfaces npm
# stderr too. Without this guard, a future "tidy up bin/hatch" PR could
# silently revert to the lazy pattern.
# ─────────────────────────────────────────────────────────────────────────
BRIDGE_FAIL_HOME="${TMP}/bridge-fail-home/.monoclaw"
mkdir -p "${BRIDGE_FAIL_HOME}/vendor/whatsapp-bridge"
printf '{}' > "${BRIDGE_FAIL_HOME}/vendor/whatsapp-bridge/package.json"

BRIDGE_FAIL_HARNESS="${TMP}/bridge_fail_harness.sh"
cat > "${BRIDGE_FAIL_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${BRIDGE_FAIL_HOME}"; }
have_command() { return 0; }
npm() {
  printf 'npm error code EACCES\n' >&2
  printf 'npm error path /Users/test/.monoclaw/vendor/whatsapp-bridge/node_modules\n' >&2
  return 1
}
export -f npm
$(awk "${_RUN_WARM_HELPER_AWK}" "${ROOT}/bin/hatch")
$(awk "${_WARM_BRIDGE_AWK}" "${ROOT}/bin/hatch")
warm_whatsapp_bridge_install
HARNESS_EOF
chmod +x "${BRIDGE_FAIL_HARNESS}"

BRIDGE_OUT="$(bash "${BRIDGE_FAIL_HARNESS}" 2>&1)"
case "${BRIDGE_OUT}" in
  *"EACCES"*) ;;
  *)
    printf 'fail: warm_whatsapp_bridge_install regressed to swallowing npm stderr. got:\n%s\n' "${BRIDGE_OUT}" >&2
    exit 1
    ;;
esac


printf 'ok: hatch_warm_tui_install_tests passed (8 cases)\n'
