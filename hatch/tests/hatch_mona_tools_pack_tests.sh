#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PACK="${TMP}/tool-packs/mona-secretary-tools"
HOME_DIR="${TMP}/home"
mkdir -p \
  "${PACK}/bin" \
  "${PACK}/go/wacrawl" \
  "${PACK}/go/slacrawl" \
  "${PACK}/node/current/bin" \
  "${PACK}/node/apps/macos-automator-mcp/dist" \
  "${PACK}/plugins/mona-secretary-tools" \
  "${PACK}/config" \
  "${PACK}/docs" \
  "${HOME_DIR}"

cat > "${PACK}/bin/wacrawl" <<'SH'
#!/usr/bin/env bash
printf 'wacrawl placeholder\n'
SH
chmod +x "${PACK}/bin/wacrawl"
printf 'go wacrawl payload\n' > "${PACK}/go/wacrawl/README.txt"
printf 'go slacrawl payload\n' > "${PACK}/go/slacrawl/README.txt"
cat > "${PACK}/node/current/bin/node" <<'SH'
#!/usr/bin/env bash
printf 'v26.0.0\n'
SH
chmod +x "${PACK}/node/current/bin/node"
printf 'automator placeholder\n' > "${PACK}/node/apps/macos-automator-mcp/dist/server.js"
printf 'plugin: mona-secretary-tools\n' > "${PACK}/plugins/mona-secretary-tools/plugin.yaml"
printf 'mcp_servers: {}\n' > "${PACK}/config/mcp_servers.mona.example.yaml"
printf '# Mona tools\n' > "${PACK}/docs/README.md"
printf '# Permissions\n' > "${PACK}/docs/permissions.md"

python3 "${ROOT}/scripts/generate_tools_pack_manifest.py" \
  --tools-pack-root "${PACK}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tool "wacrawl:0.1.0:bin/wacrawl:default:full-disk-access" \
  --tool "macos-automator-mcp:0.4.1:node/apps/macos-automator-mcp/dist/server.js:opt-in:automation,accessibility"

test -f "${PACK}/tools-pack-manifest.json"

printf 'finder metadata\n' > "${PACK}/.DS_Store"
printf 'appledouble metadata\n' > "${PACK}/._mona"
mkdir -p "${PACK}/__MACOSX" "${PACK}/.Spotlight-V100" "${PACK}/.fseventsd" "${PACK}/.Trashes"
printf 'archive metadata\n' > "${PACK}/__MACOSX/._mona"
printf 'spotlight metadata\n' > "${PACK}/.Spotlight-V100/store"
printf 'fsevents metadata\n' > "${PACK}/.fseventsd/events"
printf 'trash metadata\n' > "${PACK}/.Trashes/501"

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --tools-pack-root "${PACK}" verify-tools-pack | tee "${TMP}/verify-pack.out"
grep -q "Tools pack verified for mona-secretary-tools" "${TMP}/verify-pack.out"

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --tools-pack-root "${PACK}" install-tools | tee "${TMP}/install-tools.out"
grep -q "dry-run: rm -rf ${HOME_DIR}/.monoclaw/vendor/mona-tools" "${TMP}/install-tools.out"
grep -q "dry-run: mkdir -p ${HOME_DIR}/.monoclaw/vendor" "${TMP}/install-tools.out"
grep -q "dry-run: cp -R ${PACK} ${HOME_DIR}/.monoclaw/vendor/mona-tools" "${TMP}/install-tools.out"
grep -q "dry-run: install Mona secretary plugins into ${HOME_DIR}/.monoclaw/plugins" "${TMP}/install-tools.out"
grep -q "manual: review ${HOME_DIR}/.monoclaw/vendor/mona-tools/docs/permissions.md before enabling host automation tools" "${TMP}/install-tools.out"
grep -q "next: technician provision complete; end user runs: monoclaw onboard" "${TMP}/install-tools.out"
if grep -q "plugins.enabled" "${TMP}/install-tools.out"; then
  printf 'install-tools should not activate Mona plugins; run monoclaw setup system for reviewed activation\n' >&2
  exit 1
fi
grep -q '_available("wacrawl")' "${ROOT}/bundle-inputs/vendor/mona-tools/templates/plugins/mona-secretary-tools/__init__.py"
grep -q "kind: standalone" "${ROOT}/bundle-inputs/vendor/mona-tools/templates/plugins/mona-secretary-tools/plugin.yaml"
python3 - "${ROOT}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
source_lock = json.loads((root / "bundle-inputs/vendor/mona-tools/source-lock.json").read_text())
source_tools = {tool["name"]: tool for tool in source_lock["tools"]}
vox = source_tools["vox"]
assert vox["mode"] == "node-app"
assert vox["activation"] == "opt-in"
assert vox["optional"] is True
assert vox["entrypoint"] == "dist/cli.js"
assert vox["build"]["type"] == "node"
assert vox["build"]["package_manager"] == "pnpm"
assert "telecom-consent" in vox["required_permissions"]

for name in ("brabble", "sweetlink", "birdclaw"):
    tool = source_tools[name]
    assert tool["mode"] == "deferred"
    assert tool["activation"] == "deferred"
    assert isinstance(tool.get("promotion_gates"), list) and tool["promotion_gates"]

example = json.loads((root / "bundle-inputs/vendor/mona-tools/tool-lock.example.json").read_text())
example_tools = {tool["name"]: tool for tool in example["tools"]}
assert example_tools["vox"]["path"] == "node/apps/vox/dist/cli.js"
assert example_tools["vox"]["activation"] == "opt-in"

secretary = (root / "bundle-inputs/vendor/mona-tools/templates/config/secretary-tools.example.yaml").read_text()
assert "vox_phone_bridge:" in secretary
assert "command: \"~/.monoclaw/vendor/mona-tools/bin/vox\"" in secretary

readme = (root / "bundle-inputs/vendor/mona-tools/templates/docs/README.md").read_text()
assert "vox" in readme
assert "Twilio Media Streams" in readme
PY

PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --apply --tools-pack-root "${PACK}" install-tools | tee "${TMP}/apply-tools.out"
test -f "${HOME_DIR}/.monoclaw/vendor/mona-tools/tools-pack-manifest.json"
test -x "${HOME_DIR}/.monoclaw/vendor/mona-tools/bin/wacrawl"
test ! -d "${PACK}/skills"
test -f "${HOME_DIR}/.monoclaw/plugins/mona-secretary-tools/plugin.yaml"
grep -q "Mona secretary tools installed" "${TMP}/apply-tools.out"
test ! -f "${HOME_DIR}/.monoclaw/config.yaml"

printf 'existing plugin\n' > "${HOME_DIR}/.monoclaw/plugins/mona-secretary-tools/plugin.yaml"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --apply --tools-pack-root "${PACK}" install-tools >"${TMP}/apply-tools-again.out"
grep -q "Keeping existing plugin ${HOME_DIR}/.monoclaw/plugins/mona-secretary-tools" "${TMP}/apply-tools-again.out"
grep -q "existing plugin" "${HOME_DIR}/.monoclaw/plugins/mona-secretary-tools/plugin.yaml"

DISABLE_HOME="${TMP}/home-plugin-disabled"
mkdir -p "${DISABLE_HOME}/.monoclaw"
cat > "${DISABLE_HOME}/.monoclaw/config.yaml" <<'EOF'
plugins:
  disabled:
    - mona-secretary-tools
EOF
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${DISABLE_HOME}" \
  bash "${ROOT}/bin/hatch" --apply --tools-pack-root "${PACK}" install-tools | tee "${TMP}/install-tools-disabled.out"
grep -Fq "disabled:" "${DISABLE_HOME}/.monoclaw/config.yaml"
test "$(grep -c "mona-secretary-tools" "${DISABLE_HOME}/.monoclaw/config.yaml" || true)" -eq 1

printf 'real stray file\n' > "${PACK}/notes.txt"
if PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --tools-pack-root "${PACK}" verify-tools-pack >"${TMP}/unlisted.out" 2>&1; then
  printf 'expected tools pack verification to fail for an unlisted payload file\n' >&2
  exit 1
fi
grep -q "tools pack file is not listed in manifest artifacts: notes.txt" "${TMP}/unlisted.out"
rm "${PACK}/notes.txt"

python3 - "${PACK}/tools-pack-manifest.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["artifacts"][0]["path"] = "../escape"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --tools-pack-root "${PACK}" verify-tools-pack >"${TMP}/escape.out" 2>&1; then
  printf 'expected tools pack verification to fail for path escape\n' >&2
  exit 1
fi
grep -q "tools pack path escapes pack root" "${TMP}/escape.out"

python3 "${ROOT}/scripts/generate_tools_pack_manifest.py" \
  --tools-pack-root "${PACK}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tool "wacrawl:0.1.0:bin/wacrawl:default:full-disk-access"

printf 'tampered\n' > "${PACK}/bin/wacrawl"
if PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${ROOT}/bin/hatch" --dry-run --tools-pack-root "${PACK}" verify-tools-pack >"${TMP}/tamper.out" 2>&1; then
  printf 'expected tools pack verification to fail after tamper\n' >&2
  exit 1
fi
grep -Eq "tools pack file (byte size|sha256) mismatch" "${TMP}/tamper.out"

BUILD_INPUTS="${TMP}/build-inputs"
BUILD_PACK_ROOT="${TMP}/built-tool-packs"
mkdir -p \
  "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/bin" \
  "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/node/current/bin" \
  "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp/dist" \
  "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/node/apps/vox/dist" \
  "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/config" \
  "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/plugins/mona-secretary-tools" \
  "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/docs"

cat > "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/bin/wacrawl" <<'SH'
#!/usr/bin/env bash
printf 'wacrawl fixture\n'
SH
chmod +x "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/bin/wacrawl"
cat > "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/node/current/bin/node" <<'SH'
#!/usr/bin/env bash
printf 'v26.0.0\n'
SH
chmod +x "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/node/current/bin/node"
printf 'server fixture\n' > "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp/dist/server.js"
printf 'vox cli fixture\n' > "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/node/apps/vox/dist/cli.js"
printf '# permissions\n' > "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/docs/permissions.md"
printf 'mcp_servers: {}\n' > "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/config/mcp_servers.mona.example.yaml"
printf 'name: mona-secretary-tools\n' > "${BUILD_INPUTS}/vendor/mona-tools/prebuilt/plugins/mona-secretary-tools/plugin.yaml"
cat > "${BUILD_INPUTS}/vendor/mona-tools/tool-lock.json" <<'JSON'
{
  "schema_version": 1,
  "pack": {
    "id": "mona-secretary-tools",
    "version": "0.1.0"
  },
  "node": {
    "version": "26.0.0",
    "source": "vendor/mona-tools/prebuilt/node/current"
  },
  "tools": [
    {
      "name": "wacrawl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/wacrawl",
      "source_ref": "test-fixture",
      "mode": "go-binary",
      "source": "vendor/mona-tools/prebuilt/bin/wacrawl",
      "path": "bin/wacrawl",
      "activation": "default",
      "required_permissions": ["full-disk-access"]
    },
    {
      "name": "macos-automator-mcp",
      "version": "0.4.1",
      "license": "MIT",
      "repository": "https://github.com/steipete/macos-automator-mcp",
      "source_ref": "test-fixture",
      "mode": "node-app",
      "source": "vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp",
      "path": "node/apps/macos-automator-mcp/dist/server.js",
      "activation": "opt-in",
      "required_permissions": ["automation", "accessibility"]
    },
    {
      "name": "vox",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/vox",
      "source_ref": "test-fixture",
      "mode": "node-app",
      "source": "vendor/mona-tools/prebuilt/node/apps/vox",
      "path": "node/apps/vox/dist/cli.js",
      "activation": "opt-in",
      "required_permissions": ["network", "telecom-consent"]
    },
    {
      "name": "brabble",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/brabble",
      "source_ref": "test-fixture",
      "mode": "deferred",
      "activation": "deferred",
      "required_permissions": ["microphone", "launchd"],
      "promotion_gates": ["signed native binaries", "launchd tests"]
    }
  ],
  "extra_artifacts": [
    {
      "source": "vendor/mona-tools/prebuilt/docs",
      "path": "docs"
    },
    {
      "source": "vendor/mona-tools/prebuilt/config",
      "path": "config"
    },
    {
      "source": "vendor/mona-tools/prebuilt/plugins",
      "path": "plugins"
    }
  ]
}
JSON

HATCH_INCLUDE_MONA_TOOLS=0 \
HATCH_INPUT_ROOT="${BUILD_INPUTS}" \
HATCH_TOOLS_PACKS_ROOT="${BUILD_PACK_ROOT}" \
  bash "${ROOT}/scripts/build_mona_tools_pack.sh" | tee "${TMP}/build-disabled.out"
grep -q "Mona secretary tools pack disabled" "${TMP}/build-disabled.out"
test ! -d "${BUILD_PACK_ROOT}/mona-secretary-tools"

MISSING_INPUTS="${TMP}/missing-inputs"
mkdir -p "${MISSING_INPUTS}/vendor/mona-tools"
if HATCH_INPUT_ROOT="${MISSING_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${BUILD_PACK_ROOT}" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/build-missing-lock.out" 2>&1; then
  printf 'expected Mona tools pack build to fail without tool-lock.json and source-lock\n' >&2
  exit 1
fi
grep -q "Mona tools source lock is required" "${TMP}/build-missing-lock.out"
grep -q "running prepare_mona_tools_inputs.sh" "${TMP}/build-missing-lock.out"

NODE_PREFLIGHT_INPUTS="${TMP}/node-preflight-inputs"
mkdir -p "${NODE_PREFLIGHT_INPUTS}/vendor/mona-tools"
cat > "${NODE_PREFLIGHT_INPUTS}/vendor/mona-tools/source-lock.json" <<'NODEJSON'
{
  "schema_version": 1,
  "pack": {
    "id": "mona-secretary-tools",
    "version": "0.1.0"
  },
  "node": {
    "version": "26.0.0",
    "source_env": "HATCH_MONA_NODE_RUNTIME_SOURCE"
  },
  "tools": [
    {
      "name": "fixture-node-app",
      "version": "1.0.0",
      "license": "MIT",
      "repository": "https://example.com/fixture-repo",
      "ref": "0000000000000000000000000000000000000000",
      "mode": "node-app",
      "activation": "default",
      "required_permissions": ["network"],
      "entrypoint": "dist/cli.js",
      "build": {
        "type": "node",
        "package_manager": "pnpm",
        "install": ["pnpm", "install"],
        "build": ["pnpm", "run", "build"]
      }
    }
  ]
}
NODEJSON

if env -u HATCH_MONA_NODE_RUNTIME_SOURCE \
  HATCH_MONA_NODE_AUTO_DOWNLOAD=0 \
  HATCH_INPUT_ROOT="${NODE_PREFLIGHT_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${BUILD_PACK_ROOT}" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/build-node-preflight.out" 2>&1; then
  printf 'expected Mona tools pack build to fail Node runtime preflight without HATCH_MONA_NODE_RUNTIME_SOURCE\n' >&2
  exit 1
fi
grep -q '\[mona-tools\] Mona tools packing needs a Darwin Node unpack directory' "${TMP}/build-node-preflight.out"
grep -q 'HATCH_INCLUDE_MONA_TOOLS=0' "${TMP}/build-node-preflight.out"
grep -q 'HATCH_MONA_NODE_RUNTIME_SOURCE' "${TMP}/build-node-preflight.out"
grep -q 'HATCH_MONA_NODE_AUTO_DOWNLOAD=0' "${TMP}/build-node-preflight.out"
if grep -q '\[mona-tools-prep\]' "${TMP}/build-node-preflight.out"; then
  printf 'expected prepare_mona_tools_inputs.sh not to run after Node runtime preflight failure\n' >&2
  exit 1
fi
test ! -f "${NODE_PREFLIGHT_INPUTS}/vendor/mona-tools/tool-lock.json"
PREP_INPUTS="${TMP}/prep-inputs"
PREP_FIXTURES="${TMP}/prep-fixtures"
PREP_PACK_ROOT="${TMP}/prep-tool-packs"
mkdir -p \
  "${PREP_INPUTS}/vendor/mona-tools" \
  "${PREP_FIXTURES}/node/current/bin" \
  "${PREP_FIXTURES}/bin" \
  "${PREP_FIXTURES}/apps/macos-automator-mcp/dist" \
  "${PREP_FIXTURES}/apps/vox/dist" \
  "${PREP_FIXTURES}/docs" \
  "${PREP_FIXTURES}/config" \
  "${PREP_FIXTURES}/plugins/mona-secretary-tools"
cat > "${PREP_FIXTURES}/node/current/bin/node" <<'SH'
#!/usr/bin/env bash
printf 'v26.0.0\n'
SH
chmod +x "${PREP_FIXTURES}/node/current/bin/node"
cat > "${PREP_FIXTURES}/bin/wacrawl" <<'SH'
#!/usr/bin/env bash
printf 'wacrawl fixture\n'
SH
chmod +x "${PREP_FIXTURES}/bin/wacrawl"
printf 'server fixture\n' > "${PREP_FIXTURES}/apps/macos-automator-mcp/dist/server.js"
printf 'vox cli fixture\n' > "${PREP_FIXTURES}/apps/vox/dist/cli.js"
printf '# prep permissions\n' > "${PREP_FIXTURES}/docs/permissions.md"
printf 'mcp_servers: {}\n' > "${PREP_FIXTURES}/config/mcp_servers.mona.example.yaml"
printf 'name: mona-secretary-tools\n' > "${PREP_FIXTURES}/plugins/mona-secretary-tools/plugin.yaml"
cat > "${PREP_INPUTS}/vendor/mona-tools/source-lock.json" <<JSON
{
  "schema_version": 1,
  "pack": {
    "id": "mona-secretary-tools",
    "version": "0.1.0"
  },
  "node": {
    "version": "26.0.0",
    "source": "${PREP_FIXTURES}/node/current"
  },
  "tools": [
    {
      "name": "wacrawl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/wacrawl",
      "ref": "fixture-wacrawl-ref",
      "mode": "go-binary",
      "activation": "default",
      "required_permissions": ["full-disk-access"],
      "build": {
        "type": "copy",
        "source": "${PREP_FIXTURES}/bin/wacrawl"
      }
    },
    {
      "name": "macos-automator-mcp",
      "version": "0.4.1",
      "license": "MIT",
      "repository": "https://github.com/steipete/macos-automator-mcp",
      "ref": "fixture-automator-ref",
      "mode": "node-app",
      "activation": "opt-in",
      "required_permissions": ["automation", "accessibility"],
      "entrypoint": "dist/server.js",
      "build": {
        "type": "copy",
        "source": "${PREP_FIXTURES}/apps/macos-automator-mcp"
      }
    },
    {
      "name": "vox",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/vox",
      "ref": "fixture-vox-ref",
      "mode": "node-app",
      "activation": "opt-in",
      "optional": true,
      "required_permissions": ["network", "telecom-consent"],
      "entrypoint": "dist/cli.js",
      "build": {
        "type": "copy",
        "source": "${PREP_FIXTURES}/apps/vox"
      }
    },
    {
      "name": "brabble",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/brabble",
      "ref": "fixture-brabble-ref",
      "mode": "deferred",
      "activation": "deferred",
      "required_permissions": ["microphone", "launchd"],
      "promotion_gates": ["signed native binaries", "launchd tests"]
    }
  ],
  "extra_artifacts": [
    {
      "source": "${PREP_FIXTURES}/docs",
      "path": "docs"
    },
    {
      "source": "${PREP_FIXTURES}/config",
      "path": "config"
    },
    {
      "source": "${PREP_FIXTURES}/plugins",
      "path": "plugins"
    }
  ]
}
JSON

AUTO_PREP_INPUTS="${TMP}/auto-prep-inputs"
AUTO_PREP_BUILD="${TMP}/auto-prep-mona-sources"
AUTO_PREP_PACKS="${TMP}/auto-prep-tool-packs"
mkdir -p "${AUTO_PREP_INPUTS}/vendor/mona-tools"
cat > "${AUTO_PREP_INPUTS}/vendor/mona-tools/source-lock.json" <<JSON
{
  "schema_version": 1,
  "pack": {
    "id": "mona-secretary-tools",
    "version": "0.1.0"
  },
  "node": {
    "version": "26.0.0",
    "source": "${PREP_FIXTURES}/node/current"
  },
  "tools": [
    {
      "name": "wacrawl",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/wacrawl",
      "ref": "fixture-wacrawl-ref",
      "mode": "go-binary",
      "activation": "default",
      "required_permissions": ["full-disk-access"],
      "build": {
        "type": "copy",
        "source": "${PREP_FIXTURES}/bin/wacrawl"
      }
    },
    {
      "name": "macos-automator-mcp",
      "version": "0.4.1",
      "license": "MIT",
      "repository": "https://github.com/steipete/macos-automator-mcp",
      "ref": "fixture-automator-ref",
      "mode": "node-app",
      "activation": "opt-in",
      "required_permissions": ["automation", "accessibility"],
      "entrypoint": "dist/server.js",
      "build": {
        "type": "copy",
        "source": "${PREP_FIXTURES}/apps/macos-automator-mcp"
      }
    },
    {
      "name": "vox",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/vox",
      "ref": "fixture-vox-ref",
      "mode": "node-app",
      "activation": "opt-in",
      "optional": true,
      "required_permissions": ["network", "telecom-consent"],
      "entrypoint": "dist/cli.js",
      "build": {
        "type": "copy",
        "source": "${PREP_FIXTURES}/apps/vox"
      }
    },
    {
      "name": "brabble",
      "version": "0.1.0",
      "license": "MIT",
      "repository": "https://github.com/steipete/brabble",
      "ref": "fixture-brabble-ref",
      "mode": "deferred",
      "activation": "deferred",
      "required_permissions": ["microphone", "launchd"],
      "promotion_gates": ["signed native binaries", "launchd tests"]
    }
  ],
  "extra_artifacts": [
    {
      "source": "${PREP_FIXTURES}/docs",
      "path": "docs"
    },
    {
      "source": "${PREP_FIXTURES}/config",
      "path": "config"
    },
    {
      "source": "${PREP_FIXTURES}/plugins",
      "path": "plugins"
    }
  ]
}
JSON

rm -rf "${AUTO_PREP_BUILD}" "${AUTO_PREP_PACKS}"
mkdir -p "${AUTO_PREP_PACKS}"
HATCH_INPUT_ROOT="${AUTO_PREP_INPUTS}" \
HATCH_TOOLS_PACKS_ROOT="${AUTO_PREP_PACKS}" \
HATCH_MONA_TOOLS_BUILD_ROOT="${AUTO_PREP_BUILD}" \
  bash "${ROOT}/scripts/build_mona_tools_pack.sh" | tee "${TMP}/auto-prep-pack.out"
grep -q "running prepare_mona_tools_inputs.sh" "${TMP}/auto-prep-pack.out"
test -f "${AUTO_PREP_INPUTS}/vendor/mona-tools/tool-lock.json"
test -f "${AUTO_PREP_PACKS}/mona-secretary-tools/tools-pack-manifest.json"

HATCH_INPUT_ROOT="${PREP_INPUTS}" \
HATCH_MONA_TOOLS_FORCE=1 \
  bash "${ROOT}/scripts/prepare_mona_tools_inputs.sh" | tee "${TMP}/prepare-inputs.out"
test -f "${PREP_INPUTS}/vendor/mona-tools/tool-lock.json"
test -x "${PREP_INPUTS}/vendor/mona-tools/prebuilt/bin/wacrawl"
test -x "${PREP_INPUTS}/vendor/mona-tools/prebuilt/node/current/bin/node"
test -f "${PREP_INPUTS}/vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp/dist/server.js"
python3 - "${PREP_INPUTS}/vendor/mona-tools/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text())
assert lock["node"]["source"] == "vendor/mona-tools/prebuilt/node/current"
tools = {tool["name"]: tool for tool in lock["tools"]}
assert tools["wacrawl"]["source_ref"] == "fixture-wacrawl-ref"
assert tools["wacrawl"]["source"] == "vendor/mona-tools/prebuilt/bin/wacrawl"
assert tools["macos-automator-mcp"]["source_ref"] == "fixture-automator-ref"
assert tools["macos-automator-mcp"]["source"] == "vendor/mona-tools/prebuilt/node/apps/macos-automator-mcp"
assert tools["macos-automator-mcp"]["path"] == "node/apps/macos-automator-mcp/dist/server.js"
assert tools["vox"]["source_ref"] == "fixture-vox-ref"
assert tools["vox"]["source"] == "vendor/mona-tools/prebuilt/node/apps/vox"
assert tools["vox"]["path"] == "node/apps/vox/dist/cli.js"
assert tools["vox"]["activation"] == "opt-in"
assert tools["brabble"]["promotion_gates"] == ["signed native binaries", "launchd tests"]
PY
HATCH_INPUT_ROOT="${PREP_INPUTS}" \
HATCH_TOOLS_PACKS_ROOT="${PREP_PACK_ROOT}" \
  bash "${ROOT}/scripts/build_mona_tools_pack.sh" | tee "${TMP}/build-prepared.out"
test -f "${PREP_PACK_ROOT}/mona-secretary-tools/tools-pack-manifest.json"
test -x "${PREP_PACK_ROOT}/mona-secretary-tools/bin/vox"
test ! -e "${PREP_PACK_ROOT}/mona-secretary-tools/brabble"
grep -q "Tools pack verified for mona-secretary-tools" "${TMP}/build-prepared.out"

HATCH_INPUT_ROOT="${BUILD_INPUTS}" \
HATCH_TOOLS_PACKS_ROOT="${BUILD_PACK_ROOT}" \
  bash "${ROOT}/scripts/build_mona_tools_pack.sh" | tee "${TMP}/build-enabled.out"
BUILT_PACK="${BUILD_PACK_ROOT}/mona-secretary-tools"
test -x "${BUILT_PACK}/bin/wacrawl"
test -x "${BUILT_PACK}/bin/macos-automator-mcp"
test -x "${BUILT_PACK}/bin/vox"
test -f "${BUILT_PACK}/node/current/bin/node"
test -f "${BUILT_PACK}/node/apps/macos-automator-mcp/dist/server.js"
test -f "${BUILT_PACK}/node/apps/vox/dist/cli.js"
test -f "${BUILT_PACK}/docs/permissions.md"
test -f "${BUILT_PACK}/config/mcp_servers.mona.example.yaml"
test -f "${BUILT_PACK}/plugins/mona-secretary-tools/plugin.yaml"
test ! -d "${BUILT_PACK}/skills"
test ! -e "${BUILT_PACK}/brabble"
test -f "${BUILT_PACK}/tools-pack-manifest.json"
grep -q "Tools pack verified for mona-secretary-tools" "${TMP}/build-enabled.out"

PLACEHOLDER_INPUTS="${TMP}/placeholder-inputs"
cp -R "${BUILD_INPUTS}" "${PLACEHOLDER_INPUTS}"
python3 - "${PLACEHOLDER_INPUTS}/vendor/mona-tools/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["tools"][0]["source_ref"] = "replace-with-commit-or-release"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if HATCH_INPUT_ROOT="${PLACEHOLDER_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${TMP}/placeholder-pack-root" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/build-placeholder.out" 2>&1; then
  printf 'expected Mona tools pack build to fail for placeholder source_ref\n' >&2
  exit 1
fi
grep -q "Mona tools lock entry has placeholder source_ref" "${TMP}/build-placeholder.out"

DUPLICATE_NAME_INPUTS="${TMP}/duplicate-name-inputs"
cp -R "${BUILD_INPUTS}" "${DUPLICATE_NAME_INPUTS}"
python3 - "${DUPLICATE_NAME_INPUTS}/vendor/mona-tools/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["tools"][1]["name"] = "wacrawl"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if HATCH_INPUT_ROOT="${DUPLICATE_NAME_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${TMP}/duplicate-name-pack-root" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/build-duplicate-name.out" 2>&1; then
  printf 'expected Mona tools pack build to fail for duplicate tool names\n' >&2
  exit 1
fi
grep -q "Mona tools lock has duplicate tool name: wacrawl" "${TMP}/build-duplicate-name.out"

DUPLICATE_PATH_INPUTS="${TMP}/duplicate-path-inputs"
cp -R "${BUILD_INPUTS}" "${DUPLICATE_PATH_INPUTS}"
python3 - "${DUPLICATE_PATH_INPUTS}/vendor/mona-tools/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["tools"][1]["mode"] = "go-binary"
data["tools"][1]["source"] = "vendor/mona-tools/prebuilt/bin/wacrawl"
data["tools"][1]["path"] = "bin/wacrawl"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if HATCH_INPUT_ROOT="${DUPLICATE_PATH_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${TMP}/duplicate-path-pack-root" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/build-duplicate-path.out" 2>&1; then
  printf 'expected Mona tools pack build to fail for duplicate active paths\n' >&2
  exit 1
fi
grep -q "Mona tools lock has duplicate active path: bin/wacrawl" "${TMP}/build-duplicate-path.out"

MISSING_NODE_DECL_INPUTS="${TMP}/missing-node-decl-inputs"
cp -R "${BUILD_INPUTS}" "${MISSING_NODE_DECL_INPUTS}"
python3 - "${MISSING_NODE_DECL_INPUTS}/vendor/mona-tools/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["node"] = {}
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if HATCH_INPUT_ROOT="${MISSING_NODE_DECL_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${TMP}/missing-node-decl-pack-root" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/build-missing-node-decl.out" 2>&1; then
  printf 'expected Mona tools pack build to fail for node-app without node runtime declaration\n' >&2
  exit 1
fi
grep -q "Mona tools node runtime declaration is required when node-app tools are active" "${TMP}/build-missing-node-decl.out"

ESCAPE_INPUTS="${TMP}/escape-inputs"
cp -R "${BUILD_INPUTS}" "${ESCAPE_INPUTS}"
python3 - "${ESCAPE_INPUTS}/vendor/mona-tools/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["tools"][0]["path"] = "../outside"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if HATCH_INCLUDE_MONA_TOOLS=1 \
  HATCH_INPUT_ROOT="${ESCAPE_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${TMP}/escape-pack-root" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/build-escape.out" 2>&1; then
  printf 'expected Mona tools pack build to fail for destination escape\n' >&2
  exit 1
fi
grep -q "Mona tools destination escapes pack root" "${TMP}/build-escape.out"

NO_NODE_PACK="${TMP}/no-node-pack"
mkdir -p "${NO_NODE_PACK}/bin" "${NO_NODE_PACK}/docs" "${NO_NODE_PACK}/config" "${NO_NODE_PACK}/plugins/mona-secretary-tools"
printf 'binary\n' > "${NO_NODE_PACK}/bin/wacrawl"
printf '# permissions\n' > "${NO_NODE_PACK}/docs/permissions.md"
printf 'mcp_servers: {}\n' > "${NO_NODE_PACK}/config/mcp_servers.mona.example.yaml"
printf 'name: mona-secretary-tools\n' > "${NO_NODE_PACK}/plugins/mona-secretary-tools/plugin.yaml"
if python3 "${ROOT}/scripts/generate_tools_pack_manifest.py" \
  --tools-pack-root "${NO_NODE_PACK}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tool "wacrawl:0.1.0:bin/wacrawl:default:full-disk-access" >"${TMP}/no-node.out" 2>&1; then
  printf 'expected tools pack manifest generation to fail without bundled node\n' >&2
  exit 1
fi
grep -q "tools pack node runtime missing" "${TMP}/no-node.out"
