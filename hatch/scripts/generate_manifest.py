#!/usr/bin/env python3
"""Generate a Hatch bundle manifest from a staged dist tree."""

from __future__ import annotations

import argparse
import hashlib
import json
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


def collect_artifacts(root: Path) -> list[dict[str, object]]:
    artifacts: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = relative_path(path, root)
        if rel == "hatch-manifest.json":
            continue
        artifacts.append(
            {
                "path": rel,
                "kind": "file",
                "sha256": sha256(path),
                "bytes": path.stat().st_size,
            }
        )
    return artifacts


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-root", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--bundle-version", required=True)
    parser.add_argument("--runtime-version", required=True)
    parser.add_argument("--target-arch", required=True)
    parser.add_argument("--minimum-macos", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.bundle_root).resolve()
    wheel = root / "runtime" / "monoclaw-runtime.whl"
    model = root / "vendor" / "models" / "gemma-4-e4b" / "gemma-4-e4b.gguf"

    if not wheel.is_file():
        raise SystemExit(f"runtime wheel missing: {wheel}")
    if not model.is_file():
        raise SystemExit(f"Gemma 4 E4B model missing: {model}")

    manifest = {
        "schema_version": 1,
        "bundle_id": args.bundle_id,
        "bundle_version": args.bundle_version,
        "created_at": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "target": {
            "platform": "darwin",
            "arch": args.target_arch,
            "minimum_macos": args.minimum_macos,
        },
        "runtime": {
            "package": "monoclaw-runtime",
            "version": args.runtime_version,
            "wheel": "runtime/monoclaw-runtime.whl",
            "entrypoints": ["monoclaw", "monoclaw-agent", "monoclaw-acp"],
        },
        "capabilities": {
            "local_inference": True,
            "lm_studio": True,
            "telegram_gateway": True,
            "browser_automation": (root / "vendor" / "browser").is_dir(),
            "sandbox_worker": (root / "vendor" / "support").is_dir(),
            "voice": False,
        },
        "models": [
            {
                "id": "local:gemma4:e4b",
                "provider": "lm-studio",
                "role": "chat",
                "path": "vendor/models/gemma-4-e4b/gemma-4-e4b.gguf",
                "required": True,
            }
        ],
        "artifacts": collect_artifacts(root),
    }

    (root / "hatch-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
