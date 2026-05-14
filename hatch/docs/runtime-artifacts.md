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
   medium. Hatch verifies its manifest before mutating the target Mac. Optional
   large sidecar payloads such as model packs and Mona secretary `tool-packs/`
   live beside `dist/` and carry their own manifests.
3. **Installed customer runtime**: `~/.monoclaw/` on the target Mac. It uses
   bundle-provided runtime files, support runtimes, skills, and launchd
   configuration. Hatch makes the bundled `monoclaw` runtime runnable, then
   hands technician/customer-specific initialization to `monoclaw setup`.

Assembly-time dependencies are not target-Mac dependencies unless the installer
explicitly requires them after manifest verification.

## Assembly Happy Path

Run the production assembler from the Hatch source directory:

```bash
cd /Users/admin/Projects/hatch
bash scripts/build_wheelhouse.sh
./build.sh
```

The assembler expects the runtime checkout at `../monoclaw-runtime` and non-git
inputs under `/Users/admin/Projects/hatch/bundle-inputs/`. Required production
inputs are `bundle-inputs/vendor/python/current/bin/python3` and a populated
`bundle-inputs/vendor/wheelhouse/` for the `local-office` runtime dependency
profile. Optional vendor trees such as `support`, `browser`, `skills`, and
`launchd` are copied when present and represented in the generated manifest.
When `bundle-inputs/vendor/skills` is absent, the assembler stages the bundled
runtime skills from `../monoclaw-runtime/skills`.

If `bundle-inputs/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf` exists, the
assembler creates an optional sibling sidecar at
`model-packs/gemma-4-e4b/`. That model pack is not part of the core
`dist/hatch-manifest.json`; it has its own `model-pack-manifest.json` and is
installed with `dist/install-gemma-model.sh`.

By default (`HATCH_INCLUDE_MONA_TOOLS` not set to `0`), the assembler also
builds `tool-packs/mona-secretary-tools/` beside `dist/`. That Mona secretary
tools pack is not part of `dist/hatch-manifest.json`; it ships its own
`tools-pack-manifest.json` and is installed after the core bundle via
`dist/install-mona-tools.sh` (invoked from `dist/install.sh`). Copy `tool-packs/`
to the provisioning medium next to `dist/`, the same way optional model packs are
copied. Omit the directory only when you disabled Mona at build time or plan to
skip install-time Mona with `HATCH_INSTALL_MONA_TOOLS=0` on the target.

A second sidecar slot is reserved for **skill-deps-pack** at
`tool-packs/skill-deps-pack/`. It is the per-skill counterpart to Mona
and exists for small CLI dependencies that move individual MonoClaw
skills from `external_runtime_only` to `provisioned_user_config_required`
in their `metadata.monoclaw.provisioning` block. The pack is **disabled
by default** (`HATCH_INCLUDE_SKILL_DEPS=1` to enable). When enabled and
populated, it follows the same shape as the Mona pack:
`bundle-inputs/vendor/skill-deps/tool-lock.json` drives the build, the
output sits beside `dist/`, the install post-step is
`dist/install-skill-deps.sh`, and `HATCH_INSTALL_SKILL_DEPS=0` skips the
post-step on the target. See `bundle-inputs/vendor/skill-deps/README.md`
for the contract and the per-binary PR checklist.

`scripts/build_wheelhouse.sh` is the canonical helper for populating
`bundle-inputs/vendor/wheelhouse/` on the assembly machine. It builds/downloads
wheels for bootstrap tools (`pip`, `setuptools`, `wheel`) and
`../monoclaw-runtime[local-office]`. Set `HATCH_CLEAN_WHEELHOUSE=1` when you
need to refresh the directory from scratch. The target Mac install remains
offline for core runtime dependencies.

Copy both `dist/` and (when built) sibling directories such as `tool-packs/` and
optional `model-packs/` under the same parent on the pendrive. After copying,
the target Mac happy path is:

```bash
cd /Volumes/<PENDRIVE>/dist
./install.sh
```

`install.sh` is generated into the prepared bundle and invokes
`bin/hatch --apply --bundle-root <dist> install`, then runs `install-mona-tools.sh`
when Mona tools are enabled at install time unless `HATCH_INSTALL_MONA_TOOLS=0`.

## Prepared Bundle Layout

```text
dist/
  hatch-manifest.json
  install.sh
  install-gemma-model.sh
  install-mona-tools.sh
  bin/
    hatch
  lib/
    common.sh
  runtime/
    monoclaw_runtime-<version>-py3-none-any.whl
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
    browser/
      chromium/
    skills/
    wheelhouse/
      *.whl
    launchd/
  tests/
    run-hatch-dry-run.sh

model-packs/
  gemma-4-e4b/
    model-pack-manifest.json
    gemma-4-e4b.gguf

tool-packs/
  mona-secretary-tools/
    tools-pack-manifest.json
    bin/
    plugins/
    ...
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
- `models`: list of bundled core-bundle model descriptors with `id`,
  `provider`, `role`, `path`, and `required`. This list may be empty; optional
  sidecar model packs are represented by their own manifests.
- `artifacts`: list of files with relative `path`, `kind`, `sha256`, and
  `bytes`. Future manifests may also include directory entries, but file entries
  are the integrity boundary for generated Hatch bundles.

Every listed path must stay inside the bundle root after symlink resolution.
Installers must reject absolute paths, `..` traversal, missing required
artifacts, SHA mismatches, and architecture mismatches.

Closure verification ignores only known macOS transport metadata that can be
created after the bundle is copied to a pendrive: `.DS_Store`, AppleDouble
`._*` files, and files under `__MACOSX/`, `.Spotlight-V100/`, `.fseventsd/`,
or `.Trashes/`. These files are also omitted if present during manifest
generation. Any other unlisted file, including generated bytecode, logs, or
unexpected payload files, remains a verification failure.

## Installed Runtime Layout

```text
~/.monoclaw/
  .env
  customer/
  logs/
  skills/
  vendor/
    runtime/
      monoclaw_runtime-<version>-py3-none-any.whl
      venv/
    python/
    support/
    models/
    browser/
    skills/
    wheelhouse/
    launchd/
```

`vendor/` is owned by Hatch and can be replaced during install or update.
`customer/` is preserved unless the technician explicitly confirms a fresh
reset. Logs may be rotated or captured, but must not be committed to source
control. Existing `~/.monoclaw/.env` and `~/.monoclaw/config.yaml` are preserved
on reruns; Hatch leaves missing configuration files for `monoclaw setup`
instead of forcing a local-inference default.
The user-facing command shim is installed at `~/.local/bin/monoclaw` and points
at `~/.monoclaw/vendor/runtime/venv/bin/monoclaw`.

## Runtime Bootstrap Contract

After copying verified assets, Hatch creates a managed Python virtual
environment under `~/.monoclaw/vendor/runtime/venv` and installs:

```bash
~/.monoclaw/vendor/runtime/monoclaw_runtime-<version>-py3-none-any.whl[local-office]
```

Hatch installs with `--no-index --find-links ~/.monoclaw/vendor/wheelhouse`.
The wheelhouse is required for production runtime bootstrap; if it is omitted,
Hatch fails unless `HATCH_ALLOW_RUNTIME_NETWORK_FALLBACK=1` is explicitly set
for diagnostics. Runtime wheels must keep their PEP 427 filename
(`monoclaw_runtime-...-py3-none-any.whl`) so pip can validate and install them.
For older bundles that used the legacy `monoclaw-runtime.whl` staging name,
Hatch copies the file to a temporary valid wheel filename before invoking pip.
The runtime requires a bundled Python 3.11 or newer. Hatch chooses
`HATCH_RUNTIME_PYTHON` when set, then bundled interpreters under
`~/.monoclaw/vendor/python/current/bin/`. System or Homebrew Python is only used
when `HATCH_ALLOW_SYSTEM_RUNTIME_PYTHON=1` is explicitly set for diagnostics. If
no bundled Python 3.11+ interpreter is available, Hatch fails before creating the
runtime venv so the assembly bundle can be fixed. If venv creation fails during
`ensurepip`, Hatch fails rather than fetching `get-pip.py`; the prepared bundle
must be rebuilt with a working Python runtime.
Hatch probes bundled Python with bytecode writes disabled; do not run Python
smoke tests inside `dist/` after manifest generation because Python may rewrite
`__pycache__` files and invalidate the manifest.

Fresh configs are not seeded with LM Studio defaults. The technician runs
`monoclaw setup` to choose LM Studio, a hosted provider, messaging platforms,
and customer-specific secrets.

## Target Mac Prerequisites

- Apple Silicon Mac.
- Supported macOS version declared by the manifest.
- Xcode Command Line Tools installed or installable from the bundled CLT
  payload. If macOS opens a GUI prompt, Hatch must tell the technician exactly
  what to do.
- Homebrew is installed automatically with the official internet installer when
  missing. Set `HATCH_SKIP_HOMEBREW_INSTALL=1` to skip this step for offline
  bench tests or technician-managed installs. Homebrew is not the runtime Python
  provider; the prepared bundle must include `vendor/python/current/bin/python3`.
- LM Studio is installed manually from the official `.dmg` when local inference
  is required. Hatch checks and reports readiness, but does not run LM Studio's
  installer or CLI import commands.
- Docker Desktop is installed manually from the official `.dmg` when sandboxed
  tools are required. Missing or unlaunched Docker should warn unless the
  enabled capability marks it required.
- macOS privacy permissions for automation features, handled as technician
  checklist items rather than hidden terminal assumptions.

## Verification Contract

`hatch verify` must check:

- Manifest was verified for the installed core bundle.
- `~/.monoclaw/vendor` exists and has the expected runtime, support, skill, and
  non-model assets for enabled core capabilities.
- `~/.monoclaw/vendor/runtime/venv/bin/monoclaw` and
  `~/.local/bin/monoclaw` exist.
- `monoclaw --version` resolves from the installed runtime after the command
  shim is on `PATH`.
- Bundled skills are present in `~/.monoclaw/skills` without deleting
  technician-created skills.
- launchd agents for enabled services are loaded only after bundle plists are
  finalized and service installation is enabled.
- Logs are writable.
- Technician-facing diagnostics avoid printing secrets, tokens, or customer
  content.

Optional local inference readiness is checked separately with
`hatch verify-local-inference`. Optional Gemma model packs are verified with
`hatch --model-pack-root <pack> verify-model-pack` and staged with
`hatch --model-pack-root <pack> install-model` or the generated
`dist/install-gemma-model.sh` wrapper. Hatch copies the model into
`~/.monoclaw/vendor/models/gemma-4-e4b/` and prints manual LM Studio import
instructions.
