# Hatch Provisioning Contract

Hatch is responsible for making a factory-reset Mac ready to run MonoClaw for a
non-technical office worker.

## Managed By Hatch

- MonoClaw runtime installation.
- Optional local inference readiness checks and optional Gemma 4 E4B model-pack
  staging when the sidecar is present on the provisioning medium.
- Agent skills, tools, and default workspace bootstrap.
- Technician handoff: `./install.sh` auto-runs `monoclaw provision
  --non-interactive` (identity-free system defaults). End users run
  `monoclaw onboard` for secrets, messaging, email, and macOS permissions.
- launchd service lifecycle for MonoClaw-managed processes after finalized
  plists are shipped.
- Existing MonoClaw and legacy runtime gateway cleanup for repeated bench runs.
- Technician-readable readiness checks.

## Manual Or Semi-Manual Prerequisites

- Xcode Command Line Tools can trigger a macOS GUI prompt.
- Homebrew installation uses the official internet installer when `brew` is
  missing, unless explicitly skipped for offline bench work. Homebrew is not the
  core runtime Python provider; the prepared bundle must include Python 3.11+.
- LM Studio is a manual `.dmg` install and first-launch task when local
  inference is required.
- Docker Desktop can require GUI installation, first launch, and permission
  approval.
- macOS privacy permissions may require System Settings interaction.

Hatch must detect these states and tell the technician exactly what to do. It
should not pretend GUI-only steps can always be solved from the terminal.

## Managed Paths

- Runtime home: `~/.monoclaw`
- Vendor-managed files: `~/.monoclaw/vendor`
- Runtime venv: `~/.monoclaw/vendor/runtime/venv`
- Command shim: `~/.local/bin/monoclaw`
- Customer-preserved files: `~/.monoclaw/customer`
- Logs and diagnostics: `~/.monoclaw/logs`
- Future local model cache: `~/.monoclaw/vendor/model-cache`

## Prepared Bundle Contract

Hatch installs from a manifest-verified prepared bundle. The detailed artifact
layout, manifest fields, target Mac prerequisites, and verification checks live
in `docs/runtime-artifacts.md`.

Target Macs should receive bundled runtime assets rather than relying on
Homebrew, source checkouts, or network downloads for the core MonoClaw install.
Assembly machines may use those tools while creating the prepared bundle. A
bundle-provided `vendor/wheelhouse` is required for `local-office` Python
dependencies; network resolution is a diagnostic-only fallback behind an
explicit opt-in flag. Assembly operators should run
`bash scripts/build_wheelhouse.sh` before `./build.sh` when the wheelhouse is
missing or stale. Optional model packs are manifest-verified sidecars, not part
of the core runtime manifest.

Hatch owns deterministic installation. The setup wizard owns technician and
customer choices. A successful install should end with a clear handoff:

```bash
monoclaw --version
monoclaw provision --non-interactive   # technician (auto-run by install.sh)
monoclaw onboard                       # end user after receiving the Mac
```

## Safety Defaults

- Dry-run is the default for every lifecycle command; real host mutation requires
  an explicit `--apply`.
- Existing services must be stopped before runtime files are replaced.
- Existing `~/.monoclaw/.env`, `~/.monoclaw/config.yaml`,
  `~/.monoclaw/customer`, and technician-created skills must be preserved.
- Secrets, customer data, provisioning logs, model weights, and vendor bundles
  must never be committed to `monoclaw-developer`.
