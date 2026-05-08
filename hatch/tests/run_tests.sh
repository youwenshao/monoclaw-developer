#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${ROOT}/build.sh"
bash -n "${ROOT}/bin/hatch"
bash -n "${ROOT}/lib/common.sh"
bash -n "${ROOT}/templates/install.sh"
bash -n "${ROOT}/tests/hatch_dry_run_tests.sh"
bash -n "${ROOT}/tests/hatch_build_tests.sh"
python3 -m py_compile "${ROOT}/scripts/generate_manifest.py"
bash "${ROOT}/tests/hatch_dry_run_tests.sh"
bash "${ROOT}/tests/hatch_build_tests.sh"
