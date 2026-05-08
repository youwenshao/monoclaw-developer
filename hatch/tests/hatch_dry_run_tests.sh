#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

BUNDLE="${TMP}/dist"
HOME_DIR="${TMP}/home"
mkdir -p "${BUNDLE}/runtime" "${BUNDLE}/vendor/lm-studio" "${BUNDLE}/vendor/models/gemma-4-e4b" "${HOME_DIR}"
printf 'hello hatch\n' > "${BUNDLE}/runtime/about.md"
printf 'LM Studio app placeholder\n' > "${BUNDLE}/vendor/lm-studio/LM Studio.app"
printf 'Gemma 4 E4B GGUF placeholder\n' > "${BUNDLE}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"

SHA="$(shasum -a 256 "${BUNDLE}/runtime/about.md" | awk '{print $1}')"
BYTES="$(wc -c < "${BUNDLE}/runtime/about.md" | tr -d ' ')"
APP_SHA="$(shasum -a 256 "${BUNDLE}/vendor/lm-studio/LM Studio.app" | awk '{print $1}')"
APP_BYTES="$(wc -c < "${BUNDLE}/vendor/lm-studio/LM Studio.app" | tr -d ' ')"
MODEL_SHA="$(shasum -a 256 "${BUNDLE}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf" | awk '{print $1}')"
MODEL_BYTES="$(wc -c < "${BUNDLE}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf" | tr -d ' ')"

cat > "${BUNDLE}/hatch-manifest.json" <<JSON
{
  "schema_version": 1,
  "bundle_id": "test-bundle",
  "bundle_version": "0.0.0-test",
  "created_at": "2026-05-08T00:00:00Z",
  "target": {
    "platform": "darwin",
    "arch": "$(uname -m)",
    "minimum_macos": "14.0"
  },
  "runtime": {
    "package": "monoclaw-runtime",
    "version": "0.0.0-test",
    "wheel": "runtime/about.md",
    "entrypoints": ["monoclaw"]
  },
  "capabilities": {
    "local_inference": true,
    "telegram_gateway": true,
    "browser_automation": false,
    "sandbox_worker": false,
    "voice": false
  },
  "models": [
    {
      "id": "local:gemma4:e4b",
      "provider": "lm-studio",
      "role": "chat",
      "path": "vendor/models/gemma-4-e4b/gemma-4-e4b.gguf",
      "required": true
    }
  ],
  "artifacts": [
    {
      "path": "runtime/about.md",
      "kind": "file",
      "sha256": "${SHA}",
      "bytes": ${BYTES}
    },
    {
      "path": "vendor/lm-studio/LM Studio.app",
      "kind": "file",
      "sha256": "${APP_SHA}",
      "bytes": ${APP_BYTES}
    },
    {
      "path": "vendor/models/gemma-4-e4b/gemma-4-e4b.gguf",
      "kind": "file",
      "sha256": "${MODEL_SHA}",
      "bytes": ${MODEL_BYTES}
    }
  ]
}
JSON

run_hatch() {
  HOME="${HOME_DIR}" "${ROOT}/bin/hatch" --dry-run --bundle-root "${BUNDLE}" "$@"
}

run_hatch_default() {
  HOME="${HOME_DIR}" "${ROOT}/bin/hatch" --bundle-root "${BUNDLE}" "$@"
}

run_hatch preflight | tee "${TMP}/preflight.out"
grep -q "Manifest verified for bundle test-bundle" "${TMP}/preflight.out"

run_hatch install | tee "${TMP}/install.out"
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/install.out"
grep -q "dry-run: write ${HOME_DIR}/.monoclaw/.env with LM Studio defaults" "${TMP}/install.out"
grep -q "dry-run: write ${HOME_DIR}/.monoclaw/config.yaml with LM Studio defaults" "${TMP}/install.out"
grep -q "dry-run: cp ${BUNDLE}/hatch-manifest.json ${HOME_DIR}/.monoclaw/vendor/hatch-manifest.json" "${TMP}/install.out"
grep -q "dry-run: cp -R ${BUNDLE}/runtime ${HOME_DIR}/.monoclaw/vendor/runtime" "${TMP}/install.out"
grep -q "dry-run: cp -R ${BUNDLE}/vendor/lm-studio ${HOME_DIR}/.monoclaw/vendor/lm-studio" "${TMP}/install.out"
grep -q "dry-run: cp -R ${BUNDLE}/vendor/models ${HOME_DIR}/.monoclaw/vendor/models" "${TMP}/install.out"

run_hatch_default install | tee "${TMP}/default-install.out"
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/default-install.out"

mkdir -p "${HOME_DIR}/.monoclaw/vendor/runtime" "${HOME_DIR}/.monoclaw/logs"
cat > "${HOME_DIR}/.monoclaw/.env" <<'ENV'
MONOCLAW_MODEL=local:gemma4:e4b
OPENAI_BASE_URL=http://127.0.0.1:1234/v1
OPENAI_API_KEY=lm-studio
ENV
cat > "${HOME_DIR}/.monoclaw/config.yaml" <<'YAML'
model:
  provider: custom
  model: local:gemma4:e4b
  base_url: http://127.0.0.1:1234/v1
  api_key: lm-studio
YAML
cp -R "${BUNDLE}/runtime/." "${HOME_DIR}/.monoclaw/vendor/runtime/"
cp -R "${BUNDLE}/vendor/lm-studio" "${HOME_DIR}/.monoclaw/vendor/lm-studio"
cp -R "${BUNDLE}/vendor/models" "${HOME_DIR}/.monoclaw/vendor/models"
cp "${BUNDLE}/hatch-manifest.json" "${HOME_DIR}/.monoclaw/vendor/hatch-manifest.json"

run_hatch install | tee "${TMP}/existing-config-install.out"
grep -q "dry-run: keep existing ${HOME_DIR}/.monoclaw/.env" "${TMP}/existing-config-install.out"
grep -q "dry-run: keep existing ${HOME_DIR}/.monoclaw/config.yaml" "${TMP}/existing-config-install.out"

run_hatch verify | tee "${TMP}/verify.out"
grep -q "MonoClaw home exists" "${TMP}/verify.out"
grep -q "vendor runtime assets present" "${TMP}/verify.out"
grep -q "LM Studio bundle present" "${TMP}/verify.out"
grep -q "Gemma 4 E4B model present" "${TMP}/verify.out"
grep -q "LM Studio runtime defaults present" "${TMP}/verify.out"
grep -q "installed Hatch manifest present" "${TMP}/verify.out"

run_hatch doctor | tee "${TMP}/doctor.out"
grep -q "Hatch doctor complete" "${TMP}/doctor.out"
