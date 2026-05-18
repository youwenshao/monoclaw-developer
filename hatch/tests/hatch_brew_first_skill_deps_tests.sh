#!/usr/bin/env bash
# Phase 3 brew-first / bundle-fallback resolution for Class-A skill-dep tools.
#
# Locks down the contract from ``CLAUDE.md`` "Hybrid Brew / Bundle Resolution
# For Non-Python Tools": after the bundle copy, ``run_install_skill_deps``
# opportunistically runs ``brew install`` for each Class-A formula. The brew
# step is skipped when:
#
#   * ``HATCH_INSTALL_OFFLINE=1`` is set (air-gap mode).
#   * ``HATCH_INSTALL_BREW_FORMULAS=0`` is set (technician opt-out).
#   * ``brew`` is not on PATH.
#
# We exercise the helper directly via ``bash -c`` rather than running a full
# install pipeline — that keeps the test hermetic on every CI host regardless
# of bundle availability, python interpreter location, or any other
# prerequisite that ``run_install_skill_deps`` checks before reaching us.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# ``install_class_a_brew_formulas`` is defined inside ``bin/hatch``. We
# extract just that function plus its dependencies into a tiny harness so
# we can exercise it without setting up the whole install pipeline.
HARNESS="${TMP}/harness.sh"
cat > "${HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail

# Pull in the shared log helpers (log_step, log_ok, log_warn, have_command).
. "${ROOT}/lib/common.sh"

# Hatch dry-run mode keeps the harness from actually trying to install.
HATCH_DRY_RUN=true
export HATCH_DRY_RUN

# Inline the function under test. We use a sed range so the test fails
# loudly if someone renames the function or reorganises the block.
$(awk '/^install_class_a_brew_formulas\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")

install_class_a_brew_formulas
HARNESS_EOF
chmod +x "${HARNESS}"

# Stub ``brew`` so ``have_command brew`` returns true. The function does NOT
# actually invoke brew in dry-run mode (it prints the plan instead) — but a
# real PATH lookup must succeed for the function to reach the brew-install
# loop.
BREW_STUB_DIR="${TMP}/stubs"
mkdir -p "${BREW_STUB_DIR}"
cat > "${BREW_STUB_DIR}/brew" <<'STUB'
#!/usr/bin/env sh
# stub: only used for `have_command brew` detection. In dry-run, the
# function never `exec`s us. If you see this fired, the test is wrong.
printf 'stub-brew: this should not be invoked in dry-run mode\n' >&2
exit 1
STUB
chmod +x "${BREW_STUB_DIR}/brew"

run_harness() {
  PATH="${BREW_STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1
}

# ── Case 1: dry-run with brew present + flags default ────────────────────────
OUT="$(run_harness)"

case "${OUT}" in
  *"skill-deps:brew"*) ;;
  *) printf 'fail: missing skill-deps:brew log header. got:\n%s\n' "${OUT}" >&2; exit 1;;
esac

# Each Class-A tool must appear in the dry-run plan with the right spec.
for needle in \
    "brew install --quiet himalaya" \
    "brew install --quiet steipete/tap/remindctl" \
    "brew install --quiet antoniorodr/memo/memo"; do
  case "${OUT}" in
    *"${needle}"*) ;;
    *)
      printf 'fail: dry-run output missing expected brew install line:\n  %s\n' "${needle}" >&2
      printf '\noutput was:\n%s\n' "${OUT}" >&2
      exit 1
      ;;
  esac
done

# Class-B tools must NOT appear — imsg has no brew formula.
case "${OUT}" in
  *"brew install --quiet imsg"*) printf 'fail: imsg must not be in Class-A brew list\n' >&2; exit 1;;
esac

# ── Case 2: HATCH_INSTALL_OFFLINE=1 must skip brew entirely ─────────────────
OFFLINE_OUT="$(HATCH_INSTALL_OFFLINE=1 PATH="${BREW_STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${OFFLINE_OUT}" in
  *"HATCH_INSTALL_OFFLINE=1; skipping brew install"*) ;;
  *) printf 'fail: offline mode did not skip brew step. got:\n%s\n' "${OFFLINE_OUT}" >&2; exit 1;;
esac
case "${OFFLINE_OUT}" in
  *"brew install --quiet"*)
    printf 'fail: offline mode should not emit any brew install dry-run lines\n' >&2
    printf '\noutput was:\n%s\n' "${OFFLINE_OUT}" >&2
    exit 1
    ;;
esac

# ── Case 3: HATCH_INSTALL_BREW_FORMULAS=0 must skip brew ────────────────────
OPT_OUT="$(HATCH_INSTALL_BREW_FORMULAS=0 PATH="${BREW_STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${OPT_OUT}" in
  *"HATCH_INSTALL_BREW_FORMULAS=0; skipping brew install"*) ;;
  *) printf 'fail: HATCH_INSTALL_BREW_FORMULAS=0 did not skip brew step. got:\n%s\n' "${OPT_OUT}" >&2; exit 1;;
esac

# ── Case 4: brew absent from PATH falls through cleanly ─────────────────────
# Build a strict PATH that does NOT include the brew stub. We pin
# /usr/bin:/bin so log helpers (printf, sed, etc.) still resolve, and rely on
# the host not having `brew` somewhere in that range (the CI images and
# stock macOS layouts agree on this).
NO_BREW_OUT="$(PATH="/usr/bin:/bin" bash "${HARNESS}" 2>&1)"
case "${NO_BREW_OUT}" in
  *"brew not on PATH; skipping brew install"*) ;;
  *) printf 'fail: missing-brew case did not surface a clear message. got:\n%s\n' "${NO_BREW_OUT}" >&2; exit 1;;
esac

printf 'ok: hatch brew-first / bundle-fallback skill-deps install plan\n'
