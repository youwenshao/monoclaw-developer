#!/usr/bin/env bash
# Optional sidecar pack for small CLI dependencies a MonoClaw skill needs.
#
# This is the per-skill counterpart to `scripts/build_mona_tools_pack.sh`.
# When not skipped with `HATCH_INCLUDE_SKILL_DEPS=0` (or legacy
# `HATCH_INCLUDE_SKILLS_DEPS=0`), it produces `tool-packs/skill-deps-pack/`
# from `bundle-inputs/vendor/skill-deps/` (`tool-lock.json` + `prebuilt/`),
# exactly mirroring the verified-pack pattern Mona uses.
#
# Default: enabled. With no populated tool-lock.json the script exits after
# logging that there is nothing to build (no pack directory).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"
HATCH_TOOLS_PACKS_ROOT="${HATCH_TOOLS_PACKS_ROOT:-$(cd "${HATCH_ROOT}" && pwd)/tool-packs}"

log() {
  printf '[skill-deps] %s\n' "$1"
}

_hatch_skill_deps_include="${HATCH_INCLUDE_SKILL_DEPS:-${HATCH_INCLUDE_SKILLS_DEPS:-1}}"
if [[ "${_hatch_skill_deps_include}" != "1" ]]; then
  log "Skill dependencies pack disabled (HATCH_INCLUDE_SKILL_DEPS/HATCH_INCLUDE_SKILLS_DEPS!=1)"
  exit 0
fi

LOCK_PATH="${HATCH_INPUT_ROOT}/vendor/skill-deps/tool-lock.json"
SOURCE_LOCK_PATH="${HATCH_INPUT_ROOT}/vendor/skill-deps/source-lock.json"
PACK_ROOT="${HATCH_TOOLS_PACKS_ROOT}/skill-deps-pack"
SKILL_DEPS_VENDOR="${HATCH_INPUT_ROOT}/vendor/skill-deps"

rm -rf "${PACK_ROOT}"
if [[ ! -f "${LOCK_PATH}" ]]; then
  if [[ -f "${SOURCE_LOCK_PATH}" ]]; then
    if [[ "${HATCH_SKILL_DEPS_AUTO_PREP:-1}" != "1" ]]; then
      printf 'Skill dependencies lock is missing and auto-prep is disabled: %s\n' "${LOCK_PATH}" >&2
      exit 1
    fi
    log "Skill dependencies lock missing (${LOCK_PATH}); running prepare_skill_deps_inputs.sh"
    HATCH_ROOT="${HATCH_ROOT}" \
    HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
    HATCH_SKILL_DEPS_SOURCE_LOCK="${SOURCE_LOCK_PATH}" \
    HATCH_SKILL_DEPS_BUILD_ROOT="${HATCH_SKILL_DEPS_BUILD_ROOT:-${HATCH_ROOT}/.skill-deps-build}" \
    HATCH_SKILL_DEPS_FORCE="${HATCH_SKILL_DEPS_FORCE:-0}" \
    HATCH_RUNTIME_ROOT="${HATCH_RUNTIME_ROOT:-}" \
    HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH:-$(uname -m)}" \
      bash "${HATCH_ROOT}/scripts/prepare_skill_deps_inputs.sh"
  else
    log "No tool-lock.json at ${LOCK_PATH}; nothing to build (no skill-deps source lock present)."
    exit 0
  fi
fi

if python3 - "${LOCK_PATH}" "${HATCH_INPUT_ROOT}" <<'PY'
import json
import sys
from pathlib import Path

lock_path = Path(sys.argv[1])
input_root = Path(sys.argv[2])
data = json.loads(lock_path.read_text(encoding="utf-8"))
for tool in data.get("tools") or []:
    sha = str(tool.get("sha256", "")).strip().lower()
    source = str(tool.get("source", "")).strip()
    if not sha or sha.startswith(("replace", "todo", "tbd")):
        raise SystemExit(42)
    if not source or not (input_root / "vendor" / "skill-deps" / source).is_file():
        raise SystemExit(42)
raise SystemExit(0)
PY
then
  :
else
  if [[ -f "${SOURCE_LOCK_PATH}" && "${HATCH_SKILL_DEPS_AUTO_PREP:-1}" == "1" ]]; then
    log "Skill dependencies lock has placeholders or missing sources; running prepare_skill_deps_inputs.sh"
    HATCH_ROOT="${HATCH_ROOT}" \
    HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
    HATCH_SKILL_DEPS_SOURCE_LOCK="${SOURCE_LOCK_PATH}" \
    HATCH_SKILL_DEPS_BUILD_ROOT="${HATCH_SKILL_DEPS_BUILD_ROOT:-${HATCH_ROOT}/.skill-deps-build}" \
    HATCH_SKILL_DEPS_FORCE="${HATCH_SKILL_DEPS_FORCE:-0}" \
    HATCH_RUNTIME_ROOT="${HATCH_RUNTIME_ROOT:-}" \
    HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH:-$(uname -m)}" \
      bash "${HATCH_ROOT}/scripts/prepare_skill_deps_inputs.sh"
  else
    printf 'Skill dependencies lock has placeholders or missing sources; run scripts/prepare_skill_deps_inputs.sh or set HATCH_INCLUDE_SKILL_DEPS=0.\n' >&2
    exit 1
  fi
fi

mkdir -p "${PACK_ROOT}"

python3 - "${LOCK_PATH}" "${HATCH_INPUT_ROOT}" "${PACK_ROOT}" <<'PY'
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

lock_path = Path(sys.argv[1]).resolve()
input_root = Path(sys.argv[2]).resolve()
pack_root = Path(sys.argv[3]).resolve()
vendor_root = (input_root / "vendor" / "skill-deps").resolve()

data = json.loads(lock_path.read_text(encoding="utf-8"))
if data.get("schema_version") != 1:
    raise SystemExit("skill-deps tool-lock schema_version must be 1")

pack = data.get("pack")
if not isinstance(pack, dict):
    raise SystemExit("skill-deps tool-lock pack must be an object")
if pack.get("id") != "skill-deps-pack":
    raise SystemExit("skill-deps tool-lock pack.id must be skill-deps-pack")
if not str(pack.get("version", "")).strip():
    raise SystemExit("skill-deps tool-lock pack.version is required")

tools = data.get("tools") or []
if not tools:
    raise SystemExit("skill-deps tool-lock has no tools; refusing to ship empty pack")

seen_names: set[str] = set()
seen_paths: set[str] = set()
active_tools: list[dict[str, object]] = []

def ensure_inside(path: Path, root: Path, message: str) -> None:
    try:
        path.relative_to(root)
    except ValueError:
        raise SystemExit(message) from None

def path_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def pack_destination(relative: str) -> Path:
    destination = (pack_root / relative).resolve()
    ensure_inside(destination, pack_root, f"skill-deps destination escapes pack root: {relative}")
    return destination

def vendor_source(relative: str, label: str) -> Path:
    source = vendor_root / relative
    resolved = source.resolve(strict=False)
    ensure_inside(resolved, vendor_root, f"skill-deps {label} escapes vendor/skill-deps: {relative}")
    return source

def ensure_tree_symlinks_inside(tree: Path, root: Path, label: str) -> None:
    for path in tree.rglob("*"):
        if not path.is_symlink():
            continue
        resolved = path.resolve(strict=False)
        ensure_inside(resolved, root, f"{label} symlink escapes expected root: {path}")

def parse_version(value: str) -> tuple[int, int, int] | None:
    if not value:
        return None
    parts = str(value).split(".")
    try:
        return (
            int(parts[0]),
            int(parts[1]) if len(parts) > 1 else 0,
            int(parts[2]) if len(parts) > 2 else 0,
        )
    except (TypeError, ValueError):
        return None

def python_version(python: Path) -> tuple[int, int, int] | None:
    try:
        raw = subprocess.check_output(
            [
                str(python),
                "-c",
                "import sys; print('.'.join(map(str, sys.version_info[:3])))",
            ],
            text=True,
            timeout=15,
        ).strip()
    except (OSError, subprocess.SubprocessError):
        return None
    return parse_version(raw)

def ensure_bundled_python_satisfies(spec: dict[str, object], spec_path: Path) -> None:
    minimum = parse_version(str(spec.get("min_python") or ""))
    if minimum is None:
        return
    bundled_python = input_root / "vendor" / "python" / "current" / "bin" / "python3"
    actual = python_version(bundled_python) if bundled_python.is_file() else None
    if actual is None or actual < minimum:
        need = ".".join(str(part) for part in minimum)
        found = ".".join(str(part) for part in actual) if actual else "missing"
        raise SystemExit(
            f"skill-deps Python wheelhouse {spec_path.relative_to(pack_root)} "
            f"requires bundled Python >= {need}, found {found}; "
            "stage bundle-inputs/vendor/python/current/bin/python3 with a compatible interpreter"
        )

def python_wheel_metadata(path: Path) -> dict[str, object] | None:
    spec = path / "package-spec.json"
    wheelhouse = path / "wheelhouse"
    if not spec.is_file() or not wheelhouse.is_dir():
        return None
    spec_data = json.loads(spec.read_text(encoding="utf-8"))
    ensure_bundled_python_satisfies(spec_data, spec)
    wheels = []
    for wheel in sorted(wheelhouse.glob("*.whl")):
        wheels.append(
            {
                "path": wheel.relative_to(pack_root).as_posix(),
                "sha256": path_sha256(wheel),
                "bytes": wheel.stat().st_size,
            }
        )
    return {
        "kind": "python_wheelhouse",
        "package_spec": spec.relative_to(pack_root).as_posix(),
        "wheels": wheels,
    }

for tool in tools:
    name = tool.get("name")
    version = tool.get("version")
    source = tool.get("source")
    rel_path = tool.get("path")
    activation = str(tool.get("activation", "default")).strip() or "default"
    required_permissions = tool.get("required_permissions") or []
    extra_artifacts = tool.get("extra_artifacts") or []
    if not name or not version or not source or not rel_path:
        raise SystemExit(f"skill-deps tool entry missing required fields: {tool!r}")
    if not isinstance(required_permissions, list):
        raise SystemExit(f"skill-deps tool required_permissions must be a list: {tool!r}")
    if not isinstance(extra_artifacts, list):
        raise SystemExit(f"skill-deps tool extra_artifacts must be a list: {tool!r}")
    if name in seen_names:
        raise SystemExit(f"skill-deps tool-lock has duplicate tool name: {name}")
    if rel_path in seen_paths:
        raise SystemExit(f"skill-deps tool-lock has duplicate active path: {rel_path}")
    seen_names.add(name)
    seen_paths.add(rel_path)
    src_path = vendor_source(str(source), "source")
    if not src_path.is_file():
        raise SystemExit(f"skill-deps source missing: {src_path}")
    expected_sha = str(tool.get("sha256", "")).strip()
    if not expected_sha or expected_sha.lower().startswith(("replace", "todo", "tbd")):
        raise SystemExit(f"skill-deps tool {name} requires a real sha256")
    actual_sha = path_sha256(src_path)
    if actual_sha != expected_sha:
        raise SystemExit(
            f"skill-deps source sha256 mismatch for {name}: expected {expected_sha}, got {actual_sha}"
        )
    dst_path = pack_destination(str(rel_path))
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_path, dst_path)
    if not dst_path.suffix:
        dst_path.chmod(0o755)
    tool_metadata: dict[str, object] = {}
    for artifact in extra_artifacts:
        if not isinstance(artifact, dict):
            raise SystemExit(f"skill-deps extra_artifact must be an object: {artifact!r}")
        artifact_source = artifact.get("source")
        artifact_path = artifact.get("path")
        if not artifact_source or not artifact_path:
            raise SystemExit(f"skill-deps extra_artifact missing source/path: {artifact!r}")
        src_extra = vendor_source(str(artifact_source), "extra_artifact source")
        if not src_extra.exists():
            raise SystemExit(f"skill-deps extra_artifact source missing: {src_extra}")
        dst_extra = pack_destination(str(artifact_path))
        dst_extra.parent.mkdir(parents=True, exist_ok=True)
        if src_extra.is_dir():
            ensure_tree_symlinks_inside(src_extra, vendor_root, "skill-deps extra_artifact source")
            if dst_extra.exists():
                shutil.rmtree(dst_extra)
            shutil.copytree(src_extra, dst_extra, symlinks=True)
            ensure_tree_symlinks_inside(dst_extra, pack_root, "skill-deps extra_artifact destination")
        else:
            shutil.copy2(src_extra, dst_extra)
        metadata = python_wheel_metadata(dst_extra if dst_extra.is_dir() else dst_extra.parent)
        if metadata:
            tool_metadata.update(metadata)
    active_tool = {
        "name": name,
        "version": version,
        "path": rel_path,
        "activation": activation,
        "required_permissions": required_permissions,
    }
    # Verification contract: propagate the same fields the Mona pack uses so
    # generate_tools_pack_manifest.py emits them into the manifest. See
    # plans/mona-tool-verify-command-implementation.md (Phase 5).
    for verify_key in ("verify_command", "verify_strict", "verify_env", "verify_skip_reason"):
        if verify_key in tool and tool[verify_key] not in (None, ""):
            active_tool[verify_key] = tool[verify_key]
    active_tool.update(tool_metadata)
    active_tools.append(active_tool)

ensure_tree_symlinks_inside(pack_root, pack_root, "skill-deps pack")

(pack_root / ".skill-deps-active.json").write_text(
    json.dumps(
        {
            "pack": pack,
            "tools": active_tools,
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

PACK_ID="$(python3 - "${PACK_ROOT}/.skill-deps-active.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("pack", {}).get("id", "skill-deps-pack"))
PY
)"
PACK_VERSION="$(python3 - "${PACK_ROOT}/.skill-deps-active.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("pack", {}).get("version", "0.0.0"))
PY
)"

# Write the tools-file payload OUTSIDE the pack root so the manifest
# generator's recursive artifact scan does not pick it up as an unlisted
# file. Keep the legacy colon-encoded shape behind --tools-file for now;
# Phase 5 of the verify_command rollout will add verify_command/skip_reason
# fields to skill-deps source-lock.json. See
# plans/mona-tool-verify-command-implementation.md.
TOOLS_FILE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/skill-deps-manifest-input.XXXXXX")"
TOOLS_FILE="${TOOLS_FILE_DIR}/tools.json"
python3 - "${PACK_ROOT}/.skill-deps-active.json" "${TOOLS_FILE}" <<'PY'
import json
import sys
from pathlib import Path

active = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
output_path = Path(sys.argv[2])

MANIFEST_KEYS = (
    "name",
    "version",
    "path",
    "activation",
    "required_permissions",
    "verify_command",
    "verify_strict",
    "verify_env",
    "verify_skip_reason",
)

tools_for_manifest: list[dict[str, object]] = []
for item in active.get("tools", []):
    entry: dict[str, object] = {}
    for key in MANIFEST_KEYS:
        if key in item and item[key] not in (None, ""):
            entry[key] = item[key]
    entry.setdefault("activation", "default")
    entry.setdefault("required_permissions", [])
    tools_for_manifest.append(entry)

output_path.write_text(
    json.dumps(tools_for_manifest, indent=2) + "\n",
    encoding="utf-8",
)
PY
rm -f "${PACK_ROOT}/.skill-deps-active.json"

python3 "${HATCH_ROOT}/scripts/generate_tools_pack_manifest.py" \
  --tools-pack-root "${PACK_ROOT}" \
  --pack-id "${PACK_ID}" \
  --pack-version "${PACK_VERSION}" \
  --target-arch "${HATCH_TARGET_ARCH:-$(uname -m)}" \
  --tools-file "${TOOLS_FILE}" || {
    rm -rf "${TOOLS_FILE_DIR}"
    log "Failed to generate tools-pack-manifest.json for skill-deps-pack"
    exit 1
  }
rm -rf "${TOOLS_FILE_DIR}"

# Run the same verifier the Mona pack uses, including verify_command probes
# and strict-mode honoring. Note: verify-skill-deps uses --skill-deps-pack-root,
# not --tools-pack-root (which is for verify-tools-pack against Mona). The
# verifier looks up the pack-id "skill-deps-pack" internally.
bash "${HATCH_ROOT}/bin/hatch" --dry-run --skill-deps-pack-root "${PACK_ROOT}" verify-skill-deps

log "skill-deps pack built at ${PACK_ROOT}"
