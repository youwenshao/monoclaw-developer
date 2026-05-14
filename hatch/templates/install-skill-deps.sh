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
  printf 'The pack is optional and only built when HATCH_INCLUDE_SKILL_DEPS=1 was set during ./build.sh.\n' >&2
  printf 'No skill in the bundled library currently requires it; nothing to install.\n' >&2
  exit 0
fi

exec bash "${SCRIPT_DIR}/bin/hatch" "${MODE}" --bundle-root "${SCRIPT_DIR}" --skill-deps-pack-root "${SKILL_DEPS_PACK_ROOT}" install-skill-deps "$@"
