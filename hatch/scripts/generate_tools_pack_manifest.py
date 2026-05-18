#!/usr/bin/env python3
"""Generate a manifest for an optional Hatch tools pack."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
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


_VERIFY_OPTIONAL_KEYS = (
    "verify_command",
    "verify_strict",
    "verify_env",
    "verify_skip_reason",
)


def _validate_verify_fields(name: str, entry: dict[str, object]) -> None:
    """Reject illegal verify_* combinations before they reach the manifest."""

    has_cmd = entry.get("verify_command") not in (None, [])
    has_skip = bool(entry.get("verify_skip_reason"))
    if has_cmd and has_skip:
        raise SystemExit(
            f"tool {name!r} sets both verify_command and verify_skip_reason "
            "(mutually exclusive)"
        )
    cmd = entry.get("verify_command")
    if cmd is not None:
        if not isinstance(cmd, list) or not cmd or not all(
            isinstance(part, str) for part in cmd
        ):
            raise SystemExit(
                f"tool {name!r} verify_command must be a non-empty list of strings"
            )
    strict = entry.get("verify_strict")
    if strict is not None and not isinstance(strict, bool):
        raise SystemExit(f"tool {name!r} verify_strict must be a boolean")
    env = entry.get("verify_env")
    if env is not None:
        if not isinstance(env, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in env.items()
        ):
            raise SystemExit(
                f"tool {name!r} verify_env must be an object of string->string"
            )
    skip = entry.get("verify_skip_reason")
    if skip is not None and (not isinstance(skip, str) or not skip.strip()):
        raise SystemExit(
            f"tool {name!r} verify_skip_reason must be a non-empty string"
        )


def _check_pack_path(name: str, rel_path: str, root: Path) -> Path:
    raw_path = root / rel_path
    path = raw_path.resolve(strict=False)
    if path != root and root not in path.parents:
        raise SystemExit(f"tool {name!r} artifact escapes pack root: {rel_path}")
    if is_ignored_metadata(path, root):
        raise SystemExit(
            f"tool {name!r} artifact points to ignored metadata: {rel_path}"
        )
    if not path.is_file():
        raise SystemExit(f"tool {name!r} artifact missing: {rel_path}")
    return path


def parse_tool(value: str, root: Path) -> dict[str, object]:
    """Parse a colon-encoded --tool string (legacy)."""

    parts = value.split(":", 5)
    if len(parts) != 5:
        raise SystemExit(
            "--tool must use name:version:path:activation:permission[,permission] format"
        )
    name, version, rel_path, activation, permissions = [part.strip() for part in parts]
    if not name or not version or not rel_path or not activation:
        raise SystemExit("--tool fields must be non-empty")
    path = _check_pack_path(name, rel_path, root)
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


def parse_tools_file(path: Path, root: Path) -> list[dict[str, object]]:
    """Parse a JSON tools descriptor file.

    Each entry must declare name, version, path, activation,
    required_permissions. Optional verify_command, verify_strict,
    verify_env, verify_skip_reason are validated and passed through.
    """

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--tools-file is not valid JSON: {path} ({exc})") from None
    if not isinstance(raw, list):
        raise SystemExit("--tools-file must contain a JSON list of tool objects")
    tools: list[dict[str, object]] = []
    for index, entry in enumerate(raw):
        if not isinstance(entry, dict):
            raise SystemExit(f"--tools-file entry {index} is not an object")
        for required in ("name", "version", "path", "activation", "required_permissions"):
            if required not in entry or entry[required] in (None, "", []):
                raise SystemExit(
                    f"--tools-file entry {index} missing required field {required!r}"
                )
        if not isinstance(entry["required_permissions"], list) or not all(
            isinstance(perm, str) and perm for perm in entry["required_permissions"]
        ):
            raise SystemExit(
                f"--tools-file entry {index} required_permissions must be a list of non-empty strings"
            )
        name = str(entry["name"]).strip()
        rel_path = str(entry["path"]).strip()
        path_resolved = _check_pack_path(name, rel_path, root)
        normalized: dict[str, object] = {
            "name": name,
            "version": str(entry["version"]).strip(),
            "path": path_resolved.relative_to(root).as_posix(),
            "activation": str(entry["activation"]).strip(),
            "required_permissions": list(entry["required_permissions"]),
        }
        for key in _VERIFY_OPTIONAL_KEYS:
            if key in entry:
                normalized[key] = entry[key]
        _validate_verify_fields(name, normalized)
        tools.append(normalized)
    return tools


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools-pack-root", required=True)
    parser.add_argument("--pack-id", required=True)
    parser.add_argument("--pack-version", required=True)
    parser.add_argument("--target-arch", required=True)
    parser.add_argument("--node-version", default="")
    parser.add_argument("--node-path", default="node/current/bin/node")
    parser.add_argument(
        "--tool",
        action="append",
        default=[],
        help="(deprecated) Legacy colon-encoded tool descriptor. "
        "Prefer --tools-file for new schemas including verify_command.",
    )
    parser.add_argument(
        "--tools-file",
        default=None,
        help="Path to a JSON file containing a list of tool descriptors. "
        "Supports verify_command, verify_strict, verify_env, verify_skip_reason.",
    )
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

    tools: list[dict[str, object]] = []
    if args.tools_file:
        if args.tool:
            raise SystemExit(
                "use either --tools-file or --tool, not both "
                "(--tool is the legacy colon-encoded path)"
            )
        tools.extend(parse_tools_file(Path(args.tools_file).resolve(), root))
    else:
        if args.tool:
            print(
                "[generate_tools_pack_manifest] warn: --tool colon-encoded "
                "args are deprecated; migrate to --tools-file to declare "
                "verify_command/verify_strict/verify_env/verify_skip_reason.",
                file=sys.stderr,
            )
        tools.extend(parse_tool(tool, root) for tool in args.tool)
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
