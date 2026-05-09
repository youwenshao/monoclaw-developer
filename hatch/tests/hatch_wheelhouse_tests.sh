#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

INPUTS="${TMP}/bundle-inputs"
RUNTIME="${TMP}/monoclaw-runtime"
FAKE_PYTHON="${TMP}/fake-python"
PIP_LOG="${TMP}/pip.log"
mkdir -p "${INPUTS}/vendor/python/current/bin" "${RUNTIME}"

cat > "${RUNTIME}/pyproject.toml" <<'TOML'
[project]
name = "monoclaw-runtime"
version = "0.13.0"

[project.optional-dependencies]
local-office = ["requests>=2"]
TOML

cat > "${FAKE_PYTHON}" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-c" ]]; then
  exit 0
fi
printf '%s\n' "$*" >> "${HATCH_FAKE_PIP_LOG}"

wheel_dir=""
previous=""
for arg in "$@"; do
  if [[ "${previous}" == "--wheel-dir" ]]; then
    wheel_dir="${arg}"
    break
  fi
  previous="${arg}"
done

if [[ -z "${wheel_dir}" ]]; then
  printf 'missing --wheel-dir in fake pip invocation\n' >&2
  exit 1
fi

mkdir -p "${wheel_dir}"
printf 'fake wheel\n' > "${wheel_dir}/fake_dependency-0.0.0-py3-none-any.whl"
SH
chmod +x "${FAKE_PYTHON}"
cp "${FAKE_PYTHON}" "${INPUTS}/vendor/python/current/bin/python3"

HATCH_INPUT_ROOT="${INPUTS}" \
HATCH_RUNTIME_ROOT="${RUNTIME}" \
HATCH_FAKE_PIP_LOG="${PIP_LOG}" \
  bash "${ROOT}/scripts/build_wheelhouse.sh" | tee "${TMP}/wheelhouse.out"

test -f "${INPUTS}/vendor/wheelhouse/fake_dependency-0.0.0-py3-none-any.whl"
grep -q "Building bootstrap tool wheels" "${TMP}/wheelhouse.out"
grep -q "Building monoclaw-runtime\\[local-office\\] wheelhouse" "${TMP}/wheelhouse.out"
grep -q "Using wheelhouse Python ${INPUTS}/vendor/python/current/bin/python3" "${TMP}/wheelhouse.out"
grep -q -- "-m pip wheel --wheel-dir ${INPUTS}/vendor/wheelhouse pip setuptools wheel" "${PIP_LOG}"
grep -Fq -- "-m pip wheel --wheel-dir ${INPUTS}/vendor/wheelhouse ${RUNTIME}[local-office]" "${PIP_LOG}"

if HATCH_INPUT_ROOT="${INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_DIST_ROOT="${TMP}/inputs-as-dist" \
  HATCH_RUNTIME_WHEEL="${TMP}/missing.whl" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
  HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
    bash "${ROOT}/build.sh" >"${TMP}/missing-wheel.out" 2>&1; then
  printf 'expected build to fail before a runtime wheel is provided\n' >&2
  exit 1
fi

EMPTY_INPUTS="${TMP}/empty-inputs"
mkdir -p "${EMPTY_INPUTS}/vendor/python/current/bin"
cp "${FAKE_PYTHON}" "${EMPTY_INPUTS}/vendor/python/current/bin/python3"
if HATCH_INPUT_ROOT="${EMPTY_INPUTS}" \
  HATCH_RUNTIME_ROOT="${RUNTIME}" \
  HATCH_DIST_ROOT="${TMP}/empty-dist" \
  HATCH_RUNTIME_WHEEL="${TMP}/missing.whl" \
  HATCH_SKIP_RUNTIME_BUILD=1 \
  HATCH_SKIP_RUNTIME_PYTHON_SMOKE=1 \
    bash "${ROOT}/build.sh" >"${TMP}/empty-wheelhouse.out" 2>&1; then
  printf 'expected build to fail when wheelhouse is missing\n' >&2
  exit 1
fi
grep -q "run: bash scripts/build_wheelhouse.sh" "${TMP}/empty-wheelhouse.out"
