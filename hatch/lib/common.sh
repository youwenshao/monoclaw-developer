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
  [[ -f "${manifest}" ]] || die "bundle manifest not found at ${manifest}"
  python_bin="$(hatch_manifest_python "${bundle_root}")" || die "Python is required to verify the Hatch manifest"

  PYTHONDONTWRITEBYTECODE=1 HATCH_BUNDLE_ROOT="${bundle_root}" HATCH_HOST_ARCH="$(uname -m)" "${python_bin}" <<'PY'
import hashlib
import json
import os
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
    candidate = (root / relative).resolve()
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
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    rel = path.relative_to(root).as_posix()
    if rel == "hatch-manifest.json":
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
    candidate = (root / relative).resolve()
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
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    rel = path.relative_to(root).as_posix()
    if rel == "model-pack-manifest.json":
        continue
    if rel not in listed_files:
        raise SystemExit(f"model pack file is not listed in manifest artifacts: {rel}")

print(f"Model pack verified for {model['id']} ({model_path.stat().st_size} bytes)")
PY
}
