# Hatch Provisioning Contract

Hatch is responsible for making a factory-reset Mac ready to run MonoClaw for a
non-technical office worker.

## Managed By Hatch

- MonoClaw runtime installation.
- Local inference runtime detection and future model staging.
- Agent skills, tools, and default workspace bootstrap.
- launchd service lifecycle for MonoClaw-managed processes.
- Existing MonoClaw and legacy Hermes gateway cleanup for repeated bench runs.
- Technician-readable readiness checks.

## Manual Or Semi-Manual Prerequisites

- Xcode Command Line Tools can trigger a macOS GUI prompt.
- Docker Desktop can require GUI installation, first launch, and permission
  approval.
- macOS privacy permissions may require System Settings interaction.

Hatch must detect these states and tell the technician exactly what to do. It
should not pretend GUI-only steps can always be solved from the terminal.

## Managed Paths

- Runtime home: `~/.monoclaw`
- Vendor-managed files: `~/.monoclaw/vendor`
- Customer-preserved files: `~/.monoclaw/customer`
- Logs and diagnostics: `~/.monoclaw/logs`
- Future local model cache: `~/.monoclaw/vendor/model-cache`

## Safety Defaults

- `--dry-run` must remain available for every lifecycle command.
- Existing services must be stopped before runtime files are replaced.
- Secrets, customer data, provisioning logs, model weights, and vendor bundles
  must never be committed to `monoclaw-developer`.
