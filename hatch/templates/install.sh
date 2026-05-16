#!/usr/bin/env bash
set -euo pipefail

DIST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="--apply"

if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  MODE="--dry-run"
fi

printf '  info: MonoClaw Hatch install from bundle root: %s\n' "${DIST_ROOT}" >&2

bash "${DIST_ROOT}/bin/hatch" "${MODE}" --bundle-root "${DIST_ROOT}" install

if [[ "${HATCH_INSTALL_MONA_TOOLS:-1}" != "1" ]]; then
  printf '  info: skipping Mona secretary tools because HATCH_INSTALL_MONA_TOOLS=0\n'
else
  if ! bash "${DIST_ROOT}/install-mona-tools.sh"; then
    printf '  warning: Mona secretary tools installation failed; core MonoClaw runtime remains installed\n' >&2
  fi
fi

if [[ "${HATCH_INSTALL_SKILL_DEPS:-1}" != "1" ]]; then
  printf '  info: skipping skill dependencies pack because HATCH_INSTALL_SKILL_DEPS=0\n'
  exit 0
fi

if [[ -f "${DIST_ROOT}/install-skill-deps.sh" ]]; then
  if ! bash "${DIST_ROOT}/install-skill-deps.sh"; then
    printf '  warning: skill dependencies installation failed; core MonoClaw runtime remains installed\n' >&2
  fi
fi
