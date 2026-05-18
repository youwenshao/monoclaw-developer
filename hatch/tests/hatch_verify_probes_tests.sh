#!/usr/bin/env bash
# Tests for the run_verify behavioral probes added in Phase 6 of the
# verify_command rollout:
#
#   - hatch_run_with_timeout: portable timeout wrapper (gtimeout/timeout/perl).
#     macOS doesn't ship `timeout`; this guarded against a real regression
#     where line 808 of bin/hatch literally errored "timeout: command not found"
#     and turned every `monoclaw --version` smoke into a no-op warn.
#   - monoclaw_runtime import probe: layered before --version so module/venv
#     breaks surface with a cleaner diagnostic.
#   - monoclaw --version probe: now actually executes against the fake binary
#     and reports the version line.
#
# Each case scaffolds its own ~/.monoclaw and runs `hatch --dry-run verify`
# under a restricted PATH that hides any system `timeout`/`gtimeout`. That
# forces the perl fallback path so we test what real macOS users hit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

HATCH_BIN="${ROOT}/bin/hatch"

# Build a directory containing the minimum set of binaries `bin/hatch` needs
# (bash, perl, python3, sh, mkdir, ls, sed, grep, cat, chmod, cp, rm, find,
# uname, mktemp, env, head, tee, awk, dirname, basename, sort, tr, true,
# false, kill, sleep) but WITHOUT `timeout` or `gtimeout`. This proves the
# perl fallback works.
restricted_path() {
  local outdir="$1"
  mkdir -p "${outdir}"
  local bin
  for bin in bash perl python3 sh mkdir ls sed grep cat chmod cp rm find uname \
             mktemp env head tee awk dirname basename sort tr true false kill \
             sleep wc tail readlink od xargs date stat ln; do
    if command -v "${bin}" >/dev/null 2>&1; then
      ln -sf "$(command -v "${bin}")" "${outdir}/${bin}"
    fi
  done
}

PATH_DIR="${TMP}/restricted-path"
restricted_path "${PATH_DIR}"

# Helper: scaffold a fake bundle + ~/.monoclaw matching what hatch_dry_run_tests
# uses so `hatch verify` runs end-to-end.
scaffold_install() {
  local home_dir="$1"
  local monoclaw_behavior="$2"   # "ok", "fail", "hang"
  local include_venv_python="$3" # "yes" | "no"
  mkdir -p \
    "${home_dir}/.monoclaw/vendor/runtime/venv/bin" \
    "${home_dir}/.monoclaw/logs" \
    "${home_dir}/.monoclaw/skills/customer-office" \
    "${home_dir}/.local/bin" \
    "${home_dir}/.monoclaw/vendor/wheelhouse"
  printf 'wheel placeholder\n' > "${home_dir}/.monoclaw/vendor/runtime/monoclaw-runtime.whl"
  printf '{"bundle_id":"test-bundle","bundle_version":"0.0.0-test"}\n' \
    > "${home_dir}/.monoclaw/vendor/hatch-manifest.json"
  printf 'skill placeholder\n' > "${home_dir}/.monoclaw/skills/customer-office/SKILL.md"

  # Optional fake venv python that handles "-c 'import monoclaw_runtime; ...'".
  if [[ "${include_venv_python}" == "yes" ]]; then
    cat > "${home_dir}/.monoclaw/vendor/runtime/venv/bin/python" <<'PY'
#!/usr/bin/env bash
# Tiny stub that just prints a synthetic version for any -c invocation. We
# don't need to actually import; the probe asserts on exit code, not contents.
if [[ "$1" == "-c" ]]; then
  printf '0.0.0-test\n'
  exit 0
fi
exit 0
PY
    chmod +x "${home_dir}/.monoclaw/vendor/runtime/venv/bin/python"
  fi

  case "${monoclaw_behavior}" in
    ok)
      cat > "${home_dir}/.monoclaw/vendor/runtime/venv/bin/monoclaw" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'monoclaw 0.0.0-test\n'
  exit 0
fi
if [[ "$1" == "doctor" ]]; then
  printf '{"issues": []}\n'
  exit 0
fi
exit 0
SH
      ;;
    fail)
      cat > "${home_dir}/.monoclaw/vendor/runtime/venv/bin/monoclaw" <<'SH'
#!/usr/bin/env bash
printf 'simulated --version failure\n' >&2
exit 7
SH
      ;;
    hang)
      cat > "${home_dir}/.monoclaw/vendor/runtime/venv/bin/monoclaw" <<'SH'
#!/usr/bin/env bash
# Sleep longer than the verifier's 15s timeout so the perl fallback has to
# kill us.
sleep 30
SH
      ;;
  esac
  chmod +x "${home_dir}/.monoclaw/vendor/runtime/venv/bin/monoclaw"
  cat > "${home_dir}/.local/bin/monoclaw" <<SH
#!/usr/bin/env bash
exec "${home_dir}/.monoclaw/vendor/runtime/venv/bin/monoclaw" "\$@"
SH
  chmod +x "${home_dir}/.local/bin/monoclaw"
}

run_verify_restricted() {
  local home_dir="$1"
  local extra_path="${home_dir}/.local/bin"
  PATH="${PATH_DIR}:${extra_path}" \
    HOME="${home_dir}" \
    bash "${HATCH_BIN}" --dry-run --bundle-root "${home_dir}/.monoclaw/vendor" verify
}

# CASE 1 — happy path: monoclaw --version OK, venv python OK, no timeout
# binary on PATH (forcing perl fallback).
CASE1_HOME="${TMP}/case1-home"
scaffold_install "${CASE1_HOME}" ok yes
run_verify_restricted "${CASE1_HOME}" >"${TMP}/case1.out" 2>"${TMP}/case1.err"
grep -q "monoclaw_runtime imported (version 0.0.0-test)" "${TMP}/case1.out"
grep -q "monoclaw --version: monoclaw 0.0.0-test" "${TMP}/case1.out"
grep -q "monoclaw doctor: all essential checks green" "${TMP}/case1.out"
# Sanity: confirm the perl fallback is what actually ran (no timeout binary
# leaked through the restricted PATH).
if PATH="${PATH_DIR}:${CASE1_HOME}/.local/bin" command -v timeout >/dev/null 2>&1; then
  printf 'restricted PATH leaked `timeout`; test invariant broken\n' >&2
  exit 1
fi
if PATH="${PATH_DIR}:${CASE1_HOME}/.local/bin" command -v gtimeout >/dev/null 2>&1; then
  printf 'restricted PATH leaked `gtimeout`; test invariant broken\n' >&2
  exit 1
fi

# CASE 2 — venv python missing: import probe should skip with a warn, but
# --version still runs and succeeds.
CASE2_HOME="${TMP}/case2-home"
scaffold_install "${CASE2_HOME}" ok no
run_verify_restricted "${CASE2_HOME}" >"${TMP}/case2.out" 2>"${TMP}/case2.err"
grep -q "Skipping monoclaw_runtime import probe: venv python not found" "${TMP}/case2.out"
grep -q "monoclaw --version: monoclaw 0.0.0-test" "${TMP}/case2.out"

# CASE 3 — monoclaw --version exits non-zero. In --dry-run mode warn_or_die
# becomes warn, so the verify command itself exits 0 but the warn message
# must surface and `doctor` must NOT have been attempted (early `return`).
CASE3_HOME="${TMP}/case3-home"
scaffold_install "${CASE3_HOME}" fail yes
run_verify_restricted "${CASE3_HOME}" >"${TMP}/case3.out" 2>"${TMP}/case3.err"
grep -q "monoclaw --version failed (exit 7)" "${TMP}/case3.out"
if grep -q "Running monoclaw doctor --json probe" "${TMP}/case3.out"; then
  printf 'expected verify to short-circuit after --version failure\n' >&2
  exit 1
fi

# CASE 4 — monoclaw hangs longer than the 15s timeout. The perl fallback must
# kill it and surface a "timed out" warn, NOT block the whole test run.
# Use bash's SECONDS to assert the verify command returns in well under 25s
# (15s hang timeout + grace).
CASE4_HOME="${TMP}/case4-home"
scaffold_install "${CASE4_HOME}" hang yes
case4_start=${SECONDS}
run_verify_restricted "${CASE4_HOME}" >"${TMP}/case4.out" 2>"${TMP}/case4.err"
case4_elapsed=$(( SECONDS - case4_start ))
if (( case4_elapsed > 25 )); then
  printf 'verify took %ds on hanging monoclaw; timeout helper failed to kill it\n' "${case4_elapsed}" >&2
  exit 1
fi
grep -q "monoclaw --version timed out after 15s" "${TMP}/case4.out"

printf 'verify probes tests passed\n'
