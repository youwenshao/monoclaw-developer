#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="${SCRIPT_DIR}"

HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"
if [[ -z "${HATCH_RUNTIME_ROOT:-}" ]]; then
  if [[ -d "${HATCH_ROOT}/../monoclaw-runtime" ]]; then
    HATCH_RUNTIME_ROOT="$(cd "${HATCH_ROOT}/../monoclaw-runtime" && pwd)"
  elif [[ -d "${HATCH_ROOT}/../../monoclaw-runtime" ]]; then
    HATCH_RUNTIME_ROOT="$(cd "${HATCH_ROOT}/../../monoclaw-runtime" && pwd)"
  else
    HATCH_RUNTIME_ROOT="$(cd "${HATCH_ROOT}/.." && pwd)/monoclaw-runtime"
  fi
fi
HATCH_DIST_ROOT="${HATCH_DIST_ROOT:-${HATCH_ROOT}/dist}"
HATCH_MODEL_PACKS_ROOT="${HATCH_MODEL_PACKS_ROOT:-$(cd "$(dirname "${HATCH_DIST_ROOT}")" && pwd)/model-packs}"
HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH:-$(uname -m)}"
HATCH_MINIMUM_MACOS="${HATCH_MINIMUM_MACOS:-14.0}"

log() {
  printf '[hatch-build] %s\n' "$1"
}

die() {
  printf '[hatch-build] fail: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || die "$2: $1"
}

require_dir() {
  [[ -d "$1" ]] || die "$2: $1"
}

validate_dist_root() {
  HATCH_ROOT="${HATCH_ROOT}" \
  HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
  HATCH_RUNTIME_ROOT="${HATCH_RUNTIME_ROOT}" \
  HATCH_DIST_ROOT="${HATCH_DIST_ROOT}" \
  python3 <<'PY'
import os
from pathlib import Path

hatch = Path(os.environ["HATCH_ROOT"]).resolve()
inputs = Path(os.environ["HATCH_INPUT_ROOT"]).resolve()
runtime = Path(os.environ["HATCH_RUNTIME_ROOT"]).resolve()
dist = Path(os.environ["HATCH_DIST_ROOT"]).resolve()
default_dist = hatch / "dist"

def contains(parent: Path, child: Path) -> bool:
    return parent == child or parent in child.parents

unsafe = dist == Path("/")
unsafe = unsafe or contains(dist, hatch)
unsafe = unsafe or contains(dist, inputs) or contains(inputs, dist)
unsafe = unsafe or contains(dist, runtime) or contains(runtime, dist)
unsafe = unsafe or (contains(hatch, dist) and dist != default_dist)

if unsafe:
    raise SystemExit(f"unsafe dist root: {dist}")
PY
}

runtime_version() {
  HATCH_RUNTIME_ROOT="${HATCH_RUNTIME_ROOT}" python3 <<'PY'
import os
import tomllib
from pathlib import Path

pyproject = Path(os.environ["HATCH_RUNTIME_ROOT"]) / "pyproject.toml"
data = tomllib.loads(pyproject.read_text(encoding="utf-8"))
print(data["project"]["version"])
PY
}

build_runtime_web_assets() {
  local web_dir="${HATCH_RUNTIME_ROOT}/web"

  if [[ "${HATCH_SKIP_RUNTIME_BUILD:-0}" == "1" ]]; then
    log "Skipping runtime web build because HATCH_SKIP_RUNTIME_BUILD=1"
    return
  fi

  require_file "${web_dir}/package.json" "runtime web package is missing"
  require_file "${web_dir}/package-lock.json" "runtime web package lock is missing"
  log "Building runtime web dashboard assets"
  (cd "${web_dir}" && npm ci && npm run build)
}

build_runtime_wheel() {
  local wheel_dir="$1"
  mkdir -p "${wheel_dir}"

  if [[ -n "${HATCH_RUNTIME_WHEEL:-}" ]]; then
    require_file "${HATCH_RUNTIME_WHEEL}" "runtime wheel override is missing"
    cp "${HATCH_RUNTIME_WHEEL}" "${wheel_dir}/$(basename "${HATCH_RUNTIME_WHEEL}")"
    return
  fi

  if [[ "${HATCH_SKIP_RUNTIME_BUILD:-0}" == "1" ]]; then
    die "HATCH_SKIP_RUNTIME_BUILD=1 requires HATCH_RUNTIME_WHEEL"
  fi

  local python_bin="python3"
  if [[ -x "${HATCH_RUNTIME_ROOT}/.venv/bin/python" ]]; then
    python_bin="${HATCH_RUNTIME_ROOT}/.venv/bin/python"
  fi

  log "Building monoclaw-runtime wheel"
  "${python_bin}" -m build --wheel --outdir "${wheel_dir}" "${HATCH_RUNTIME_ROOT}"

  python3 - "${wheel_dir}" <<'PY'
import sys
from pathlib import Path

wheel_dir = Path(sys.argv[1])
wheels = sorted(wheel_dir.glob("monoclaw_runtime-*.whl"))
if not wheels:
    raise SystemExit("no monoclaw_runtime wheel was produced")
PY
}

verify_runtime_python_bundle() {
  local python_bin="${HATCH_INPUT_ROOT}/vendor/python/current/bin/python3"
  require_file "${python_bin}" "Python 3.11+ runtime bundle is required"

  "${python_bin}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' \
    || die "Python runtime bundle must be Python 3.11+: ${python_bin}"

  if [[ "${HATCH_SKIP_RUNTIME_PYTHON_SMOKE:-0}" == "1" ]]; then
    log "Skipping runtime Python smoke test because HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1"
    return
  fi

  local smoke_dir
  smoke_dir="$(mktemp -d)"
  trap 'rm -rf "${smoke_dir}"' RETURN
  log "Smoke testing bundled Python runtime"
  "${python_bin}" -m venv "${smoke_dir}/venv"
  "${smoke_dir}/venv/bin/python" -m pip --version >/dev/null
  rm -rf "${smoke_dir}"
  trap - RETURN
}

verify_runtime_wheelhouse() {
  local wheelhouse="${HATCH_INPUT_ROOT}/vendor/wheelhouse"
  if [[ ! -d "${wheelhouse}" ]]; then
    die "runtime wheelhouse is required for production bundles: ${wheelhouse}; run: bash scripts/build_wheelhouse.sh"
  fi
  if [[ -z "$(ls -A "${wheelhouse}" 2>/dev/null || true)" ]]; then
    die "runtime wheelhouse must contain local-office dependency wheels: ${wheelhouse}; run: bash scripts/build_wheelhouse.sh"
  fi
}

copy_optional_vendor_asset() {
  local asset="$1"
  if [[ -d "${HATCH_INPUT_ROOT}/vendor/${asset}" ]]; then
    log "Staging vendor/${asset}"
    mkdir -p "${HATCH_DIST_ROOT}/vendor"
    cp -R "${HATCH_INPUT_ROOT}/vendor/${asset}" "${HATCH_DIST_ROOT}/vendor/${asset}"
  fi
}

stage_model_packs() {
  local source_model="${HATCH_INPUT_ROOT}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf"
  local pack_root="${HATCH_MODEL_PACKS_ROOT}/gemma-4-e4b"

  rm -rf "${pack_root}"
  if [[ ! -f "${source_model}" ]]; then
    log "No Gemma 4 E4B model input found; skipping optional model pack"
    return
  fi

  log "Staging optional Gemma 4 E4B model pack"
  mkdir -p "${pack_root}"
  cp "${source_model}" "${pack_root}/gemma-4-e4b.gguf"
  python3 "${HATCH_ROOT}/scripts/generate_model_pack_manifest.py" \
    --model-pack-root "${pack_root}" \
    --model-id "local:gemma4:e4b" \
    --provider "lm-studio" \
    --role "chat" \
    --model-file "gemma-4-e4b.gguf"
}

stage_runtime_skills() {
  if [[ -d "${HATCH_DIST_ROOT}/vendor/skills" ]]; then
    log "Using curated vendor/skills from bundle inputs"
    return
  fi

  if [[ -d "${HATCH_RUNTIME_ROOT}/skills" ]]; then
    log "Staging runtime bundled skills"
    mkdir -p "${HATCH_DIST_ROOT}/vendor"
    cp -R "${HATCH_RUNTIME_ROOT}/skills" "${HATCH_DIST_ROOT}/vendor/skills"
  fi
}

stage_bundle() {
  require_dir "${HATCH_INPUT_ROOT}" "bundle input directory is missing"
  require_dir "${HATCH_RUNTIME_ROOT}" "runtime checkout is missing"
  require_file "${HATCH_RUNTIME_ROOT}/pyproject.toml" "runtime pyproject is missing"
  verify_runtime_python_bundle
  verify_runtime_wheelhouse
  validate_dist_root

  rm -rf "${HATCH_DIST_ROOT}"
  mkdir -p "${HATCH_DIST_ROOT}/bin" "${HATCH_DIST_ROOT}/lib" "${HATCH_DIST_ROOT}/runtime" "${HATCH_DIST_ROOT}/tests"

  cp "${HATCH_ROOT}/bin/hatch" "${HATCH_DIST_ROOT}/bin/hatch"
  cp "${HATCH_ROOT}/lib/common.sh" "${HATCH_DIST_ROOT}/lib/common.sh"
  cp "${HATCH_ROOT}/templates/install.sh" "${HATCH_DIST_ROOT}/install.sh"
  cp "${HATCH_ROOT}/templates/install-gemma-model.sh" "${HATCH_DIST_ROOT}/install-gemma-model.sh"
  cp "${HATCH_ROOT}/tests/hatch_dry_run_tests.sh" "${HATCH_DIST_ROOT}/tests/run-hatch-dry-run.sh"
  chmod +x "${HATCH_DIST_ROOT}/bin/hatch" "${HATCH_DIST_ROOT}/install.sh" "${HATCH_DIST_ROOT}/install-gemma-model.sh" "${HATCH_DIST_ROOT}/tests/run-hatch-dry-run.sh"

  build_runtime_web_assets
  build_runtime_wheel "${HATCH_DIST_ROOT}/runtime"

  local version
  version="$(runtime_version)"
  cat > "${HATCH_DIST_ROOT}/runtime/about.md" <<EOF
MonoClaw Runtime ${version}

Built by Hatch from ${HATCH_RUNTIME_ROOT}.
EOF
  cat > "${HATCH_DIST_ROOT}/runtime/constraints.txt" <<'EOF'
# Hatch customer bundle constraints.
#
# monoclaw-runtime currently has no checked-in lock/export file for this bundle
# profile. Install the bundled runtime with the local-office extra from the
# adjacent wheel:
#
#   python -m pip install "./monoclaw_runtime-<version>-py3-none-any.whl[local-office]"
EOF

  for asset in python support browser skills launchd wheelhouse; do
    copy_optional_vendor_asset "${asset}"
  done
  stage_runtime_skills
  stage_model_packs

  python3 "${HATCH_ROOT}/scripts/generate_manifest.py" \
    --bundle-root "${HATCH_DIST_ROOT}" \
    --bundle-id "${HATCH_BUNDLE_ID:-monoclaw-hatch-${version}-${HATCH_TARGET_ARCH}}" \
    --bundle-version "${HATCH_BUNDLE_VERSION:-${version}}" \
    --runtime-version "${version}" \
    --target-arch "${HATCH_TARGET_ARCH}" \
    --minimum-macos "${HATCH_MINIMUM_MACOS}"

  log "Verifying prepared bundle"
  bash "${HATCH_DIST_ROOT}/bin/hatch" --dry-run --bundle-root "${HATCH_DIST_ROOT}" prepare-bundle
}

stage_bundle
