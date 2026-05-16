#!/usr/bin/env python3
"""Verify Hatch staged the complete official skill library."""

from __future__ import annotations

import argparse
from pathlib import Path


IGNORED_PARTS = {".git", ".github", ".hub"}


def skill_manifest_paths(root: Path) -> set[str]:
    """Return relative SKILL.md paths, ignoring metadata trees."""
    manifests: set[str] = set()
    if not root.is_dir():
        return manifests
    for skill_md in root.rglob("SKILL.md"):
        rel = skill_md.relative_to(root)
        if any(part in IGNORED_PARTS for part in rel.parts):
            continue
        manifests.add(rel.as_posix())
    return manifests


def verify_tree(label: str, source: Path, staged: Path) -> list[str]:
    source_manifests = skill_manifest_paths(source)
    staged_manifests = skill_manifest_paths(staged)
    errors: list[str] = []

    if not source_manifests:
        errors.append(f"runtime {label} skills source has no SKILL.md files: {source}")
        return errors
    if not staged_manifests:
        errors.append(
            f"staged {label} skills count 0 does not match runtime {label} skills count "
            f"{len(source_manifests)}: {staged}"
        )
        return errors

    missing = sorted(source_manifests - staged_manifests)
    extra = sorted(staged_manifests - source_manifests)
    if missing or extra:
        errors.append(
            f"staged {label} skills count {len(staged_manifests)} does not match runtime "
            f"{label} skills count {len(source_manifests)}"
        )
        if missing:
            errors.append(f"missing {label} skill manifests: {', '.join(missing[:10])}")
        if extra:
            errors.append(f"unexpected {label} skill manifests: {', '.join(extra[:10])}")

    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--bundle-root", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    runtime_root = Path(args.runtime_root).resolve()
    bundle_root = Path(args.bundle_root).resolve()

    checks = [
        ("default", runtime_root / "skills", bundle_root / "vendor" / "skills"),
        (
            "optional",
            runtime_root / "optional-skills",
            bundle_root / "vendor" / "optional-skills",
        ),
    ]
    errors: list[str] = []
    for label, source, staged in checks:
        errors.extend(verify_tree(label, source, staged))

    if errors:
        raise SystemExit("\n".join(errors))

    default_count = len(skill_manifest_paths(runtime_root / "skills"))
    optional_count = len(skill_manifest_paths(runtime_root / "optional-skills"))
    total = default_count + optional_count
    print(
        f"Official skill bundle verified: {default_count} default + "
        f"{optional_count} optional = {total}"
    )


if __name__ == "__main__":
    main()
