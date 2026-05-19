#!/usr/bin/env python3
"""Refuse Hatch bundles that are missing the Node subsystems the runtime
needs at first launch.

May 2026 incident: ``monoclaw --tui`` and ``monoclaw whatsapp`` both
relied on source-tree paths (``PROJECT_ROOT/ui-tui`` and
``PROJECT_ROOT/scripts/whatsapp-bridge``) that resolve to non-existent
``site-packages/…`` directories under a wheel install. Hatch now stages
both subtrees under ``dist/vendor/`` and the runtime resolves them via
``$MONOCLAW_HOME/vendor/{tui,whatsapp-bridge}/``. This script is the gate
that fails the bundle build the moment one of those subtrees vanishes.

Lock the contract here so future ``build.sh`` refactors can't silently
drop the staging step.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


# (relative path under dist/, human-readable label, why)
REQUIRED_FILES: tuple[tuple[str, str, str], ...] = (
    (
        "vendor/tui/package.json",
        "TUI sources",
        "monoclaw --tui needs package.json to run `npm install` on the customer Mac",
    ),
    (
        "vendor/tui/dist/entry.js",
        "TUI prebuilt entry",
        "Without prebuilt dist/entry.js, first-run --tui would require a full "
        "`npm run build` on the customer Mac (slow and fails on air-gapped boxes)",
    ),
    (
        # esbuild output filename — see ui-tui/packages/monoclaw-ink/package.json
        # build script (``esbuild src/entry-exports.ts --outdir=dist``). The
        # runtime's ``_monoclaw_ink_bundle_stale`` checks this exact path.
        "vendor/tui/packages/monoclaw-ink/dist/entry-exports.js",
        "TUI Ink bundle",
        "Prebuilt Ink bundle is part of the runtime's _tui_build_needed contract; "
        "without it the runtime triggers a local rebuild on every launch",
    ),
    (
        "vendor/whatsapp-bridge/bridge.js",
        "WhatsApp bridge script",
        "monoclaw whatsapp and the WhatsAppAdapter both spawn node "
        "$MONOCLAW_HOME/vendor/whatsapp-bridge/bridge.js",
    ),
    (
        "vendor/whatsapp-bridge/package.json",
        "WhatsApp bridge package.json",
        "Required for the install-time `warm_whatsapp_bridge_install` "
        "step and for the wizard's on-demand `npm install` fallback",
    ),
    (
        "vendor/whatsapp-bridge/package-lock.json",
        "WhatsApp bridge package-lock.json",
        "Pins the exact whatsapp-web.js / Baileys version we ship; "
        "without it `npm install` would resolve at install time and drift",
    ),
)


def verify(bundle_root: Path) -> list[str]:
    errors: list[str] = []
    if not bundle_root.is_dir():
        return [f"bundle root does not exist: {bundle_root}"]

    for rel, label, why in REQUIRED_FILES:
        path = bundle_root / rel
        if not path.is_file():
            errors.append(
                f"missing {label}: {rel}\n"
                f"  why required: {why}\n"
                f"  expected at: {path}"
            )

    # Defensive: ensure ``vendor/tui/node_modules`` is NOT in the bundle.
    # We intentionally ship sources only — the customer Mac builds a
    # platform-correct ``node_modules`` on first launch. A leaked
    # ``node_modules`` from the Hatch host adds ~150 MB and may carry
    # host-specific native binaries (e.g. macOS-ARM64 .node files that
    # break under Rosetta).
    leaked_dirs = [
        "vendor/tui/node_modules",
        "vendor/whatsapp-bridge/node_modules",
    ]
    for rel in leaked_dirs:
        if (bundle_root / rel).is_dir():
            errors.append(
                f"unwanted node_modules in bundle: {rel}\n"
                f"  why a problem: ships ~150 MB of host-specific binaries "
                f"that may not match the customer Mac's arch"
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bundle-root",
        required=True,
        type=Path,
        help="Path to the prepared bundle directory (typically hatch/dist).",
    )
    args = parser.parse_args()

    errors = verify(args.bundle_root)
    if errors:
        print(
            f"[verify-node-subsystems] FAIL: bundle {args.bundle_root} "
            "is missing required Node subsystems:",
            file=sys.stderr,
        )
        for err in errors:
            print(f"\n  - {err}", file=sys.stderr)
        return 1

    print(
        f"[verify-node-subsystems] ok: vendor/tui and vendor/whatsapp-bridge "
        f"present at {args.bundle_root}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
