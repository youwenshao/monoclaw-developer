# Hatch Verification Gates

## Repo Gate

Run before handing off Hatch script changes:

```bash
bash tests/run_tests.sh
bash bin/hatch --dry-run preflight
bash -n bin/hatch
```

This checks shell syntax, the manifest-backed dry-run lifecycle test for
`preflight`, `install`, `verify`, `verify-local-inference`, `doctor`, and the
optional model-pack and tools-pack commands, plus the no-flag `build.sh` and generated install
wrappers using fixture bundle inputs.

## Assembly Gate

Before cutting a production provisioning medium, run the real assembler from
`/Users/admin/Projects/hatch` with production inputs staged in
`/Users/admin/Projects/hatch/bundle-inputs/`:

```bash
bash scripts/build_wheelhouse.sh
./build.sh
bash dist/bin/hatch --dry-run --bundle-root dist prepare-bundle
if [[ -d model-packs/gemma-4-e4b ]]; then
  bash dist/bin/hatch --dry-run --bundle-root dist --model-pack-root model-packs/gemma-4-e4b verify-model-pack
fi
if [[ -d tool-packs/mona-secretary-tools ]]; then
  test -f tool-packs/mona-secretary-tools/tools-pack-manifest.json
  bash dist/bin/hatch --dry-run --bundle-root dist --tools-pack-root tool-packs/mona-secretary-tools verify-tools-pack
fi
```

When Mona secretary tools are enabled (default), `./build.sh` leaves
`tool-packs/mona-secretary-tools/` beside `dist/` with
`tools-pack-manifest.json` inside. Confirm that tree exists before copying the
medium unless you intentionally built with `HATCH_INCLUDE_MONA_TOOLS=0`.

Capture the bundle ID, bundle version, and SHA-256 of `dist/hatch-manifest.json`
for release evidence. If a model pack is present, also capture the SHA-256 of
`model-packs/gemma-4-e4b/model-pack-manifest.json`. If a Mona tools pack is
present, also capture the SHA-256 of
`tool-packs/mona-secretary-tools/tools-pack-manifest.json`. Do not commit `dist/`,
`bundle-inputs/`, `model-packs/`, `tool-packs/`, model weights, or vendor payloads.

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

## Docs Translation Gate

Run from `monoclaw-developer` root after adding or modifying wiki documents in `docs/`
or `hatch/docs/`:

```bash
# List English wiki files missing zh-hans or zh-hant translations.
# Exempt files: READMEs (developer-facing), TRANSLATION-GLOSSARY.md, TRANSLATION-TEMPLATE.md, .plan.md (implementation plans).
for f in docs/*.md hatch/docs/*.md; do
  case "$(basename "$f")" in
    README.md|TRANSLATION-*.md|*.plan.md) continue ;;
  esac
  if [[ "$f" == *.zh-hans.md ]] || [[ "$f" == *.zh-hant.md ]]; then
    continue
  fi
  missing=""
  [[ -f "${f%.md}.zh-hans.md" ]] || missing="zh-hans"
  [[ -f "${f%.md}.zh-hant.md" ]] || missing="${missing:+$missing, }zh-hant"
  [[ -n "$missing" ]] && echo "[missing $missing] $f"
done
```

Expected: no output when all P0–P2 documents are fully translated. If a new
English document is intentionally English-only, add it to the exemption list
above or open a follow-up issue tagged `translation-drift`.

## Skill Readiness Gate

Run after Hatch installs the bundle on the target Mac to confirm every
shipped SKILL.md declares a known `metadata.monoclaw.provisioning`
bundle policy and that any `system_dependencies` declared by those
skills are present under `~/.monoclaw/vendor/skill-deps/bin/` or
`~/.monoclaw/vendor/mona-tools/bin/`.

```bash
bash dist/bin/hatch --dry-run --bundle-root dist verify-skill-readiness
```

Set `HATCH_SKILL_READINESS_FAIL_ON=external_runtime_only` (or another
policy) when you want `--apply` to fail the gate at a stricter
threshold; the default is `blocked_unknown`. The gate is also wired
into `hatch doctor` next to `verify` and `verify-local-inference`.

## Physical Bench Gate

Before release, run Hatch on a dedicated Apple Silicon Mac with a prepared
bundle and capture:

- Hatch command, bundle ID, bundle version, and manifest hash.
- `hatch --dry-run --bundle-root <dist> doctor` output.
- Real `./install.sh` output from the copied pendrive `dist/` directory.
- Optional `./install-gemma-model.sh` output when the pendrive includes
  `model-packs/gemma-4-e4b/`.
- Mona secretary tools post-step (`dist/install-mona-tools.sh`) when the pendrive
  includes `tool-packs/mona-secretary-tools/` beside `dist/` (copy both from the
  assembly machine).
- Manual LM Studio `.dmg` install and first-launch/import notes when local
  inference is part of the bench scenario.
- Fresh-reset rerun output when `MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1` is
  intentionally set on the bench.
- `hatch verify` output after restart, plus `hatch verify-local-inference` when
  local inference was configured.
- Redacted `~/.monoclaw/logs` tails and launchd summaries.

Do not capture customer secrets, Telegram tokens, hosted-provider API keys,
model weights, or raw conversation content.
