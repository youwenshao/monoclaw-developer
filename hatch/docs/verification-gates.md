# Hatch Verification Gates

## Repo Gate

Run before handing off Hatch script changes:

```bash
bash tests/run_tests.sh
bash bin/hatch --dry-run preflight
bash -n bin/hatch
```

This checks shell syntax, the manifest-backed dry-run lifecycle test for
`preflight`, `install`, `verify`, and `doctor`, plus the no-flag `build.sh` and
generated `install.sh` wrapper using fixture bundle inputs.

## Assembly Gate

Before cutting a production provisioning medium, run the real assembler from
`/Users/admin/Projects/hatch` with production inputs staged in
`/Users/admin/Projects/hatch/bundle-inputs/`:

```bash
./build.sh
bash dist/bin/hatch --dry-run --bundle-root dist prepare-bundle
```

Capture the bundle ID, bundle version, and SHA-256 of `dist/hatch-manifest.json`
for release evidence. Do not commit `dist/`, `bundle-inputs/`, model weights, or
vendor payloads.

## Runtime Gate

Run from `../monoclaw-runtime` after runtime packaging, dependency profile, or
rebrand changes:

```bash
scripts/run_tests.sh tests/test_project_metadata.py::test_local_office_extra_is_customer_bundle_profile -q
scripts/run_tests.sh tests/monoclaw_cli/test_banner.py::test_build_welcome_banner_uses_monoclaw_branding_not_upstream_vendor -q
```

If the runtime checkout has no virtual environment, create or attach the
standard runtime venv before claiming these tests pass.

## Web Gate

Run from `../monoclaw-web` after website, legal, translation, or contract changes:

```bash
python3 -m json.tool messages/en.json >/dev/null
python3 -m json.tool messages/zh-hans.json >/dev/null
python3 -m json.tool messages/zh-hant.json >/dev/null
npm run generate-contract-seed
npm run test
npm run build
```

Supabase reset and database smoke checks are separate gated workflows because
they require Docker and local Supabase services.

## Physical Bench Gate

Before release, run Hatch on a dedicated Apple Silicon Mac with a prepared
bundle and capture:

- Hatch command, bundle ID, bundle version, and manifest hash.
- `hatch --dry-run --bundle-root <dist> doctor` output.
- Real `./install.sh` output from the copied pendrive `dist/` directory.
- Fresh-reset rerun output when `MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1` is
  intentionally set on the bench.
- `hatch verify` output after restart.
- Redacted `~/.monoclaw/logs` tails and launchd summaries.

Do not capture customer secrets, Telegram tokens, hosted-provider API keys,
model weights, or raw conversation content.
