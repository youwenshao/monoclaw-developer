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


def ensure_inside(path: Path, root: Path, message: str) -> None:
    try:
        path.relative_to(root)
    except ValueError:
        raise SystemExit(message) from None


def checked_bundle_path(path: Path, root: Path) -> Path:
    resolved = path.resolve(strict=False)
    ensure_inside(resolved, root, f"bundle artifact escapes bundle root: {relative_path(path, root)}")
    return resolved


def collect_artifacts(root: Path) -> list[dict[str, object]]:
    artifacts: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if is_ignored_metadata(path, root):
            continue
        rel = relative_path(path, root)
        if rel == "hatch-manifest.json":
            continue
        checked = checked_bundle_path(path, root)
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


def collect_provisioning_summary(root: Path) -> dict[str, object]:
    lock = root / "vendor" / "provisioning" / "monoclaw-provisioning-lock.json"
    summary: dict[str, object] = {
        "lock": lock.relative_to(root).as_posix() if lock.is_file() else "",
        "provisioned_tools": 0,
        "provisioned_skills": 0,
        "user_config_required": 0,
    }
    if not lock.is_file():
        return summary
    try:
        data = json.loads(lock.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return summary
    for item in data.get("items", []):
        if not isinstance(item, dict):
            continue
        classification = item.get("classification")
        if classification == "stock_bundle_candidate":
            if item.get("kind") == "skill":
                summary["provisioned_skills"] = int(summary["provisioned_skills"]) + 1
            elif item.get("kind") == "tool":
                summary["provisioned_tools"] = int(summary["provisioned_tools"]) + 1
        elif classification == "provisioned_user_config_required":
            summary["user_config_required"] = int(summary["user_config_required"]) + 1
    return summary


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
    provisioning = collect_provisioning_summary(root)

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
            "provisioning_audit": bool(provisioning["lock"]),
            "provisioned_tools": provisioning["provisioned_tools"],
            "provisioned_skills": provisioning["provisioned_skills"],
            "user_config_required_integrations": provisioning["user_config_required"],
        },
        "models": models,
        "artifacts": collect_artifacts(root),
    }

    (root / "hatch-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
