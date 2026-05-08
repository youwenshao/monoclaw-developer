# Hatch Provisioning Contract

Hatch is responsible for making a factory-reset Mac ready to run MonoClaw for a
non-technical office worker.

## Managed By Hatch

- MonoClaw runtime installation.
- Local inference runtime detection and future model staging.
- Agent skills, tools, and default workspace bootstrap.
- launchd service lifecycle for MonoClaw-managed processes.
- Existing MonoClaw and legacy runtime gateway cleanup for repeated bench runs.
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

## Prepared Bundle Contract

Hatch installs from a manifest-verified prepared bundle. The detailed artifact
layout, manifest fields, target Mac prerequisites, and verification checks live
in `docs/runtime-artifacts.md`.

Target Macs should receive bundled runtime assets rather than relying on
Homebrew, source checkouts, or network downloads for the core MonoClaw install.
Assembly machines may use those tools while creating the prepared bundle.

## Safety Defaults

- Dry-run is the default for every lifecycle command; real host mutation requires
  an explicit `--apply`.
- Existing services must be stopped before runtime files are replaced.
- Secrets, customer data, provisioning logs, model weights, and vendor bundles
  must never be committed to `monoclaw-developer`.
