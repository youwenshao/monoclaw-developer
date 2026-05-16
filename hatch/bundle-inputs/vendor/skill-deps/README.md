# Skill Dependencies Pack — Bundle Inputs

This directory is the staging contract for an **optional** Hatch sidecar
pack named `tool-packs/skill-deps-pack`. It mirrors the `mona-secretary-tools`
pattern and exists so individual MonoClaw skills (e.g. `apple-reminders`,
`maps`, `findmy`) can move from
`metadata.monoclaw.provisioning.bundle_policy: external_runtime_only`
to `provisioned_user_config_required` by shipping the small CLI they
depend on through Hatch instead of asking the customer to install it
themselves.

## Status: secretary pack lock

The pack is enabled by default when `tool-lock.json` is present. The
secretary bundle currently declares these small CLI dependencies:

- `remindctl` — Apple Reminders
- `memo` — Apple Notes
- `imsg` — Messages/iMessage
- `himalaya` — email

Prepared binaries and Python wheelhouses live under `prebuilt/` and are
intentionally ignored by git. `source-lock.json` records the reviewed upstream
source for each tool. `./build.sh` runs `scripts/prepare_skill_deps_inputs.sh`
automatically when `tool-lock.json` is missing, still has placeholder hashes, or
points at missing prebuilt files. The prep step downloads or builds the tools,
stages `prebuilt/`, and rewrites `tool-lock.json` with concrete SHA-256s. The
later pack build remains strict: it fails if a declared source is missing, its
SHA-256 does not match the generated lock, or a copied symlink resolves outside
the pack.

The matching install-time gate is **`HATCH_INSTALL_SKILL_DEPS=0`** which
skips `dist/install-skill-deps.sh` on the target Mac when set.

## Contract

When enabled, `scripts/build_skill_deps_pack.sh` (called from `build.sh`):

1. Runs `scripts/prepare_skill_deps_inputs.sh` from `source-lock.json` when the
   lock is absent, placeholder-filled, or missing sources.
2. Reads `tool-lock.json` (`schema_version: 1`).
3. Verifies every active artifact's SHA-256 from the lock.
4. Copies named binaries from `prebuilt/` into
   `tool-packs/skill-deps-pack/bin/<binary>`.
5. Copies declared support artifacts. Python-backed tools, such as `memo`, ship
   `python/<tool>/wheelhouse/*.whl`, `python/<tool>/package-spec.json`, and a
   marker file; they do **not** ship an assembly-machine virtualenv.
6. Generates `tool-packs/skill-deps-pack/tools-pack-manifest.json` so
   `bin/hatch verify-skill-deps` can verify SHA-256s against the lock.

The pack is **not** part of `dist/hatch-manifest.json`. It is installed
as a post-step by `dist/install-skill-deps.sh`, which copies into
`~/.monoclaw/vendor/skill-deps/` and runs from a sibling of `dist/` on the
provisioning medium. During install, Hatch creates Python-backed tool venvs on
the target from the shipped wheelhouse using
`~/.monoclaw/vendor/python/current/bin/python3`, then writes the
`~/.monoclaw/vendor/skill-deps/bin/<tool>` shim.

Each skill that wants to consume one of these binaries must:

- Set `system_dependencies: ["<binary>"]` in its
  `metadata.monoclaw.provisioning` block.
- Use the path `~/.monoclaw/vendor/skill-deps/bin/<binary>` for invocation.
- Be re-classified to `provisioned_user_config_required` (or
  `stock_bundle_candidate` if no further user config is required) by
  the next run of `scripts/audit_skill_readiness.py` and
  `scripts/apply_skill_readiness.py` in `monoclaw-runtime`.

## Out of scope

- Heavy Python/GPU stacks (PyTorch, vLLM, Flash Attention, NeMo Curator,
  etc.) stay external_runtime_only — they belong with operator-class
  workflows and would fight the offline-wheelhouse contract documented in
  `docs/runtime-artifacts.md`.
- Anything requiring sudo, broad disk access, or background launchd
  services. Those continue to land via `mona-secretary-tools` with the
  permissions review documented in
  `monoclaw-runtime/website/docs/user-guide/features/mona-secretary-tools.md`.

## Refreshing or forcing prep

- `HATCH_SKILL_DEPS_FORCE=1 ./build.sh` refreshes existing `prebuilt/` files.
- Python-backed tools require `bundle-inputs/vendor/python/current/bin/python3`
  to satisfy their `min_python` (**`memo` upstream requires Python >= 3.13** — use
  `scripts/stage_vendor_python_macos.sh` on assembly macOS); `HATCH_SKILL_DEPS_PYTHON` is an explicit
  diagnostics override for assembly only.
- `HATCH_SKILL_DEPS_AUTO_PREP=0 ./build.sh` disables network/build prep and
  preserves strict failure if `tool-lock.json` is incomplete.
- `HATCH_INCLUDE_SKILL_DEPS=0 ./build.sh` skips the pack entirely; do not use
  this for a release bundle that promises secretary skills after install.

When adding a tool, add it to `source-lock.json` first. The generated
`tool-lock.json` is the release evidence for the exact files that landed in the
pack.

Keep secrets out of this directory.
