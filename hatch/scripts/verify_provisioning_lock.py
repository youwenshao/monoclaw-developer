#!/usr/bin/env python3
"""Verify Hatch's provisioning lock before bundle assembly."""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
from pathlib import Path
from typing import Any

LOCK_REL = Path("vendor/provisioning/monoclaw-provisioning-lock.json")
ALLOWED_CLASSIFICATIONS = {
    "stock_bundle_candidate",
    "provisioned_user_config_required",
    "external_runtime_only",
}


def _die(message: str) -> None:
    raise SystemExit(message)


def _string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _dependency_name(requirement: str) -> str:
    value = str(requirement).strip()
    if "@" in value:
        value = value.split("@", 1)[0].strip()
    for marker in ("[", "<", ">", "=", "!", "~", ";", " "):
        if marker in value:
            value = value.split(marker, 1)[0].strip()
    return value.lower().replace("_", "-")


def _local_office_dependency_names(pyproject_path: Path) -> set[str]:
    if not pyproject_path.is_file():
        _die(f"runtime pyproject is missing: {pyproject_path}")
    with pyproject_path.open("rb") as handle:
        project = tomllib.load(handle).get("project", {})

    dependencies: set[str] = set()
    for dep in _string_list(project.get("dependencies")):
        name = _dependency_name(dep)
        if name:
            dependencies.add(name)

    optional = project.get("optional-dependencies")
    optional = optional if isinstance(optional, dict) else {}
    seen: set[str] = set()

    def visit(extra: str) -> None:
        if extra in seen:
            return
        seen.add(extra)
        for dep in _string_list(optional.get(extra)):
            if dep.startswith("monoclaw-runtime[") and "]" in dep:
                visit(dep.split("[", 1)[1].split("]", 1)[0])
                continue
            name = _dependency_name(dep)
            if name:
                dependencies.add(name)

    visit("local-office")
    return dependencies


def verify_lock(input_root: Path, runtime_root: Path, lock_path: Path | None = None) -> list[str]:
    lock_path = lock_path or input_root / LOCK_REL
    issues: list[str] = []

    if not lock_path.is_file():
        return [f"provisioning lock is required: {lock_path}"]
    try:
        data = json.loads(lock_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"provisioning lock is invalid JSON: {exc}"]

    if data.get("schema_version") != 1:
        issues.append("provisioning lock schema_version must be 1")
    items = data.get("items")
    if not isinstance(items, list):
        return issues + ["provisioning lock items must be a list"]

    available_deps = _local_office_dependency_names(runtime_root / "pyproject.toml")

    for item in items:
        if not isinstance(item, dict):
            issues.append("provisioning lock item must be an object")
            continue
        label = f"{item.get('kind')}:{item.get('name')}"
        classification = item.get("classification")
        if classification == "blocked_unknown":
            issues.append(f"{label} is blocked_unknown")
            continue
        if classification not in ALLOWED_CLASSIFICATIONS:
            issues.append(f"{label} has invalid classification {classification!r}")
            continue
        if classification in {"stock_bundle_candidate", "provisioned_user_config_required"}:
            for dep in _string_list(item.get("python_dependencies")):
                dep_name = _dependency_name(dep)
                if dep_name and dep_name not in available_deps:
                    issues.append(f"{label} missing local-office dependency: {dep_name}")
        for rel in _string_list(item.get("bundled_artifacts")):
            artifact = (input_root / rel).resolve()
            try:
                artifact.relative_to(input_root)
            except ValueError:
                issues.append(f"{label} bundled artifact escapes input root: {rel}")
                continue
            if not artifact.exists():
                issues.append(f"{label} bundled artifact missing: {rel}")

    return issues


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify Hatch provisioning lock")
    parser.add_argument("--input-root", required=True)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--lock")
    args = parser.parse_args(argv)

    issues = verify_lock(
        Path(args.input_root).resolve(),
        Path(args.runtime_root).resolve(),
        Path(args.lock).resolve() if args.lock else None,
    )
    if issues:
        for issue in issues:
            print(issue, file=sys.stderr)
        return 1
    print("Provisioning lock verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
