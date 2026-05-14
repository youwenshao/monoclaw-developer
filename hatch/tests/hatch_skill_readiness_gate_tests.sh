#!/usr/bin/env bash
# Smoke test for the `verify-skill-readiness` verb added in Phase 7.  We
# build a fake MONOCLAW_HOME with a handful of SKILL.md files of varying
# bundle policies and confirm:
#   * the verb counts each policy correctly,
#   * dry-run never aborts the gate,
#   * apply mode aborts when --fail-on threshold (env) matches.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

HOME_DIR="${TMP}/monoclaw_home"
mkdir -p "${HOME_DIR}/skills/research/ready" "${HOME_DIR}/skills/research/creds" "${HOME_DIR}/skills/research/external"

cat > "${HOME_DIR}/skills/research/ready/SKILL.md" <<'YAML'
---
name: ready-skill
metadata:
  monoclaw:
    provisioning:
      bundle_policy: stock_bundle_candidate
      requires_personal_config: false
      python_dependencies: []
      system_dependencies: []
---
# body
YAML

cat > "${HOME_DIR}/skills/research/creds/SKILL.md" <<'YAML'
---
name: creds-skill
metadata:
  monoclaw:
    provisioning:
      bundle_policy: provisioned_user_config_required
      requires_personal_config: true
      python_dependencies: []
      system_dependencies: []
---
# body
YAML

cat > "${HOME_DIR}/skills/research/external/SKILL.md" <<'YAML'
---
name: external-skill
metadata:
  monoclaw:
    provisioning:
      bundle_policy: external_runtime_only
      requires_personal_config: false
      python_dependencies: []
      system_dependencies: ["needsthis"]
---
# body
YAML

# Dry-run should always succeed and report counts.
OUT="$(MONOCLAW_HOME="${HOME_DIR}" bash "${ROOT}/bin/hatch" --dry-run verify-skill-readiness 2>&1)"
case "${OUT}" in
  *"Ready"*"1"*) ;;
  *) printf 'fail: dry-run output missing Ready 1 line. got: %s\n' "${OUT}" >&2; exit 1;;
esac
case "${OUT}" in
  *"Setup required"*"1"*) ;;
  *) printf 'fail: dry-run output missing Setup required count. got: %s\n' "${OUT}" >&2; exit 1;;
esac
case "${OUT}" in
  *"External runtime"*"1"*) ;;
  *) printf 'fail: dry-run output missing External runtime count. got: %s\n' "${OUT}" >&2; exit 1;;
esac
case "${OUT}" in
  *"declare system_dependencies that are not installed"*) ;;
  *) printf 'fail: dry-run output missing missing-deps note. got: %s\n' "${OUT}" >&2; exit 1;;
esac

# Apply mode with FAIL_ON=external_runtime_only should fail.
if MONOCLAW_HOME="${HOME_DIR}" \
   HATCH_SKILL_READINESS_FAIL_ON=external_runtime_only \
   bash "${ROOT}/bin/hatch" --apply verify-skill-readiness >"${TMP}/apply.out" 2>&1; then
  printf 'fail: --apply with external_runtime_only threshold should have errored\n' >&2
  cat "${TMP}/apply.out" >&2
  exit 1
fi

# Apply mode with default threshold (blocked_unknown) and zero offenders should pass.
if ! MONOCLAW_HOME="${HOME_DIR}" \
     bash "${ROOT}/bin/hatch" --apply verify-skill-readiness >"${TMP}/apply2.out" 2>&1; then
  printf 'fail: --apply with no blocked_unknown skills should have passed\n' >&2
  cat "${TMP}/apply2.out" >&2
  exit 1
fi

printf 'ok: skill readiness gate\n'
