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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-pack-root", required=True)
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--provider", required=True)
    parser.add_argument("--role", default="chat")
    parser.add_argument("--model-file", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.model_pack_root).resolve()
    model_path = (root / args.model_file).resolve()
    if root != model_path and root not in model_path.parents:
        raise SystemExit(f"model file escapes pack root: {args.model_file}")
    if is_ignored_metadata(model_path, root):
        raise SystemExit(f"model file points to ignored metadata: {args.model_file}")
    if not model_path.is_file():
        raise SystemExit(f"model file missing: {model_path}")

    rel_model_path = model_path.relative_to(root).as_posix()
    manifest = {
        "schema_version": 1,
        "created_at": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "model": {
            "id": args.model_id,
            "provider": args.provider,
            "role": args.role,
            "path": rel_model_path,
            "required": False,
        },
        "artifacts": [
            {
                "path": rel_model_path,
                "kind": "file",
                "sha256": sha256(model_path),
                "bytes": model_path.stat().st_size,
            }
        ],
    }
    (root / "model-pack-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
