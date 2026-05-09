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
# Assembly machine, from /Users/admin/Projects/hatch.
bash scripts/build_wheelhouse.sh
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
under `~/.monoclaw/vendor` while preserving `~/.monoclaw/customer`. Hatch also
creates a managed runtime venv, installs the bundled wheel with the
`local-office` extra, writes a `~/.local/bin/monoclaw` shim, and hands the
technician to `monoclaw setup` for customer-specific initialization.
If `~/.monoclaw/.env` or `~/.monoclaw/config.yaml` already exists, Hatch keeps
those files instead of overwriting technician or customer configuration.

## Production Bundle Inputs

`./build.sh` is strict by default. It expects the MonoClaw runtime checkout at
`../monoclaw-runtime` and production-only large inputs under this checkout's
`bundle-inputs/` directory. For the standard workspace, that is
`/Users/admin/Projects/hatch/bundle-inputs/`, which is intentionally ignored by
git:

```text
bundle-inputs/
  vendor/
    python/
      current/
        bin/python3
    support/       # optional
    browser/       # optional
    skills/        # optional
    wheelhouse/    # required for offline local-office deps
    launchd/       # optional
    models/        # optional model-pack inputs, not staged into core dist
      gemma-4-e4b/
        gemma-4-e4b.gguf
```

The builder stages these files into `dist/`, builds the runtime dashboard assets
and Python wheel from `../monoclaw-runtime`, writes `hatch-manifest.json` with
artifact sizes and SHA-256 hashes, and verifies the bundle before returning. If
no curated `bundle-inputs/vendor/skills` tree exists, the builder stages the
runtime checkout's bundled `skills/` tree. Copy the resulting `dist/` directory
to the provisioning pendrive. When the optional Gemma input is present, the
builder writes a sibling `model-packs/gemma-4-e4b/` directory with its own
`model-pack-manifest.json`; copy that sibling directory to the pendrive beside
`dist/` if you want to avoid downloading the model on the target Mac.

Populate the required runtime wheelhouse before `./build.sh`:

```bash
bash scripts/build_wheelhouse.sh
```

The helper downloads/builds wheels for `pip`, `setuptools`, `wheel`, and
`../monoclaw-runtime[local-office]` into
`bundle-inputs/vendor/wheelhouse/`. Use `HATCH_CLEAN_WHEELHOUSE=1` to rebuild
that directory from scratch. `./build.sh` fails when the wheelhouse is missing
because the target Mac must not discover or repair core runtime dependencies.

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
- Install the bundled runtime so `monoclaw setup` is available without a source
  checkout.
- Stop and uninstall existing MonoClaw or legacy runtime services before
  replacing runtime files.
- Produce clear readiness checks for technicians instead of requiring them to
  read long logs.

## Non-Goals For This Scaffold

- It does not download LLM weights yet.
- It installs Homebrew with the official terminal installer when needed, but it
  does not use Homebrew Python for the core runtime venv or install arbitrary
  Homebrew packages yet.
- It does not install GUI apps such as LM Studio or Docker Desktop. Technicians
  install those manually from their official `.dmg` packages when required.
- It does not collect customer secrets or messaging credentials; technicians use
  `monoclaw setup` for those choices.
- It does not mutate launchd services until finalized plists are shipped and
  service installation is enabled.
