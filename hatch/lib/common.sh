#!/usr/bin/env bash

log_step() {
  printf '\n[%s] %s\n' "$1" "$2"
}

log_ok() {
  printf '  ok: %s\n' "$1"
}

log_warn() {
  printf '  warn: %s\n' "$1"
}

log_fail() {
  printf '  fail: %s\n' "$1" >&2
}

die() {
  log_fail "$1"
  exit 1
}

log_action() {
  if [[ "${HATCH_DRY_RUN:-true}" == "true" ]]; then
    printf '  dry-run: %s\n' "$*"
  else
    printf '  run: %s\n' "$*"
    "$@"
  fi
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

detect_launch_agent() {
  local label="$1"
  launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1
}

monoclaw_home() {
  printf '%s\n' "${MONOCLAW_HOME:-${HOME}/.monoclaw}"
}

hatch_manifest_python() {
  local bundle_root="${1:-}"
  local candidate
  for candidate in \
    "${bundle_root}/vendor/python/current/bin/python3" \
    "${bundle_root}/vendor/python/current/bin/python3.13" \
    "${bundle_root}/vendor/python/current/bin/python3.12" \
    "${bundle_root}/vendor/python/current/bin/python3.11"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  if have_command python3; then
    command -v python3
    return 0
  fi
  return 1
}

verify_bundle_manifest() {
  local bundle_root="${1:-}"
  local manifest="${bundle_root}/hatch-manifest.json"
  local python_bin

  [[ -n "${bundle_root}" ]] || die "bundle root is empty"
  if [[ ! -f "${manifest}" ]]; then
    printf '\n' >&2
    printf '  This folder is not a complete Hatch bundle (missing hatch-manifest.json).\n' >&2
    printf '  Expected manifest at: %s\n' "${manifest}" >&2
    printf '  Regenerate the bundle on the assembly machine: cd /path/to/hatch && ./build.sh\n' >&2
    printf '  If assembly already failed, capture logs with: bash -x ./build.sh 2>&1 | tee hatch-build.log\n' >&2
    printf '\n' >&2
    die "bundle manifest not found at ${manifest}"
  fi
  python_bin="$(hatch_manifest_python "${bundle_root}")" || die "Python is required to verify the Hatch manifest"

  PYTHONDONTWRITEBYTECODE=1 HATCH_BUNDLE_ROOT="${bundle_root}" HATCH_HOST_ARCH="$(uname -m)" "${python_bin}" <<'PY'
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(os.environ["HATCH_BUNDLE_ROOT"]).resolve()
host_arch = os.environ.get("HATCH_HOST_ARCH", "")
manifest_path = root / "hatch-manifest.json"
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = [
    "schema_version",
    "bundle_id",
    "bundle_version",
    "created_at",
    "target",
    "runtime",
    "capabilities",
    "models",
    "artifacts",
]
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit(f"manifest missing required fields: {', '.join(missing)}")

target = data["target"]
if target.get("platform") != "darwin":
    raise SystemExit("manifest target.platform must be darwin")
if target.get("arch") and target["arch"] != host_arch:
    raise SystemExit(f"manifest target.arch {target['arch']} does not match host {host_arch}")

def safe_path(relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise SystemExit("manifest path entries must be non-empty strings")
    candidate = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink():
            resolved = current.resolve(strict=False)
            if resolved != root and root not in resolved.parents:
                raise SystemExit(f"manifest path escapes bundle root: {relative}")
    candidate = candidate.resolve(strict=False)
    if candidate != root and root not in candidate.parents:
        raise SystemExit(f"manifest path escapes bundle root: {relative}")
    return candidate

def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def is_ignored_metadata(path: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )

runtime = data["runtime"]
runtime_missing = [
    key for key in ("package", "version", "wheel", "entrypoints")
    if key not in runtime or runtime[key] in (None, "", [])
]
if runtime_missing:
    raise SystemExit(f"runtime manifest missing required fields: {', '.join(runtime_missing)}")
if runtime.get("package") != "monoclaw-runtime":
    raise SystemExit("runtime.package must be monoclaw-runtime")
wheel = runtime.get("wheel")
if wheel:
    wheel_path = safe_path(wheel)
    if not wheel_path.exists():
        raise SystemExit(f"runtime wheel path missing: {wheel}")
entrypoints = runtime.get("entrypoints")
if not isinstance(entrypoints, list) or "monoclaw" not in entrypoints:
    raise SystemExit("runtime.entrypoints must include monoclaw")

for model in data.get("models", []):
    if model.get("id") == "local:gemma4:e4b" and model.get("provider") != "lm-studio":
        raise SystemExit("local:gemma4:e4b must use provider lm-studio")
    path = model.get("path")
    if model.get("required") and path and not safe_path(path).exists():
        raise SystemExit(f"required model path missing: {path}")

listed_files = set()
for artifact in data["artifacts"]:
    rel = artifact.get("path")
    kind = artifact.get("kind")
    path = safe_path(rel)
    if kind == "directory":
        if not path.is_dir():
            raise SystemExit(f"artifact directory missing: {rel}")
        continue
    if kind != "file":
        raise SystemExit(f"artifact kind must be file or directory: {rel}")
    if not path.is_file():
        raise SystemExit(f"artifact file missing: {rel}")
    listed_files.add(rel)
    expected_bytes = artifact.get("bytes")
    if expected_bytes is None:
        raise SystemExit(f"artifact file missing byte size: {rel}")
    if expected_bytes is not None and path.stat().st_size != int(expected_bytes):
        raise SystemExit(f"artifact byte size mismatch: {rel}")
    expected_sha = artifact.get("sha256")
    if not expected_sha:
        raise SystemExit(f"artifact file missing sha256: {rel}")
    actual_sha = file_sha256(path)
    if actual_sha != expected_sha:
        raise SystemExit(f"artifact sha256 mismatch: {rel}")

for path in root.rglob("*"):
    rel = path.relative_to(root).as_posix()
    if rel == "hatch-manifest.json":
        continue
    path = safe_path(rel)
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    if rel not in listed_files:
        raise SystemExit(f"bundle file is not listed in manifest artifacts: {rel}")

print(f"Manifest verified for bundle {data['bundle_id']} ({data['bundle_version']})")
PY
}

verify_model_pack_manifest() {
  local pack_root="${1:-}"
  local manifest="${pack_root}/model-pack-manifest.json"
  local python_bin

  [[ -n "${pack_root}" ]] || die "model pack root is empty"
  [[ -f "${manifest}" ]] || die "model pack manifest not found at ${manifest}"
  python_bin="$(hatch_manifest_python "${HATCH_BUNDLE_ROOT:-}")" || die "Python is required to verify the model pack manifest"

  PYTHONDONTWRITEBYTECODE=1 HATCH_MODEL_PACK_ROOT="${pack_root}" "${python_bin}" <<'PY'
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(os.environ["HATCH_MODEL_PACK_ROOT"]).resolve()
manifest_path = root / "model-pack-manifest.json"
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = ["schema_version", "model", "artifacts"]
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit(f"model pack manifest missing required fields: {', '.join(missing)}")

model = data["model"]
model_missing = [
    key for key in ("id", "provider", "role", "path")
    if key not in model or model[key] in (None, "", [])
]
if model_missing:
    raise SystemExit(f"model pack manifest missing model fields: {', '.join(model_missing)}")

def safe_path(relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise SystemExit("model pack paths must be non-empty strings")
    candidate = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink():
            resolved = current.resolve(strict=False)
            if resolved != root and root not in resolved.parents:
                raise SystemExit(f"model pack path escapes root: {relative}")
    candidate = candidate.resolve(strict=False)
    if candidate != root and root not in candidate.parents:
        raise SystemExit(f"model pack path escapes root: {relative}")
    return candidate

def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def is_ignored_metadata(path: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )

model_path = safe_path(model["path"])
if not model_path.is_file():
    raise SystemExit(f"model pack file missing: {model['path']}")

listed_files = set()
for artifact in data["artifacts"]:
    rel = artifact.get("path")
    kind = artifact.get("kind")
    path = safe_path(rel)
    if kind != "file":
        raise SystemExit(f"model pack artifact kind must be file: {rel}")
    if not path.is_file():
        raise SystemExit(f"model pack file missing: {rel}")
    listed_files.add(rel)
    expected_bytes = artifact.get("bytes")
    if expected_bytes is None:
        raise SystemExit(f"model pack file missing byte size: {rel}")
    if path.stat().st_size != int(expected_bytes):
        raise SystemExit(f"model pack file byte size mismatch: {rel}")
    expected_sha = artifact.get("sha256")
    if not expected_sha:
        raise SystemExit(f"model pack file missing sha256: {rel}")
    if file_sha256(path) != expected_sha:
        raise SystemExit(f"model pack file sha256 mismatch: {rel}")

for path in root.rglob("*"):
    rel = path.relative_to(root).as_posix()
    if rel == "model-pack-manifest.json":
        continue
    path = safe_path(rel)
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    if rel not in listed_files:
        raise SystemExit(f"model pack file is not listed in manifest artifacts: {rel}")

print(f"Model pack verified for {model['id']} ({model_path.stat().st_size} bytes)")
PY
}

verify_tools_pack_manifest() {
  local pack_root="${1:-}"
  local expected_pack_id="${2:-mona-secretary-tools}"
  local manifest="${pack_root}/tools-pack-manifest.json"
  local python_bin

  [[ -n "${pack_root}" ]] || die "tools pack root is empty"
  [[ -f "${manifest}" ]] || die "tools pack manifest not found at ${manifest}"
  python_bin="$(hatch_manifest_python "${HATCH_BUNDLE_ROOT:-}")" || die "Python is required to verify the tools pack manifest"

  PYTHONDONTWRITEBYTECODE=1 HATCH_TOOLS_PACK_ROOT="${pack_root}" HATCH_EXPECTED_PACK_ID="${expected_pack_id}" HATCH_HOST_ARCH="$(uname -m)" "${python_bin}" <<'PY'
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(os.environ["HATCH_TOOLS_PACK_ROOT"]).resolve()
expected_pack_id = os.environ.get("HATCH_EXPECTED_PACK_ID", "mona-secretary-tools")
host_arch = os.environ.get("HATCH_HOST_ARCH", "")
manifest_path = root / "tools-pack-manifest.json"
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = ["schema_version", "pack", "target", "runtime", "tools", "artifacts"]
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit(f"tools pack manifest missing required fields: {', '.join(missing)}")

pack = data["pack"]
pack_missing = [
    key for key in ("id", "version")
    if key not in pack or pack[key] in (None, "", [])
]
if pack_missing:
    raise SystemExit(f"tools pack manifest missing pack fields: {', '.join(pack_missing)}")
if expected_pack_id and pack.get("id") != expected_pack_id:
    raise SystemExit(f"tools pack pack.id must be {expected_pack_id}")

target = data["target"]
if target.get("platform") != "darwin":
    raise SystemExit("tools pack target.platform must be darwin")
if target.get("arch") and target["arch"] != host_arch:
    raise SystemExit(f"tools pack target.arch {target['arch']} does not match host {host_arch}")

runtime = data["runtime"]
if not isinstance(runtime, dict):
    raise SystemExit("tools pack runtime must be an object")
node_runtime = runtime.get("node")
if node_runtime is not None:
    if not isinstance(node_runtime, dict):
        raise SystemExit("tools pack runtime.node must be an object")
    if not node_runtime.get("version"):
        raise SystemExit("tools pack runtime.node.version is required")

def safe_path(relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise SystemExit("tools pack paths must be non-empty strings")
    candidate = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink():
            resolved = current.resolve(strict=False)
            if resolved != root and root not in resolved.parents:
                raise SystemExit(f"tools pack path escapes pack root: {relative}")
    candidate = candidate.resolve(strict=False)
    if candidate != root and root not in candidate.parents:
        raise SystemExit(f"tools pack path escapes pack root: {relative}")
    return candidate

def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def is_ignored_metadata(path: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )

for tool in data["tools"]:
    for key in ("name", "version", "path", "activation", "required_permissions"):
        if key not in tool:
            raise SystemExit(f"tools pack tool missing field {key}")
    tool_path = safe_path(tool["path"])
    if not tool_path.is_file():
        raise SystemExit(f"tools pack tool file missing: {tool['path']}")

if isinstance(node_runtime, dict) and node_runtime.get("path"):
    node_path = node_runtime.get("path", "")
    node = safe_path(node_path)
    if not node.is_file():
        raise SystemExit(f"tools pack node runtime missing: {node_path}")
    if not os.access(node, os.X_OK):
        raise SystemExit(f"tools pack node runtime is not executable: {node_path}")
    expected_version = node_runtime.get("version", "")
    try:
        actual_version = subprocess.check_output([str(node), "--version"], text=True, timeout=10).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"tools pack node runtime smoke failed: {exc}") from exc
    if actual_version != f"v{expected_version}":
        raise SystemExit(f"tools pack node runtime version mismatch: expected v{expected_version}, got {actual_version}")

required_handoff_files = [
    "docs/permissions.md",
    "config/mcp_servers.mona.example.yaml",
    "plugins/mona-secretary-tools/plugin.yaml",
]
if pack.get("id") == "mona-secretary-tools":
    for relative in required_handoff_files:
        path = safe_path(relative)
        if not path.is_file():
            raise SystemExit(f"tools pack required handoff file missing: {relative}")

listed_files = set()
for artifact in data["artifacts"]:
    rel = artifact.get("path")
    kind = artifact.get("kind")
    path = safe_path(rel)
    if kind != "file":
        raise SystemExit(f"tools pack artifact kind must be file: {rel}")
    if not path.is_file():
        raise SystemExit(f"tools pack file missing: {rel}")
    listed_files.add(rel)
    expected_bytes = artifact.get("bytes")
    if expected_bytes is None:
        raise SystemExit(f"tools pack file missing byte size: {rel}")
    if path.stat().st_size != int(expected_bytes):
        raise SystemExit(f"tools pack file byte size mismatch: {rel}")
    expected_sha = artifact.get("sha256")
    if not expected_sha:
        raise SystemExit(f"tools pack file missing sha256: {rel}")
    if file_sha256(path) != expected_sha:
        raise SystemExit(f"tools pack file sha256 mismatch: {rel}")

for path in root.rglob("*"):
    rel = path.relative_to(root).as_posix()
    if rel == "tools-pack-manifest.json":
        continue
    path = safe_path(rel)
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    if rel not in listed_files:
        raise SystemExit(f"tools pack file is not listed in manifest artifacts: {rel}")

print(f"Tools pack verified for {pack['id']} ({len(listed_files)} files)")
PY
}
