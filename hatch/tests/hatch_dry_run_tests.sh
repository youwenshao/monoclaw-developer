#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

BUNDLE="${TMP}/dist"
HOME_DIR="${TMP}/home"
WHEEL_NAME="monoclaw-runtime.whl"
PIP_WHEEL_NAME="monoclaw_runtime-0.0.0_test-py3-none-any.whl"
mkdir -p "${BUNDLE}/runtime" "${BUNDLE}/vendor/skills/customer-office" "${BUNDLE}/vendor/optional-skills/research/deep-research" "${BUNDLE}/vendor/wheelhouse" "${HOME_DIR}"
FAKE_PYTHON="${TMP}/python3.11"
FAKE_ENSUREPIP_BROKEN_PYTHON="${TMP}/python3.11-ensurepip-broken"
cat > "${FAKE_PYTHON}" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "-c" ]; then
  printf '3.11.9\n'
  exit 0
fi
exec /usr/bin/python3 "$@"
SH
chmod +x "${FAKE_PYTHON}"
cat > "${FAKE_ENSUREPIP_BROKEN_PYTHON}" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "-c" ]; then
  printf '3.11.9\n'
  exit 0
fi
exec /usr/bin/python3 "$@"
SH
chmod +x "${FAKE_ENSUREPIP_BROKEN_PYTHON}"
printf 'hello hatch\n' > "${BUNDLE}/runtime/about.md"
printf 'wheel placeholder\n' > "${BUNDLE}/runtime/${WHEEL_NAME}"
printf 'skill placeholder\n' > "${BUNDLE}/vendor/skills/customer-office/SKILL.md"
printf 'optional skill placeholder\n' > "${BUNDLE}/vendor/optional-skills/research/deep-research/SKILL.md"
printf 'pip wheel placeholder\n' > "${BUNDLE}/vendor/wheelhouse/pip-24.0-py3-none-any.whl"

SHA="$(shasum -a 256 "${BUNDLE}/runtime/about.md" | awk '{print $1}')"
BYTES="$(wc -c < "${BUNDLE}/runtime/about.md" | tr -d ' ')"
WHEEL_SHA="$(shasum -a 256 "${BUNDLE}/runtime/${WHEEL_NAME}" | awk '{print $1}')"
WHEEL_BYTES="$(wc -c < "${BUNDLE}/runtime/${WHEEL_NAME}" | tr -d ' ')"
SKILL_SHA="$(shasum -a 256 "${BUNDLE}/vendor/skills/customer-office/SKILL.md" | awk '{print $1}')"
SKILL_BYTES="$(wc -c < "${BUNDLE}/vendor/skills/customer-office/SKILL.md" | tr -d ' ')"
OPTIONAL_SKILL_SHA="$(shasum -a 256 "${BUNDLE}/vendor/optional-skills/research/deep-research/SKILL.md" | awk '{print $1}')"
OPTIONAL_SKILL_BYTES="$(wc -c < "${BUNDLE}/vendor/optional-skills/research/deep-research/SKILL.md" | tr -d ' ')"
WHEELHOUSE_SHA="$(shasum -a 256 "${BUNDLE}/vendor/wheelhouse/pip-24.0-py3-none-any.whl" | awk '{print $1}')"
WHEELHOUSE_BYTES="$(wc -c < "${BUNDLE}/vendor/wheelhouse/pip-24.0-py3-none-any.whl" | tr -d ' ')"

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
    "wheel": "runtime/${WHEEL_NAME}",
    "entrypoints": ["monoclaw"]
  },
  "capabilities": {
    "local_inference": false,
    "lm_studio": false,
    "telegram_gateway": true,
    "browser_automation": false,
    "sandbox_worker": false,
    "voice": false
  },
  "models": [],
  "artifacts": [
    {
      "path": "runtime/about.md",
      "kind": "file",
      "sha256": "${SHA}",
      "bytes": ${BYTES}
    },
    {
      "path": "runtime/${WHEEL_NAME}",
      "kind": "file",
      "sha256": "${WHEEL_SHA}",
      "bytes": ${WHEEL_BYTES}
    },
    {
      "path": "vendor/skills/customer-office/SKILL.md",
      "kind": "file",
      "sha256": "${SKILL_SHA}",
      "bytes": ${SKILL_BYTES}
    },
    {
      "path": "vendor/optional-skills/research/deep-research/SKILL.md",
      "kind": "file",
      "sha256": "${OPTIONAL_SKILL_SHA}",
      "bytes": ${OPTIONAL_SKILL_BYTES}
    },
    {
      "path": "vendor/wheelhouse/pip-24.0-py3-none-any.whl",
      "kind": "file",
      "sha256": "${WHEELHOUSE_SHA}",
      "bytes": ${WHEELHOUSE_BYTES}
    }
  ]
}
JSON

run_hatch() {
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_RUNTIME_PYTHON="${FAKE_PYTHON}" "${ROOT}/bin/hatch" --dry-run --bundle-root "${BUNDLE}" "$@"
}

# Variant that includes the home dir's .local/bin so have_command monoclaw can find the shim.
run_hatch_with_local_bin() {
  PATH="${HOME_DIR}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_RUNTIME_PYTHON="${FAKE_PYTHON}" "${ROOT}/bin/hatch" --dry-run --bundle-root "${BUNDLE}" "$@"
}

run_hatch_default() {
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_RUNTIME_PYTHON="${FAKE_PYTHON}" "${ROOT}/bin/hatch" --bundle-root "${BUNDLE}" "$@"
}

run_hatch_without_runtime_python() {
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_FORCE_RUNTIME_PYTHON_MISSING=1 "${ROOT}/bin/hatch" --dry-run --bundle-root "${BUNDLE}" "$@"
}

run_hatch_with_broken_ensurepip() {
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" HATCH_FORCE_HOMEBREW_MISSING=1 HATCH_TEST_VENV_ENSUREPIP_FAIL=1 HATCH_RUNTIME_PYTHON="${FAKE_ENSUREPIP_BROKEN_PYTHON}" "${ROOT}/bin/hatch" --dry-run --bundle-root "${BUNDLE}" "$@"
}

run_hatch preflight | tee "${TMP}/preflight.out"
grep -q "Manifest verified for bundle test-bundle" "${TMP}/preflight.out"
grep -q "dry-run: install Homebrew with official installer" "${TMP}/preflight.out"
MANUAL_LINE="$(awk '/Checking manual macOS prerequisites/{print NR; exit}' "${TMP}/preflight.out")"
BUNDLE_LINE="$(awk '/Verifying prepared Hatch bundle/{print NR; exit}' "${TMP}/preflight.out")"
test "${MANUAL_LINE}" -lt "${BUNDLE_LINE}"
if grep -q "Hatch will .*LM Studio" "${TMP}/preflight.out"; then
  printf 'preflight should not promise scripted LM Studio installation\n' >&2
  exit 1
fi

run_hatch_without_runtime_python preflight | tee "${TMP}/preflight-python.out"
grep -q "Python 3.11+ runtime interpreter missing; bundle vendor/python/current/bin/python3" "${TMP}/preflight-python.out"

run_hatch install | tee "${TMP}/install.out"
VERIFY_LINE="$(awk '/Checking prepared Hatch bundle/{print NR; exit}' "${TMP}/install.out")"
HOMEBREW_LINE="$(awk '/install Homebrew with official installer/{print NR; exit}' "${TMP}/install.out")"
test "${VERIFY_LINE}" -lt "${HOMEBREW_LINE}"
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/install.out"
grep -q "dry-run: leave ${HOME_DIR}/.monoclaw/.env for monoclaw setup" "${TMP}/install.out"
grep -q "dry-run: leave ${HOME_DIR}/.monoclaw/config.yaml for monoclaw setup" "${TMP}/install.out"
grep -q "dry-run: cp ${BUNDLE}/hatch-manifest.json ${HOME_DIR}/.monoclaw/vendor/hatch-manifest.json" "${TMP}/install.out"
grep -q "dry-run: cp -R ${BUNDLE}/runtime ${HOME_DIR}/.monoclaw/vendor/runtime" "${TMP}/install.out"
grep -q "dry-run: cp -R ${BUNDLE}/vendor/optional-skills ${HOME_DIR}/.monoclaw/vendor/optional-skills" "${TMP}/install.out"
grep -q "Using Python ${FAKE_PYTHON} (3.11.9) for runtime bootstrap" "${TMP}/install.out"
grep -q "dry-run: ${FAKE_PYTHON} -m venv ${HOME_DIR}/.monoclaw/vendor/runtime/venv" "${TMP}/install.out"
grep -Fq "dry-run: cp ${HOME_DIR}/.monoclaw/vendor/runtime/${WHEEL_NAME} ${HOME_DIR}/.monoclaw/vendor/runtime/.hatch-install/${PIP_WHEEL_NAME}" "${TMP}/install.out"
grep -Fq "dry-run: ${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/python -m pip install --no-index --find-links ${HOME_DIR}/.monoclaw/vendor/wheelhouse --upgrade pip setuptools wheel" "${TMP}/install.out"
grep -Fq "dry-run: ${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/python -m pip install --no-index --find-links ${HOME_DIR}/.monoclaw/vendor/wheelhouse ${HOME_DIR}/.monoclaw/vendor/runtime/.hatch-install/${PIP_WHEEL_NAME}[local-office]" "${TMP}/install.out"
grep -q "dry-run: write ${HOME_DIR}/.local/bin/monoclaw shim" "${TMP}/install.out"
grep -q "dry-run: install bundled skills into ${HOME_DIR}/.monoclaw/skills" "${TMP}/install.out"
grep -q "manual: install LM Studio from the official .dmg if local inference is required" "${TMP}/install.out"
if grep -q "lmstudio.ai/install.sh" "${TMP}/install.out"; then
  printf 'install should not script LM Studio installation\n' >&2
  exit 1
fi
grep -q "run monoclaw provision" "${TMP}/install.out"

run_hatch_with_broken_ensurepip install | tee "${TMP}/install-broken-ensurepip.out"
grep -q "Bundled Python failed to create a pip-capable venv; rebuild the bundle with a working Python runtime" "${TMP}/install-broken-ensurepip.out"
if grep -q "get-pip.py" "${TMP}/install-broken-ensurepip.out"; then
  printf 'runtime bootstrap should not fetch get-pip.py in the production path\n' >&2
  exit 1
fi

run_hatch_default install | tee "${TMP}/default-install.out"
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/default-install.out"

cp "${BUNDLE}/hatch-manifest.json" "${TMP}/hatch-manifest.with-wheelhouse.json"
mv "${BUNDLE}/vendor/wheelhouse" "${TMP}/wheelhouse.missing"
python3 - "${BUNDLE}/hatch-manifest.json" <<'PY'
import json
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
data = json.loads(manifest.read_text(encoding="utf-8"))
data["artifacts"] = [
    artifact for artifact in data["artifacts"]
    if not artifact["path"].startswith("vendor/wheelhouse/")
]
manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
run_hatch install >"${TMP}/missing-wheelhouse.out" 2>&1
grep -q "Bundled wheelhouse is required for production runtime bootstrap" "${TMP}/missing-wheelhouse.out"
mv "${TMP}/wheelhouse.missing" "${BUNDLE}/vendor/wheelhouse"
cp "${TMP}/hatch-manifest.with-wheelhouse.json" "${BUNDLE}/hatch-manifest.json"

mkdir -p "${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin" "${HOME_DIR}/.monoclaw/logs" "${HOME_DIR}/.monoclaw/skills/customer-office" "${HOME_DIR}/.local/bin"
cat > "${HOME_DIR}/.monoclaw/.env" <<'ENV'
MONOCLAW_MODEL=local:gemma4:e4b
LM_BASE_URL=http://127.0.0.1:1234/v1
LM_API_KEY=dummy-lm-api-key
ENV
cat > "${HOME_DIR}/.monoclaw/config.yaml" <<'YAML'
model:
  provider: lmstudio
  default: local:gemma4:e4b
  base_url: http://127.0.0.1:1234/v1
YAML
cp -R "${BUNDLE}/runtime/." "${HOME_DIR}/.monoclaw/vendor/runtime/"
cp "${BUNDLE}/hatch-manifest.json" "${HOME_DIR}/.monoclaw/vendor/hatch-manifest.json"
printf '#!/usr/bin/env bash\nprintf "monoclaw 0.0.0-test\\n"\n' > "${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/monoclaw"
chmod +x "${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/monoclaw"
printf '#!/usr/bin/env bash\nexec "%s/.monoclaw/vendor/runtime/venv/bin/monoclaw" "$@"\n' "${HOME_DIR}" > "${HOME_DIR}/.local/bin/monoclaw"
chmod +x "${HOME_DIR}/.local/bin/monoclaw"
printf 'skill placeholder\n' > "${HOME_DIR}/.monoclaw/skills/customer-office/SKILL.md"

run_hatch install | tee "${TMP}/existing-config-install.out"
grep -q "dry-run: keep existing ${HOME_DIR}/.monoclaw/.env" "${TMP}/existing-config-install.out"
grep -q "dry-run: keep existing ${HOME_DIR}/.monoclaw/config.yaml" "${TMP}/existing-config-install.out"

# Regression: broken shim (shim exists but venv binary absent) must not crash cleanup.
# This reproduces the scenario where a previous install failed at the pip step (e.g.
# a missing wheel), leaving install_runtime_assets having deleted the old venv while
# write_monoclaw_shim was never re-run — so the shim still points at a deleted binary.
rm -f "${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/monoclaw"
run_hatch_with_local_bin install | tee "${TMP}/broken-shim-install.out"
grep -q "monoclaw shim found but runtime venv is missing or incomplete; skipping gateway cleanup" "${TMP}/broken-shim-install.out"
if grep -q "dry-run: monoclaw gateway stop" "${TMP}/broken-shim-install.out"; then
  printf 'FAIL: gateway stop must not be attempted when venv binary is absent\n' >&2
  exit 1
fi
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/broken-shim-install.out"
# Restore venv binary for subsequent tests.
printf '#!/usr/bin/env bash\nprintf "monoclaw 0.0.0-test\\n"\n' > "${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/monoclaw"
chmod +x "${HOME_DIR}/.monoclaw/vendor/runtime/venv/bin/monoclaw"

run_hatch verify | tee "${TMP}/verify.out"
grep -q "MonoClaw home exists" "${TMP}/verify.out"
grep -q "vendor runtime assets present" "${TMP}/verify.out"
grep -q "installed Hatch manifest present" "${TMP}/verify.out"
grep -q "monoclaw venv entrypoint present" "${TMP}/verify.out"
grep -q "monoclaw command shim present" "${TMP}/verify.out"
grep -q "bundled skills installed" "${TMP}/verify.out"

run_hatch verify-local-inference | tee "${TMP}/verify-local.out"
grep -q "Checking optional local inference readiness" "${TMP}/verify-local.out"
grep -q "Gemma 4 E4B model is missing" "${TMP}/verify-local.out"

run_hatch doctor | tee "${TMP}/doctor.out"
grep -q "Hatch doctor complete" "${TMP}/doctor.out"
