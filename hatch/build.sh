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
HATCH_TOOLS_PACKS_ROOT="${HATCH_TOOLS_PACKS_ROOT:-$(cd "$(dirname "${HATCH_DIST_ROOT}")" && pwd)/tool-packs}"
HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH:-$(uname -m)}"
HATCH_MINIMUM_MACOS="${HATCH_MINIMUM_MACOS:-14.0}"

log() {
  printf '[hatch-build] %s\n' "$1"
}

log_step() {
  _HATCH_BUILD_PHASE="$1"
  printf '[hatch-build] step: %s\n' "$1"
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

ensure_provisioning_lock() {
  local lock_path="${HATCH_INPUT_ROOT}/vendor/provisioning/monoclaw-provisioning-lock.json"

  if [[ -f "${lock_path}" ]]; then
    return 0
  fi

  if [[ "${HATCH_SKIP_PROVISIONING_LOCK_AUTOGEN:-0}" == "1" ]]; then
    return 0
  fi

  local py_bin="python3"
  if [[ -x "${HATCH_RUNTIME_ROOT}/.venv/bin/python" ]]; then
    py_bin="${HATCH_RUNTIME_ROOT}/.venv/bin/python"
  fi

  log "Provisioning lock missing; generating ${lock_path}"
  mkdir -p "${HATCH_INPUT_ROOT}/vendor/provisioning"

  local gen_home
  gen_home="$(mktemp -d)"
  if ! MONOCLAW_HOME="${gen_home}" \
    PYTHONPATH="${HATCH_RUNTIME_ROOT}" \
    "${py_bin}" -m monoclaw_cli.provisioning_audit \
    --promote-unknown-external \
    --lock-out "${lock_path}"; then
    rm -rf "${gen_home}"
    die "failed to generate provisioning lock (install runtime deps or use a venv at ${HATCH_RUNTIME_ROOT}/.venv)"
  fi
  rm -rf "${gen_home}"

  log "Auto-generated provisioning lock (review and commit vendor/provisioning/monoclaw-provisioning-lock.json when promoting bundle coverage)"
}

verify_provisioning_lock() {
  python3 "${HATCH_ROOT}/scripts/verify_provisioning_lock.py" \
    --input-root "${HATCH_INPUT_ROOT}" \
    --runtime-root "${HATCH_RUNTIME_ROOT}"
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

stage_mona_tools_pack() {
  if [[ "${HATCH_INCLUDE_MONA_TOOLS:-1}" != "1" ]]; then
    log "Mona secretary tools pack disabled by HATCH_INCLUDE_MONA_TOOLS=0"
    return
  fi

  if [[ "${HATCH_TEST_FORCE_MONA_PACK_FAIL:-0}" == "1" ]]; then
    printf '[hatch-build] test hook: HATCH_TEST_FORCE_MONA_PACK_FAIL simulated failure\n' >&2
    if [[ "${HATCH_OPTIONAL_PACKS_STRICT:-1}" == "1" ]]; then
      printf '[hatch-build] fail: Mona tools pack step aborted (HATCH_OPTIONAL_PACKS_STRICT=1); see test hook message above.\n' >&2
      return 1
    fi
    log "warn: Mona secretary tools pack failed; continuing without Mona pack (HATCH_OPTIONAL_PACKS_STRICT=0)"
    rm -rf "${HATCH_TOOLS_PACKS_ROOT}/mona-secretary-tools"
    return 0
  fi

  # At build time we want the strict-verify behavior wired through
  # build_mona_tools_pack.sh -> verify-tools-pack: any tool whose probe is
  # marked verify_strict: true must succeed, and missing verify_command on a
  # bundled tool is a hard fail. The install-time path on the customer Mac
  # stays lenient (env unset). See
  # plans/mona-tool-verify-command-implementation.md (Phase 4).
  local _strict_verify="${HATCH_TOOLS_PACK_STRICT_VERIFY:-1}"
  if ! HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
    HATCH_TOOLS_PACKS_ROOT="${HATCH_TOOLS_PACKS_ROOT}" \
    HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH}" \
    HATCH_TOOLS_PACK_STRICT_VERIFY="${_strict_verify}" \
      bash "${HATCH_ROOT}/scripts/build_mona_tools_pack.sh"; then
    if [[ "${HATCH_OPTIONAL_PACKS_STRICT:-1}" == "1" ]]; then
      printf '[hatch-build] fail: Mona secretary tools pack build failed under HATCH_OPTIONAL_PACKS_STRICT=1 (see script output above).\n' >&2
      return 1
    fi
    log "warn: Mona secretary tools pack failed; continuing without Mona pack (HATCH_OPTIONAL_PACKS_STRICT=0)"
    rm -rf "${HATCH_TOOLS_PACKS_ROOT}/mona-secretary-tools"
    return 0
  fi
}

stage_skill_deps_pack() {
  # Phase 5 scaffolding for the skill readiness uplift program.
  # ON by default (`HATCH_INCLUDE_SKILL_DEPS=0` or `HATCH_INCLUDE_SKILLS_DEPS=0` to skip).
  # Even when ON the underlying script is a no-op until
  # `bundle-inputs/vendor/skill-deps/tool-lock.json` is populated.
  local _hatch_skill_deps_include
  _hatch_skill_deps_include="${HATCH_INCLUDE_SKILL_DEPS:-${HATCH_INCLUDE_SKILLS_DEPS:-1}}"
  if [[ "${_hatch_skill_deps_include}" != "1" ]]; then
    return
  fi

  if [[ "${HATCH_TEST_FORCE_SKILL_DEPS_PACK_FAIL:-0}" == "1" ]]; then
    printf '[hatch-build] test hook: HATCH_TEST_FORCE_SKILL_DEPS_PACK_FAIL simulated failure\n' >&2
    if [[ "${HATCH_OPTIONAL_PACKS_STRICT:-1}" == "1" ]]; then
      printf '[hatch-build] fail: skill-deps pack step aborted (HATCH_OPTIONAL_PACKS_STRICT=1); see test hook message above.\n' >&2
      return 1
    fi
    log "warn: skill-deps pack failed; continuing without skill-deps pack (HATCH_OPTIONAL_PACKS_STRICT=0)"
    rm -rf "${HATCH_TOOLS_PACKS_ROOT}/skill-deps-pack"
    return 0
  fi

  # Same strict-verify story as stage_mona_tools_pack: every skill-dep tool
  # bundled in the pack must have either a successful verify_command probe or
  # a documented verify_skip_reason. The install-time path on the customer Mac
  # stays lenient (env unset).
  local _skill_deps_strict_verify="${HATCH_TOOLS_PACK_STRICT_VERIFY:-1}"
  if ! HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
    HATCH_TOOLS_PACKS_ROOT="${HATCH_TOOLS_PACKS_ROOT}" \
    HATCH_RUNTIME_ROOT="${HATCH_RUNTIME_ROOT}" \
    HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH}" \
    HATCH_TOOLS_PACK_STRICT_VERIFY="${_skill_deps_strict_verify}" \
      bash "${HATCH_ROOT}/scripts/build_skill_deps_pack.sh"; then
    if [[ "${HATCH_OPTIONAL_PACKS_STRICT:-1}" == "1" ]]; then
      printf '[hatch-build] fail: skill-deps pack build failed under HATCH_OPTIONAL_PACKS_STRICT=1 (see script output above, e.g. bundled Python vs wheelhouse min_python).\n' >&2
      return 1
    fi
    log "warn: skill-deps pack failed; continuing without skill-deps pack (HATCH_OPTIONAL_PACKS_STRICT=0)"
    rm -rf "${HATCH_TOOLS_PACKS_ROOT}/skill-deps-pack"
    return 0
  fi
}

stage_skill_deps_installer() {
  local _hatch_skill_deps_include
  local pack_root
  _hatch_skill_deps_include="${HATCH_INCLUDE_SKILL_DEPS:-${HATCH_INCLUDE_SKILLS_DEPS:-1}}"
  pack_root="${HATCH_TOOLS_PACKS_ROOT}/skill-deps-pack"
  if [[ "${_hatch_skill_deps_include}" != "1" || ! -d "${pack_root}" ]]; then
    return
  fi

  cp "${HATCH_ROOT}/templates/install-skill-deps.sh" "${HATCH_DIST_ROOT}/install-skill-deps.sh"
  chmod +x "${HATCH_DIST_ROOT}/install-skill-deps.sh"
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

stage_runtime_optional_skills() {
  if [[ -d "${HATCH_DIST_ROOT}/vendor/optional-skills" ]]; then
    log "Using curated vendor/optional-skills from bundle inputs"
    return
  fi

  if [[ -d "${HATCH_RUNTIME_ROOT}/optional-skills" ]]; then
    log "Staging runtime optional skills catalog"
    mkdir -p "${HATCH_DIST_ROOT}/vendor"
    cp -R "${HATCH_RUNTIME_ROOT}/optional-skills" "${HATCH_DIST_ROOT}/vendor/optional-skills"
  fi
}

verify_skill_bundle() {
  python3 "${HATCH_ROOT}/scripts/verify_skill_bundle.py" \
    --runtime-root "${HATCH_RUNTIME_ROOT}" \
    --bundle-root "${HATCH_DIST_ROOT}"
}

stage_runtime_tui() {
  # Stage ``ui-tui/`` from the runtime source into ``dist/vendor/tui/`` so the
  # customer Mac can find it after ``install_runtime_assets`` mirrors
  # ``dist/vendor/`` into ``~/.monoclaw/vendor/``.  Pre-built ``dist/entry.js``
  # and the ``packages/monoclaw-ink`` bundle are produced on the Hatch host
  # (Node is already a build-time prereq via ``build_runtime_web_assets``).
  # First-run ``monoclaw --tui`` on the customer Mac only has to do
  # ``npm install`` (dependency resolution) — never a full ``npm run build``.
  #
  # The May 2026 incident: ``_launch_tui`` in monoclaw_cli/main.py computed
  # ``tui_dir = PROJECT_ROOT / "ui-tui"`` which in a wheel install resolves
  # to ``site-packages/ui-tui`` (absent).  Staging here is the canonical
  # supply path; ``_resolve_tui_dir`` in the runtime checks
  # ``$MONOCLAW_HOME/vendor/tui/package.json`` as the second resolution rule.
  local tui_src="${HATCH_RUNTIME_ROOT}/ui-tui"
  if [[ ! -d "${tui_src}" ]]; then
    log "warn: runtime ui-tui/ missing; TUI will NOT be bundled (monoclaw --tui will fail)"
    return 0
  fi

  if [[ "${HATCH_SKIP_RUNTIME_BUILD:-0}" == "1" ]]; then
    log "Skipping TUI prebuild because HATCH_SKIP_RUNTIME_BUILD=1; relying on pre-staged dist/"
  else
    log "Building TUI (npm ci + npm run build in ${tui_src})"
    (cd "${tui_src}" && npm ci --no-fund --no-audit --progress=false >/dev/null)
    (cd "${tui_src}" && npm run build >/dev/null)
  fi

  if [[ ! -f "${tui_src}/dist/entry.js" ]]; then
    die "TUI prebuild did not produce ui-tui/dist/entry.js — rebuild with HATCH_SKIP_RUNTIME_BUILD unset"
  fi

  log "Staging vendor/tui (sources + prebuilt dist; no node_modules)"
  mkdir -p "${HATCH_DIST_ROOT}/vendor/tui"
  # rsync excludes the host's node_modules — the customer Mac builds its own
  # platform-correct tree via npm install at first launch. Also exclude test
  # output and editor metadata to keep the bundle small.
  rsync -a --delete \
    --exclude '/node_modules' \
    --exclude '/.cache' \
    --exclude '/coverage' \
    --exclude '/.vitest' \
    --exclude '.DS_Store' \
    "${tui_src}/" "${HATCH_DIST_ROOT}/vendor/tui/"
}

stage_runtime_whatsapp_bridge() {
  # Stage ``scripts/whatsapp-bridge/`` into ``dist/vendor/whatsapp-bridge/``.
  # Sources only — the customer Mac runs ``npm install`` either through Hatch's
  # ``warm_whatsapp_bridge_install`` step at install time (canonical path) or
  # the on-demand fallback in ``monoclaw whatsapp`` for dev-mode installs.
  #
  # May 2026 incident: ``WhatsAppAdapter._DEFAULT_BRIDGE_DIR`` resolved to
  # ``site-packages/scripts/whatsapp-bridge`` in wheel installs and crashed
  # the setup wizard.  ``_resolve_bridge_dir`` in the runtime checks
  # ``$MONOCLAW_HOME/vendor/whatsapp-bridge/bridge.js`` as the second
  # resolution rule.
  local bridge_src="${HATCH_RUNTIME_ROOT}/scripts/whatsapp-bridge"
  if [[ ! -d "${bridge_src}" ]]; then
    log "warn: runtime scripts/whatsapp-bridge/ missing; WhatsApp bridge will NOT be bundled"
    return 0
  fi

  log "Staging vendor/whatsapp-bridge (sources only; install-time npm install)"
  mkdir -p "${HATCH_DIST_ROOT}/vendor/whatsapp-bridge"
  rsync -a --delete \
    --exclude '/node_modules' \
    --exclude '/.cache' \
    --exclude '.DS_Store' \
    "${bridge_src}/" "${HATCH_DIST_ROOT}/vendor/whatsapp-bridge/"
}

_hatch_build_test_fail_maybe() {
  local marker="$1"
  if [[ "${HATCH_TEST_FAIL_AFTER_STEP:-}" != "${marker}" ]]; then
    return 0
  fi
  printf '[hatch-build] test hook: HATCH_TEST_FAIL_AFTER_STEP=%s\n' "${marker}" >&2
  return 1
}

stage_bundle() {
  require_dir "${HATCH_INPUT_ROOT}" "bundle input directory is missing"
  require_dir "${HATCH_RUNTIME_ROOT}" "runtime checkout is missing"
  require_file "${HATCH_RUNTIME_ROOT}/pyproject.toml" "runtime pyproject is missing"
  verify_runtime_python_bundle
  verify_runtime_wheelhouse
  ensure_provisioning_lock
  verify_provisioning_lock
  validate_dist_root

  local final_dist="${HATCH_DIST_ROOT}"
  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/hatch-dist-staging.XXXXXX")"

  _hatch_stage_bundle_cleanup_err() {
    local status=$?
    local cmd="${BASH_COMMAND:-?}"
    printf '[hatch-build] fail: exit %s' "${status}" >&2
    if [[ -n "${_HATCH_BUILD_PHASE:-}" ]]; then
      printf ' (phase: %s)' "${_HATCH_BUILD_PHASE}" >&2
    fi
    printf '\n' >&2
    case "${cmd}" in
      return | return\ *)
        printf '[hatch-build] hint: details are usually on the lines above (sub-script or strict optional-pack check).\n' >&2
        printf '[hatch-build] hint: for optional Mona/skill-deps only, try HATCH_OPTIONAL_PACKS_STRICT=0 while debugging.\n' >&2
        ;;
      *)
        printf '[hatch-build] fail: failing command: %s\n' "${cmd}" >&2
        ;;
    esac
    rm -rf "${staging}"
    exit "${status}"
  }
  trap '_hatch_stage_bundle_cleanup_err' ERR

  HATCH_DIST_ROOT="${staging}"

  log_step "prepare staging directory"
  mkdir -p "${HATCH_DIST_ROOT}/bin" "${HATCH_DIST_ROOT}/lib" "${HATCH_DIST_ROOT}/runtime" "${HATCH_DIST_ROOT}/tests"
  _hatch_build_test_fail_maybe after_mkdir

  log_step "copy hatch templates and scripts into staging bundle"
  cp "${HATCH_ROOT}/bin/hatch" "${HATCH_DIST_ROOT}/bin/hatch"
  cp "${HATCH_ROOT}/lib/common.sh" "${HATCH_DIST_ROOT}/lib/common.sh"
  cp "${HATCH_ROOT}/templates/install.sh" "${HATCH_DIST_ROOT}/install.sh"
  cp "${HATCH_ROOT}/templates/install-gemma-model.sh" "${HATCH_DIST_ROOT}/install-gemma-model.sh"
  cp "${HATCH_ROOT}/templates/install-mona-tools.sh" "${HATCH_DIST_ROOT}/install-mona-tools.sh"
  cp "${HATCH_ROOT}/tests/hatch_dry_run_tests.sh" "${HATCH_DIST_ROOT}/tests/run-hatch-dry-run.sh"
  chmod +x "${HATCH_DIST_ROOT}/bin/hatch" "${HATCH_DIST_ROOT}/install.sh" "${HATCH_DIST_ROOT}/install-gemma-model.sh" "${HATCH_DIST_ROOT}/install-mona-tools.sh" "${HATCH_DIST_ROOT}/tests/run-hatch-dry-run.sh"
  _hatch_build_test_fail_maybe after_templates

  log_step "build runtime web assets and wheel"
  build_runtime_web_assets
  build_runtime_wheel "${HATCH_DIST_ROOT}/runtime"
  _hatch_build_test_fail_maybe after_wheel

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

  log_step "stage vendor assets"
  for asset in python support browser skills optional-skills launchd wheelhouse provisioning; do
    copy_optional_vendor_asset "${asset}"
  done
  _hatch_build_test_fail_maybe after_vendor

  log_step "stage runtime skills catalogs"
  stage_runtime_skills
  stage_runtime_optional_skills

  log_step "stage runtime Node subsystems (TUI + WhatsApp bridge)"
  stage_runtime_tui
  stage_runtime_whatsapp_bridge
  _hatch_build_test_fail_maybe after_node_subsystems

  log_step "verify staged Node subsystems"
  # Refuse the bundle the moment vendor/tui or vendor/whatsapp-bridge
  # vanishes. Catches build.sh refactors that silently drop staging
  # (May 2026 incident — both subtrees were never staged at all).
  python3 "${HATCH_ROOT}/scripts/verify_node_subsystems.py" \
    --bundle-root "${HATCH_DIST_ROOT}"
  _hatch_build_test_fail_maybe after_node_subsystems_verify

  log_step "verify staged skill bundle against runtime checkout"
  verify_skill_bundle
  _hatch_build_test_fail_maybe after_skill_verify

  log_step "stage optional model pack and tool packs"
  stage_model_packs
  stage_mona_tools_pack
  stage_skill_deps_pack
  stage_skill_deps_installer
  _hatch_build_test_fail_maybe after_optional_packs

  log_step "generate hatch-manifest.json"
  python3 "${HATCH_ROOT}/scripts/generate_manifest.py" \
    --bundle-root "${HATCH_DIST_ROOT}" \
    --bundle-id "${HATCH_BUNDLE_ID:-monoclaw-hatch-${version}-${HATCH_TARGET_ARCH}}" \
    --bundle-version "${HATCH_BUNDLE_VERSION:-${version}}" \
    --runtime-version "${version}" \
    --target-arch "${HATCH_TARGET_ARCH}" \
    --minimum-macos "${HATCH_MINIMUM_MACOS}"
  _hatch_build_test_fail_maybe after_manifest

  log_step "verify prepared bundle (prepare-bundle dry-run)"
  bash "${HATCH_DIST_ROOT}/bin/hatch" --dry-run --bundle-root "${HATCH_DIST_ROOT}" prepare-bundle

  trap - ERR

  log_step "publish bundle directory (atomic swap)"
  rm -rf "${final_dist}"
  mv "${staging}" "${final_dist}"
  HATCH_DIST_ROOT="${final_dist}"

  log "Published Hatch bundle at ${final_dist}"
}

stage_bundle
