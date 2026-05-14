#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="--apply"
TOOLS_PACK_ROOT="${SCRIPT_DIR}/../tool-packs/mona-secretary-tools"

if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  MODE="--dry-run"
fi

if [[ ! -d "${TOOLS_PACK_ROOT}" ]]; then
  printf 'Mona secretary tools pack not found: %s\n' "${TOOLS_PACK_ROOT}" >&2
  printf 'Expected tool-packs/mona-secretary-tools as a sibling of this bundle directory (mirror ./build.sh output on the assembly machine).\n' >&2
  printf 'Copy both dist/ and tool-packs/ to the provisioning medium, or rebuild with HATCH_INCLUDE_MONA_TOOLS=1 if the pack was never produced.\n' >&2
  printf 'Set HATCH_INSTALL_MONA_TOOLS=0 on the target to skip this post-install step.\n' >&2
  exit 1
fi

exec bash "${SCRIPT_DIR}/bin/hatch" "${MODE}" --bundle-root "${SCRIPT_DIR}" --tools-pack-root "${TOOLS_PACK_ROOT}" install-tools "$@"
