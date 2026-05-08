#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/workspace.manifest.json"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

python3 - "$MANIFEST" <<'PY' | while IFS=$'\t' read -r name url path branch local reference_only; do
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text())
root = manifest_path.parent

for repo in manifest["repositories"]:
    path = (root / repo["path"]).resolve()
    print(
        repo["name"],
        repo.get("url") or "__local__",
        str(path),
        repo.get("branch", "main"),
        str(repo.get("local", False)).lower(),
        str(repo.get("referenceOnly", False)).lower(),
        sep="\t",
    )
PY
  if [[ "${local}" == "true" ]]; then
    run mkdir -p "${path}"
    continue
  fi

  if [[ -z "${url}" || "${url}" == "__local__" ]]; then
    printf 'Missing URL for %s\n' "${name}" >&2
    exit 1
  fi

  if [[ -d "${path}/.git" ]]; then
    printf 'Updating %s at %s\n' "${name}" "${path}"
    run git -C "${path}" fetch --prune origin
    if [[ "${reference_only}" == "true" ]]; then
      run git -C "${path}" checkout "${branch}"
      run git -C "${path}" pull --ff-only origin "${branch}"
    fi
  else
    printf 'Cloning %s into %s\n' "${name}" "${path}"
    run git clone --branch "${branch}" "${url}" "${path}"
  fi
done
