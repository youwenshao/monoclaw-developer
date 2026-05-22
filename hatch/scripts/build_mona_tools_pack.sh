#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"
HATCH_TOOLS_PACKS_ROOT="${HATCH_TOOLS_PACKS_ROOT:-$(cd "${HATCH_ROOT}" && pwd)/tool-packs}"
HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH:-$(uname -m)}"

log() {
  printf '[mona-tools] %s\n' "$1"
}

if [[ "${HATCH_INCLUDE_MONA_TOOLS:-1}" != "1" ]]; then
  log "Mona secretary tools pack disabled by HATCH_INCLUDE_MONA_TOOLS=0"
  exit 0
fi

LOCK_PATH="${HATCH_INPUT_ROOT}/vendor/mona-tools/tool-lock.json"
PACK_ROOT="${HATCH_TOOLS_PACKS_ROOT}/mona-secretary-tools"
MONA_VENDOR="${HATCH_INPUT_ROOT}/vendor/mona-tools"
MONA_PREP_BUILD_ROOT="${HATCH_MONA_TOOLS_BUILD_ROOT:-${HATCH_ROOT}/.mona-tools-build}"

if [[ ! -f "${LOCK_PATH}" ]]; then
  SOURCE_LOCK="${HATCH_MONA_TOOLS_SOURCE_LOCK:-${HATCH_INPUT_ROOT}/vendor/mona-tools/source-lock.json}"
  if [[ -f "${SOURCE_LOCK}" ]]; then
    ENSURE_NODE_OUT=""
    if ENSURE_NODE_OUT="$(
      HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH}" \
      HATCH_MONA_TOOLS_BUILD_ROOT="${MONA_PREP_BUILD_ROOT}" \
      HATCH_MONA_NODE_RUNTIME_SOURCE="${HATCH_MONA_NODE_RUNTIME_SOURCE:-}" \
      HATCH_MONA_NODE_AUTO_DOWNLOAD="${HATCH_MONA_NODE_AUTO_DOWNLOAD:-1}" \
        python3 "${HATCH_ROOT}/scripts/mona_tools_ensure_node_runtime.py" \
          --source-lock "${SOURCE_LOCK}" \
          --hatch-root "${HATCH_ROOT}"
    )"; then
      if [[ -n "${ENSURE_NODE_OUT}" ]]; then
        export HATCH_MONA_NODE_RUNTIME_SOURCE="${ENSURE_NODE_OUT}"
      fi
    else
      exit 1
    fi
  fi

  log "Mona tools lock missing (${LOCK_PATH}); running prepare_mona_tools_inputs.sh"
  PREP_FORCE="${HATCH_MONA_TOOLS_FORCE:-0}"
  if [[ "${PREP_FORCE}" != "1" ]] && [[ -e "${MONA_VENDOR}/prebuilt" ]]; then
    PREP_FORCE=1
  fi
  HATCH_ROOT="${HATCH_ROOT}" \
  HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
  HATCH_MONA_TOOLS_FORCE="${PREP_FORCE}" \
  HATCH_MONA_TOOLS_BUILD_ROOT="${MONA_PREP_BUILD_ROOT}" \
  HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH}" \
  HATCH_MONA_TOOLS_SOURCE_LOCK="${HATCH_MONA_TOOLS_SOURCE_LOCK:-}" \
  HATCH_MONA_NODE_RUNTIME_SOURCE="${HATCH_MONA_NODE_RUNTIME_SOURCE:-}" \
    bash "${HATCH_ROOT}/scripts/prepare_mona_tools_inputs.sh"

  if [[ ! -f "${LOCK_PATH}" ]]; then
    printf 'Mona tools lock is still missing after preparation: %s\n' "${LOCK_PATH}" >&2
    exit 1
  fi
fi

rm -rf "${PACK_ROOT}"
mkdir -p "${PACK_ROOT}"

python3 - "${LOCK_PATH}" "${HATCH_INPUT_ROOT}" "${PACK_ROOT}" <<'PY'
import json
import shutil
import sys
from pathlib import Path

lock_path = Path(sys.argv[1]).resolve()
input_root = Path(sys.argv[2]).resolve()
pack_root = Path(sys.argv[3]).resolve()

data = json.loads(lock_path.read_text(encoding="utf-8"))
if data.get("schema_version") != 1:
    raise SystemExit("Mona tools lock schema_version must be 1")
pack = data.get("pack")
if not isinstance(pack, dict):
    raise SystemExit("Mona tools lock pack must be an object")
if pack.get("id") != "mona-secretary-tools":
    raise SystemExit("Mona tools lock pack.id must be mona-secretary-tools")
if not str(pack.get("version", "")).strip():
    raise SystemExit("Mona tools lock pack.version is required")

allowed_modes = {"go-binary", "node-app", "skills-only", "deferred"}
placeholder_source_refs = {
    "replace-with-commit-or-release",
    "replace-with-commit",
    "replace-with-release",
    "placeholder",
    "tbd",
    "todo",
}

def resolve_input(relative: str) -> Path:
    source = (input_root / relative).resolve()
    try:
        source.relative_to(input_root)
    except ValueError:
        raise SystemExit(f"Mona tools source escapes input root: {relative}") from None
    if not source.exists():
        raise SystemExit(f"Mona tools source missing: {relative}")
    return source

def pack_destination(relative: str) -> Path:
    destination = (pack_root / relative).resolve()
    try:
        destination.relative_to(pack_root)
    except ValueError:
        raise SystemExit(f"Mona tools destination escapes pack root: {relative}") from None
    return destination

def ensure_tree_symlinks_inside(tree: Path, root: Path, label: str) -> None:
    for path in tree.rglob("*"):
        if not path.is_symlink():
            continue
        resolved = path.resolve(strict=False)
        try:
            resolved.relative_to(root)
        except ValueError:
            raise SystemExit(f"{label} symlink escapes expected root: {path}") from None

def copy_path(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        ensure_tree_symlinks_inside(source, input_root, "Mona tools source")
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination, symlinks=True)
        ensure_tree_symlinks_inside(destination, pack_root, "Mona tools destination")
    else:
        shutil.copy2(source, destination)

node = data.get("node") if isinstance(data.get("node"), dict) else {}
node_source = node.get("source")
if node_source:
    copy_path(resolve_input(str(node_source)), pack_root / "node/current")

active_tools = []
seen_names: set[str] = set()
seen_active_paths: set[str] = set()
for item in data.get("tools", []):
    if not isinstance(item, dict):
        raise SystemExit("Mona tools lock tools entries must be objects")
    mode = str(item.get("mode", "")).strip()
    if mode not in allowed_modes:
        raise SystemExit(f"Mona tools lock has unsupported build mode: {mode}")
    for required_key in ("name", "version", "license", "repository", "source_ref", "activation", "required_permissions"):
        if required_key not in item or item[required_key] in (None, "", []):
            raise SystemExit(f"Mona tools lock entry missing {required_key}")
    name = str(item.get("name", "")).strip()
    if name in seen_names:
        raise SystemExit(f"Mona tools lock has duplicate tool name: {name}")
    seen_names.add(name)
    source_ref = str(item.get("source_ref", "")).strip()
    if source_ref.lower() in placeholder_source_refs or source_ref.lower().startswith("replace-with-"):
        raise SystemExit(f"Mona tools lock entry has placeholder source_ref: {name}")
    if mode == "deferred":
        continue
    source = str(item.get("source", "")).strip()
    rel_path = str(item.get("path", "")).strip()
    if not name or not source or not rel_path:
        raise SystemExit("Mona tools active entries require name, source, and path")
    if mode == "node-app" and (
        not str(node.get("version", "")).strip() or not str(node.get("source", "")).strip()
    ):
        raise SystemExit("Mona tools node runtime declaration is required when node-app tools are active")
    source_path = resolve_input(source)
    pack_destination(rel_path)
    if mode == "node-app":
        active_path = f"bin/{name}"
    else:
        active_path = rel_path
    if source_path.is_dir() and mode == "node-app":
        destination = pack_destination(f"node/apps/{name}")
    else:
        destination = pack_destination(rel_path)
    if active_path in seen_active_paths:
        raise SystemExit(f"Mona tools lock has duplicate active path: {active_path}")
    seen_active_paths.add(active_path)
    copy_path(source_path, destination)
    if mode == "node-app":
        entrypoint = pack_destination(rel_path)
        if not entrypoint.is_file():
            raise SystemExit(f"Mona tools node app entrypoint missing after copy: {rel_path}")
        wrapper = pack_destination(f"bin/{name}")
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        wrapper.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n"
            "PACK_ROOT=\"$(cd \"${SCRIPT_DIR}/..\" && pwd)\"\n"
            f"exec \"${{PACK_ROOT}}/node/current/bin/node\" \"${{PACK_ROOT}}/{rel_path}\" \"$@\"\n",
            encoding="utf-8",
        )
        wrapper.chmod(0o755)
        item = dict(item)
        item["path"] = f"bin/{name}"
    active_tools.append(item)

for item in data.get("extra_artifacts", []):
    if not isinstance(item, dict):
        raise SystemExit("Mona tools extra_artifacts entries must be objects")
    source = str(item.get("source", "")).strip()
    rel_path = str(item.get("path", "")).strip()
    if not source or not rel_path:
        raise SystemExit("Mona tools extra_artifacts entries require source and path")
    if rel_path == "skills":
        raise SystemExit(
            "Mona pack must not carry skills; ship via monoclaw-runtime/skills/"
        )
    copy_path(resolve_input(source), pack_destination(rel_path))

(pack_root / ".mona-tools-active.json").write_text(
    json.dumps(
        {
            "pack": data.get("pack", {}),
            "node": node,
            "tools": active_tools,
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
ensure_tree_symlinks_inside(pack_root, pack_root, "Mona tools pack")
PY

PACK_ID="$(python3 - "${PACK_ROOT}/.mona-tools-active.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("pack", {}).get("id", "mona-secretary-tools"))
PY
)"
PACK_VERSION="$(python3 - "${PACK_ROOT}/.mona-tools-active.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("pack", {}).get("version", "0.0.0"))
PY
)"
NODE_VERSION="$(python3 - "${PACK_ROOT}/.mona-tools-active.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("node", {}).get("version", ""))
PY
)"

# Write the tools-file payload OUTSIDE the pack root so the manifest
# generator's recursive artifact scan does not pick it up as an unlisted
# file.
TOOLS_FILE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mona-tools-manifest-input.XXXXXX")"
TOOLS_FILE="${TOOLS_FILE_DIR}/tools.json"
python3 - "${PACK_ROOT}/.mona-tools-active.json" "${TOOLS_FILE}" <<'PY'
import json
import sys
from pathlib import Path

active = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
output_path = Path(sys.argv[2])

# Keys passed to generate_tools_pack_manifest.py via --tools-file. Only the
# manifest-relevant fields make it through; everything else (mode, license,
# repository, source_ref, etc.) stays in tool-lock.json and is not exposed in
# tools-pack-manifest.json.
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
    if str(item.get("mode", "")).strip() == "deferred":
        continue
    entry: dict[str, object] = {}
    for key in MANIFEST_KEYS:
        if key in item and item[key] not in (None, ""):
            entry[key] = item[key]
    entry.setdefault("activation", "opt-in")
    entry.setdefault("required_permissions", [])
    tools_for_manifest.append(entry)

output_path.write_text(
    json.dumps(tools_for_manifest, indent=2) + "\n",
    encoding="utf-8",
)
PY
rm -f "${PACK_ROOT}/.mona-tools-active.json"

python3 "${HATCH_ROOT}/scripts/generate_tools_pack_manifest.py" \
  --tools-pack-root "${PACK_ROOT}" \
  --pack-id "${PACK_ID}" \
  --pack-version "${PACK_VERSION}" \
  --target-arch "${HATCH_TARGET_ARCH}" \
  --node-version "${NODE_VERSION}" \
  --tools-file "${TOOLS_FILE}"
rm -rf "${TOOLS_FILE_DIR}"

bash "${HATCH_ROOT}/bin/hatch" --dry-run --tools-pack-root "${PACK_ROOT}" verify-tools-pack
log "Mona secretary tools pack staged at ${PACK_ROOT}"
