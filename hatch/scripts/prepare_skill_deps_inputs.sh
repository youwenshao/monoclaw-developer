#!/usr/bin/env bash
# Prepare ignored prebuilt inputs for the optional skill-deps pack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HATCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT:-${HATCH_ROOT}/bundle-inputs}"
HATCH_SKILL_DEPS_SOURCE_LOCK="${HATCH_SKILL_DEPS_SOURCE_LOCK:-${HATCH_INPUT_ROOT}/vendor/skill-deps/source-lock.json}"
HATCH_SKILL_DEPS_BUILD_ROOT="${HATCH_SKILL_DEPS_BUILD_ROOT:-${HATCH_ROOT}/.skill-deps-build}"
HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH:-$(uname -m)}"

if [[ ! -f "${HATCH_SKILL_DEPS_SOURCE_LOCK}" ]]; then
  printf 'Skill deps source lock is required: %s\n' "${HATCH_SKILL_DEPS_SOURCE_LOCK}" >&2
  exit 1
fi

HATCH_ROOT="${HATCH_ROOT}" \
HATCH_INPUT_ROOT="${HATCH_INPUT_ROOT}" \
HATCH_SKILL_DEPS_SOURCE_LOCK="${HATCH_SKILL_DEPS_SOURCE_LOCK}" \
HATCH_SKILL_DEPS_BUILD_ROOT="${HATCH_SKILL_DEPS_BUILD_ROOT}" \
HATCH_SKILL_DEPS_FORCE="${HATCH_SKILL_DEPS_FORCE:-0}" \
HATCH_RUNTIME_ROOT="${HATCH_RUNTIME_ROOT:-}" \
HATCH_TARGET_ARCH="${HATCH_TARGET_ARCH}" \
python3 <<'PY'
from __future__ import annotations

import fnmatch
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path
from typing import Any


def log(message: str) -> None:
    print(f"[skill-deps-prep] {message}")


def fail(message: str) -> None:
    raise SystemExit(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def platform_key() -> str:
    platform = sys.platform
    if platform.startswith("darwin"):
        os_name = "darwin"
    elif platform.startswith("linux"):
        os_name = "linux"
    else:
        os_name = platform
    arch = os.environ.get("HATCH_TARGET_ARCH", "").strip() or os.uname().machine
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x86_64", "amd64": "x86_64"}.get(arch, arch)
    return f"{os_name}-{arch}"


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    log(f"downloading {url}")
    with urllib.request.urlopen(url, timeout=120) as response:
        with destination.open("wb") as handle:
            shutil.copyfileobj(response, handle)


def github_release_asset(method: dict[str, Any], build_dir: Path) -> Path:
    owner = str(method["owner"])
    repo = str(method["repo"])
    tag = str(method.get("tag") or "latest")
    api = (
        f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
        if tag == "latest"
        else f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
    )
    with urllib.request.urlopen(api, timeout=120) as response:
        release = json.loads(response.read().decode("utf-8"))
    assets = release.get("assets") or []
    patterns = (method.get("asset_patterns") or {}).get(platform_key()) or []
    selected = None
    for asset in assets:
        name = str(asset.get("name") or "")
        if any(fnmatch.fnmatch(name, pattern) for pattern in patterns):
            selected = asset
            break
    if selected is None:
        raise RuntimeError("no matching release asset")
    asset_path = build_dir / str(selected["name"])
    download(str(selected["browser_download_url"]), asset_path)
    expected_sha = str(method.get("archive_sha256") or "").strip()
    if expected_sha and sha256(asset_path) != expected_sha:
        fail(f"archive sha256 mismatch for {asset_path.name}")
    return extract_binary(asset_path, build_dir / "extract", str(method.get("binary") or ""))


def extract_binary(archive: Path, extract_dir: Path, binary_name: str) -> Path:
    if extract_dir.exists():
        shutil.rmtree(extract_dir)
    extract_dir.mkdir(parents=True)
    suffixes = "".join(archive.suffixes)
    if suffixes.endswith((".tar.gz", ".tgz", ".tar")):
        with tarfile.open(archive) as tar:
            tar.extractall(extract_dir)
    elif archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(extract_dir)
    else:
        return archive
    matches = [path for path in extract_dir.rglob(binary_name) if path.is_file()]
    if not matches:
        matches = [path for path in extract_dir.rglob("*") if path.is_file() and path.name == binary_name]
    if not matches:
        fail(f"binary {binary_name!r} not found in {archive}")
    return matches[0]


def download_archive(method: dict[str, Any], build_dir: Path) -> Path:
    urls = method.get("urls") or {}
    url = urls.get(platform_key()) if isinstance(urls, dict) else None
    if not url:
        raise RuntimeError(f"no archive URL for {platform_key()}")
    archive = build_dir / Path(str(url)).name
    download(str(url), archive)
    expected_sha = str(method.get("archive_sha256") or "").strip()
    if expected_sha and sha256(archive) != expected_sha:
        fail(f"archive sha256 mismatch for {archive.name}")
    return extract_binary(archive, build_dir / "extract", str(method["binary"]))


def local_binary(method: dict[str, Any], input_root: Path) -> Path:
    raw = str(method.get("path") or method.get("source") or "")
    if not raw:
        raise RuntimeError("local_binary method requires path")
    path = Path(raw)
    if not path.is_absolute():
        path = input_root / "vendor" / "skill-deps" / path
    path = path.resolve()
    if not path.is_file():
        raise RuntimeError(f"local binary missing: {path}")
    return path


def swift_build(method: dict[str, Any], build_dir: Path) -> Path:
    if not shutil.which("git"):
        raise RuntimeError("git is required for swift_build")
    if not shutil.which("swift"):
        raise RuntimeError("swift is required for swift_build")
    repo_dir = build_dir / "repo"
    if repo_dir.exists():
        shutil.rmtree(repo_dir)
    subprocess.check_call(["git", "clone", "--depth", "1", "--branch", str(method["ref"]), str(method["repository"]), str(repo_dir)])
    subprocess.check_call(["swift", "build", "-c", "release", "--product", str(method["product"])], cwd=repo_dir)
    binary = repo_dir / ".build" / "release" / str(method["product"])
    if not binary.is_file():
        raise RuntimeError(f"swift product not found: {binary}")
    return binary


def python_supports_venv(python: str, build_dir: Path) -> bool:
    probe = build_dir / "venv-probe"
    if probe.exists():
        shutil.rmtree(probe)
    try:
        subprocess.check_call(
            [python, "-m", "venv", str(probe)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.check_call(
            [str(probe / "bin" / "python"), "-m", "pip", "--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False
    finally:
        shutil.rmtree(probe, ignore_errors=True)


def python_version_tuple(python: str) -> tuple[int, int, int] | None:
    try:
        raw = subprocess.check_output(
            [
                python,
                "-c",
                "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')",
            ],
            text=True,
            timeout=15,
        ).strip()
    except (OSError, subprocess.SubprocessError):
        return None
    parts = raw.split(".")
    try:
        major = int(parts[0])
        minor = int(parts[1]) if len(parts) > 1 else 0
        micro = int(parts[2]) if len(parts) > 2 else 0
    except (TypeError, ValueError):
        return None
    return major, minor, micro


def parse_min_python(value: str | None) -> tuple[int, int, int] | None:
    if not value:
        return None
    parts = str(value).strip().split(".")
    try:
        major = int(parts[0])
        minor = int(parts[1]) if len(parts) > 1 else 0
        micro = int(parts[2]) if len(parts) > 2 else 0
    except (TypeError, ValueError):
        return None
    return major, minor, micro


def version_satisfies(version: tuple[int, int, int] | None, minimum: tuple[int, int, int] | None) -> bool:
    if version is None:
        return False
    if minimum is None:
        return True
    return version >= minimum


def resolve_skill_deps_python(vendor_root: Path, build_dir: Path, min_python: str | None = None) -> str:
    minimum = parse_min_python(min_python)
    candidates: list[tuple[str, Path | None]] = []
    explicit = os.environ.get("HATCH_SKILL_DEPS_PYTHON")
    if explicit:
        candidates.append(("HATCH_SKILL_DEPS_PYTHON", Path(explicit)))
    staged = vendor_root.parent / "python" / "current" / "bin" / "python3"
    candidates.append(("bundled Python", staged))

    failures: list[str] = []
    def try_candidates(items: list[tuple[str, Path | None]]) -> str | None:
        nonlocal failures
        for label, path in items:
            if path is None:
                continue
            if not path.is_file() or not os.access(path, os.X_OK):
                failures.append(f"{label}: not executable at {path}")
                continue
            version = python_version_tuple(str(path))
            if not version_satisfies(version, minimum):
                requirement = ".".join(str(part) for part in minimum) if minimum else "unknown"
                found = ".".join(str(part) for part in version) if version else "unknown"
                failures.append(f"{label}: Python {found} does not satisfy >= {requirement} at {path}")
                if label == "HATCH_SKILL_DEPS_PYTHON":
                    break
                continue
            if python_supports_venv(str(path), build_dir / label.replace(" ", "-").replace("/", "-")):
                log(f"using {label} for Python skill dependency packaging: {path}")
                return str(path)
            failures.append(f"{label}: venv/pip probe failed at {path}")
            if label == "HATCH_SKILL_DEPS_PYTHON":
                break
        return None

    resolved = try_candidates(candidates)
    if resolved:
        return resolved

    fail(
        "no pip-capable Python available for skill dependency packaging; "
        "stage bundle-inputs/vendor/python/current/bin/python3 or set "
        "HATCH_SKILL_DEPS_PYTHON for diagnostics. "
        + " | ".join(failures)
    )

    # Unreachable, but keeps type checkers happy.
    raise AssertionError("unreachable")

def python_wheelhouse_extra_artifacts(method: dict[str, Any]) -> list[dict[str, str]]:
    if method.get("type") != "python_wheelhouse":
        return []
    return [
        {
            "source": str(method.get("support_source") or "prebuilt/python/tool"),
            "path": str(method.get("support_path") or "python/tool"),
        }
    ]


def declared_extra_artifacts(tool: dict[str, Any]) -> list[dict[str, str]]:
    extras = list(tool.get("extra_artifacts") or [])
    for method in tool.get("methods") or []:
        extras.extend(python_wheelhouse_extra_artifacts(method))
    deduped: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for artifact in extras:
        if not isinstance(artifact, dict):
            continue
        source = str(artifact.get("source") or "")
        path = str(artifact.get("path") or "")
        if not source or not path:
            continue
        key = (source, path)
        if key in seen:
            continue
        seen.add(key)
        deduped.append({"source": source, "path": path})
    return deduped


def python_wheelhouse(
    method: dict[str, Any],
    tool: dict[str, Any],
    vendor_root: Path,
    build_dir: Path,
) -> tuple[Path, list[dict[str, str]]]:
    python = resolve_skill_deps_python(vendor_root, build_dir, str(method.get("min_python") or ""))
    support_source = vendor_root / str(method.get("support_source") or "prebuilt/python/tool")
    wheelhouse_stage = build_dir / "wheelhouse"
    if wheelhouse_stage.exists():
        shutil.rmtree(wheelhouse_stage)
    wheelhouse_stage.mkdir(parents=True)
    support_source.parent.mkdir(parents=True, exist_ok=True)
    package = str(method["package"])
    try:
        subprocess.check_call([python, "-m", "pip", "wheel", "--wheel-dir", str(wheelhouse_stage), package])
        if support_source.exists():
            shutil.rmtree(support_source)
        (support_source / "wheelhouse").parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(wheelhouse_stage, support_source / "wheelhouse")
    except Exception:
        shutil.rmtree(wheelhouse_stage, ignore_errors=True)
        shutil.rmtree(support_source, ignore_errors=True)
        raise
    wheels = sorted((support_source / "wheelhouse").glob("*.whl"))
    if not wheels:
        raise RuntimeError(f"pip wheel produced no wheels for {package}")
    package_spec = {
        "schema_version": 1,
        "tool": str(tool["name"]),
        "package": str(method.get("install_package") or method.get("package_name") or tool["name"]),
        "version": str(method.get("install_version") or tool["version"]),
        "entrypoint": str(method["entrypoint"]),
        "min_python": str(method.get("min_python") or ""),
        "source_package": package,
    }
    (support_source / "package-spec.json").write_text(
        json.dumps(package_spec, indent=2) + "\n",
        encoding="utf-8",
    )
    marker = support_source / ".install-marker"
    marker.write_text(
        "This Python-backed skill dependency is installed from wheelhouse/ on the target Mac.\n",
        encoding="utf-8",
    )
    return marker, python_wheelhouse_extra_artifacts(method)


def copy_executable(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    destination.chmod(destination.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def prepare_tool(tool: dict[str, Any], input_root: Path, vendor_root: Path, build_root: Path, force: bool) -> dict[str, Any]:
    output = vendor_root / str(tool["source"])
    extra_artifacts = declared_extra_artifacts(tool)
    if output.exists() and not force:
        log(f"using existing {output.relative_to(vendor_root)}")
    else:
        if output.exists():
            output.unlink()
        methods = tool.get("methods") or []
        errors: list[str] = []
        for index, method in enumerate(methods):
            method_type = str(method.get("type") or "")
            method_build_dir = build_root / str(tool["name"]) / str(index)
            if method_build_dir.exists():
                shutil.rmtree(method_build_dir)
            method_build_dir.mkdir(parents=True, exist_ok=True)
            try:
                if method_type == "github_release_asset":
                    source = github_release_asset(method, method_build_dir)
                    copy_executable(source, output)
                elif method_type == "download_archive":
                    source = download_archive(method, method_build_dir)
                    copy_executable(source, output)
                elif method_type == "local_binary":
                    source = local_binary(method, input_root)
                    copy_executable(source, output)
                elif method_type == "swift_build":
                    source = swift_build(method, method_build_dir)
                    copy_executable(source, output)
                elif method_type == "python_wheelhouse":
                    output, extra_artifacts = python_wheelhouse(method, tool, vendor_root, method_build_dir)
                else:
                    raise RuntimeError(f"unsupported method type: {method_type}")
                break
            except Exception as exc:
                errors.append(f"{method_type}: {exc}")
        else:
            fail(f"could not prepare {tool['name']}:\n  " + "\n  ".join(errors))

    prepared = {key: tool[key] for key in ("name", "version", "license", "repository", "source_ref", "activation", "required_permissions", "source", "path") if key in tool}
    prepared["sha256"] = sha256(output)
    if output.name == output.stem:
        output.chmod(output.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    # Preserve extra artifacts from Python wheelhouses or source lock declarations.
    if extra_artifacts:
        prepared["extra_artifacts"] = extra_artifacts
    log(f"prepared {tool['name']} ({prepared['sha256']})")
    return prepared


def main() -> None:
    input_root = Path(os.environ["HATCH_INPUT_ROOT"]).resolve()
    source_lock = Path(os.environ["HATCH_SKILL_DEPS_SOURCE_LOCK"]).resolve()
    build_root = Path(os.environ["HATCH_SKILL_DEPS_BUILD_ROOT"]).resolve()
    vendor_root = input_root / "vendor" / "skill-deps"
    force = os.environ.get("HATCH_SKILL_DEPS_FORCE", "0") == "1"

    data = json.loads(source_lock.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        fail("skill-deps source-lock schema_version must be 1")
    pack = data.get("pack")
    if not isinstance(pack, dict) or pack.get("id") != "skill-deps-pack":
        fail("skill-deps source-lock pack.id must be skill-deps-pack")

    vendor_root.mkdir(parents=True, exist_ok=True)
    build_root.mkdir(parents=True, exist_ok=True)
    tools = [prepare_tool(tool, input_root, vendor_root, build_root, force) for tool in data.get("tools", [])]
    if not tools:
        fail("skill-deps source-lock has no tools")
    lock = {"schema_version": 1, "pack": pack, "tools": tools}
    (vendor_root / "tool-lock.json").write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
    log(f"wrote {vendor_root / 'tool-lock.json'}")


if __name__ == "__main__":
    main()
PY
