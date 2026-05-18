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

# ── Post-install provision prompt ──────────────────────────────────────────
# ``monoclaw provision`` is the canonical first-run onboarding wizard. It
# walks every setup section (model → tools → gateway → system → agent) in
# order and runs a live verification probe after each step. The old
# ``monoclaw setup system`` command remains available as a targeted re-entry
# point but is no longer the primary post-install instruction.
#
# We only offer to launch it when both stdin and stdout are interactive
# terminals. Headless CI, remote SSH without PTY, or non-interactive scripts
# must run ``monoclaw provision`` manually — the wizard cannot prompt for
# secrets or drive upstream sub-wizards (himalaya account configure, etc.)
# without an attached TTY.
#
# Set HATCH_AUTO_PROVISION=0 to suppress this prompt entirely (e.g. in bench
# automation that provisions via a separate Ansible step).
if [[ "${HATCH_INSTALL_DRY_RUN:-0}" == "1" ]]; then
  printf '\n  dry-run: would prompt to run monoclaw provision now\n'
elif [[ "${HATCH_AUTO_PROVISION:-1}" == "0" ]]; then
  printf '\n  info: HATCH_AUTO_PROVISION=0; skipping provision prompt.\n'
  printf '  info: Run "monoclaw provision" manually to complete setup.\n'
elif [[ -t 0 && -t 1 ]]; then
  printf '\n'
  printf '  MonoClaw is installed.\n'
  printf '  Run "monoclaw provision" now to configure your email account,\n'
  printf '  secretary tools, credentials, and core dependencies? [Y/n] '
  read -r _PROVISION_ANSWER
  if [[ -z "${_PROVISION_ANSWER}" ]] || [[ "${_PROVISION_ANSWER}" =~ ^[Yy] ]]; then
    # Ensure the shim is on PATH before we try to run it. The shell that
    # launched install.sh may not have sourced ~/.profile yet.
    export PATH="${HOME}/.local/bin:${PATH}"
    if command -v monoclaw >/dev/null 2>&1; then
      if ! monoclaw provision; then
        printf '\n  warning: provision finished with issues.\n' >&2
        printf '  info: Run "monoclaw doctor" any time to re-diagnose.\n' >&2
      fi
    else
      printf '  warning: monoclaw shim not found on PATH.\n' >&2
      printf '  info: Open a new terminal and run "monoclaw provision" manually.\n' >&2
    fi
  else
    printf '  info: Run "monoclaw provision" in a new terminal when ready.\n'
  fi
else
  printf '\n  info: Install complete (non-interactive).\n'
  printf '  info: Run "monoclaw provision" in an interactive terminal to finish setup.\n'
fi
