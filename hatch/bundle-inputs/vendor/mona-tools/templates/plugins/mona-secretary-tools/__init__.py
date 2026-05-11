"""MonoClaw plugin wrappers for the optional Mona secretary tools pack."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any


def _home() -> Path:
    return Path(os.environ.get("MONOCLAW_HOME", Path.home() / ".monoclaw")).expanduser()


def _tool(name: str) -> Path:
    return _home() / "vendor" / "mona-tools" / "bin" / name


_SECRET_PATTERNS = [
    (re.compile(r"xox[baprs]-[A-Za-z0-9-]+"), "xox***"),
    (re.compile(r"gh[pousr]_[A-Za-z0-9_]+"), "gh***"),
    (re.compile(r"sk-[A-Za-z0-9_-]{12,}"), "sk-***"),
    (re.compile(r"TWILIO_AUTH_TOKEN=[^\s]+", re.I), "TWILIO_AUTH_TOKEN=***"),
]


def _redact(text: str) -> str:
    value = text or ""
    for pattern, replacement in _SECRET_PATTERNS:
        value = pattern.sub(replacement, value)
    return value


def _run_json(command: list[str], timeout: int = 60) -> str:
    try:
        proc = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        return json.dumps({"success": False, "error": str(exc)})
    except subprocess.TimeoutExpired:
        return json.dumps({"success": False, "error": "command timed out"})

    if proc.returncode != 0:
        return json.dumps(
            {
                "success": False,
                "exit_code": proc.returncode,
                "stderr": _redact(proc.stderr[-2000:]),
            }
        )
    try:
        payload: Any = json.loads(proc.stdout)
    except json.JSONDecodeError:
        payload = {"text": proc.stdout}
    return json.dumps({"success": True, "data": payload})


def _available(binary: str) -> bool:
    path = _tool(binary)
    return path.is_file() and os.access(path, os.X_OK)


def _doctor(binary: str, *args: str) -> bool:
    if not _available(binary):
        return False
    try:
        proc = subprocess.run(
            [str(_tool(binary)), *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0


def register(ctx: Any) -> None:
    ctx.register_tool(
        name="mona_whatsapp_search",
        toolset="mona_secretary",
        schema={
            "name": "mona_whatsapp_search",
            "description": "Search the local read-only WhatsApp Desktop archive via wacrawl.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "limit": {"type": "integer", "default": 20},
                },
                "required": ["query"],
            },
        },
        handler=lambda args, **_: _run_json(
            [
                str(_tool("wacrawl")),
                "--json",
                "search",
                str(args.get("query", "")),
                "--limit",
                str(args.get("limit", 20)),
            ]
        ),
        check_fn=lambda: _doctor("wacrawl", "--json", "doctor"),
    )

    ctx.register_tool(
        name="mona_whatsapp_unread",
        toolset="mona_secretary",
        schema={
            "name": "mona_whatsapp_unread",
            "description": "List unread WhatsApp chats from the local read-only wacrawl archive.",
            "parameters": {
                "type": "object",
                "properties": {
                    "limit": {"type": "integer", "default": 20},
                },
            },
        },
        handler=lambda args, **_: _run_json(
            [
                str(_tool("wacrawl")),
                "--json",
                "unread",
                "--limit",
                str(args.get("limit", 20)),
            ]
        ),
        check_fn=lambda: _doctor("wacrawl", "--json", "doctor"),
    )

    ctx.register_tool(
        name="mona_slack_search",
        toolset="mona_secretary",
        schema={
            "name": "mona_slack_search",
            "description": "Search the local Slack archive via slacrawl.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "workspace": {"type": "string", "default": ""},
                },
                "required": ["query"],
            },
        },
        handler=lambda args, **_: _run_json(
            [
                str(_tool("slacrawl")),
                "--format",
                "json",
                "search",
                *(
                    ["--workspace", str(args.get("workspace"))]
                    if args.get("workspace")
                    else []
                ),
                str(args.get("query", "")),
            ]
        ),
        check_fn=lambda: _doctor("slacrawl", "doctor", "--format", "json"),
    )

    ctx.register_tool(
        name="mona_slack_digest",
        toolset="mona_secretary",
        schema={
            "name": "mona_slack_digest",
            "description": "Generate a local Slack activity digest via slacrawl.",
            "parameters": {
                "type": "object",
                "properties": {
                    "since": {"type": "string", "default": "7d"},
                    "workspace": {"type": "string", "default": ""},
                },
            },
        },
        handler=lambda args, **_: _run_json(
            [
                str(_tool("slacrawl")),
                "--format",
                "json",
                "digest",
                "--since",
                str(args.get("since", "7d")),
                *(
                    ["--workspace", str(args.get("workspace"))]
                    if args.get("workspace")
                    else []
                ),
            ]
        ),
        check_fn=lambda: _doctor("slacrawl", "doctor", "--format", "json"),
    )

    ctx.register_tool(
        name="mona_summarize",
        toolset="mona_secretary",
        schema={
            "name": "mona_summarize",
            "description": "Summarize a URL or local file via the Hatch-bundled summarize CLI.",
            "parameters": {
                "type": "object",
                "properties": {
                    "source": {"type": "string"},
                    "json": {"type": "boolean", "default": True},
                },
                "required": ["source"],
            },
        },
        handler=lambda args, **_: _run_json(
            [
                str(_tool("summarize")),
                str(args.get("source", "")),
                "--json",
            ],
            timeout=180,
        ),
        check_fn=lambda: _doctor("summarize", "--help"),
    )

    ctx.register_tool(
        name="mona_github_triage",
        toolset="mona_secretary",
        schema={
            "name": "mona_github_triage",
            "description": "Inspect local ghcrawl clusters for GitHub issue and PR triage.",
            "parameters": {
                "type": "object",
                "properties": {
                    "repo": {"type": "string"},
                    "limit": {"type": "integer", "default": 20},
                    "min_size": {"type": "integer", "default": 2},
                },
                "required": ["repo"],
            },
        },
        handler=lambda args, **_: _run_json(
            [
                str(_tool("ghcrawl")),
                "clusters",
                str(args.get("repo", "")),
                "--limit",
                str(args.get("limit", 20)),
                "--min-size",
                str(args.get("min_size", 2)),
                "--json",
            ],
            timeout=120,
        ),
        check_fn=lambda: _doctor("ghcrawl", "doctor", "--json"),
    )
