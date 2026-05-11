#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"
HATCH_MONA_TOOLS_SOURCE_LOCK="${HATCH_MONA_TOOLS_SOURCE_LOCK:-${HATCH_INPUT_ROOT}/vendor/mona-tools/source-lock.json}"
HATCH_MONA_TOOLS_BUILD_ROOT="${HATCH_MONA_TOOLS_BUILD_ROOT:-${HATCH_ROOT}/.mona-tools-build}"
HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH:-$(uname -m)}"

log() {
  printf '[mona-tools-prep] %s\n' "$1"
}

if [[ ! -f "${HATCH_MONA_TOOLS_SOURCE_LOCK}" ]]; then
  printf 'Mona tools source lock is required: %s\n' "${HATCH_MONA_TOOLS_SOURCE_LOCK}" >&2
  exit 1
fi

ENSURE_NODE_OUT=""
if ENSURE_NODE_OUT="$(
  HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH}" \
  HATCH_MONA_TOOLS_BUILD_ROOT="${HATCH_MONA_TOOLS_BUILD_ROOT}" \
  HATCH_MONA_NODE_RUNTIME_SOURCE="${HATCH_MONA_NODE_RUNTIME_SOURCE:-}" \
  HATCH_MONA_NODE_AUTO_DOWNLOAD="${HATCH_MONA_NODE_AUTO_DOWNLOAD:-1}" \
    python3 "${HATCH_ROOT}/scripts/mona_tools_ensure_node_runtime.py" \
      --source-lock "${HATCH_MONA_TOOLS_SOURCE_LOCK}" \
      --hatch-root "${HATCH_ROOT}"
)"; then
  if [[ -n "${ENSURE_NODE_OUT}" ]]; then
    export HATCH_MONA_NODE_RUNTIME_SOURCE="${ENSURE_NODE_OUT}"
  fi
else
  exit 1
fi

HATCH_ROOT="${HATCH_ROOT}" \
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
HATCH_MONA_TOOLS_SOURCE_LOCK="${HATCH_MONA_TOOLS_SOURCE_LOCK}" \
HATCH_MONA_TOOLS_BUILD_ROOT="${HATCH_MONA_TOOLS_BUILD_ROOT}" \
HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH}" \
HATCH_MONA_TOOLS_FORCE="${HATCH_MONA_TOOLS_FORCE:-0}" \
HATCH_MONA_NODE_RUNTIME_SOURCE="${HATCH_MONA_NODE_RUNTIME_SOURCE:-}" \
python3 <<'PY'
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def log(message: str) -> None:
    print(f"[mona-tools-prep] {message}")


def fail(message: str) -> None:
    raise SystemExit(message)


def resolve_path(raw: str, base: Path) -> Path:
    path = Path(raw)
    if not path.is_absolute():
        path = base / path
    return path.resolve()


def ensure_inside(parent: Path, child: Path, label: str) -> None:
    try:
        child.relative_to(parent)
    except ValueError:
        fail(f"{label} escapes expected root: {child}")


def copy_path(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(
            source,
            destination,
            symlinks=True,
            ignore=shutil.ignore_patterns(".git", ".hg", ".svn"),
        )
    else:
        shutil.copy2(source, destination)


def require_executable(name: str) -> str:
    value = shutil.which(name)
    if not value:
        fail(f"required build tool missing: {name}")
    return value


def brew_executable() -> Path | None:
    which_brew = shutil.which("brew")
    if which_brew:
        return Path(which_brew)
    for candidate in (Path("/opt/homebrew/bin/brew"), Path("/usr/local/bin/brew")):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def prepend_homebrew_bins_to_os_path() -> None:
    brew = brew_executable()
    if not brew:
        return
    try:
        prefix = subprocess.run(
            [str(brew), "--prefix"],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        ).stdout.strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError):
        return
    bindir = str(Path(prefix) / "bin")
    parts = [p for p in os.environ.get("PATH", "").split(os.pathsep) if p]
    if bindir not in parts:
        os.environ["PATH"] = f"{bindir}{os.pathsep}{os.environ.get('PATH', '')}"


def prepend_staged_node_bin_to_os_path(prebuilt_root: Path) -> None:
    """Prefer the pinned Mona Node runtime during pnpm/npm builds."""
    bindir = (prebuilt_root / "node" / "current" / "bin").resolve()
    node_bin = bindir / "node"
    if not node_bin.is_file():
        return
    prefix = str(bindir)
    parts = [p for p in os.environ.get("PATH", "").split(os.pathsep) if p]
    try:
        if parts and Path(parts[0]).resolve() == bindir:
            return
    except OSError:
        pass
    os.environ["PATH"] = f"{prefix}{os.pathsep}{os.environ.get('PATH', '')}"


def mona_go_autoinstall_enabled() -> bool:
    raw = os.environ.get("HATCH_MONA_AUTOINSTALL_GO", "1").strip().lower()
    return raw not in ("0", "false", "no", "off")


def ensure_go_installed_for_prep() -> None:
    prepend_homebrew_bins_to_os_path()
    if shutil.which("go"):
        return
    if not mona_go_autoinstall_enabled():
        fail("required build tool missing: go")
    if sys.platform != "darwin":
        fail("required build tool missing: go")
    brew = brew_executable()
    if not brew:
        fail(
            "required build tool missing: go "
            "(install Go from https://go.dev/dl/ or install Homebrew for automatic install)",
        )
    log("Go not found on PATH; running `brew install go`")
    env = os.environ.copy()
    env.setdefault("HOMEBREW_NO_AUTO_UPDATE", "1")
    try:
        subprocess.check_call(
            [str(brew), "install", "go"],
            timeout=7200,
            env=env,
        )
    except subprocess.CalledProcessError as exc:
        fail(f"`brew install go` failed (exit {exc.returncode}); install Go manually")
    except subprocess.TimeoutExpired:
        fail("timed out running `brew install go`; install Go manually")
    prepend_homebrew_bins_to_os_path()
    if not shutil.which("go"):
        fail("`go` still missing after `brew install go`; extend PATH with $(brew --prefix)/bin")


def mona_pnpm_autoinstall_enabled() -> bool:
    raw = os.environ.get("HATCH_MONA_AUTOINSTALL_PNPM", "1").strip().lower()
    return raw not in ("0", "false", "no", "off")


def ensure_pnpm_or_package_manager(package_manager: str) -> None:
    if package_manager != "pnpm":
        require_executable(package_manager)
        return
    prepend_homebrew_bins_to_os_path()
    if shutil.which("pnpm"):
        return
    if not mona_pnpm_autoinstall_enabled():
        fail("required build tool missing: pnpm")
    if sys.platform != "darwin":
        fail("required build tool missing: pnpm")
    brew = brew_executable()
    if not brew:
        fail(
            "required build tool missing: pnpm "
            "(install from https://pnpm.io/installation or install Homebrew for automatic install)",
        )
    log("pnpm not found on PATH; running `brew install pnpm`")
    env = os.environ.copy()
    env.setdefault("HOMEBREW_NO_AUTO_UPDATE", "1")
    try:
        subprocess.check_call(
            [str(brew), "install", "pnpm"],
            timeout=3600,
            env=env,
        )
    except subprocess.CalledProcessError as exc:
        fail(f"`brew install pnpm` failed (exit {exc.returncode}); install pnpm manually")
    except subprocess.TimeoutExpired:
        fail("timed out running `brew install pnpm`; install pnpm manually")
    prepend_homebrew_bins_to_os_path()
    if not shutil.which("pnpm"):
        fail("`pnpm` still missing after `brew install pnpm`; extend PATH with $(brew --prefix)/bin")


def go_toolchain_arch(monoclaw_arch: str) -> str:
    raw = monoclaw_arch.strip().lower()
    if raw in ("aarch64", "arm64"):
        return "arm64"
    if raw in ("amd64", "x86_64"):
        return "amd64"
    fail(f"HATCH_TARGET_ARCH {monoclaw_arch!r} is unsupported for darwin/go builds")


def run(command: list[str], cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    log(f"run: {' '.join(command)}")
    subprocess.check_call(command, cwd=str(cwd) if cwd else None, env=env)


def git_source(tool: dict[str, object], source_root: Path) -> tuple[Path, str]:
    repository = str(tool.get("repository", "")).strip()
    ref = str(tool.get("ref", "")).strip()
    name = str(tool.get("name", "")).strip()
    if not repository:
        fail(f"Mona tools source-lock entry missing repository: {name}")
    if not ref or ref.lower().startswith("replace-with-"):
        fail(f"Mona tools source-lock entry missing pinned ref: {name}")

    destination = source_root / name
    if destination.exists():
        shutil.rmtree(destination)
    run(["git", "clone", "--no-checkout", repository, str(destination)])
    run(["git", "checkout", ref], cwd=destination)
    actual_ref = subprocess.check_output(
        ["git", "rev-parse", "HEAD"],
        cwd=destination,
        text=True,
    ).strip()
    return destination, actual_ref


def local_ref(tool: dict[str, object]) -> str:
    ref = str(tool.get("ref", "")).strip()
    if not ref or ref.lower().startswith("replace-with-"):
        fail(f"Mona tools source-lock entry missing pinned ref: {tool.get('name', '')}")
    return ref


def build_go_tool(tool: dict[str, object], source_root: Path, prebuilt_root: Path, target_arch: str) -> dict[str, object]:
    require_executable("git")
    ensure_go_installed_for_prep()
    name = str(tool["name"])
    source, actual_ref = git_source(tool, source_root)
    package = str((tool.get("build") or {}).get("package", "."))
    output = prebuilt_root / "bin" / name
    output.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["GOOS"] = "darwin"
    env["GOARCH"] = go_toolchain_arch(target_arch)
    run(["go", "build", "-trimpath", "-o", str(output), package], cwd=source, env=env)
    output.chmod(0o755)
    return {
        **lock_common(tool, actual_ref),
        "source": f"vendor/mona-tools/prebuilt/bin/{name}",
        "path": f"bin/{name}",
    }


def copy_tool(tool: dict[str, object], source_lock_dir: Path, prebuilt_root: Path) -> dict[str, object]:
    name = str(tool["name"])
    mode = str(tool["mode"])
    build = tool.get("build") if isinstance(tool.get("build"), dict) else {}
    raw_source = str(build.get("source", "")).strip()
    if not raw_source:
        fail(f"Mona tools copy build missing source: {name}")
    source = resolve_path(raw_source, source_lock_dir)
    if not source.exists():
        fail(f"Mona tools copy source missing: {source}")
    actual_ref = local_ref(tool)
    if mode == "go-binary":
        destination = prebuilt_root / "bin" / name
        copy_path(source, destination)
        destination.chmod(0o755)
        return {
            **lock_common(tool, actual_ref),
            "source": f"vendor/mona-tools/prebuilt/bin/{name}",
            "path": f"bin/{name}",
        }
    if mode == "node-app":
        entrypoint = str(tool.get("entrypoint", "")).strip()
        if not entrypoint:
            fail(f"Mona tools node-app missing entrypoint: {name}")
        destination = prebuilt_root / "node/apps" / name
        copy_path(source, destination)
        if not (destination / entrypoint).is_file():
            fail(f"Mona tools node-app entrypoint missing after copy: {name}/{entrypoint}")
        return {
            **lock_common(tool, actual_ref),
            "source": f"vendor/mona-tools/prebuilt/node/apps/{name}",
            "path": f"node/apps/{name}/{entrypoint}",
        }
    fail(f"Mona tools copy build does not support mode {mode}: {name}")


def build_node_tool(tool: dict[str, object], source_root: Path, prebuilt_root: Path) -> dict[str, object]:
    require_executable("git")
    name = str(tool["name"])
    entrypoint = str(tool.get("entrypoint", "")).strip()
    if not entrypoint:
        fail(f"Mona tools node-app missing entrypoint: {name}")
    build = tool.get("build") if isinstance(tool.get("build"), dict) else {}
    package_manager = str(build.get("package_manager", "pnpm"))
    ensure_pnpm_or_package_manager(package_manager)

    source, actual_ref = git_source(tool, source_root)
    install_cmd = [str(part) for part in build.get("install", [package_manager, "install", "--frozen-lockfile"])]
    build_cmd = [str(part) for part in build.get("build", [package_manager, "run", "build"])]
    run(install_cmd, cwd=source)
    run(build_cmd, cwd=source)
    if not (source / entrypoint).is_file():
        fail(f"Mona tools node-app entrypoint missing after build: {name}/{entrypoint}")
    destination = prebuilt_root / "node/apps" / name
    copy_path(source, destination)
    return {
        **lock_common(tool, actual_ref),
        "source": f"vendor/mona-tools/prebuilt/node/apps/{name}",
        "path": f"node/apps/{name}/{entrypoint}",
    }


def lock_common(tool: dict[str, object], source_ref: str) -> dict[str, object]:
    return {
        "name": tool["name"],
        "version": tool["version"],
        "license": tool["license"],
        "repository": tool["repository"],
        "source_ref": source_ref,
        "mode": tool["mode"],
        "activation": tool["activation"],
        "required_permissions": tool["required_permissions"],
    }


def deferred_tool(tool: dict[str, object], reason: str | None = None) -> dict[str, object]:
    result = {
        **lock_common(tool, local_ref(tool)),
        "mode": "deferred",
        "activation": "deferred",
    }
    if reason:
        result["deferred_reason"] = reason
    return result


def build_tool(tool: dict[str, object], source_lock_dir: Path, source_root: Path, prebuilt_root: Path, target_arch: str) -> dict[str, object]:
    mode = str(tool.get("mode", "")).strip()
    build = tool.get("build") if isinstance(tool.get("build"), dict) else {}
    build_type = str(build.get("type", "")).strip()
    if mode == "deferred":
        return deferred_tool(tool)
    if build_type == "copy":
        return copy_tool(tool, source_lock_dir, prebuilt_root)
    if mode == "go-binary" and build_type == "go":
        return build_go_tool(tool, source_root, prebuilt_root, target_arch)
    if mode == "node-app" and build_type == "node":
        return build_node_tool(tool, source_root, prebuilt_root)
    fail(f"Mona tools source-lock has unsupported build type for {tool.get('name', '')}: {build_type}")


def stage_node_runtime(node: dict[str, object], source_lock_dir: Path, prebuilt_root: Path, active_node_tools: bool) -> dict[str, str]:
    version = str(node.get("version", "")).strip()
    if not version:
        fail("Mona tools source-lock node.version is required")
    raw_source = str(node.get("source", "")).strip()
    source_env = str(node.get("source_env", "")).strip()
    if not raw_source and source_env:
        raw_source = os.environ.get(source_env, "").strip()
    if not raw_source and active_node_tools:
        fail(
            "Mona tools Node runtime source is required; set "
            f"{source_env or 'HATCH_MONA_NODE_RUNTIME_SOURCE'} or source-lock node.source"
        )
    if raw_source:
        source = resolve_path(raw_source, source_lock_dir)
        if not source.exists():
            fail(f"Mona tools Node runtime source missing: {source}")
        destination = prebuilt_root / "node/current"
        copy_path(source, destination)
        node_bin = destination / "bin/node"
        if not node_bin.is_file():
            fail("Mona tools Node runtime must contain bin/node")
        if not os.access(node_bin, os.X_OK):
            fail("Mona tools Node runtime bin/node must be executable")
        actual = subprocess.check_output([str(node_bin), "--version"], text=True, timeout=10).strip()
        if actual != f"v{version}":
            fail(f"Mona tools Node runtime version mismatch: expected v{version}, got {actual}")
    return {
        "version": version,
        "source": "vendor/mona-tools/prebuilt/node/current",
    }


def main() -> None:
    input_root = Path(os.environ["HATCH_INPUT_ROOT"]).resolve()
    source_lock_path = Path(os.environ["HATCH_MONA_TOOLS_SOURCE_LOCK"]).resolve()
    source_lock_dir = source_lock_path.parent
    build_root = Path(os.environ["HATCH_MONA_TOOLS_BUILD_ROOT"]).resolve()
    target_arch = os.environ["HATCH_TARGET_ARCH"]
    force = os.environ.get("HATCH_MONA_TOOLS_FORCE", "0") == "1"

    data = json.loads(source_lock_path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        fail("Mona tools source-lock schema_version must be 1")
    pack = data.get("pack")
    if not isinstance(pack, dict) or pack.get("id") != "mona-secretary-tools" or not pack.get("version"):
        fail("Mona tools source-lock pack must define id=mona-secretary-tools and version")

    mona_root = input_root / "vendor/mona-tools"
    prebuilt_root = mona_root / "prebuilt"
    tool_lock_path = mona_root / "tool-lock.json"
    for existing in (prebuilt_root, tool_lock_path):
        if existing.exists() and not force:
            fail(f"{existing} already exists; set HATCH_MONA_TOOLS_FORCE=1 to regenerate")
    if prebuilt_root.exists():
        shutil.rmtree(prebuilt_root)
    if tool_lock_path.exists():
        tool_lock_path.unlink()
    if build_root.exists() and force:
        shutil.rmtree(build_root)
    source_root = build_root / "sources"
    source_root.mkdir(parents=True, exist_ok=True)
    prebuilt_root.mkdir(parents=True, exist_ok=True)

    tools = data.get("tools")
    if not isinstance(tools, list):
        fail("Mona tools source-lock tools must be a list")
    active_node_tools = any(
        isinstance(tool, dict)
        and tool.get("mode") == "node-app"
        and not tool.get("optional")
        for tool in tools
    )
    node_lock = stage_node_runtime(
        data.get("node") if isinstance(data.get("node"), dict) else {},
        source_lock_dir,
        prebuilt_root,
        active_node_tools,
    )
    prepend_staged_node_bin_to_os_path(prebuilt_root)

    lock_tools: list[dict[str, object]] = []
    for tool in tools:
        if not isinstance(tool, dict):
            fail("Mona tools source-lock tool entries must be objects")
        try:
            lock_tools.append(build_tool(tool, source_lock_dir, source_root, prebuilt_root, target_arch))
        except Exception as exc:
            if tool.get("optional"):
                log(f"optional tool {tool.get('name', '')} was not staged: {exc}")
                lock_tools.append(deferred_tool(tool, str(exc)))
            else:
                raise

    extra_artifacts: list[dict[str, str]] = []
    for item in data.get("extra_artifacts", []):
        if not isinstance(item, dict):
            fail("Mona tools source-lock extra_artifacts entries must be objects")
        raw_source = str(item.get("source", "")).strip()
        relative_path = str(item.get("path", "")).strip()
        if not raw_source or not relative_path:
            fail("Mona tools source-lock extra_artifacts entries require source and path")
        destination = (prebuilt_root / relative_path).resolve()
        ensure_inside(prebuilt_root, destination, "Mona tools prebuilt artifact path")
        copy_path(resolve_path(raw_source, source_lock_dir), destination)
        extra_artifacts.append(
            {
                "source": f"vendor/mona-tools/prebuilt/{relative_path}",
                "path": relative_path,
            }
        )

    tool_lock = {
        "schema_version": 1,
        "pack": pack,
        "node": node_lock,
        "tools": lock_tools,
        "extra_artifacts": extra_artifacts,
    }
    mona_root.mkdir(parents=True, exist_ok=True)
    tool_lock_path.write_text(json.dumps(tool_lock, indent=2) + "\n", encoding="utf-8")
    log(f"prepared Mona tools inputs under {mona_root}")
    log(f"wrote {tool_lock_path}")


if __name__ == "__main__":
    main()
PY
