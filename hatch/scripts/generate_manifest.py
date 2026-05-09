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


def is_ignored_metadata(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    return (
        path.name == ".DS_Store"
        or path.name.startswith("._")
        or any(part in {"__MACOSX", ".Spotlight-V100", ".fseventsd", ".Trashes"} for part in parts)
    )


def collect_artifacts(root: Path) -> list[dict[str, object]]:
    artifacts: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if is_ignored_metadata(path, root):
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


def find_runtime_wheel(root: Path) -> Path:
    wheels = sorted((root / "runtime").glob("monoclaw_runtime-*.whl"))
    if not wheels:
        legacy = root / "runtime" / "monoclaw-runtime.whl"
        if legacy.is_file():
            return legacy
        raise SystemExit(f"runtime wheel missing under {root / 'runtime'}")
    return wheels[-1]


def collect_models(root: Path) -> list[dict[str, object]]:
    gemma = root / "vendor" / "models" / "gemma-4-e4b" / "gemma-4-e4b.gguf"
    if not gemma.is_file():
        return []
    return [
        {
            "id": "local:gemma4:e4b",
            "provider": "lm-studio",
            "role": "chat",
            "path": "vendor/models/gemma-4-e4b/gemma-4-e4b.gguf",
            "required": False,
        }
    ]


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
    wheel = find_runtime_wheel(root)
    models = collect_models(root)
    has_local_model = bool(models)

    if not wheel.is_file():
        raise SystemExit(f"runtime wheel missing: {wheel}")

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
            "wheel": relative_path(wheel, root),
            "entrypoints": ["monoclaw", "monoclaw-agent", "monoclaw-acp"],
        },
        "capabilities": {
            "local_inference": has_local_model,
            "lm_studio": has_local_model,
            "telegram_gateway": True,
            "browser_automation": (root / "vendor" / "browser").is_dir(),
            "sandbox_worker": (root / "vendor" / "support").is_dir(),
            "voice": False,
        },
        "models": models,
        "artifacts": collect_artifacts(root),
    }

    (root / "hatch-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
