# Hatch Installer Skill

Use this when modifying `hatch/`.

## Product Contract

Hatch provisions a fresh factory-configured Mac for MonoClaw technicians. It
should make terminal-manageable setup automatic and make manual prerequisites
obvious, calm, and recoverable for non-technical customer environments.

## Rules

- Default to `--dry-run` for destructive or machine-changing flows.
- Detect existing MonoClaw and legacy Hermes services before installing.
- Stop and uninstall old gateway services before replacing runtime files.
- Keep model weights, vendor bundles, logs, and customer overlays out of git.
- Prefer idempotent checks over assuming a fresh machine.
- Explain manual actions for Xcode CLT and Docker Desktop rather than hiding
  them behind failing commands.

## Verification

Run these before handoff:

```bash
bash hatch/bin/hatch --dry-run preflight
bash -n hatch/bin/hatch
```
