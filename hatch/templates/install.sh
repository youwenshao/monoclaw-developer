#!/usr/bin/env bash
set -euo pipefail

DIST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="--apply"

# Set HATCH_INSTALL_STRICT=0 to revert to the legacy warn-and-continue
# behaviour when a partial install is intentionally acceptable.
HATCH_INSTALL_STRICT="${HATCH_INSTALL_STRICT:-1}"

if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  MODE="--dry-run"
fi

printf '  info: MonoClaw Hatch install from bundle root: %s\n' "${DIST_ROOT}" >&2

bash "${DIST_ROOT}/bin/hatch" "${MODE}" --bundle-root "${DIST_ROOT}" install

if [[ "${HATCH_INSTALL_MONA_TOOLS:-1}" != "1" ]]; then
  printf '  info: skipping Mona secretary tools because HATCH_INSTALL_MONA_TOOLS=0\n'
else
  if ! bash "${DIST_ROOT}/install-mona-tools.sh" 2>&1; then
    # Distinguish "pack not present" (normal skip — warn only) from
    # "pack present but installer failed" (fail in strict mode).
    MONA_PACK_ROOT="$(dirname "${DIST_ROOT}")/tool-packs/mona-secretary-tools"
    if [[ -d "${MONA_PACK_ROOT}" ]] && [[ "${HATCH_INSTALL_STRICT}" == "1" ]]; then
      printf '  error: Mona secretary tools installation failed (HATCH_INSTALL_STRICT=1).\n' >&2
      printf '  error: The pack is present but the installer crashed. Set HATCH_INSTALL_STRICT=0 to continue anyway.\n' >&2
      exit 1
    else
      printf '  warning: Mona secretary tools installation failed; core MonoClaw runtime remains installed\n' >&2
    fi
  fi
fi

if [[ "${HATCH_INSTALL_GEMMA_MODEL:-1}" != "1" ]]; then
  printf '  info: skipping Gemma model pack because HATCH_INSTALL_GEMMA_MODEL=0\n'
else
  if ! bash "${DIST_ROOT}/install-gemma-model.sh" 2>&1; then
    # Distinguish "pack not present" (normal skip — warn only) from
    # "pack present but installer failed" (fail in strict mode).
    GEMMA_PACK_ROOT="$(dirname "${DIST_ROOT}")/model-packs/gemma-4-e4b"
    if [[ -d "${GEMMA_PACK_ROOT}" ]] && [[ "${HATCH_INSTALL_STRICT}" == "1" ]]; then
      printf '  error: Gemma model pack installation failed (HATCH_INSTALL_STRICT=1).\n' >&2
      printf '  error: The pack is present but the installer failed (install LM Studio from the official .dmg first). Set HATCH_INSTALL_STRICT=0 to continue anyway.\n' >&2
      exit 1
    else
      printf '  warning: Gemma model pack installation failed; core MonoClaw runtime remains installed\n' >&2
    fi
  fi
fi

if [[ "${HATCH_INSTALL_SKILL_DEPS:-1}" != "1" ]]; then
  printf '  info: skipping skill dependencies pack because HATCH_INSTALL_SKILL_DEPS=0\n'
  exit 0
fi

if [[ -f "${DIST_ROOT}/install-skill-deps.sh" ]]; then
  if ! bash "${DIST_ROOT}/install-skill-deps.sh" 2>&1; then
    # Same distinction: only fail strictly when the pack was present.
    SKILL_DEPS_PACK_ROOT="$(dirname "${DIST_ROOT}")/tool-packs/skill-deps-pack"
    if [[ -d "${SKILL_DEPS_PACK_ROOT}" ]] && [[ "${HATCH_INSTALL_STRICT}" == "1" ]]; then
      printf '  error: skill dependencies installation failed (HATCH_INSTALL_STRICT=1).\n' >&2
      printf '  error: The pack is present but the installer crashed. Set HATCH_INSTALL_STRICT=0 to continue anyway.\n' >&2
      exit 1
    else
      printf '  warning: skill dependencies installation failed; core MonoClaw runtime remains installed\n' >&2
    fi
  fi
fi

# ── Post-install technician provision ────────────────────────────────────────
# ``monoclaw provision --non-interactive`` applies identity-free system defaults
# (Mona plugin, skill-deps, core dependencies, agent defaults). Every shipped
# Mac should be identical with no personal credentials.
#
# End users run ``monoclaw onboard`` after receiving the Mac to configure model
# credentials, messaging platforms, email, and macOS permissions.
#
# Set HATCH_AUTO_PROVISION=0 to skip the automatic provision step (e.g. bench
# automation that provisions via a separate Ansible step).
if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  printf '\n  dry-run: would run monoclaw provision --non-interactive\n'
elif [[ "${HATCH_AUTO_PROVISION:-1}" == "0" ]]; then
  printf '\n  info: HATCH_AUTO_PROVISION=0; skipping automatic provision.\n'
  printf '  info: Run "monoclaw provision --non-interactive" before shipping.\n'
else
  export PATH="${HOME}/.local/bin:${PATH}"
  if command -v monoclaw >/dev/null 2>&1; then
    if ! monoclaw provision --non-interactive; then
      printf '\n  warning: monoclaw provision --non-interactive reported issues.\n' >&2
      printf '  info: Run "monoclaw doctor" any time to re-diagnose.\n' >&2
    fi
  else
    printf '  warning: monoclaw shim not found on PATH.\n' >&2
    printf '  info: Open a new terminal and run "monoclaw provision --non-interactive".\n' >&2
  fi
fi

cat <<'EOF'

  Provisioning complete. This Mac is ready to ship.
  When the end user receives it, they should run:

      monoclaw onboard

EOF
