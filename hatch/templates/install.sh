#!/usr/bin/env bash
set -euo pipefail

DIST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="--apply"

if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  MODE="--dry-run"
fi

bash "${DIST_ROOT}/bin/hatch" "${MODE}" --bundle-root "${DIST_ROOT}" install

if [[ "${HATCH_INSTALL_MONA_TOOLS:-1}" != "1" ]]; then
  printf '  info: skipping Mona secretary tools because HATCH_INSTALL_MONA_TOOLS=0\n'
  exit 0
fi

if ! bash "${DIST_ROOT}/install-mona-tools.sh"; then
  printf '  warning: Mona secretary tools installation failed; core MonoClaw runtime remains installed\n' >&2
fi
