#!/usr/bin/env python3
"""Resolve or fetch a pinned Node darwin tarball for Mona tools Hatch prep.

Stdout (single line): absolute path to unpacked Node runtime (contains bin/node), or empty
when no non-optional node-app tools are declared.

Automatically downloads matching official binaries from nodejs.org when invoked on Darwin,
HATCH_MONA_NODE_AUTO_DOWNLOAD is not disabled, with cache under Hatch root `.mona-node-dist-cache`
unless HATCH_MONA_NODE_DOWNLOAD_CACHE is set.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

NODE_DIST_BASE = "https://nodejs.org/dist"


def die(code: int, msg: str) -> None:
    sys.stderr.write(f"{msg}\n")
    raise SystemExit(code)


def resolve_path(raw: str, base: Path) -> Path:
    path = Path(raw)
    if not path.is_absolute():
        path = base / path
    return path.resolve()


def resolve_node_download_cache_root(hatch_root: Path) -> Path:
    """Cache stays outside HATCH_MONA_TOOLS_BUILD_ROOT so Mona prep FORCE rmtree cannot delete it."""
    raw = os.environ.get("HATCH_MONA_NODE_DOWNLOAD_CACHE", "").strip()
    if raw:
        candidate = Path(raw)
        return candidate.resolve() if candidate.is_absolute() else (hatch_root / candidate).resolve()
    return (hatch_root / ".mona-node-dist-cache").resolve()


def target_arch_to_node_suffix(arch_raw: str) -> str:
    arch = arch_raw.strip().lower()
    if arch in ("arm64", "aarch64"):
        return "arm64"
    if arch in ("x86_64", "amd64"):
        return "x64"
    die(1, f"[mona-tools] unsupported HATCH_TARGET_ARCH for Node dist: {arch_raw!r}")


def emit_manual_runtime_help(readme: Path, hint: str, nv: str, situation: str) -> None:
    """situation: off | unsupported_host | exhausted."""
    version_line = ""
    if nv:
        version_line = f"[mona-tools] Must match source-lock node.version ({nv}).\n"
    if situation == "off":
        tip = "[mona-tools] Automatic Node download is off (HATCH_MONA_NODE_AUTO_DOWNLOAD=0).\n"
    elif situation == "unsupported_host":
        tip = (
            "[mona-tools] Automatic Node download runs only when the Hatch build host is macOS; "
            "set HATCH_MONA_NODE_RUNTIME_SOURCE on other hosts.\n"
        )
    else:
        tip = (
            "[mona-tools] Automatic download from nodejs.org failed "
            "(set HATCH_MONA_NODE_RUNTIME_SOURCE or fix network access).\n"
        )
    sys.stderr.write(
        "[mona-tools] Mona tools packing needs a Darwin Node unpack directory containing bin/node.\n"
        f"[mona-tools] Export {hint}=/path/to/node/unpack_root or add source-lock node.source.\n"
        f"{version_line}"
        f"{tip}"
        "[mona-tools] To omit the Mona tools sidecar entirely, set HATCH_INCLUDE_MONA_TOOLS=0.\n"
        f"[mona-tools] See {readme} for prerequisites.\n"
    )


def read_source_lock(lock_path: Path) -> tuple[dict[str, object], bool, Path]:
    lock_path = lock_path.resolve()
    data_obj: object = json.loads(lock_path.read_text(encoding="utf-8"))
    if not isinstance(data_obj, dict):
        die(1, "[mona-tools] Mona tools source-lock JSON must be an object")
    data: dict[str, object] = data_obj
    tools_obj = data.get("tools")
    tools_list: list = tools_obj if isinstance(tools_obj, list) else []

    active_node_apps = bool(
        any(
            isinstance(t, dict)
            and str(t.get("mode", "")).strip() == "node-app"
            and not bool(t.get("optional"))
            for t in tools_list
        )
    )

    lock_dir = lock_path.parent.resolve()
    return data, active_node_apps, lock_dir


def verify_node_tree(node_root: Path, expected_version: str) -> Path:
    node_bin = node_root / "bin" / "node"
    if not node_bin.is_file():
        die(1, f"[mona-tools] Node runtime must contain bin/node: {node_root}")
    if not os.access(node_bin, os.X_OK):
        die(1, f"[mona-tools] bin/node must be executable: {node_bin}")
    try:
        actual = subprocess.check_output(
            [str(node_bin), "--version"],
            text=True,
            timeout=60,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        die(
            1,
            "[mona-tools] Cannot execute bundled bin/node (--version failed): "
            f"{node_bin}: {exc}",
        )
    if actual != f"v{expected_version}":
        die(
            1,
            "[mona-tools] Node runtime version mismatch: "
            f"expected v{expected_version}, got {actual!r}",
        )
    return node_root.resolve()


def try_existing_path(candidate: Path, expected_version: str) -> Path | None:
    if not candidate.exists():
        return None
    return verify_node_tree(candidate, expected_version)


def fetch_url(url: str, destination: Path) -> None:
    req = Request(url, headers={"User-Agent": "hatch/mona-tools-ensure-node"})
    with urlopen(req, timeout=120) as resp:  # noqa: S310 (fixed nodejs.org dist URL scheme)
        with destination.open("wb") as handle:
            shutil.copyfileobj(resp, handle)


def download_node_dist(
    *,
    readme: Path,
    hint_env: str,
    nv: str,
    version: str,
    darwin_suffix: str,
    extract_parent: Path,
) -> Path:
    extract_parent.mkdir(parents=True, exist_ok=True)
    basename = f"node-v{version}-darwin-{darwin_suffix}"
    dest_dir = extract_parent / basename

    candidates = (
        (f"{basename}.tar.xz", True),
        (f"{basename}.tar.gz", False),
    )
    last_exc: BaseException | None = None

    for fname, xz in candidates:
        url = f"{NODE_DIST_BASE}/v{version}/{fname}"
        dest_file = extract_parent / fname
        try:
            sys.stderr.write(f"[mona-tools] fetching Node: {url}\n")
            fetch_url(url, dest_file)
        except URLError as exc:
            last_exc = exc
            dest_file.unlink(missing_ok=True)
            continue

        try:
            if dest_dir.exists():
                shutil.rmtree(dest_dir)
            mode = "r:xz" if xz else "r:gz"
            with tarfile.open(dest_file, mode) as archive:
                archive.extractall(path=extract_parent)
            dest_file.unlink(missing_ok=True)
        except (OSError, tarfile.ReadError, tarfile.TarError) as exc:
            dest_file.unlink(missing_ok=True)
            last_exc = exc
            continue

        if not dest_dir.is_dir():
            die(1, f"[mona-tools] Unexpected tarball layout after extract: missing {dest_dir}")
        return dest_dir

    emit_manual_runtime_help(readme, hint_env, nv, "exhausted")
    err = repr(last_exc) if last_exc else "no candidate archive reachable"
    die(1, f"[mona-tools] Exhausted Node dist download retries; detail: {err}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ensure Node runtime for Mona Hatch prep.")
    parser.add_argument("--source-lock", required=True, type=Path)
    parser.add_argument("--hatch-root", required=True, type=Path)
    args = parser.parse_args()

    hatch_root = Path(args.hatch_root).resolve()
    readme = hatch_root / "bundle-inputs/vendor/mona-tools/README.md"
    data, active_node_apps, lock_dir = read_source_lock(Path(args.source_lock))

    if not active_node_apps:
        return

    node_obj_raw = data.get("node")
    node_obj: dict[str, object] = node_obj_raw if isinstance(node_obj_raw, dict) else {}
    ver = str(node_obj.get("version", "")).strip()
    if not ver:
        die(1, "[mona-tools] source-lock node.version is required when node-app tools are active")

    source_env_name = str(node_obj.get("source_env", "")).strip()
    hint_env = source_env_name or "HATCH_MONA_NODE_RUNTIME_SOURCE"

    auto_raw = os.environ.get("HATCH_MONA_NODE_AUTO_DOWNLOAD", "1").strip().lower()
    auto_download = auto_raw not in ("0", "false", "no", "off")

    inline_raw = str(node_obj.get("source", "")).strip()
    if inline_raw:
        got = try_existing_path(resolve_path(inline_raw, lock_dir), ver)
        if got is not None:
            print(got, flush=True)
            return

    resolved_env = ""
    if source_env_name:
        resolved_env = os.environ.get(source_env_name, "").strip()
    if resolved_env:
        got = try_existing_path(resolve_path(resolved_env, lock_dir), ver)
        if got is not None:
            print(got, flush=True)
            return

    if not auto_download:
        emit_manual_runtime_help(readme, hint_env, ver, "off")
        raise SystemExit(1)

    if sys.platform != "darwin":
        emit_manual_runtime_help(readme, hint_env, ver, "unsupported_host")
        die(
            1,
            f"[mona-tools] Automatic Node downloads require a macOS build host; vend Node v{ver} externally.",
        )

    hatch_arch_raw = (
        os.environ.get("HATCH_TARGET_ARCH") or platform.machine()
    ).strip()
    suffix = target_arch_to_node_suffix(hatch_arch_raw)
    download_cache_root = resolve_node_download_cache_root(hatch_root)
    cache_parent = (download_cache_root / f"darwin-{suffix}").resolve()

    basename = f"node-v{ver}-darwin-{suffix}"
    cached = cache_parent / basename
    cached_bin = cached / "bin" / "node"

    if cached_bin.is_file():
        try:
            subprocess.check_call(
                [str(cached_bin), "--version"],
                timeout=60,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except (
            subprocess.CalledProcessError,
            OSError,
            FileNotFoundError,
        ):
            shutil.rmtree(cached, ignore_errors=True)
        else:
            ok = verify_node_tree(cached, ver)
            sys.stderr.write(f"[mona-tools] reuse cached Node {ok}\n")
            print(ok, flush=True)
            return

    unpacked = download_node_dist(
        readme=readme,
        hint_env=hint_env,
        nv=ver,
        version=ver,
        darwin_suffix=suffix,
        extract_parent=cache_parent,
    )
    ok_dir = verify_node_tree(unpacked, ver)
    sys.stderr.write(f"[mona-tools] unpacked Node runtime for Mona prep: {ok_dir}\n")
    print(ok_dir, flush=True)


if __name__ == "__main__":
    main()
