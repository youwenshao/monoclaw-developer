#!/usr/bin/env bash
# Optional sidecar pack for small CLI dependencies a MonoClaw skill needs.
#
# This is the per-skill counterpart to `scripts/build_mona_tools_pack.sh`.
# When enabled with `HATCH_INCLUDE_SKILL_DEPS=1`, it produces
# `tool-packs/skill-deps-pack/` from `bundle-inputs/vendor/skill-deps/`
# (`tool-lock.json` + `prebuilt/`), exactly mirroring the verified-pack
# pattern Mona uses.
#
# Default: disabled. The customer bundle does not change unless this
# pack is intentionally turned on for a specific release.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"
HATCH_TOOLS_PACKS_ROOT="${HATCH_TOOLS_PACKS_ROOT:-$(cd "${HATCH_ROOT}" && pwd)/tool-packs}"

log() {
  printf '[skill-deps] %s\n' "$1"
}

if [[ "${HATCH_INCLUDE_SKILL_DEPS:-0}" != "1" ]]; then
  log "Skill dependencies pack disabled (HATCH_INCLUDE_SKILL_DEPS!=1)"
  exit 0
fi

LOCK_PATH="${HATCH_INPUT_ROOT}/vendor/skill-deps/tool-lock.json"
PACK_ROOT="${HATCH_TOOLS_PACKS_ROOT}/skill-deps-pack"
SKILL_DEPS_VENDOR="${HATCH_INPUT_ROOT}/vendor/skill-deps"

if [[ ! -f "${LOCK_PATH}" ]]; then
  log "No tool-lock.json at ${LOCK_PATH}; nothing to build (Phase 5 scaffolding ships without binaries)."
  exit 0
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
    raise SystemExit("skill-deps tool-lock schema_version must be 1")

tools = data.get("tools") or []
if not tools:
    raise SystemExit("skill-deps tool-lock has no tools; refusing to ship empty pack")

seen_names: set[str] = set()
seen_paths: set[str] = set()
for tool in tools:
    name = tool.get("name")
    source = tool.get("source")
    rel_path = tool.get("path")
    if not name or not source or not rel_path:
        raise SystemExit(f"skill-deps tool entry missing required fields: {tool!r}")
    if name in seen_names:
        raise SystemExit(f"skill-deps tool-lock has duplicate tool name: {name}")
    if rel_path in seen_paths:
        raise SystemExit(f"skill-deps tool-lock has duplicate active path: {rel_path}")
    seen_names.add(name)
    seen_paths.add(rel_path)
    src_path = (input_root / "vendor" / "skill-deps" / source).resolve()
    if not src_path.is_file():
        raise SystemExit(f"skill-deps source missing: {src_path}")
    dst_path = (pack_root / rel_path).resolve()
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_path, dst_path)
    if not dst_path.suffix:
        dst_path.chmod(0o755)
PY

python3 "${HATCH_ROOT}/scripts/generate_tools_pack_manifest.py" \
  --pack-root "${PACK_ROOT}" \
  --pack-name "skill-deps-pack" || {
    log "Failed to generate tools-pack-manifest.json for skill-deps-pack"
    exit 1
  }

log "skill-deps pack built at ${PACK_ROOT}"
