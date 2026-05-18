#!/usr/bin/env bash

log_step() {
  printf '\n[%s] %s\n' "$1" "$2"
}

log_ok() {
  printf '  ok: %s\n' "$1"
}

log_warn() {
  printf '  warn: %s\n' "$1"
}

log_fail() {
  printf '  fail: %s\n' "$1" >&2
}

die() {
  log_fail "$1"
  exit 1
}

log_action() {
  if [[ "${HATCH_DRY_RUN:-true}" == "true" ]]; then
    printf '  dry-run: %s\n' "$*"
  else
    printf '  run: %s\n' "$*"
    "$@"
  fi
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

# Portable wrapper around `timeout`. macOS does not ship a `timeout` binary by
# default; the GNU coreutils alternative `gtimeout` is only present if the user
# installed coreutils via Homebrew. Hatch's verify probes need a bounded
# execution time without taking a hard dependency on Homebrew, so fall back to
# Perl (always present on macOS) as the last resort.
#
# Usage: hatch_run_with_timeout <seconds> <command> [arg ...]
# Exit code: the command's exit code, or 124 on timeout (matching GNU
# `timeout`).
hatch_run_with_timeout() {
  local seconds="$1"
  shift
  if [[ -z "${seconds}" || $# -eq 0 ]]; then
    printf 'hatch_run_with_timeout: usage: <seconds> <command> [args...]\n' >&2
    return 2
  fi
  if have_command gtimeout; then
    gtimeout "${seconds}" "$@"
    return $?
  fi
  if have_command timeout; then
    timeout "${seconds}" "$@"
    return $?
  fi
  if have_command perl; then
    perl -e '
      use strict;
      use warnings;
      use POSIX ();
      my $seconds = shift @ARGV;
      my $pid = fork();
      if (!defined $pid) {
        die "fork failed: $!";
      } elsif ($pid == 0) {
        # Become session leader so SIGTERM/SIGKILL to -$pid kills the whole
        # process group, including any shell wrapper'\''s children (e.g. a
        # nested `sleep` from a stub binary).
        POSIX::setsid() or die "setsid failed: $!";
        exec { $ARGV[0] } @ARGV or die "exec failed: $!";
      }
      local $SIG{ALRM} = sub {
        kill "TERM", -$pid;
        # Give well-behaved children up to 1s to clean up before SIGKILL.
        for (1..10) {
          last if waitpid($pid, POSIX::WNOHANG) > 0;
          select(undef, undef, undef, 0.1);
        }
        kill "KILL", -$pid;
        waitpid $pid, 0;
        exit 124;
      };
      alarm $seconds;
      waitpid $pid, 0;
      alarm 0;
      exit ($? >> 8);
    ' "${seconds}" "$@"
    return $?
  fi
  printf 'hatch_run_with_timeout: no timeout / gtimeout / perl available; refusing to run unbounded\n' >&2
  return 127
}

detect_launch_agent() {
  local label="$1"
  launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1
}

monoclaw_home() {
  printf '%s\n' "${MONOCLAW_HOME:-${HOME}/.monoclaw}"
}

hatch_manifest_python() {
  local bundle_root="${1:-}"
  local candidate
  for candidate in \
    "${bundle_root}/vendor/python/current/bin/python3" \
    "${bundle_root}/vendor/python/current/bin/python3.13" \
    "${bundle_root}/vendor/python/current/bin/python3.12" \
    "${bundle_root}/vendor/python/current/bin/python3.11"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  if have_command python3; then
    command -v python3
    return 0
  fi
  return 1
}

verify_bundle_manifest() {
  local bundle_root="${1:-}"
  local manifest="${bundle_root}/hatch-manifest.json"
  local python_bin

  [[ -n "${bundle_root}" ]] || die "bundle root is empty"
  if [[ ! -f "${manifest}" ]]; then
    printf '\n' >&2
    printf '  This folder is not a complete Hatch bundle (missing hatch-manifest.json).\n' >&2
    printf '  Expected manifest at: %s\n' "${manifest}" >&2
    printf '  Regenerate the bundle on the assembly machine: cd /path/to/hatch && ./build.sh\n' >&2
    printf '  If assembly already failed, capture logs with: bash -x ./build.sh 2>&1 | tee hatch-build.log\n' >&2
    printf '\n' >&2
    die "bundle manifest not found at ${manifest}"
  fi
  python_bin="$(hatch_manifest_python "${bundle_root}")" || die "Python is required to verify the Hatch manifest"

  PYTHONDONTWRITEBYTECODE=1 HATCH_BUNDLE_ROOT="${bundle_root}" HATCH_HOST_ARCH="$(uname -m)" "${python_bin}" <<'PY'
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(os.environ["HATCH_BUNDLE_ROOT"]).resolve()
host_arch = os.environ.get("HATCH_HOST_ARCH", "")
manifest_path = root / "hatch-manifest.json"
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = [
    "schema_version",
    "bundle_id",
    "bundle_version",
    "created_at",
    "target",
    "runtime",
    "capabilities",
    "models",
    "artifacts",
]
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit(f"manifest missing required fields: {', '.join(missing)}")

target = data["target"]
if target.get("platform") != "darwin":
    raise SystemExit("manifest target.platform must be darwin")
if target.get("arch") and target["arch"] != host_arch:
    raise SystemExit(f"manifest target.arch {target['arch']} does not match host {host_arch}")

def safe_path(relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise SystemExit("manifest path entries must be non-empty strings")
    candidate = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink():
            resolved = current.resolve(strict=False)
            if resolved != root and root not in resolved.parents:
                raise SystemExit(f"manifest path escapes bundle root: {relative}")
    candidate = candidate.resolve(strict=False)
    if candidate != root and root not in candidate.parents:
        raise SystemExit(f"manifest path escapes bundle root: {relative}")
    return candidate

def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def is_ignored_metadata(path: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )

runtime = data["runtime"]
runtime_missing = [
    key for key in ("package", "version", "wheel", "entrypoints")
    if key not in runtime or runtime[key] in (None, "", [])
]
if runtime_missing:
    raise SystemExit(f"runtime manifest missing required fields: {', '.join(runtime_missing)}")
if runtime.get("package") != "monoclaw-runtime":
    raise SystemExit("runtime.package must be monoclaw-runtime")
wheel = runtime.get("wheel")
if wheel:
    wheel_path = safe_path(wheel)
    if not wheel_path.exists():
        raise SystemExit(f"runtime wheel path missing: {wheel}")
entrypoints = runtime.get("entrypoints")
if not isinstance(entrypoints, list) or "monoclaw" not in entrypoints:
    raise SystemExit("runtime.entrypoints must include monoclaw")

for model in data.get("models", []):
    if model.get("id") == "local:gemma4:e4b" and model.get("provider") != "lm-studio":
        raise SystemExit("local:gemma4:e4b must use provider lm-studio")
    path = model.get("path")
    if model.get("required") and path and not safe_path(path).exists():
        raise SystemExit(f"required model path missing: {path}")

listed_files = set()
for artifact in data["artifacts"]:
    rel = artifact.get("path")
    kind = artifact.get("kind")
    path = safe_path(rel)
    if kind == "directory":
        if not path.is_dir():
            raise SystemExit(f"artifact directory missing: {rel}")
        continue
    if kind != "file":
        raise SystemExit(f"artifact kind must be file or directory: {rel}")
    if not path.is_file():
        raise SystemExit(f"artifact file missing: {rel}")
    listed_files.add(rel)
    expected_bytes = artifact.get("bytes")
    if expected_bytes is None:
        raise SystemExit(f"artifact file missing byte size: {rel}")
    if expected_bytes is not None and path.stat().st_size != int(expected_bytes):
        raise SystemExit(f"artifact byte size mismatch: {rel}")
    expected_sha = artifact.get("sha256")
    if not expected_sha:
        raise SystemExit(f"artifact file missing sha256: {rel}")
    actual_sha = file_sha256(path)
    if actual_sha != expected_sha:
        raise SystemExit(f"artifact sha256 mismatch: {rel}")

for path in root.rglob("*"):
    rel = path.relative_to(root).as_posix()
    if rel == "hatch-manifest.json":
        continue
    path = safe_path(rel)
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    if rel not in listed_files:
        raise SystemExit(f"bundle file is not listed in manifest artifacts: {rel}")

print(f"Manifest verified for bundle {data['bundle_id']} ({data['bundle_version']})")
PY
}

verify_model_pack_manifest() {
  local pack_root="${1:-}"
  local manifest="${pack_root}/model-pack-manifest.json"
  local python_bin

  [[ -n "${pack_root}" ]] || die "model pack root is empty"
  [[ -f "${manifest}" ]] || die "model pack manifest not found at ${manifest}"
  python_bin="$(hatch_manifest_python "${HATCH_BUNDLE_ROOT:-}")" || die "Python is required to verify the model pack manifest"

  PYTHONDONTWRITEBYTECODE=1 HATCH_MODEL_PACK_ROOT="${pack_root}" "${python_bin}" <<'PY'
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(os.environ["HATCH_MODEL_PACK_ROOT"]).resolve()
manifest_path = root / "model-pack-manifest.json"
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = ["schema_version", "model", "artifacts"]
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit(f"model pack manifest missing required fields: {', '.join(missing)}")

model = data["model"]
model_missing = [
    key for key in ("id", "provider", "role", "path")
    if key not in model or model[key] in (None, "", [])
]
if model_missing:
    raise SystemExit(f"model pack manifest missing model fields: {', '.join(model_missing)}")

def safe_path(relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise SystemExit("model pack paths must be non-empty strings")
    candidate = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink():
            resolved = current.resolve(strict=False)
            if resolved != root and root not in resolved.parents:
                raise SystemExit(f"model pack path escapes root: {relative}")
    candidate = candidate.resolve(strict=False)
    if candidate != root and root not in candidate.parents:
        raise SystemExit(f"model pack path escapes root: {relative}")
    return candidate

def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def is_ignored_metadata(path: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )

model_path = safe_path(model["path"])
if not model_path.is_file():
    raise SystemExit(f"model pack file missing: {model['path']}")

listed_files = set()
for artifact in data["artifacts"]:
    rel = artifact.get("path")
    kind = artifact.get("kind")
    path = safe_path(rel)
    if kind != "file":
        raise SystemExit(f"model pack artifact kind must be file: {rel}")
    if not path.is_file():
        raise SystemExit(f"model pack file missing: {rel}")
    listed_files.add(rel)
    expected_bytes = artifact.get("bytes")
    if expected_bytes is None:
        raise SystemExit(f"model pack file missing byte size: {rel}")
    if path.stat().st_size != int(expected_bytes):
        raise SystemExit(f"model pack file byte size mismatch: {rel}")
    expected_sha = artifact.get("sha256")
    if not expected_sha:
        raise SystemExit(f"model pack file missing sha256: {rel}")
    if file_sha256(path) != expected_sha:
        raise SystemExit(f"model pack file sha256 mismatch: {rel}")

for path in root.rglob("*"):
    rel = path.relative_to(root).as_posix()
    if rel == "model-pack-manifest.json":
        continue
    path = safe_path(rel)
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    if rel not in listed_files:
        raise SystemExit(f"model pack file is not listed in manifest artifacts: {rel}")

print(f"Model pack verified for {model['id']} ({model_path.stat().st_size} bytes)")
PY
}

verify_tools_pack_manifest() {
  local pack_root="${1:-}"
  local expected_pack_id="${2:-mona-secretary-tools}"
  local manifest="${pack_root}/tools-pack-manifest.json"
  local python_bin

  [[ -n "${pack_root}" ]] || die "tools pack root is empty"
  [[ -f "${manifest}" ]] || die "tools pack manifest not found at ${manifest}"
  python_bin="$(hatch_manifest_python "${HATCH_BUNDLE_ROOT:-}")" || die "Python is required to verify the tools pack manifest"

  PYTHONDONTWRITEBYTECODE=1 \
    HATCH_TOOLS_PACK_ROOT="${pack_root}" \
    HATCH_EXPECTED_PACK_ID="${expected_pack_id}" \
    HATCH_HOST_ARCH="$(uname -m)" \
    HATCH_TOOLS_PACK_STRICT_VERIFY="${HATCH_TOOLS_PACK_STRICT_VERIFY:-0}" \
    "${python_bin}" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

root = Path(os.environ["HATCH_TOOLS_PACK_ROOT"]).resolve()
expected_pack_id = os.environ.get("HATCH_EXPECTED_PACK_ID", "mona-secretary-tools")
host_arch = os.environ.get("HATCH_HOST_ARCH", "")
strict_verify = os.environ.get("HATCH_TOOLS_PACK_STRICT_VERIFY", "0").strip().lower() in ("1", "true", "yes", "on")
manifest_path = root / "tools-pack-manifest.json"
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = ["schema_version", "pack", "target", "runtime", "tools", "artifacts"]
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit(f"tools pack manifest missing required fields: {', '.join(missing)}")

pack = data["pack"]
pack_missing = [
    key for key in ("id", "version")
    if key not in pack or pack[key] in (None, "", [])
]
if pack_missing:
    raise SystemExit(f"tools pack manifest missing pack fields: {', '.join(pack_missing)}")
if expected_pack_id and pack.get("id") != expected_pack_id:
    raise SystemExit(f"tools pack pack.id must be {expected_pack_id}")

target = data["target"]
if target.get("platform") != "darwin":
    raise SystemExit("tools pack target.platform must be darwin")
if target.get("arch") and target["arch"] != host_arch:
    raise SystemExit(f"tools pack target.arch {target['arch']} does not match host {host_arch}")

runtime = data["runtime"]
if not isinstance(runtime, dict):
    raise SystemExit("tools pack runtime must be an object")
node_runtime = runtime.get("node")
if node_runtime is not None:
    if not isinstance(node_runtime, dict):
        raise SystemExit("tools pack runtime.node must be an object")
    if not node_runtime.get("version"):
        raise SystemExit("tools pack runtime.node.version is required")

def safe_path(relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise SystemExit("tools pack paths must be non-empty strings")
    candidate = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink():
            resolved = current.resolve(strict=False)
            if resolved != root and root not in resolved.parents:
                raise SystemExit(f"tools pack path escapes pack root: {relative}")
    candidate = candidate.resolve(strict=False)
    if candidate != root and root not in candidate.parents:
        raise SystemExit(f"tools pack path escapes pack root: {relative}")
    return candidate

def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def is_ignored_metadata(path: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )

for tool in data["tools"]:
    for key in ("name", "version", "path", "activation", "required_permissions"):
        if key not in tool:
            raise SystemExit(f"tools pack tool missing field {key}")
    tool_path = safe_path(tool["path"])
    if not tool_path.is_file():
        raise SystemExit(f"tools pack tool file missing: {tool['path']}")

    name = tool["name"]
    verify_cmd = tool.get("verify_command")
    verify_strict_flag = bool(tool.get("verify_strict", False))
    verify_skip_reason = tool.get("verify_skip_reason")
    verify_env_overrides = tool.get("verify_env")

    if verify_cmd not in (None, []) and verify_skip_reason:
        raise SystemExit(
            f"tools pack tool {name!r} sets both verify_command and "
            f"verify_skip_reason (mutually exclusive)"
        )
    if verify_env_overrides is not None and not isinstance(verify_env_overrides, dict):
        raise SystemExit(
            f"tools pack tool {name!r} verify_env must be an object of string->string"
        )

    if verify_cmd and isinstance(verify_cmd, list) and len(verify_cmd) > 0:
        # Substitute {bin} placeholder with the actual binary path.
        resolved_cmd = [str(tool_path) if arg == "{bin}" else arg for arg in verify_cmd]
        env = os.environ.copy()
        if isinstance(verify_env_overrides, dict):
            for env_key, env_value in verify_env_overrides.items():
                if not isinstance(env_key, str) or not isinstance(env_value, str):
                    raise SystemExit(
                        f"tools pack tool {name!r} verify_env keys/values must be strings"
                    )
                env[env_key] = env_value
        try:
            result = subprocess.run(
                resolved_cmd, capture_output=True, text=True, timeout=10, env=env
            )
        except FileNotFoundError:
            # Binary missing / not executable is always a pack-integrity failure.
            raise SystemExit(
                f"tools pack binary not executable: {tool['path']} (verify: {verify_cmd})"
            )
        except subprocess.TimeoutExpired:
            message = f"  warn: {name} verify_command timed out (non-fatal)"
            if verify_strict_flag and strict_verify:
                raise SystemExit(
                    f"tools pack {name} verify_command timed out under "
                    f"HATCH_TOOLS_PACK_STRICT_VERIFY=1 (verify: {verify_cmd})"
                )
            print(message, file=sys.stderr)
        except Exception as exc:
            message = f"  warn: {name} verify_command error: {exc}"
            if verify_strict_flag and strict_verify:
                raise SystemExit(
                    f"tools pack {name} verify_command failed under "
                    f"HATCH_TOOLS_PACK_STRICT_VERIFY=1: {exc}"
                )
            print(message, file=sys.stderr)
        else:
            if result.returncode != 0:
                # `verify_strict: true` tools are expected to be self-contained
                # (no host permissions, no external state). Fail closed at install
                # time too because the binary itself is broken. The strict-build
                # env var also upgrades any non-zero exit on a strict probe to a
                # hard fail (covers strict-true tools in lenient install context).
                detail = (result.stderr or result.stdout or "").strip()
                if verify_strict_flag:
                    raise SystemExit(
                        f"tools pack {name} verify_command exited {result.returncode} "
                        f"(strict probe, no host-permission dependency expected); "
                        f"output: {detail or '(empty)'}"
                    )
                print(
                    f"  warn: {name} verify_command exited {result.returncode} "
                    f"(permissions may require 'monoclaw setup system')",
                    file=sys.stderr,
                )
    elif verify_skip_reason:
        # Honestly silenced: the manifest declares why no probe runs.
        print(
            f"  info: {name} verify skipped: {verify_skip_reason}",
            file=sys.stderr,
        )
    elif verify_cmd is None:
        message = (
            f"  warn: {name} has no verify_command in manifest "
            f"(add one for behavioral verification, or declare verify_skip_reason)"
        )
        if strict_verify:
            raise SystemExit(
                f"tools pack {name} is missing verify_command under "
                f"HATCH_TOOLS_PACK_STRICT_VERIFY=1; declare verify_command "
                f"(preferred) or verify_skip_reason"
            )
        print(message, file=sys.stderr)

if isinstance(node_runtime, dict) and node_runtime.get("path"):
    node_path = node_runtime.get("path", "")
    node = safe_path(node_path)
    if not node.is_file():
        raise SystemExit(f"tools pack node runtime missing: {node_path}")
    if not os.access(node, os.X_OK):
        raise SystemExit(f"tools pack node runtime is not executable: {node_path}")
    expected_version = node_runtime.get("version", "")
    try:
        actual_version = subprocess.check_output([str(node), "--version"], text=True, timeout=10).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"tools pack node runtime smoke failed: {exc}") from exc
    if actual_version != f"v{expected_version}":
        raise SystemExit(f"tools pack node runtime version mismatch: expected v{expected_version}, got {actual_version}")

required_handoff_files = [
    "docs/permissions.md",
    "config/mcp_servers.mona.example.yaml",
    "plugins/mona-secretary-tools/plugin.yaml",
]
if pack.get("id") == "mona-secretary-tools":
    for relative in required_handoff_files:
        path = safe_path(relative)
        if not path.is_file():
            raise SystemExit(f"tools pack required handoff file missing: {relative}")

listed_files = set()
for artifact in data["artifacts"]:
    rel = artifact.get("path")
    kind = artifact.get("kind")
    path = safe_path(rel)
    if kind != "file":
        raise SystemExit(f"tools pack artifact kind must be file: {rel}")
    if not path.is_file():
        raise SystemExit(f"tools pack file missing: {rel}")
    listed_files.add(rel)
    expected_bytes = artifact.get("bytes")
    if expected_bytes is None:
        raise SystemExit(f"tools pack file missing byte size: {rel}")
    if path.stat().st_size != int(expected_bytes):
        raise SystemExit(f"tools pack file byte size mismatch: {rel}")
    expected_sha = artifact.get("sha256")
    if not expected_sha:
        raise SystemExit(f"tools pack file missing sha256: {rel}")
    if file_sha256(path) != expected_sha:
        raise SystemExit(f"tools pack file sha256 mismatch: {rel}")

for path in root.rglob("*"):
    rel = path.relative_to(root).as_posix()
    if rel == "tools-pack-manifest.json":
        continue
    path = safe_path(rel)
    if not path.is_file():
        continue
    if is_ignored_metadata(path):
        continue
    if rel not in listed_files:
        raise SystemExit(f"tools pack file is not listed in manifest artifacts: {rel}")

print(f"Tools pack verified for {pack['id']} ({len(listed_files)} files)")
PY
}
