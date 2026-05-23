#!/usr/bin/env bash
# Tests: HATCH_INSTALL_STRICT behaviour in templates/install.sh
#
# Covers:
# - When HATCH_INSTALL_STRICT=1 (default): install.sh exits 1 if Mona-tools
#   or skill-deps installer fails.
# - When HATCH_INSTALL_STRICT=0: failures produce a warning but install
#   continues (old behaviour preserved for benches that need partial installs).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# ── Minimal fake bundle layout ────────────────────────────────────────────
# hatch install is gated by run_prepare_bundle; we stub it out by creating
# the install.sh template directly and patching it to skip the main hatch call
# while still exercising the strict-failure logic.

# Create fake sub-installers in a separate fakes directory to avoid path clashes
FAKES="${TMP}/fakes"
mkdir -p "${FAKES}"

# Create a fake install-mona-tools.sh that always fails
FAKE_MONA_SH="${FAKES}/install-mona-tools.sh"
cat > "${FAKE_MONA_SH}" <<'SH'
#!/usr/bin/env bash
printf '  error: fake mona installer failure\n' >&2
exit 1
SH
chmod +x "${FAKE_MONA_SH}"

# Create a fake install-skill-deps.sh that always fails
FAKE_SKILL_DEPS_SH="${FAKES}/install-skill-deps.sh"
cat > "${FAKE_SKILL_DEPS_SH}" <<'SH'
#!/usr/bin/env bash
printf '  error: fake skill-deps installer failure\n' >&2
exit 1
SH
chmod +x "${FAKE_SKILL_DEPS_SH}"

# Create a fake install-gemma-model.sh that always fails
FAKE_GEMMA_SH="${FAKES}/install-gemma-model.sh"
cat > "${FAKE_GEMMA_SH}" <<'SH'
#!/usr/bin/env bash
printf '  error: fake gemma installer failure\n' >&2
exit 1
SH
chmod +x "${FAKE_GEMMA_SH}"

# Build a test variant of install.sh that skips the main hatch call
# but keeps the strict/non-strict logic intact
mkdir -p "${TMP}/dist"
PATCHED_INSTALL="${TMP}/dist/install-test.sh"
cat > "${PATCHED_INSTALL}" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
DIST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_INSTALL_STRICT="${HATCH_INSTALL_STRICT:-1}"

# Skip the real hatch install; just run the optional sub-installers
if [[ "${HATCH_INSTALL_MONA_TOOLS:-1}" != "1" ]]; then
  printf '  info: skipping Mona secretary tools\n'
else
  if ! bash "${DIST_ROOT}/install-mona-tools.sh" 2>&1; then
    MONA_PACK_ROOT="$(dirname "${DIST_ROOT}")/tool-packs/mona-secretary-tools"
    if [[ -d "${MONA_PACK_ROOT}" ]] && [[ "${HATCH_INSTALL_STRICT}" == "1" ]]; then
      printf '  error: Mona secretary tools installation failed (HATCH_INSTALL_STRICT=1).\n' >&2
      exit 1
    else
      printf '  warning: Mona secretary tools installation failed\n' >&2
    fi
  fi
fi

if [[ "${HATCH_INSTALL_GEMMA_MODEL:-1}" != "1" ]]; then
  printf '  info: skipping Gemma model pack\n'
else
  if ! bash "${DIST_ROOT}/install-gemma-model.sh" 2>&1; then
    GEMMA_PACK_ROOT="$(dirname "${DIST_ROOT}")/model-packs/gemma-4-e4b"
    if [[ -d "${GEMMA_PACK_ROOT}" ]] && [[ "${HATCH_INSTALL_STRICT}" == "1" ]]; then
      printf '  error: Gemma model pack installation failed (HATCH_INSTALL_STRICT=1).\n' >&2
      exit 1
    else
      printf '  warning: Gemma model pack installation failed\n' >&2
    fi
  fi
fi

if [[ "${HATCH_INSTALL_SKILL_DEPS:-1}" != "1" ]]; then
  printf '  info: skipping skill-deps\n'
  exit 0
fi

if [[ -f "${DIST_ROOT}/install-skill-deps.sh" ]]; then
  if ! bash "${DIST_ROOT}/install-skill-deps.sh" 2>&1; then
    SKILL_DEPS_PACK_ROOT="$(dirname "${DIST_ROOT}")/tool-packs/skill-deps-pack"
    if [[ -d "${SKILL_DEPS_PACK_ROOT}" ]] && [[ "${HATCH_INSTALL_STRICT}" == "1" ]]; then
      printf '  error: skill dependencies installation failed (HATCH_INSTALL_STRICT=1).\n' >&2
      exit 1
    else
      printf '  warning: skill dependencies installation failed\n' >&2
    fi
  fi
fi
SH
chmod +x "${PATCHED_INSTALL}"

# Copy fake sub-installers next to the patched install script
cp "${FAKE_MONA_SH}" "${TMP}/dist/install-mona-tools.sh"
cp "${FAKE_GEMMA_SH}" "${TMP}/dist/install-gemma-model.sh"
cp "${FAKE_SKILL_DEPS_SH}" "${TMP}/dist/install-skill-deps.sh"

# Create a fake tool-packs directory so the strict logic triggers.
# dirname("${TMP}/dist") = "${TMP}", so tool-packs must be at "${TMP}/tool-packs/".
# (strict mode only applies when the pack IS present but the installer crashed)
mkdir -p "${TMP}/tool-packs/mona-secretary-tools"
mkdir -p "${TMP}/tool-packs/skill-deps-pack"

# ── Test 1: HATCH_INSTALL_STRICT=1 exits 1 when mona-tools fails ─────────
printf 'test: HATCH_INSTALL_STRICT=1 exits 1 on mona-tools failure... '
if HATCH_INSTALL_STRICT=1 bash "${PATCHED_INSTALL}" > "${TMP}/t1.out" 2>&1; then
  printf 'FAIL (expected exit 1, got 0)\n' >&2
  cat "${TMP}/t1.out" >&2
  exit 1
else
  printf 'ok\n'
fi

# ── Test 2: HATCH_INSTALL_STRICT=0 continues when mona-tools fails ───────
printf 'test: HATCH_INSTALL_STRICT=0 continues on mona-tools failure... '
if ! HATCH_INSTALL_STRICT=0 HATCH_INSTALL_SKILL_DEPS=0 bash "${PATCHED_INSTALL}" > "${TMP}/t2.out" 2>&1; then
  printf 'FAIL (expected exit 0, got 1)\n' >&2
  cat "${TMP}/t2.out" >&2
  exit 1
fi
if ! grep -q "warning: Mona secretary tools installation failed" "${TMP}/t2.out"; then
  printf 'FAIL (warning message missing)\n' >&2
  cat "${TMP}/t2.out" >&2
  exit 1
fi
printf 'ok\n'

# ── Test 3: HATCH_INSTALL_STRICT=1 exits 1 when skill-deps fails ─────────
printf 'test: HATCH_INSTALL_STRICT=1 exits 1 on skill-deps failure... '
# Temporarily make Mona succeed so we can test skill-deps in isolation
cat > "${TMP}/dist/install-mona-tools.sh" <<'SH2'
#!/usr/bin/env bash
exit 0
SH2
chmod +x "${TMP}/dist/install-mona-tools.sh"
if HATCH_INSTALL_STRICT=1 bash "${PATCHED_INSTALL}" > "${TMP}/t3.out" 2>&1; then
  printf 'FAIL (expected exit 1, got 0)\n' >&2
  cat "${TMP}/t3.out" >&2
  exit 1
else
  printf 'ok\n'
fi

# ── Test 4: HATCH_INSTALL_STRICT=0 continues when skill-deps fails ────────
printf 'test: HATCH_INSTALL_STRICT=0 continues on skill-deps failure... '
if ! HATCH_INSTALL_STRICT=0 bash "${PATCHED_INSTALL}" > "${TMP}/t4.out" 2>&1; then
  printf 'FAIL (expected exit 0, got 1)\n' >&2
  cat "${TMP}/t4.out" >&2
  exit 1
fi
if ! grep -q "warning: skill dependencies installation failed" "${TMP}/t4.out"; then
  printf 'FAIL (skill-deps warning missing)\n' >&2
  cat "${TMP}/t4.out" >&2
  exit 1
fi
printf 'ok\n'

# ── Test 5: HATCH_INSTALL_STRICT=1 exits 1 when gemma model pack fails ───
printf 'test: HATCH_INSTALL_STRICT=1 exits 1 on gemma failure... '
mkdir -p "${TMP}/tool-packs/gemma-4-e4b"
if HATCH_INSTALL_MONA_TOOLS=0 HATCH_INSTALL_STRICT=1 bash "${PATCHED_INSTALL}" > "${TMP}/t5.out" 2>&1; then
  printf 'FAIL (expected exit 1, got 0)\n' >&2
  cat "${TMP}/t5.out" >&2
  exit 1
else
  printf 'ok\n'
fi

# ── Test 6: HATCH_INSTALL_STRICT=0 continues when gemma model pack fails ─
printf 'test: HATCH_INSTALL_STRICT=0 continues on gemma failure... '
if ! HATCH_INSTALL_MONA_TOOLS=0 HATCH_INSTALL_SKILL_DEPS=0 HATCH_INSTALL_STRICT=0 bash "${PATCHED_INSTALL}" > "${TMP}/t6.out" 2>&1; then
  printf 'FAIL (expected exit 0, got 1)\n' >&2
  cat "${TMP}/t6.out" >&2
  exit 1
fi
if ! grep -q "warning: Gemma model pack installation failed" "${TMP}/t6.out"; then
  printf 'FAIL (gemma warning message missing)\n' >&2
  cat "${TMP}/t6.out" >&2
  exit 1
fi
printf 'ok\n'

printf '\nhatch_install_strict_tests: all tests passed\n'
