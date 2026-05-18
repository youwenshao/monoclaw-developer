#!/usr/bin/env bash
# Tests for the verify_command contract on optional tools packs.
#
# Covers:
#   - JSON --tools-file roundtrip with verify_command/verify_strict/verify_env/
#     verify_skip_reason
#   - successful probe (exit 0) emits no warn
#   - strict-true probe that exits non-zero fails the verifier
#   - strict-false probe that exits non-zero warns but does not fail
#   - verify_skip_reason silences the "no verify_command" warn (info instead)
#   - missing verify_command + missing skip_reason warns by default and fails
#     under HATCH_TOOLS_PACK_STRICT_VERIFY=1
#   - verify_command + verify_skip_reason together is rejected at generation
#   - verify_env values reach the probe subprocess
#   - legacy colon --tool path still works (with deprecation warning)
#   - --tool + --tools-file together is rejected
#
# Test isolation: every fixture lives under "${TMP}" and runs hatch with
# PATH="/usr/bin:/bin:/usr/sbin:/sbin" + HOME="${HOME_DIR}" so the host's
# brew/python/node never leak in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

HOME_DIR="${TMP}/home"
mkdir -p "${HOME_DIR}"
HATCH_BIN="${ROOT}/bin/hatch"
GEN="${ROOT}/scripts/generate_tools_pack_manifest.py"

# Shared helper that scaffolds a minimal Mona-shaped tools pack on disk and
# returns the pack root.
scaffold_pack() {
  local pack_root="$1"
  mkdir -p \
    "${pack_root}/bin" \
    "${pack_root}/node/current/bin" \
    "${pack_root}/docs" \
    "${pack_root}/config" \
    "${pack_root}/plugins/mona-secretary-tools"
  cat > "${pack_root}/bin/exit-zero" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "${pack_root}/bin/exit-one" <<'SH'
#!/usr/bin/env bash
echo "simulated failure" >&2
exit 1
SH
  cat > "${pack_root}/bin/check-env" <<'SH'
#!/usr/bin/env bash
# Succeeds only when VERIFY_PROBE_TOKEN matches the expected fixture value.
if [[ "${VERIFY_PROBE_TOKEN:-}" == "expected-token" ]]; then
  exit 0
fi
echo "VERIFY_PROBE_TOKEN was '${VERIFY_PROBE_TOKEN:-<unset>}', expected 'expected-token'" >&2
exit 1
SH
  chmod +x \
    "${pack_root}/bin/exit-zero" \
    "${pack_root}/bin/exit-one" \
    "${pack_root}/bin/check-env"
  cat > "${pack_root}/node/current/bin/node" <<'SH'
#!/usr/bin/env bash
printf 'v26.0.0\n'
SH
  chmod +x "${pack_root}/node/current/bin/node"
  printf '# permissions\n' > "${pack_root}/docs/permissions.md"
  printf 'mcp_servers: {}\n' > "${pack_root}/config/mcp_servers.mona.example.yaml"
  printf 'name: mona-secretary-tools\n' > "${pack_root}/plugins/mona-secretary-tools/plugin.yaml"
}

# CASE 1 — JSON --tools-file roundtrip
PACK1="${TMP}/pack-json-roundtrip"
scaffold_pack "${PACK1}"
cat > "${PACK1}.tools.json" <<'JSON'
[
  {
    "name": "exit-zero",
    "version": "1.0.0",
    "path": "bin/exit-zero",
    "activation": "default",
    "required_permissions": ["network"],
    "verify_command": ["{bin}"],
    "verify_strict": true
  },
  {
    "name": "exit-one",
    "version": "1.0.0",
    "path": "bin/exit-one",
    "activation": "opt-in",
    "required_permissions": ["filesystem"],
    "verify_skip_reason": "Deliberately skipped for this fixture."
  }
]
JSON
python3 "${GEN}" \
  --tools-pack-root "${PACK1}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK1}.tools.json"
python3 - "${PACK1}/tools-pack-manifest.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tools = {tool["name"]: tool for tool in data["tools"]}
assert tools["exit-zero"]["verify_command"] == ["{bin}"], tools["exit-zero"]
assert tools["exit-zero"]["verify_strict"] is True, tools["exit-zero"]
assert "verify_skip_reason" not in tools["exit-zero"], tools["exit-zero"]
assert tools["exit-one"]["verify_skip_reason"] == "Deliberately skipped for this fixture.", tools["exit-one"]
assert "verify_command" not in tools["exit-one"], tools["exit-one"]
PY

# CASE 2 — verify succeeds (exit 0): no warnings, no failure
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK1}" verify-tools-pack 2>"${TMP}/case2.err" | tee "${TMP}/case2.out"
grep -q "Tools pack verified for mona-secretary-tools" "${TMP}/case2.out"
if grep -q "verify_command exited" "${TMP}/case2.err"; then
  printf 'unexpected verify_command warn for exit-zero fixture\n' >&2
  exit 1
fi
grep -q "info: exit-one verify skipped: Deliberately skipped" "${TMP}/case2.err"

# CASE 3 — strict-true probe that exits non-zero fails (even in lenient install
# context, because strict-true means "binary is supposed to be self-contained")
PACK3="${TMP}/pack-strict-fail"
scaffold_pack "${PACK3}"
cat > "${PACK3}.tools.json" <<'JSON'
[
  {
    "name": "exit-one",
    "version": "1.0.0",
    "path": "bin/exit-one",
    "activation": "default",
    "required_permissions": ["network"],
    "verify_command": ["{bin}"],
    "verify_strict": true
  }
]
JSON
python3 "${GEN}" \
  --tools-pack-root "${PACK3}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK3}.tools.json"
if PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK3}" verify-tools-pack >"${TMP}/case3.out" 2>"${TMP}/case3.err"; then
  printf 'expected strict-true + exit-1 to fail verification\n' >&2
  cat "${TMP}/case3.err" >&2
  exit 1
fi
grep -q "strict probe, no host-permission dependency expected" "${TMP}/case3.err"

# CASE 4 — strict-false probe that exits non-zero warns but does not fail
PACK4="${TMP}/pack-lenient-warn"
scaffold_pack "${PACK4}"
cat > "${PACK4}.tools.json" <<'JSON'
[
  {
    "name": "exit-one",
    "version": "1.0.0",
    "path": "bin/exit-one",
    "activation": "default",
    "required_permissions": ["network"],
    "verify_command": ["{bin}"],
    "verify_strict": false
  }
]
JSON
python3 "${GEN}" \
  --tools-pack-root "${PACK4}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK4}.tools.json"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK4}" verify-tools-pack >"${TMP}/case4.out" 2>"${TMP}/case4.err"
grep -q "Tools pack verified" "${TMP}/case4.out"
grep -q "warn: exit-one verify_command exited 1" "${TMP}/case4.err"

# CASE 5 — missing verify_command + missing skip_reason → warn (lenient),
# fail (strict).
PACK5="${TMP}/pack-missing"
scaffold_pack "${PACK5}"
cat > "${PACK5}.tools.json" <<'JSON'
[
  {
    "name": "exit-zero",
    "version": "1.0.0",
    "path": "bin/exit-zero",
    "activation": "default",
    "required_permissions": ["network"]
  }
]
JSON
python3 "${GEN}" \
  --tools-pack-root "${PACK5}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK5}.tools.json"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK5}" verify-tools-pack >"${TMP}/case5-lenient.out" 2>"${TMP}/case5-lenient.err"
grep -q "Tools pack verified" "${TMP}/case5-lenient.out"
grep -q "warn: exit-zero has no verify_command in manifest" "${TMP}/case5-lenient.err"
if HATCH_TOOLS_PACK_STRICT_VERIFY=1 \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
    bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK5}" verify-tools-pack >"${TMP}/case5-strict.out" 2>"${TMP}/case5-strict.err"; then
  printf 'expected strict mode to fail when verify_command is missing\n' >&2
  cat "${TMP}/case5-strict.err" >&2
  exit 1
fi
grep -q "HATCH_TOOLS_PACK_STRICT_VERIFY=1" "${TMP}/case5-strict.err"

# CASE 6 — verify_command + verify_skip_reason together: rejected at manifest
# generation time.
PACK6="${TMP}/pack-both-fields"
scaffold_pack "${PACK6}"
cat > "${PACK6}.tools.json" <<'JSON'
[
  {
    "name": "exit-zero",
    "version": "1.0.0",
    "path": "bin/exit-zero",
    "activation": "default",
    "required_permissions": ["network"],
    "verify_command": ["{bin}"],
    "verify_skip_reason": "should not be allowed alongside verify_command"
  }
]
JSON
if python3 "${GEN}" \
  --tools-pack-root "${PACK6}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK6}.tools.json" >"${TMP}/case6.out" 2>"${TMP}/case6.err"; then
  printf 'expected manifest generation to reject verify_command + verify_skip_reason\n' >&2
  exit 1
fi
grep -q "mutually exclusive" "${TMP}/case6.err"

# CASE 7 — verify_env is applied to the probe subprocess. The check-env binary
# only exits 0 when VERIFY_PROBE_TOKEN matches; this proves the env reaches
# the probe and also guards against accidental env-stripping later.
PACK7="${TMP}/pack-verify-env"
scaffold_pack "${PACK7}"
cat > "${PACK7}.tools.json" <<'JSON'
[
  {
    "name": "check-env",
    "version": "1.0.0",
    "path": "bin/check-env",
    "activation": "default",
    "required_permissions": ["network"],
    "verify_command": ["{bin}"],
    "verify_strict": true,
    "verify_env": { "VERIFY_PROBE_TOKEN": "expected-token" }
  }
]
JSON
python3 "${GEN}" \
  --tools-pack-root "${PACK7}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK7}.tools.json"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK7}" verify-tools-pack >"${TMP}/case7.out" 2>"${TMP}/case7.err"
grep -q "Tools pack verified" "${TMP}/case7.out"
# Sanity check that the manifest preserved the verify_env override.
python3 - "${PACK7}/tools-pack-manifest.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tool = data["tools"][0]
assert tool["verify_env"] == {"VERIFY_PROBE_TOKEN": "expected-token"}, tool
PY

# CASE 8 — legacy colon --tool still works (with deprecation warning)
PACK8="${TMP}/pack-legacy-colon"
scaffold_pack "${PACK8}"
python3 "${GEN}" \
  --tools-pack-root "${PACK8}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tool "exit-zero:1.0.0:bin/exit-zero:default:network" 2>"${TMP}/case8.err"
grep -q "colon-encoded.*deprecated" "${TMP}/case8.err"
PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
  bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK8}" verify-tools-pack >"${TMP}/case8-verify.out" 2>"${TMP}/case8-verify.err"
grep -q "Tools pack verified" "${TMP}/case8-verify.out"
grep -q "warn: exit-zero has no verify_command in manifest" "${TMP}/case8-verify.err"

# CASE 9 — --tool AND --tools-file together is rejected
PACK9="${TMP}/pack-both-args"
scaffold_pack "${PACK9}"
cat > "${PACK9}.tools.json" <<'JSON'
[
  {
    "name": "exit-zero",
    "version": "1.0.0",
    "path": "bin/exit-zero",
    "activation": "default",
    "required_permissions": ["network"]
  }
]
JSON
if python3 "${GEN}" \
  --tools-pack-root "${PACK9}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK9}.tools.json" \
  --tool "exit-zero:1.0.0:bin/exit-zero:default:network" >"${TMP}/case9.out" 2>"${TMP}/case9.err"; then
  printf 'expected --tool + --tools-file together to be rejected\n' >&2
  exit 1
fi
grep -q "use either --tools-file or --tool, not both" "${TMP}/case9.err"

# CASE 4b — strict env mode does NOT upgrade verify_strict: false probes to
# hard fails. Strict env only fails on (a) missing verify_command and
# (b) verify_strict: true probes that exit non-zero. This guards against
# accidental scope creep that would make every probe block the build.
PACK4B="${TMP}/pack-strict-env-lenient-probe"
scaffold_pack "${PACK4B}"
cat > "${PACK4B}.tools.json" <<'JSON'
[
  {
    "name": "exit-one",
    "version": "1.0.0",
    "path": "bin/exit-one",
    "activation": "default",
    "required_permissions": ["network"],
    "verify_command": ["{bin}"],
    "verify_strict": false
  }
]
JSON
python3 "${GEN}" \
  --tools-pack-root "${PACK4B}" \
  --pack-id "mona-secretary-tools" \
  --pack-version "0.1.0" \
  --target-arch "$(uname -m)" \
  --node-version "26.0.0" \
  --tools-file "${PACK4B}.tools.json"
HATCH_TOOLS_PACK_STRICT_VERIFY=1 \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME_DIR}" \
    bash "${HATCH_BIN}" --dry-run --tools-pack-root "${PACK4B}" verify-tools-pack >"${TMP}/case4b.out" 2>"${TMP}/case4b.err"
grep -q "Tools pack verified" "${TMP}/case4b.out"
grep -q "warn: exit-one verify_command exited 1" "${TMP}/case4b.err"

# CASE 10 — end-to-end: source-lock with probe fields propagates through
# prepare_mona_tools_inputs.sh + build_mona_tools_pack.sh into
# tools-pack-manifest.json.
E2E_INPUTS="${TMP}/e2e-inputs"
E2E_FIXTURES="${TMP}/e2e-fixtures"
E2E_PACKS="${TMP}/e2e-packs"
mkdir -p \
  "${E2E_INPUTS}/vendor/mona-tools" \
  "${E2E_FIXTURES}/node/current/bin" \
  "${E2E_FIXTURES}/bin" \
  "${E2E_FIXTURES}/apps/sample-mcp/dist" \
  "${E2E_FIXTURES}/docs" \
  "${E2E_FIXTURES}/config" \
  "${E2E_FIXTURES}/plugins/mona-secretary-tools"
cat > "${E2E_FIXTURES}/node/current/bin/node" <<'SH'
#!/usr/bin/env bash
printf 'v26.0.0\n'
SH
chmod +x "${E2E_FIXTURES}/node/current/bin/node"
cat > "${E2E_FIXTURES}/bin/sample-go" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${E2E_FIXTURES}/bin/sample-go"
printf 'mcp fixture\n' > "${E2E_FIXTURES}/apps/sample-mcp/dist/server.js"
printf '# permissions\n' > "${E2E_FIXTURES}/docs/permissions.md"
printf 'mcp_servers: {}\n' > "${E2E_FIXTURES}/config/mcp_servers.mona.example.yaml"
printf 'name: mona-secretary-tools\n' > "${E2E_FIXTURES}/plugins/mona-secretary-tools/plugin.yaml"
cat > "${E2E_INPUTS}/vendor/mona-tools/source-lock.json" <<JSON
{
  "schema_version": 1,
  "pack": {
    "id": "mona-secretary-tools",
    "version": "0.1.0"
  },
  "node": {
    "version": "26.0.0",
    "source": "${E2E_FIXTURES}/node/current"
  },
  "tools": [
    {
      "name": "sample-go",
      "version": "1.0.0",
      "license": "MIT",
      "repository": "https://example.com/sample-go",
      "ref": "fixture-go",
      "mode": "go-binary",
      "activation": "default",
      "required_permissions": ["network"],
      "verify_command": ["{bin}"],
      "verify_strict": true,
      "verify_env": { "VERIFY_PROBE_TOKEN": "expected-token" },
      "build": {
        "type": "copy",
        "source": "${E2E_FIXTURES}/bin/sample-go"
      }
    },
    {
      "name": "sample-mcp",
      "version": "1.0.0",
      "license": "MIT",
      "repository": "https://example.com/sample-mcp",
      "ref": "fixture-mcp",
      "mode": "node-app",
      "activation": "opt-in",
      "required_permissions": ["network"],
      "entrypoint": "dist/server.js",
      "verify_skip_reason": "Fixture MCP server has no non-blocking probe.",
      "build": {
        "type": "copy",
        "source": "${E2E_FIXTURES}/apps/sample-mcp"
      }
    }
  ],
  "extra_artifacts": [
    {
      "source": "${E2E_FIXTURES}/docs",
      "path": "docs"
    },
    {
      "source": "${E2E_FIXTURES}/config",
      "path": "config"
    },
    {
      "source": "${E2E_FIXTURES}/plugins",
      "path": "plugins"
    }
  ]
}
JSON

HATCH_INPUT_ROOT="${E2E_INPUTS}" \
HATCH_MONA_TOOLS_FORCE=1 \
  bash "${ROOT}/scripts/prepare_mona_tools_inputs.sh" >"${TMP}/case10-prepare.out" 2>&1
test -f "${E2E_INPUTS}/vendor/mona-tools/tool-lock.json"

# Confirm tool-lock.json carries the new fields propagated by lock_common().
python3 - "${E2E_INPUTS}/vendor/mona-tools/tool-lock.json" <<'PY'
import json
import sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text())
tools = {tool["name"]: tool for tool in lock["tools"]}
go = tools["sample-go"]
assert go["verify_command"] == ["{bin}"], go
assert go["verify_strict"] is True, go
assert go["verify_env"] == {"VERIFY_PROBE_TOKEN": "expected-token"}, go
mcp = tools["sample-mcp"]
assert mcp["verify_skip_reason"] == "Fixture MCP server has no non-blocking probe.", mcp
assert "verify_command" not in mcp, mcp
PY

HATCH_INPUT_ROOT="${E2E_INPUTS}" \
HATCH_TOOLS_PACKS_ROOT="${E2E_PACKS}" \
  bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/case10-build.out" 2>"${TMP}/case10-build.err"
test -f "${E2E_PACKS}/mona-secretary-tools/tools-pack-manifest.json"

# Confirm tools-pack-manifest.json carries the propagated fields.
python3 - "${E2E_PACKS}/mona-secretary-tools/tools-pack-manifest.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tools = {tool["name"]: tool for tool in data["tools"]}
go = tools["sample-go"]
assert go["verify_command"] == ["{bin}"], go
assert go["verify_strict"] is True, go
assert go["verify_env"] == {"VERIFY_PROBE_TOKEN": "expected-token"}, go
mcp = tools["sample-mcp"]
assert mcp["verify_skip_reason"] == "Fixture MCP server has no non-blocking probe.", mcp
assert "verify_command" not in mcp, mcp
PY

# The verifier inside build_mona_tools_pack.sh should now:
#   - run sample-go's probe with the env override (succeeds → exit 0)
#   - print info: sample-mcp verify skipped
#   - print NO warn lines
grep -q "info: sample-mcp verify skipped" "${TMP}/case10-build.err"
if grep -E "warn: (sample-go|sample-mcp) " "${TMP}/case10-build.err"; then
  printf 'unexpected warn from end-to-end verify\n' >&2
  exit 1
fi

# Sanity check: strict mode is honored end-to-end. Tamper sample-go to exit 1
# and rerun build → it should fail under HATCH_TOOLS_PACK_STRICT_VERIFY=1
# because sample-go has verify_strict: true.
rm -rf "${E2E_INPUTS}/vendor/mona-tools/prebuilt" "${E2E_INPUTS}/vendor/mona-tools/tool-lock.json"
cat > "${E2E_FIXTURES}/bin/sample-go" <<'SH'
#!/usr/bin/env bash
echo "tampered failure" >&2
exit 1
SH
chmod +x "${E2E_FIXTURES}/bin/sample-go"
HATCH_INPUT_ROOT="${E2E_INPUTS}" \
HATCH_MONA_TOOLS_FORCE=1 \
  bash "${ROOT}/scripts/prepare_mona_tools_inputs.sh" >"${TMP}/case10-reprepare.out" 2>&1
if HATCH_TOOLS_PACK_STRICT_VERIFY=1 \
  HATCH_INPUT_ROOT="${E2E_INPUTS}" \
  HATCH_TOOLS_PACKS_ROOT="${E2E_PACKS}" \
    bash "${ROOT}/scripts/build_mona_tools_pack.sh" >"${TMP}/case10-strict.out" 2>"${TMP}/case10-strict.err"; then
  printf 'expected strict end-to-end build to fail when verify_strict probe exits non-zero\n' >&2
  exit 1
fi
grep -q "strict probe" "${TMP}/case10-strict.err"

printf 'tools-pack verify_command tests passed\n'
