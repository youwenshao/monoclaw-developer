# Hatch Runtime Artifacts

## Purpose

Hatch installs MonoClaw from a prepared bundle. The target customer Mac should
not depend on Homebrew, GitHub clones, or ad hoc package downloads for the core
runtime. Network access may be used by technicians only when a documented
fallback is enabled.

## Three Environments

Keep these environments separate in code, docs, logs, and product claims:

1. **Assembly environment**: a developer or technician Mac that builds and
   stages the prepared bundle. It may use Homebrew, Python build tools, Node,
   network downloads, and local source checkouts.
2. **Prepared bundle**: the immutable `dist/` tree copied to a provisioning
   medium. Hatch verifies its manifest before mutating the target Mac.
3. **Installed customer runtime**: `~/.monoclaw/` on the target Mac. It uses
   bundle-provided runtime files, support runtimes, model files, skills, and
   launchd configuration.

Assembly-time dependencies are not target-Mac dependencies unless the installer
explicitly requires them after manifest verification.

## Assembly Happy Path

Run the production assembler from the Hatch source directory:

```bash
cd hatch
./build.sh
```

The assembler expects the runtime checkout at `../../monoclaw-runtime` and large,
non-git inputs under `hatch/bundle-inputs/`. Required production inputs are
`bundle-inputs/vendor/lm-studio/LM Studio.app` and
`bundle-inputs/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf`. Optional vendor
trees such as `python`, `support`, `browser`, `skills`, and `launchd` are copied
when present and represented in the generated manifest.

After `dist/` is copied to a pendrive, the target Mac happy path is:

```bash
cd /Volumes/<PENDRIVE>/dist
./install.sh
```

`install.sh` is generated into the prepared bundle and invokes
`bin/hatch --apply --bundle-root <dist> install`.

## Prepared Bundle Layout

```text
dist/
  hatch-manifest.json
  install.sh
  bin/
    hatch
  lib/
    common.sh
  runtime/
    monoclaw-runtime.whl
    constraints.txt
    about.md
  vendor/
    python/
      current/
    support/
      node/
        current/
      clt/
        current/
    lm-studio/
      LM Studio.app
    models/
      gemma-4-e4b/
        gemma-4-e4b.gguf
    browser/
      chromium/
    skills/
    launchd/
  tests/
    run-hatch-dry-run.sh
```

The layout may omit optional directories when the manifest marks the matching
capability as disabled. The installer must not silently assume omitted optional
assets are available.

## Manifest Contract

`dist/hatch-manifest.json` is required. Hatch must verify it before cleanup,
install, update, or service start steps that mutate the target Mac.

Required top-level fields:

- `schema_version`: integer manifest schema version.
- `bundle_id`: stable identifier for the prepared bundle.
- `bundle_version`: human-readable version or release tag.
- `created_at`: ISO-8601 timestamp from the assembly environment.
- `target`: object with `platform`, `arch`, and `minimum_macos`.
- `runtime`: object with MonoClaw package name, version, wheel path, and entry
  point paths.
- `capabilities`: object declaring enabled optional surfaces such as
  `local_inference`, `lm_studio`, `telegram_gateway`, `browser_automation`,
  `sandbox_worker`, and `voice`.
- `models`: list of bundled model descriptors with `id`, `provider`, `role`,
  `path`, and `required`.
- `artifacts`: list of files with relative `path`, `kind`, `sha256`, and
  `bytes`. Future manifests may also include directory entries, but file entries
  are the integrity boundary for generated Hatch bundles.

Every listed path must stay inside the bundle root after symlink resolution.
Installers must reject absolute paths, `..` traversal, missing required
artifacts, SHA mismatches, and architecture mismatches.

## Installed Runtime Layout

```text
~/.monoclaw/
  .env
  customer/
  logs/
  vendor/
    runtime/
    python/
    support/
    lm-studio/
    models/
    browser/
    skills/
    launchd/
```

`vendor/` is owned by Hatch and can be replaced during install or update.
`customer/` is preserved unless the technician explicitly confirms a fresh
reset. Logs may be rotated or captured, but must not be committed to source
control. Existing `~/.monoclaw/.env` and `~/.monoclaw/config.yaml` are preserved
on reruns; Hatch only writes LM Studio defaults when those files do not exist.

## Target Mac Prerequisites

- Apple Silicon Mac.
- Supported macOS version declared by the manifest.
- Xcode Command Line Tools installed or installable from the bundled CLT
  payload. If macOS opens a GUI prompt, Hatch must tell the technician exactly
  what to do.
- Docker Desktop only when the bundle enables sandbox-worker assets. Missing or
  unlaunched Docker should warn unless the enabled capability marks it required.
- macOS privacy permissions for automation features, handled as technician
  checklist items rather than hidden terminal assumptions.

## Verification Contract

`hatch verify` must check:

- Manifest was verified for the installed bundle.
- `~/.monoclaw/vendor` exists and has the expected runtime, support, skill, and
  model assets for enabled capabilities.
- `monoclaw --version` resolves from the installed runtime.
- LM Studio assets and Gemma 4 E4B are present when `local_inference` is
  enabled. Technicians may use `~/.lmstudio/bin/lms bootstrap` and
  `lms import <model.gguf> --copy --yes` after first launch when CLI import is
  available; Hatch must keep a manual first-launch fallback for macOS GUI
  approvals.
- launchd agents for enabled services are loaded.
- Logs are writable.
- Technician-facing diagnostics avoid printing secrets, tokens, or customer
  content.
