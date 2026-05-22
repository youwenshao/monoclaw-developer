#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PACK="${TMP}/model-packs/gemma-4-e4b"
HOME_DIR="${TMP}/home"
LM_STUDIO_APP="${TMP}/LM Studio.app"
mkdir -p "${PACK}" "${HOME_DIR}" "${LM_STUDIO_APP}"

printf 'Gemma 4 E4B GGUF placeholder\n' > "${PACK}/gemma-4-E4B-it-Q4_K_M.gguf"
printf 'Gemma 4 E4B mmproj placeholder\n' > "${PACK}/mmproj-gemma-4-E4B-it-f16.gguf"

python3 "${ROOT}/scripts/generate_model_pack_manifest.py" \
  --model-pack-root "${PACK}" \
  --model-id "local:gemma4:e4b" \
  --provider "lm-studio" \
  --role "chat" \
  --model-file "gemma-4-E4B-it-Q4_K_M.gguf" \
  --extra-file "mmproj-gemma-4-E4B-it-f16.gguf"

test -f "${PACK}/model-pack-manifest.json"

printf 'finder metadata\n' > "${PACK}/.DS_Store"
printf 'appledouble metadata\n' > "${PACK}/._gemma"
mkdir -p "${PACK}/__MACOSX" "${PACK}/.Spotlight-V100" "${PACK}/.fseventsd" "${PACK}/.Trashes"
printf 'archive metadata\n' > "${PACK}/__MACOSX/._gemma"
printf 'spotlight metadata\n' > "${PACK}/.Spotlight-V100/store"
printf 'fsevents metadata\n' > "${PACK}/.fseventsd/events"
printf 'trash metadata\n' > "${PACK}/.Trashes/501"

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --model-pack-root "${PACK}" verify-model-pack | tee "${TMP}/verify-pack.out"
grep -q "Model pack verified for local:gemma4:e4b" "${TMP}/verify-pack.out"

GEMMA_TARGET="${HOME_DIR}/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF"

if PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_LM_STUDIO_APP_PATH="${TMP}/missing-lm-studio.app" \
  bash "${ROOT}/bin/hatch" --dry-run --model-pack-root "${PACK}" install-model >"${TMP}/no-lmstudio.out" 2>&1; then
  printf 'expected install-model to fail when LM Studio is not installed\n' >&2
  exit 1
fi
grep -q "LM Studio is not installed" "${TMP}/no-lmstudio.out"

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_LM_STUDIO_APP_PATH="${LM_STUDIO_APP}" \
  bash "${ROOT}/bin/hatch" --dry-run --model-pack-root "${PACK}" install-model | tee "${TMP}/install-model.out"
grep -q "dry-run: mkdir -p ${GEMMA_TARGET}" "${TMP}/install-model.out"
grep -q "dry-run: cp ${PACK}/gemma-4-E4B-it-Q4_K_M.gguf ${GEMMA_TARGET}/.gemma-4-E4B-it-Q4_K_M.gguf.tmp" "${TMP}/install-model.out"
grep -q "dry-run: cp ${PACK}/mmproj-gemma-4-E4B-it-f16.gguf ${GEMMA_TARGET}/.mmproj-gemma-4-E4B-it-f16.gguf.tmp" "${TMP}/install-model.out"
grep -q "auto-discover the bundled GGUF" "${TMP}/install-model.out" || true

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_LM_STUDIO_APP_PATH="${LM_STUDIO_APP}" \
  bash "${ROOT}/bin/hatch" --apply --model-pack-root "${PACK}" install-model | tee "${TMP}/apply-model.out"
test -f "${GEMMA_TARGET}/gemma-4-E4B-it-Q4_K_M.gguf"
test -f "${GEMMA_TARGET}/mmproj-gemma-4-E4B-it-f16.gguf"
grep -q "Gemma 4 E4B model pack installed" "${TMP}/apply-model.out"

printf 'real stray file\n' > "${PACK}/notes.txt"
if PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --model-pack-root "${PACK}" verify-model-pack >"${TMP}/unlisted.out" 2>&1; then
  printf 'expected model pack verification to fail for an unlisted payload file\n' >&2
  exit 1
fi
grep -q "model pack file is not listed in manifest artifacts: notes.txt" "${TMP}/unlisted.out"
rm "${PACK}/notes.txt"

printf 'tampered\n' > "${PACK}/gemma-4-E4B-it-Q4_K_M.gguf"
if PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --model-pack-root "${PACK}" verify-model-pack >"${TMP}/tamper.out" 2>&1; then
  printf 'expected model pack verification to fail after tamper\n' >&2
  exit 1
fi
grep -Eq "model pack file (byte size|sha256) mismatch" "${TMP}/tamper.out"
