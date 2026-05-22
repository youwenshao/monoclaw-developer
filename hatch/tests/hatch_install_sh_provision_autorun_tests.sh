#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="${ROOT}/templates/install.sh"

grep -q 'monoclaw provision --non-interactive' "${INSTALL_SH}"
grep -q 'monoclaw onboard' "${INSTALL_SH}"
grep -q 'ready to ship' "${INSTALL_SH}"

# Legacy interactive Y/N prompt must not return.
if grep -q 'Run "monoclaw provision" now' "${INSTALL_SH}"; then
  echo "install.sh still contains the old interactive provision prompt" >&2
  exit 1
fi

echo "ok: install.sh auto-runs provision and hands off to onboard"
