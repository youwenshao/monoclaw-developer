#!/usr/bin/env bash
# Tests for the Hatch staging contract for monoclaw-runtime's Node
# subsystems (TUI + WhatsApp bridge) introduced 2026-05.
#
# May 2026 incident: ``monoclaw --tui`` and ``monoclaw whatsapp`` both
# crashed on fresh customer Macs because their source-tree paths
# (PROJECT_ROOT/ui-tui and PROJECT_ROOT/scripts/whatsapp-bridge) resolve
# into ``site-packages/...`` directories that never existed. Hatch must
# now stage both subtrees into ``dist/vendor/{tui,whatsapp-bridge}/``,
# and ``install_runtime_assets`` must mirror them into
# ``~/.monoclaw/vendor/`` so the runtime's ``_resolve_tui_dir`` /
# ``_resolve_bridge_dir`` helpers can find them.
#
# These tests:
#   1. ``verify_node_subsystems.py`` refuses a bundle missing either
#      subtree (locks the bundle-build gate).
#   2. ``install_runtime_assets`` copies ``vendor/tui`` and
#      ``vendor/whatsapp-bridge`` when present in the bundle.
#   3. ``warm_whatsapp_bridge_install`` is non-fatal when offline / npm
#      is absent (no hard install gate by default).
#   4. ``warm_whatsapp_bridge_install`` does a clean no-op when
#      ``node_modules`` already exists (idempotent).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT


# ─────────────────────────────────────────────────────────────────────────
# Case 1: verify_node_subsystems.py FAILS on an empty bundle
# ─────────────────────────────────────────────────────────────────────────
EMPTY_BUNDLE="${TMP}/empty-bundle"
mkdir -p "${EMPTY_BUNDLE}/vendor"
if python3 "${ROOT}/scripts/verify_node_subsystems.py" --bundle-root "${EMPTY_BUNDLE}" 2>/dev/null; then
  printf 'fail: verify_node_subsystems.py accepted a bundle with no vendor/tui or vendor/whatsapp-bridge\n' >&2
  exit 1
fi


# ─────────────────────────────────────────────────────────────────────────
# Case 2: verify_node_subsystems.py FAILS on a bundle missing only the
# WhatsApp bridge (catches half-baked staging refactors)
# ─────────────────────────────────────────────────────────────────────────
HALF_BUNDLE="${TMP}/half-bundle"
mkdir -p "${HALF_BUNDLE}/vendor/tui/packages/monoclaw-ink/dist"
mkdir -p "${HALF_BUNDLE}/vendor/tui/dist"
printf '{}' > "${HALF_BUNDLE}/vendor/tui/package.json"
printf '// entry' > "${HALF_BUNDLE}/vendor/tui/dist/entry.js"
# esbuild output filename — see ui-tui/packages/monoclaw-ink/package.json
printf '// ink' > "${HALF_BUNDLE}/vendor/tui/packages/monoclaw-ink/dist/entry-exports.js"
if python3 "${ROOT}/scripts/verify_node_subsystems.py" --bundle-root "${HALF_BUNDLE}" 2>/dev/null; then
  printf 'fail: verify_node_subsystems.py accepted a bundle missing the WhatsApp bridge\n' >&2
  exit 1
fi


# ─────────────────────────────────────────────────────────────────────────
# Case 3: verify_node_subsystems.py PASSES on a fully-staged bundle
# ─────────────────────────────────────────────────────────────────────────
FULL_BUNDLE="${TMP}/full-bundle"
mkdir -p "${FULL_BUNDLE}/vendor/tui/packages/monoclaw-ink/dist"
mkdir -p "${FULL_BUNDLE}/vendor/tui/dist"
printf '{}' > "${FULL_BUNDLE}/vendor/tui/package.json"
printf '// entry' > "${FULL_BUNDLE}/vendor/tui/dist/entry.js"
printf '// ink' > "${FULL_BUNDLE}/vendor/tui/packages/monoclaw-ink/dist/entry-exports.js"
mkdir -p "${FULL_BUNDLE}/vendor/whatsapp-bridge"
printf '{}' > "${FULL_BUNDLE}/vendor/whatsapp-bridge/package.json"
printf '{}' > "${FULL_BUNDLE}/vendor/whatsapp-bridge/package-lock.json"
printf '// bridge' > "${FULL_BUNDLE}/vendor/whatsapp-bridge/bridge.js"
if ! python3 "${ROOT}/scripts/verify_node_subsystems.py" --bundle-root "${FULL_BUNDLE}" >/dev/null; then
  printf 'fail: verify_node_subsystems.py rejected a fully-staged bundle\n' >&2
  exit 1
fi


# ─────────────────────────────────────────────────────────────────────────
# Case 4: verify_node_subsystems.py FAILS on a bundle that leaked
# ``node_modules`` (host-specific binaries that may break on the target)
# ─────────────────────────────────────────────────────────────────────────
LEAK_BUNDLE="${TMP}/leak-bundle"
mkdir -p "${LEAK_BUNDLE}/vendor/tui/packages/monoclaw-ink/dist"
mkdir -p "${LEAK_BUNDLE}/vendor/tui/dist"
mkdir -p "${LEAK_BUNDLE}/vendor/tui/node_modules"  # the leak
printf '{}' > "${LEAK_BUNDLE}/vendor/tui/package.json"
printf '// entry' > "${LEAK_BUNDLE}/vendor/tui/dist/entry.js"
printf '// ink' > "${LEAK_BUNDLE}/vendor/tui/packages/monoclaw-ink/dist/entry-exports.js"
mkdir -p "${LEAK_BUNDLE}/vendor/whatsapp-bridge"
printf '{}' > "${LEAK_BUNDLE}/vendor/whatsapp-bridge/package.json"
printf '{}' > "${LEAK_BUNDLE}/vendor/whatsapp-bridge/package-lock.json"
printf '// bridge' > "${LEAK_BUNDLE}/vendor/whatsapp-bridge/bridge.js"
if python3 "${ROOT}/scripts/verify_node_subsystems.py" --bundle-root "${LEAK_BUNDLE}" 2>/dev/null; then
  printf 'fail: verify_node_subsystems.py accepted a bundle with leaked node_modules\n' >&2
  exit 1
fi


# ─────────────────────────────────────────────────────────────────────────
# Case 5: install_runtime_assets copies vendor/tui + vendor/whatsapp-bridge
# Run the function in dry-run mode and verify the planned cp -R command
# names the two new subtrees.
# ─────────────────────────────────────────────────────────────────────────
INSTALL_HARNESS="${TMP}/install_harness.sh"
INSTALL_HOME="${TMP}/install-home/.monoclaw"
INSTALL_BUNDLE="${TMP}/install-bundle"
mkdir -p "${INSTALL_BUNDLE}/vendor/tui" "${INSTALL_BUNDLE}/vendor/whatsapp-bridge"
printf '{}' > "${INSTALL_BUNDLE}/vendor/tui/package.json"
printf '{}' > "${INSTALL_BUNDLE}/vendor/whatsapp-bridge/package.json"
printf '{"runtime": {}}' > "${INSTALL_BUNDLE}/hatch-manifest.json"

cat > "${INSTALL_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="true"
HATCH_BUNDLE_ROOT="${INSTALL_BUNDLE}"
export HATCH_DRY_RUN HATCH_BUNDLE_ROOT
monoclaw_home() { printf '%s' "${INSTALL_HOME}"; }
$(awk '/^install_runtime_assets\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
install_runtime_assets
HARNESS_EOF
chmod +x "${INSTALL_HARNESS}"

INSTALL_OUT="$(bash "${INSTALL_HARNESS}" 2>&1)"
for asset in tui whatsapp-bridge; do
  case "${INSTALL_OUT}" in
    *"cp -R ${INSTALL_BUNDLE}/vendor/${asset} ${INSTALL_HOME}/vendor/${asset}"*) ;;
    *)
      printf 'fail: install_runtime_assets did not plan cp -R for vendor/%s. got:\n%s\n' "${asset}" "${INSTALL_OUT}" >&2
      exit 1
      ;;
  esac
done


# ─────────────────────────────────────────────────────────────────────────
# Case 6: warm_whatsapp_bridge_install is a no-op when the bridge isn't
# staged (bundle without WhatsApp support shouldn't fail provisioning).
# ─────────────────────────────────────────────────────────────────────────
WARM_HARNESS="${TMP}/warm_harness.sh"
WARM_HOME="${TMP}/warm-home/.monoclaw"
mkdir -p "${WARM_HOME}/vendor"  # no whatsapp-bridge subtree

cat > "${WARM_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${WARM_HOME}"; }
have_command() { return 0; }  # pretend npm is present
$(awk '/^warm_whatsapp_bridge_install\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
warm_whatsapp_bridge_install
HARNESS_EOF
chmod +x "${WARM_HARNESS}"

WARM_OUT="$(bash "${WARM_HARNESS}" 2>&1)"
case "${WARM_OUT}" in
  *"WhatsApp bridge not staged"*) ;;
  *)
    printf 'fail: warm_whatsapp_bridge_install did not log skip when bridge absent. got:\n%s\n' "${WARM_OUT}" >&2
    exit 1
    ;;
esac


# ─────────────────────────────────────────────────────────────────────────
# Case 7: warm_whatsapp_bridge_install is idempotent (already-installed
# node_modules is a clean no-op, no npm exec).
# ─────────────────────────────────────────────────────────────────────────
IDEM_HOME="${TMP}/idem-home/.monoclaw"
mkdir -p "${IDEM_HOME}/vendor/whatsapp-bridge/node_modules"
printf '{}' > "${IDEM_HOME}/vendor/whatsapp-bridge/package.json"

IDEM_HARNESS="${TMP}/idem_harness.sh"
cat > "${IDEM_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${IDEM_HOME}"; }
have_command() { return 0; }
npm() { printf 'fail: npm was invoked despite existing node_modules\n' >&2; exit 99; }
$(awk '/^warm_whatsapp_bridge_install\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
warm_whatsapp_bridge_install
HARNESS_EOF
chmod +x "${IDEM_HARNESS}"
IDEM_OUT="$(bash "${IDEM_HARNESS}" 2>&1)"
case "${IDEM_OUT}" in
  *"already present"*) ;;
  *)
    printf 'fail: warm_whatsapp_bridge_install did not detect existing node_modules. got:\n%s\n' "${IDEM_OUT}" >&2
    exit 1
    ;;
esac


# ─────────────────────────────────────────────────────────────────────────
# Case 8: warm_whatsapp_bridge_install is non-fatal when npm is missing
# (default behaviour) but DOES die when HATCH_REQUIRE_WHATSAPP_BRIDGE_INSTALL=1.
# ─────────────────────────────────────────────────────────────────────────
NO_NPM_HOME="${TMP}/no-npm-home/.monoclaw"
mkdir -p "${NO_NPM_HOME}/vendor/whatsapp-bridge"
printf '{}' > "${NO_NPM_HOME}/vendor/whatsapp-bridge/package.json"

NO_NPM_HARNESS="${TMP}/no_npm_harness.sh"
cat > "${NO_NPM_HARNESS}" <<HARNESS_EOF
#!/usr/bin/env bash
set -euo pipefail
. "${ROOT}/lib/common.sh"
HATCH_DRY_RUN="false"
export HATCH_DRY_RUN
monoclaw_home() { printf '%s' "${NO_NPM_HOME}"; }
have_command() { return 1; }  # pretend npm is NOT present
$(awk '/^warm_whatsapp_bridge_install\(\) \{$/,/^\}$/' "${ROOT}/bin/hatch")
warm_whatsapp_bridge_install
HARNESS_EOF
chmod +x "${NO_NPM_HARNESS}"

# Default: warns but returns 0.
NO_NPM_OUT="$(bash "${NO_NPM_HARNESS}" 2>&1)"
case "${NO_NPM_OUT}" in
  *"npm not on PATH"*) ;;
  *)
    printf 'fail: warm_whatsapp_bridge_install did not warn about missing npm. got:\n%s\n' "${NO_NPM_OUT}" >&2
    exit 1
    ;;
esac

# Strict mode: dies.
if HATCH_REQUIRE_WHATSAPP_BRIDGE_INSTALL=1 bash "${NO_NPM_HARNESS}" 2>/dev/null; then
  printf 'fail: warm_whatsapp_bridge_install exited 0 in strict mode without npm\n' >&2
  exit 1
fi


printf 'ok: hatch_node_subsystems_tests passed (8 cases)\n'
