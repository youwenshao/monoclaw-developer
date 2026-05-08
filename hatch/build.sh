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
    cp "${HATCH_RUNTIME_WHEEL}" "${wheel_dir}/monoclaw-runtime.whl"
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

  local built_wheel
  built_wheel="$(python3 - "${wheel_dir}" <<'PY'
import sys
from pathlib import Path

wheel_dir = Path(sys.argv[1])
wheels = sorted(wheel_dir.glob("monoclaw_runtime-*.whl"))
if not wheels:
    raise SystemExit("no monoclaw_runtime wheel was produced")
print(wheels[-1])
PY
)"
  mv "${built_wheel}" "${wheel_dir}/monoclaw-runtime.whl"
}

copy_optional_vendor_asset() {
  local asset="$1"
  if [[ -d "${HATCH_INPUT_ROOT}/vendor/${asset}" ]]; then
    log "Staging vendor/${asset}"
    mkdir -p "${HATCH_DIST_ROOT}/vendor"
    cp -R "${HATCH_INPUT_ROOT}/vendor/${asset}" "${HATCH_DIST_ROOT}/vendor/${asset}"
  fi
}

stage_bundle() {
  require_dir "${HATCH_INPUT_ROOT}" "bundle input directory is missing"
  require_dir "${HATCH_RUNTIME_ROOT}" "runtime checkout is missing"
  require_file "${HATCH_RUNTIME_ROOT}/pyproject.toml" "runtime pyproject is missing"
  require_dir "${HATCH_INPUT_ROOT}/vendor/lm-studio/LM Studio.app" "LM Studio app bundle is required"
  require_file "${HATCH_INPUT_ROOT}/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf" "Gemma 4 E4B model is required"
  validate_dist_root

  rm -rf "${HATCH_DIST_ROOT}"
  mkdir -p "${HATCH_DIST_ROOT}/bin" "${HATCH_DIST_ROOT}/lib" "${HATCH_DIST_ROOT}/runtime" "${HATCH_DIST_ROOT}/tests"

  cp "${HATCH_ROOT}/bin/hatch" "${HATCH_DIST_ROOT}/bin/hatch"
  cp "${HATCH_ROOT}/lib/common.sh" "${HATCH_DIST_ROOT}/lib/common.sh"
  cp "${HATCH_ROOT}/templates/install.sh" "${HATCH_DIST_ROOT}/install.sh"
  cp "${HATCH_ROOT}/tests/hatch_dry_run_tests.sh" "${HATCH_DIST_ROOT}/tests/run-hatch-dry-run.sh"
  chmod +x "${HATCH_DIST_ROOT}/bin/hatch" "${HATCH_DIST_ROOT}/install.sh" "${HATCH_DIST_ROOT}/tests/run-hatch-dry-run.sh"

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
#   python -m pip install "./monoclaw-runtime.whl[local-office]"
EOF

  for asset in lm-studio models python support browser skills launchd; do
    copy_optional_vendor_asset "${asset}"
  done

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
