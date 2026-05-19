#!/usr/bin/env bash
# Tests for ``initialize_skills_hub_dir`` added in 2026-05.
#
# Doctor's "Skills Hub directory not initialized" warning fired on every
# fresh Hatch install because ``~/.monoclaw/skills/.hub/`` is created
# lazily by the runtime on the first ``monoclaw skills list`` call. We
# now seed it during install. The function MUST be idempotent (never
# overwrite an existing ``lock.json``) and MUST refuse to run any
# destructive side effects in dry-run mode.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Pin MONOCLAW_HOME to the temp dir so ``initialize_skills_hub_dir``
# never touches the developer's real ~/.monoclaw.
export MONOCLAW_HOME="${TMP}/.monoclaw"
mkdir -p "${MONOCLAW_HOME}"

HARNESS="${TMP}/harness.sh"
cat > "${HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="\${HATCH_DRY_RUN:-true}"
export HATCH_DRY_RUN
$(awk '/^initialize_skills_hub_dir\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
initialize_skills_hub_dir
HARNESS_EOF
chmod +x "${HARNESS}"

# ── Case 1: dry-run plans the mkdir + lock.json write but does NOT touch disk
DRY_OUT="$(HATCH_DRY_RUN=true bash "${HARNESS}" 2>&1)"
case "${DRY_OUT}" in
  *"dry-run: mkdir -p ${MONOCLAW_HOME}/skills/.hub"*) ;;
  *)
    printf 'fail: dry-run did not plan mkdir. got:\n%s\n' "${DRY_OUT}" >&2
    exit 1
    ;;
esac
case "${DRY_OUT}" in
  *"dry-run: write empty lock file at ${MONOCLAW_HOME}/skills/.hub/lock.json"*) ;;
  *)
    printf 'fail: dry-run did not plan lock.json write. got:\n%s\n' "${DRY_OUT}" >&2
    exit 1
    ;;
esac
if [[ -e "${MONOCLAW_HOME}/skills/.hub" ]]; then
  printf 'fail: dry-run actually created %s/skills/.hub\n' "${MONOCLAW_HOME}" >&2
  exit 1
fi

# ── Case 2: --apply (HATCH_DRY_RUN=false) creates dir + lock.json ─────────
APPLY_OUT="$(HATCH_DRY_RUN=false bash "${HARNESS}" 2>&1)"
case "${APPLY_OUT}" in
  *"Initialized Skills Hub at ${MONOCLAW_HOME}/skills/.hub"*) ;;
  *)
    printf 'fail: --apply mode did not announce init. got:\n%s\n' "${APPLY_OUT}" >&2
    exit 1
    ;;
esac
if [[ ! -d "${MONOCLAW_HOME}/skills/.hub" ]]; then
  printf 'fail: --apply did not create %s/skills/.hub\n' "${MONOCLAW_HOME}" >&2
  exit 1
fi
if [[ ! -f "${MONOCLAW_HOME}/skills/.hub/lock.json" ]]; then
  printf 'fail: --apply did not write lock.json\n' >&2
  exit 1
fi

# Lock file must be a valid empty-installed JSON shape.
EXPECTED='{"installed": {}}'
ACTUAL="$(cat "${MONOCLAW_HOME}/skills/.hub/lock.json" | tr -d '[:space:]')"
EXPECTED_NORMALISED="$(printf '%s' "${EXPECTED}" | tr -d '[:space:]')"
if [[ "${ACTUAL}" != "${EXPECTED_NORMALISED}" ]]; then
  printf 'fail: lock.json contents differ\n  expected: %s\n  actual:   %s\n' \
    "${EXPECTED_NORMALISED}" "${ACTUAL}" >&2
  exit 1
fi

# ── Case 3: idempotency — re-running --apply must NOT clobber existing lock
printf '{"installed": {"my-skill": "1.0.0"}}\n' > "${MONOCLAW_HOME}/skills/.hub/lock.json"
RETAINED_OUT="$(HATCH_DRY_RUN=false bash "${HARNESS}" 2>&1)"
case "${RETAINED_OUT}" in
  *"Skills Hub already initialized"*) ;;
  *)
    printf 'fail: re-run did not announce already-initialized. got:\n%s\n' "${RETAINED_OUT}" >&2
    exit 1
    ;;
esac
if ! grep -q "my-skill" "${MONOCLAW_HOME}/skills/.hub/lock.json"; then
  printf 'fail: re-run clobbered an existing lock.json\n' >&2
  cat "${MONOCLAW_HOME}/skills/.hub/lock.json" >&2
  exit 1
fi

printf 'ok: hatch initialize_skills_hub_dir (dry-run safe, --apply seeds, idempotent)\n'
