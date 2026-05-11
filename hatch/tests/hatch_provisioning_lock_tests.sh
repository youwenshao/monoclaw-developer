#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

INPUTS="${TMP}/bundle-inputs"
RUNTIME="${TMP}/monoclaw-runtime"
mkdir -p "${INPUTS}/vendor/provisioning" "${RUNTIME}"

cat > "${RUNTIME}/pyproject.toml" <<'TOML'
[project]
dependencies = ["requests>=2"]

[project.optional-dependencies]
web = ["fastapi>=0.104"]
local-office = ["monoclaw-runtime[web]", "qrcode>=7"]
TOML

VALID_LOCK="${INPUTS}/vendor/provisioning/monoclaw-provisioning-lock.json"
cat > "${VALID_LOCK}" <<'JSON'
{
  "schema_version": 1,
  "items": [
    {
      "kind": "tool",
      "name": "offline",
      "classification": "stock_bundle_candidate",
      "python_dependencies": ["requests>=2", "fastapi>=0.104"],
      "bundled_artifacts": ["vendor/provisioning/monoclaw-provisioning-lock.json"]
    },
    {
      "kind": "tool",
      "name": "tokened",
      "classification": "provisioned_user_config_required",
      "python_dependencies": ["qrcode>=7"]
    }
  ]
}
JSON

python3 "${ROOT}/scripts/verify_provisioning_lock.py" \
  --input-root "${INPUTS}" \
  --runtime-root "${RUNTIME}" | tee "${TMP}/valid.out"
grep -q "Provisioning lock verified" "${TMP}/valid.out"

mv "${VALID_LOCK}" "${TMP}/missing.json"
if python3 "${ROOT}/scripts/verify_provisioning_lock.py" \
  --input-root "${INPUTS}" \
  --runtime-root "${RUNTIME}" >"${TMP}/missing.out" 2>&1; then
  printf 'expected missing provisioning lock to fail\n' >&2
  exit 1
fi
grep -q "provisioning lock is required" "${TMP}/missing.out"
mv "${TMP}/missing.json" "${VALID_LOCK}"

python3 - "${VALID_LOCK}" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["items"][0]["classification"] = "blocked_unknown"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if python3 "${ROOT}/scripts/verify_provisioning_lock.py" \
  --input-root "${INPUTS}" \
  --runtime-root "${RUNTIME}" >"${TMP}/unknown.out" 2>&1; then
  printf 'expected blocked_unknown item to fail\n' >&2
  exit 1
fi
grep -q "blocked_unknown" "${TMP}/unknown.out"

python3 - "${VALID_LOCK}" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["items"][0]["classification"] = "stock_bundle_candidate"
data["items"][0]["python_dependencies"] = ["arxiv>=2"]
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if python3 "${ROOT}/scripts/verify_provisioning_lock.py" \
  --input-root "${INPUTS}" \
  --runtime-root "${RUNTIME}" >"${TMP}/missing-dep.out" 2>&1; then
  printf 'expected missing local-office dependency to fail\n' >&2
  exit 1
fi
grep -q "missing local-office dependency" "${TMP}/missing-dep.out"
