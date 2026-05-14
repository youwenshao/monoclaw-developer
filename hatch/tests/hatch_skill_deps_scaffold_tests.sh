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

# Build script must do nothing when HATCH_INCLUDE_SKILL_DEPS!=1.
DEFAULT_OUT="$(bash "${ROOT}/scripts/build_skill_deps_pack.sh" 2>&1)"
case "${DEFAULT_OUT}" in
  *"disabled"*) ;;
  *) printf 'fail: build_skill_deps_pack.sh did not skip when disabled. got: %s\n' "${DEFAULT_OUT}" >&2; exit 1;;
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

# Install template should exit cleanly when no pack exists alongside dist/.
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

printf 'ok: skill-deps scaffold\n'
