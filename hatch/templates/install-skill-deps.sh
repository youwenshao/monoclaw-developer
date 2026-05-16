#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="--apply"
SKILL_DEPS_PACK_ROOT="${SCRIPT_DIR}/../tool-packs/skill-deps-pack"

if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  MODE="--dry-run"
fi

if [[ ! -d "${SKILL_DEPS_PACK_ROOT}" ]]; then
  printf 'Skill dependencies pack not found: %s\n' "${SKILL_DEPS_PACK_ROOT}" >&2
  printf 'This bundle did not ship a skill-deps pack (no entries in bundle-inputs/vendor/skill-deps/tool-lock.json),\n' >&2
  printf 'or it was omitted by setting HATCH_INCLUDE_SKILL_DEPS=0 or HATCH_INCLUDE_SKILLS_DEPS=0 during ./build.sh.\n' >&2
  printf 'No bundled skill requires this pack for this release; nothing to install.\n' >&2
  exit 0
fi

exec bash "${SCRIPT_DIR}/bin/hatch" "${MODE}" --bundle-root "${SCRIPT_DIR}" --skill-deps-pack-root "${SKILL_DEPS_PACK_ROOT}" install-skill-deps "$@"
