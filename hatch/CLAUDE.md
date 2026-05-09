# Hatch Internal Notes

## Dependency Resolution Contract

Hatch is bundle-first. The target Mac should not be used to discover or repair
core MonoClaw runtime dependencies during installation. If a dependency is
needed to make `monoclaw setup` runnable, the prepared bundle must contain it
and `./build.sh` must fail when it is missing.

### Python Is A Bundled Runtime Dependency

- The core runtime venv must be created from
  `bundle-inputs/vendor/python/current/bin/python3` staged into
  `~/.monoclaw/vendor/python/current/bin/python3`.
- That interpreter must be Python 3.11+ and must be verified by a real venv
  smoke test before a release bundle is trusted.
- Do not silently fall back to Apple `/usr/bin/python3`, Homebrew Python, or an
  arbitrary `python3` on `PATH` for the customer runtime.
- Homebrew may be installed for technician tooling, but it is not the provider
  for the core MonoClaw runtime Python.
- `HATCH_ALLOW_SYSTEM_RUNTIME_PYTHON=1` is only for diagnostics, never for the
  production provisioning path.

### Avoid Lazy Target-Mac Fixups

Do not treat target install failures as prompts to layer more target-machine
fallbacks. The recent failure pattern was:

1. Renaming a wheel to `monoclaw-runtime.whl`, which pip rejects because wheel
   filenames must keep their PEP 427 tags.
2. Creating the runtime venv with Apple Python 3.9 even though
   `monoclaw-runtime` requires Python 3.11+.
3. Installing Homebrew Python on the target and trying to make it work with
   `DYLD_*` path tweaks after it loaded the wrong `libexpat`.

All three were symptoms of the same mistake: Hatch was not proving that the
prepared bundle already had a valid runtime dependency set.

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
