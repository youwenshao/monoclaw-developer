#!/usr/bin/env bash
# Phase 4 Class-C / Class-D core dependency install plan.
#
# ``run_install_core_deps`` drives ``brew install`` for Node.js (+npm), uv,
# opus, and ffmpeg. The same skip gates as Class-A apply (offline mode,
# brew missing) plus a dedicated ``HATCH_INSTALL_CORE_DEPS=0`` opt-out so a
# technician can keep Class-A formulas while skipping core deps.
#
# Exercises the function directly through a small harness — same approach
# as ``hatch_brew_first_skill_deps_tests.sh``.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

HARNESS="${TMP}/harness.sh"
cat > "${HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN=true
export HATCH_DRY_RUN
$(awk '/^run_install_core_deps\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
run_install_core_deps
HARNESS_EOF
chmod +x "${HARNESS}"

BREW_STUB_DIR="${TMP}/stubs"
mkdir -p "${BREW_STUB_DIR}"
cat > "${BREW_STUB_DIR}/brew" <<'STUB'
#!/usr/bin/env sh
printf 'stub-brew: must not run in dry-run\n' >&2
exit 1
STUB
chmod +x "${BREW_STUB_DIR}/brew"

run_harness() {
  PATH="${BREW_STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1
}

# ── Case 1: dry-run plan includes node, uv, opus, ffmpeg ────────────────────
OUT="$(run_harness)"

case "${OUT}" in
  *"[core-deps]"*) ;;
  *) printf 'fail: missing [core-deps] log header. got:\n%s\n' "${OUT}" >&2; exit 1;;
esac

for needle in \
    "brew install --quiet node" \
    "brew install --quiet uv" \
    "brew install --quiet opus" \
    "brew install --quiet ffmpeg" \
    "brew install --quiet ripgrep"; do
  # ``ripgrep`` was added 2026-05 after the install regression where
  # every fresh Hatch Mac came up without ``rg`` (because
  # ``run_install_core_deps`` only fired via the optional skill-deps
  # pack and that pack does not ship in the default local-office
  # bundle).  Pin the formula list here so the same regression cannot
  # recur silently.
  case "${OUT}" in
    *"${needle}"*) ;;
    *)
      printf 'fail: dry-run output missing expected install line:\n  %s\n' "${needle}" >&2
      printf '\noutput was:\n%s\n' "${OUT}" >&2
      exit 1
      ;;
  esac
done

# ── Case 2: HATCH_INSTALL_OFFLINE=1 skips the whole step ────────────────────
OFFLINE_OUT="$(HATCH_INSTALL_OFFLINE=1 PATH="${BREW_STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${OFFLINE_OUT}" in
  *"HATCH_INSTALL_OFFLINE=1; skipping"*) ;;
  *) printf 'fail: offline mode did not skip core-deps. got:\n%s\n' "${OFFLINE_OUT}" >&2; exit 1;;
esac
case "${OFFLINE_OUT}" in
  *"brew install --quiet"*)
    printf 'fail: offline mode emitted a brew install line\n' >&2
    exit 1
    ;;
esac

# ── Case 3: HATCH_INSTALL_CORE_DEPS=0 opt-out skips just core deps ──────────
OPT_OUT="$(HATCH_INSTALL_CORE_DEPS=0 PATH="${BREW_STUB_DIR}:${PATH}" bash "${HARNESS}" 2>&1)"
case "${OPT_OUT}" in
  *"HATCH_INSTALL_CORE_DEPS=0; skipping"*) ;;
  *) printf 'fail: HATCH_INSTALL_CORE_DEPS=0 did not skip. got:\n%s\n' "${OPT_OUT}" >&2; exit 1;;
esac

# ── Case 4: brew absent from PATH ───────────────────────────────────────────
NO_BREW_OUT="$(PATH="/usr/bin:/bin" bash "${HARNESS}" 2>&1)"
case "${NO_BREW_OUT}" in
  *"brew not on PATH; skipping"*) ;;
  *) printf 'fail: missing-brew case did not surface a clear message. got:\n%s\n' "${NO_BREW_OUT}" >&2; exit 1;;
esac

printf 'ok: hatch core-deps install plan (node, uv, opus, ffmpeg, ripgrep)\n'
