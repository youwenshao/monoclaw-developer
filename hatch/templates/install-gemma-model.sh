#!/usr/bin/env bash
set -euo pipefail

DIST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="--apply"
MODEL_PACK_ROOT="${DIST_ROOT}/../model-packs/gemma-4-e4b"

if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  MODE="--dry-run"
fi

if [[ ! -d "${MODEL_PACK_ROOT}" ]] || [[ ! -f "${MODEL_PACK_ROOT}/model-pack-manifest.json" ]]; then
  printf 'Gemma model pack not found: %s\n' "${MODEL_PACK_ROOT}" >&2
  printf 'Expected model-packs/gemma-4-e4b as a sibling of this bundle directory (mirror ./build.sh output on the assembly machine).\n' >&2
  printf 'Copy both dist/ and model-packs/ to the provisioning medium, or rebuild when the optional Gemma input is present.\n' >&2
  printf 'Set HATCH_INSTALL_GEMMA_MODEL=0 on the target to skip this post-install step.\n' >&2
  exit 1
fi

exec bash "${DIST_ROOT}/bin/hatch" "${MODE}" --bundle-root "${DIST_ROOT}" --model-pack-root "${MODEL_PACK_ROOT}" install-model
