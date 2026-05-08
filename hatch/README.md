# Hatch

Hatch is the MonoClaw provisioning installer for technician-operated Mac setup.
It is designed for fresh factory-configured Mac mini and iMac devices, while
also supporting rapid repeated test runs on CI or bench machines by detecting
and stopping existing runtimes before installation.

Hatch has two operator-facing happy paths: `./build.sh` creates a prepared
bundle on an assembly machine, and the generated `dist/install.sh` installs that
bundle from a provisioning medium on the target Mac.

## Commands

```bash
# Assembly machine, from this hatch/ directory.
./build.sh

# Target Mac, from the copied dist/ directory on the pendrive.
./install.sh
```

The lower-level lifecycle commands remain available for diagnostics:

```bash
bash bin/hatch --dry-run preflight
bash bin/hatch --dry-run cleanup-existing
bash bin/hatch --dry-run install
```

Hatch defaults to dry-run. Pass `--apply` only when running on a machine intended
for provisioning.

## Runtime Artifact Contract

Hatch is bundle-first. The target Mac install path is defined in
`docs/runtime-artifacts.md`: assembly machines create a prepared `dist/` bundle,
Hatch verifies `hatch-manifest.json`, and customer Macs receive managed files
under `~/.monoclaw/vendor` while preserving `~/.monoclaw/customer`.
If `~/.monoclaw/.env` or `~/.monoclaw/config.yaml` already exists, Hatch keeps
those files instead of overwriting technician or customer configuration.

## Production Bundle Inputs

`./build.sh` is strict by default. It expects the MonoClaw runtime checkout at
`../../monoclaw-runtime` and production-only large inputs under
`hatch/bundle-inputs/`, which is intentionally ignored by git:

```text
bundle-inputs/
  vendor/
    lm-studio/
      LM Studio.app
    models/
      gemma-4-e4b/
        gemma-4-e4b.gguf
    python/        # optional
    support/       # optional
    browser/       # optional
    skills/        # optional
    launchd/       # optional
```

The builder stages these files into `dist/`, builds the runtime dashboard assets
and Python wheel from `../../monoclaw-runtime`, writes `hatch-manifest.json` with
artifact sizes and SHA-256 hashes, and verifies the bundle before returning.
Copy the resulting `dist/` directory to the provisioning pendrive.

## Verification

```bash
bash tests/run_tests.sh
```

Release evidence and physical bench expectations are listed in
`docs/verification-gates.md`.

## Design Goals

- Make terminal-manageable setup automatic.
- Explain manual prerequisites such as Xcode CLT prompts and Docker Desktop.
- Keep local model weights and vendor bundles in managed directories.
- Stop and uninstall existing MonoClaw or legacy runtime services before
  replacing runtime files.
- Produce clear readiness checks for technicians instead of requiring them to
  read long logs.

## Non-Goals For This Scaffold

- It does not download LLM weights yet.
- It does not install Homebrew packages yet.
- It does not mutate launchd services unless dry-run is disabled and a future
  implementation fills in the install steps.
