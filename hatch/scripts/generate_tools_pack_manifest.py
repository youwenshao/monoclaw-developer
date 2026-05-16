#!/usr/bin/env python3
"""Generate a manifest for an optional Hatch tools pack."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from datetime import UTC, datetime
from pathlib import Path


def relative_path(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_ignored_metadata(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )


def ensure_inside(path: Path, root: Path, message: str) -> None:
    try:
        path.relative_to(root)
    except ValueError:
        raise SystemExit(message) from None


def checked_pack_path(path: Path, root: Path, label: str) -> Path:
    resolved = path.resolve(strict=False)
    ensure_inside(resolved, root, f"{label} escapes pack root: {relative_path(path, root)}")
    return resolved


def collect_artifacts(root: Path) -> list[dict[str, object]]:
    artifacts: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if is_ignored_metadata(path, root):
            continue
        rel = relative_path(path, root)
        if rel == "tools-pack-manifest.json":
            continue
        checked = checked_pack_path(path, root, "tool artifact")
        if not checked.is_file():
            continue
        artifacts.append(
            {
                "path": rel,
                "kind": "file",
                "sha256": sha256(checked),
                "bytes": checked.stat().st_size,
            }
        )
    return artifacts


def parse_tool(value: str, root: Path) -> dict[str, object]:
    parts = value.split(":", 5)
    if len(parts) != 5:
        raise SystemExit(
            "--tool must use name:version:path:activation:permission[,permission] format"
        )
    name, version, rel_path, activation, permissions = [part.strip() for part in parts]
    if not name or not version or not rel_path or not activation:
        raise SystemExit("--tool fields must be non-empty")
    raw_path = root / rel_path
    path = raw_path.resolve(strict=False)
    if path != root and root not in path.parents:
        raise SystemExit(f"tool artifact escapes pack root: {rel_path}")
    if is_ignored_metadata(path, root):
        raise SystemExit(f"tool artifact points to ignored metadata: {rel_path}")
    if not path.is_file():
        raise SystemExit(f"tool artifact missing: {rel_path}")
    return {
        "name": name,
        "version": version,
        "path": path.relative_to(root).as_posix(),
        "activation": activation,
        "required_permissions": [
            permission.strip()
            for permission in permissions.split(",")
            if permission.strip()
        ],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools-pack-root", required=True)
    parser.add_argument("--pack-id", required=True)
    parser.add_argument("--pack-version", required=True)
    parser.add_argument("--target-arch", required=True)
    parser.add_argument("--node-version", default="")
    parser.add_argument("--node-path", default="node/current/bin/node")
    parser.add_argument("--tool", action="append", default=[])
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.tools_pack_root).resolve()
    if not root.is_dir():
        raise SystemExit(f"tools pack root missing: {root}")

    runtime: dict[str, object] = {}
    if args.node_version:
        node_rel_path = args.node_path.strip() or "node/current/bin/node"
        node_path = root / node_rel_path
        if not node_path.is_file():
            raise SystemExit(f"tools pack node runtime missing: {node_path.relative_to(root).as_posix()}")
        if not os.access(node_path, os.X_OK):
            raise SystemExit(f"tools pack node runtime is not executable: {node_path.relative_to(root).as_posix()}")
        try:
            version = subprocess.check_output([str(node_path), "--version"], text=True, timeout=10).strip()
        except (OSError, subprocess.SubprocessError) as exc:
            raise SystemExit(f"tools pack node runtime smoke failed: {exc}") from exc
        if version != f"v{args.node_version}":
            raise SystemExit(
                f"tools pack node runtime version mismatch: expected v{args.node_version}, got {version}"
            )
        runtime["node"] = {
            "version": args.node_version,
            "path": node_rel_path,
        }

    tools = [parse_tool(tool, root) for tool in args.tool]
    manifest = {
        "schema_version": 1,
        "created_at": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "pack": {
            "id": args.pack_id,
            "version": args.pack_version,
        },
        "target": {
            "platform": "darwin",
            "arch": args.target_arch,
        },
        "runtime": runtime,
        "tools": tools,
        "artifacts": collect_artifacts(root),
    }
    (root / "tools-pack-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
