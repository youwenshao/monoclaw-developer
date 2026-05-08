# MonoClaw Developer

`monoclaw-developer` is the coordination workspace for MonoClaw engineering. It
does not vendor sibling repositories or use git submodules. Instead, it owns the
workspace manifest, bootstrap scripts, Hatch installer scaffold, coding-agent
skills, and implementation plans that coordinate the runtime, website, and
future tool repositories.

## Workspace Layout

Run the bootstrap script from this repository root. It creates or updates the
expected sibling checkouts under `/Users/admin/Projects`.

```text
Projects/
  monoclaw-developer/   # this coordinator repository
  monoclaw-runtime/     # MonoClaw runtime
  monoclaw-web/         # website, checkout, dashboards, docs
  scuttle-reference/    # read-only reference clone of the old installer
```

Hatch initially lives inside this repository at `hatch/` so installer planning,
scripts, and agent instructions can evolve together. If Hatch later becomes a
standalone product repository, add it to `workspace.manifest.json` and update
the workspace file.

## First Run

```bash
bash scripts/bootstrap-workspace.sh --dry-run
bash scripts/bootstrap-workspace.sh
bash scripts/status-workspace.sh
```

Open `monoclaw.code-workspace` in Cursor after bootstrapping to work across the
runtime, website, Hatch, and reference installer from one window.

## Repository Roles

- `monoclaw-runtime`: the local-first MonoClaw agent runtime.
- `monoclaw-web`: the existing Next.js 16 / React 19 website, checkout,
  dashboards, legal content, and Supabase schema.
- `scuttle-reference`: private historical installer/runtime bundle reference.
  Use it to study provisioning contracts, launchd handling, readiness checks,
  and offline bundle layout. Do not copy old-engine assumptions blindly.
- `hatch`: new installer scaffold for technician provisioning of factory-reset
  Macs with MonoClaw, local inference dependencies, skills, tools, and model
  weights.

## Product Truth

The refresh policy lives in `docs/product-truth-and-attribution.md`. User-facing
surfaces should say MonoClaw; Hermes/Nous provenance is retained only in legal
and upstream attribution files.

## Website Commands

The current website stack uses Next.js 16, React 19, npm, Supabase, Playwright,
and Vitest. Useful verification commands in `../monoclaw-web`:

```bash
npm ci
npm run test
npm run build
```

Supabase local verification requires Docker Desktop and project environment
values, so treat database smoke tests as a separate gated workflow.

## Public Repository Safety

This repository is public. Keep it free of customer data, secrets, provisioning
logs, `.env` files, OpenRouter keys, Telegram tokens, Supabase credentials,
model weights, vendor bundles, and machine-specific runtime output.
