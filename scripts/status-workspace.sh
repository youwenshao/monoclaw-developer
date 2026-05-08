#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/workspace.manifest.json"

python3 - "$MANIFEST" <<'PY' | while IFS=$'\t' read -r name path local; do
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text())
root = manifest_path.parent

for repo in manifest["repositories"]:
    path = (root / repo["path"]).resolve()
    print(repo["name"], str(path), str(repo.get("local", False)).lower(), sep="\t")
PY
  printf '\n== %s ==\n' "${name}"
  if [[ "${local}" == "true" ]]; then
    if [[ -d "${path}" ]]; then
      printf 'local directory: %s\n' "${path}"
    else
      printf 'missing local directory: %s\n' "${path}"
    fi
    continue
  fi

  if [[ ! -d "${path}/.git" ]]; then
    printf 'missing clone: %s\n' "${path}"
    continue
  fi

  git -C "${path}" status --short --branch
done
