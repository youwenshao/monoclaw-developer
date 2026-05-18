# Hatch Internal Notes

## Dependency Resolution Contract

Hatch is bundle-first. The target Mac should not be used to discover or repair
core MonoClaw runtime dependencies during installation. If a dependency is
needed to make `monoclaw provision` runnable, the prepared bundle must contain it
and `./build.sh` must fail when it is missing.

### Python Is A Bundled Runtime Dependency

- The core runtime venv must be created from
  `bundle-inputs/vendor/python/current/bin/python3` staged into
  `~/.monoclaw/vendor/python/current/bin/python3`.
- That interpreter must be Python 3.11+ and must be verified by a real venv
  smoke test before a release bundle is trusted. Secretary bundles also ship
  **`memo`** via skill-deps; upstream memo declares **`requires-python >= 3.13`**,
  so stage **`bundle-inputs/vendor/python/current`** with **3.13+** on assembly
  (`scripts/stage_vendor_python_macos.sh`) before `build_wheelhouse.sh` / skill-deps prep.
- Do not silently fall back to Apple `/usr/bin/python3`, Homebrew Python, or an
  arbitrary `python3` on `PATH` for the customer runtime.
- Homebrew may be installed for technician tooling, but it is not the provider
  for the core MonoClaw runtime Python.
- `HATCH_ALLOW_SYSTEM_RUNTIME_PYTHON=1` is only for diagnostics, never for the
  production provisioning path.

### Avoid Lazy Target-Mac Fixups

Do not treat target install failures as prompts to layer more target-machine
fallbacks. The historical failure pattern was:

1. Renaming a wheel to `monoclaw-runtime.whl`, which pip rejects because wheel
   filenames must keep their PEP 427 tags.
2. Creating the runtime venv with Apple Python 3.9 even though
   `monoclaw-runtime` requires Python 3.11+.
3. Installing Homebrew Python on the target and trying to make it work with
   `DYLD_*` path tweaks after it loaded the wrong `libexpat`.

All three were symptoms of the same mistake: Hatch was not proving that the
prepared bundle already had a valid runtime dependency set.

### Lazy Fixups Removed (current state as of 2026-05)

The following fixups that had crept into `bin/hatch` are now **removed from the
production install path** and moved to `bin/hatch-diagnostics`:

- **`configure_homebrew_python_library_paths`** (`DYLD_LIBRARY_PATH` / expat
  workaround): deleted entirely from `bin/hatch`. The bundled Python ships its
  own dylib closure; DYLD mutations are exactly the `libexpat` failure pattern
  this policy forbids.
- **`HATCH_ALLOW_SYSTEM_RUNTIME_PYTHON=1`**: removed from `select_runtime_python`
  in `bin/hatch`. System/Homebrew Python fallback belongs in `bin/hatch-diagnostics`
  only.
- **`HATCH_ALLOW_RUNTIME_NETWORK_FALLBACK=1`**: removed from `bootstrap_runtime`
  in `bin/hatch`. Missing wheelhouse is a build-time error; live PyPI access on a
  customer Mac violates the offline-deterministic contract.

If you need these escape hatches for a broken-bundle diagnosis, use
`bin/hatch-diagnostics` and rebuild the bundle before shipping to customers.

### Required Verification For Dependency Changes

When changing Hatch dependency or bootstrap logic:

- Add a test that fails before the fix and covers the actual failure mode.
- Run `bash tests/run_tests.sh` from `hatch`.
- Run the runtime local-office metadata test from `../monoclaw-runtime`.
- For release work, build a real bundle and smoke test that the bundled Python
  can run:
  `vendor/python/current/bin/python3 -m venv <tmp-venv>` and
  `<tmp-venv>/bin/python -m pip --version`.
- Do Python smoke tests before manifest generation, or outside `dist/`.
  Running `dist/vendor/python/current/bin/python3` after manifest generation can
  rewrite `__pycache__` files and invalidate `hatch-manifest.json`.
- Do not rely only on dry-run string assertions for runtime dependency changes.

### Post-Install Verification Contract

`run_verify` in `bin/hatch` now runs behavioral smoke probes beyond file presence:

1. `monoclaw --version` — confirms the runtime binary executes and imports correctly.
2. `monoclaw doctor --json` — confirms essential tools (web_search, terminal) are green.

Both must exit 0 for `run_verify` to pass. A file-presence-only verify that hides
a broken runtime is worse than no check. Do not regress these back to `test -x` checks.

After install, technicians run `monoclaw provision` (not `monoclaw setup system`)
for the complete first-run onboarding wizard with per-step verification.

### Hybrid Brew / Bundle Resolution For Non-Python Tools

The bundle-first Python rule above is **unchanged**. This section is an
addition that governs the *non-Python* CLI tools the runtime depends on
(`himalaya`, `remindctl`, `memo`, `node`/`npm`, `uv`, `ffmpeg`, `opus`).

Decision matrix per tool, evaluated by `bin/hatch install-skill-deps` and
`monoclaw provision`:

1. **Online + Homebrew available** *and* `HATCH_INSTALL_OFFLINE` is unset →
   prefer `brew install --quiet <pkg>` (with the appropriate tap for tools
   that need one). Record `{"source": "brew", "version": "<vN>"}` in
   `~/.monoclaw/vendor/skill-deps/.activations.json`.
2. **Offline, or brew unavailable, or brew install failed** → fall through to
   the bundled binary copy under `~/.monoclaw/vendor/skill-deps/bin/<pkg>`.
   Record `{"source": "bundle", "version": "<vN>"}`.
3. **Class-B tools without a brew formula** (today: `imsg`) → bundled binary
   is the only path. Document the absence of a brew tap; do not fabricate
   one.

`HATCH_INSTALL_OFFLINE=1` is the **single** documented escape hatch that
forces step 2 unconditionally. It lives alongside the existing diagnostic
flags in `bin/hatch-diagnostics`; the production install script never sets it
automatically.

`HATCH_INSTALL_BREW_FORMULAS=0` is a narrower opt-out for the brew-install
side only: it skips ``install_class_a_brew_formulas`` while still copying
the bundle and running the rest of the install path. Use when the technician
deliberately wants bundle-only behaviour on an online Mac (e.g. to verify the
offline path behaves identically to the online path).

Why this is **not** a "lazy target-Mac fixup":

- The historical bans (DYLD path tweaks, system Python fallback, live PyPI
  fallback) all applied to the **runtime Python venv**, which has a strict
  dylib closure and version contract.
- Brew-installed CLIs are well-trodden, version-stable, and resolved
  deterministically via `PATH`. The runtime's `tools/environments/local.py`
  already prepends `~/.monoclaw/vendor/skill-deps/bin` and
  `~/.monoclaw/vendor/mona-tools/bin` for the agent's spawn-PATH, so an
  agent-side tool call still hits the bundle first regardless of what the
  technician's shell sees.
- The `.activations.json` source field makes every resolution auditable. A
  `monoclaw doctor --json` run reports which path served each tool; we never
  have to guess.

Class-C language runtimes (`node`/`npm`, `uv`) are brew-only on macOS in this
iteration. Offline Class-C installs are tracked as a separate ticket; do not
add a target-Mac `curl | sh` fallback into Hatch.
