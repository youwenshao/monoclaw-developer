#!/usr/bin/env bash
set -euo pipefail

DIST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="--apply"
MODEL_PACK_ROOT="${DIST_ROOT}/../model-packs/gemma-4-e4b"

if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  MODE="--dry-run"
fi

exec bash "${DIST_ROOT}/bin/hatch" "${MODE}" --bundle-root "${DIST_ROOT}" --model-pack-root "${MODEL_PACK_ROOT}" install-model
