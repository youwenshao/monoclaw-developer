#!/usr/bin/env bash
# Tests for the agent-browser provisioning helper added in 2026-05.
#
# ``run_install_agent_browser`` provides the online-first / bundle-fallback
# install pattern for the npm package the runtime uses for headless browser
# automation. Pre-2026-05 Hatch never installed it on the customer Mac and
# the doctor surfaced "agent-browser not installed" on every fresh install.
#
# The tests below exercise the function directly through a small harness,
# matching the structure of ``hatch_core_deps_tests.sh`` and
# ``hatch_brew_first_skill_deps_tests.sh``. We never invoke the real
# ``npm``: every probe runs in dry-run mode (``HATCH_DRY_RUN=true``) which
# emits action plans instead of side-effecting commands.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

HARNESS="${TMP}/harness.sh"
# Carry the helper trio + the orchestrator into the harness. The awk
# expression matches a function block that begins with ``<name>() {`` and
# ends with the matching ``}`` at column 0. The four functions in the
# group depend on each other, so we inject all of them.
cat > "${HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN=true
export HATCH_DRY_RUN
HATCH_BUNDLE_ROOT="\${HATCH_BUNDLE_ROOT:-/nonexistent}"
export HATCH_BUNDLE_ROOT
$(awk '/^HATCH_AGENT_BROWSER_VERSION=/' "${ROOT}/bin/hatch")
$(awk '/^install_agent_browser_via_npm\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
$(awk '/^install_agent_browser_via_bundle\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
$(awk '/^run_install_agent_browser\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
run_install_agent_browser
HARNESS_EOF
chmod +x "${HARNESS}"

# Minimal PATH stubs. ``npm`` is required by the npm-first path; we
# provide both a "succeeds" and a "fails" stub so we can pin both
# branches deterministically.
STUB_DIR="${TMP}/stubs"
mkdir -p "${STUB_DIR}"

# In dry-run the function does NOT actually call npm — it just prints a
# plan line. So a placeholder shim that is on PATH is sufficient.
cat > "${STUB_DIR}/npm" <<'STUB'
#!/usr/bin/env sh
printf 'stub-npm: must not run in dry-run\n' >&2
exit 1
STUB
chmod +x "${STUB_DIR}/npm"

run_harness() {
  PATH="${STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1
}

# ── Case 1: dry-run plans the npm-first install ─────────────────────────────
OUT="$(run_harness)"
case "${OUT}" in
  *"[agent-browser]"*) ;;
  *) printf 'fail: missing [agent-browser] log header. got:\n%s\n' "${OUT}" >&2; exit 1;;
esac
case "${OUT}" in
  *"npm install -g agent-browser@0.26.0"*) ;;
  *)
    printf 'fail: dry-run did not plan the npm install. got:\n%s\n' "${OUT}" >&2
    exit 1
    ;;
esac

# ── Case 2: HATCH_INSTALL_OFFLINE=1 skips npm and tries the bundle ─────────
# Note we deliberately match the **plan line** prefix rather than any
# substring — the warning message for "no bundle either" mentions
# ``npm install -g agent-browser`` as a remediation hint and would
# otherwise produce a false positive.
OFFLINE_OUT="$(HATCH_INSTALL_OFFLINE=1 PATH="${STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${OFFLINE_OUT}" in
  *"HATCH_INSTALL_OFFLINE=1; skipping npm and using bundle"*) ;;
  *) printf 'fail: offline mode did not announce skipping npm. got:\n%s\n' "${OFFLINE_OUT}" >&2; exit 1;;
esac
case "${OFFLINE_OUT}" in
  *"dry-run: npm install -g agent-browser"*)
    printf 'fail: offline mode emitted the npm-install plan line\n' >&2
    exit 1
    ;;
esac

# ── Case 3: HATCH_INSTALL_AGENT_BROWSER=0 opt-out skips entirely ────────────
OPT_OUT="$(HATCH_INSTALL_AGENT_BROWSER=0 PATH="${STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${OPT_OUT}" in
  *"HATCH_INSTALL_AGENT_BROWSER=0; skipping"*) ;;
  *) printf 'fail: HATCH_INSTALL_AGENT_BROWSER=0 did not skip. got:\n%s\n' "${OPT_OUT}" >&2; exit 1;;
esac
case "${OPT_OUT}" in
  *"dry-run: npm install"*)
    printf 'fail: opt-out emitted an install plan line\n' >&2
    exit 1
    ;;
esac

# ── Case 4: pinned version bubbles through HATCH_AGENT_BROWSER_VERSION ─────
PINNED_OUT="$(HATCH_AGENT_BROWSER_VERSION=9.9.9 PATH="${STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${PINNED_OUT}" in
  *"npm install -g agent-browser@9.9.9"*) ;;
  *)
    printf 'fail: HATCH_AGENT_BROWSER_VERSION pin not honoured. got:\n%s\n' "${PINNED_OUT}" >&2
    exit 1
    ;;
esac

# ── Case 5: bundle-only fallback when npm is absent + offline ──────────────
# The bundle source lives at HATCH_BUNDLE_ROOT/vendor/browser/node_modules/agent-browser.
# We synthesise that directory and prove the dry-run notes the bundle path.
BUNDLE_ROOT="${TMP}/bundle"
mkdir -p "${BUNDLE_ROOT}/vendor/browser/node_modules/agent-browser"
BUNDLE_OUT="$(HATCH_BUNDLE_ROOT="${BUNDLE_ROOT}" HATCH_INSTALL_OFFLINE=1 PATH="${STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${BUNDLE_OUT}" in
  *"agent-browser bundle present at ${BUNDLE_ROOT}/vendor/browser"*) ;;
  *)
    printf 'fail: bundle-fallback dry-run did not surface bundle path. got:\n%s\n' "${BUNDLE_OUT}" >&2
    exit 1
    ;;
esac

printf 'ok: hatch agent-browser install plan (npm-first, bundle-fallback)\n'
