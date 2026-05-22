#!/usr/bin/env python3
"""Generate a manifest for an optional Hatch model pack."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-pack-root", required=True)
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--provider", required=True)
    parser.add_argument("--role", default="chat")
    parser.add_argument("--model-file", required=True)
    parser.add_argument(
        "--extra-file",
        action="append",
        default=[],
        help="Additional artifact paths relative to the model pack root (repeatable).",
    )
    return parser.parse_args()


def artifact_entry(root: Path, relative: str) -> dict:
    raw_path = root / relative
    path = raw_path.resolve(strict=False)
    if root != path and root not in path.parents:
        raise SystemExit(f"model pack file escapes pack root: {relative}")
    if is_ignored_metadata(path, root):
        raise SystemExit(f"model pack file points to ignored metadata: {relative}")
    if not path.is_file():
        raise SystemExit(f"model pack file missing: {path}")
    rel_path = path.relative_to(root).as_posix()
    return {
        "path": rel_path,
        "kind": "file",
        "sha256": sha256(path),
        "bytes": path.stat().st_size,
    }


def main() -> None:
    args = parse_args()
    root = Path(args.model_pack_root).resolve()
    primary = artifact_entry(root, args.model_file)
    artifacts = [primary]
    for extra in args.extra_file:
        entry = artifact_entry(root, extra)
        if any(existing["path"] == entry["path"] for existing in artifacts):
            raise SystemExit(f"duplicate model pack artifact: {entry['path']}")
        artifacts.append(entry)

    manifest = {
        "schema_version": 1,
        "created_at": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "model": {
            "id": args.model_id,
            "provider": args.provider,
            "role": args.role,
            "path": primary["path"],
            "required": False,
        },
        "artifacts": artifacts,
    }
    (root / "model-pack-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
