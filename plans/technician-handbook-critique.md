# Technician Handbook Critique & Rewrite Proposal

## The Problem

There is no single "Admin Handbook." What exists is a fractured mix of `hatch/README.md`, `hatch/docs/provisioning-contract.md`, `hatch/docs/runtime-artifacts.md`, `hatch/docs/verification-gates.md`, and `skills/technician-provisioning.md`. Together they function as the de facto handbook, but they are **written for assembly operators and developers**, not for the technician standing in front of a factory-reset Mac with a customer waiting.

The result: technicians must mentally filter out build scripts, manifest schema details, repo gates, and wheelhouse assembly instructions to find the three commands they actually need. This is not a documentation bug; it is a **category error**. The current docs describe *how the installer is built*; the handbook must describe *how to provision a machine correctly and recover when something goes wrong*.

## What the Codebase Actually Does (The Real Technician Workflow)

After reading `hatch/bin/hatch`, `hatch/build.sh`, `hatch/templates/install.sh`, and the verification tests, the actual provisioning workflow is:

### Before the Technician Touches the Mac
1. Assembly operator runs `./build.sh` on an assembly Mac.
2. The build produces `dist/` (core bundle) and, by default, a sibling `tool-packs/mona-secretary-tools/` sidecar.
3. Both `dist/` and `tool-packs/` are copied to the provisioning medium (pendrive).
4. Optional: `model-packs/gemma-4-e4b/` is also copied if local inference is requested.

### On the Target Mac (Technician Steps)
1. **Manual prerequisites** (technician must verify or install):
   - Xcode Command Line Tools (`xcode-select --install` if missing).
   - Docker Desktop (only if sandboxed tools are required by the customer contract).
   - LM Studio (only if local inference is required).
2. **Run the installer** from the pendrive:
   ```bash
   cd /Volumes/<PENDRIVE>/dist
   ./install.sh
   ```
   This is **not** just `hatch install`. `install.sh`:
   - Runs `hatch --apply --bundle-root <dist> install` (core runtime, skills, shim).
   - Then **automatically** runs `install-mona-tools.sh` unless `HATCH_INSTALL_MONA_TOOLS=0`.
3. **Post-install verification**:
   ```bash
   monoclaw --version
   monoclaw setup
   ```
4. **Optional local inference** (if customer contract includes it):
   - Install LM Studio from `.dmg`.
   - Run `./install-gemma-model.sh` from the pendrive (if model pack was copied).
   - Launch LM Studio and import `~/.monoclaw/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf`.
5. **Mona tools permission review** (if Mona tools were installed):
   - Read `~/.monoclaw/vendor/mona-tools/docs/permissions.md`.
   - Review MCP config examples before copying them into the runtime config.

### Diagnostic Commands Available to Technicians
- `hatch doctor` — runs preflight + verify + verify-local-inference in one pass.
- `hatch verify` — checks that the core runtime is installed and runnable.
- `hatch verify-local-inference` — checks LM Studio and model presence.
- `hatch --dry-run preflight` — safe preview of what would happen before applying.

## Specific Failures in the Current Docs

### 1. `hatch/README.md` — The "Handbook" Is Actually a Build Manual

**Failure:** The first code block a technician sees is:
```bash
cd /Users/admin/Projects/hatch
bash scripts/build_wheelhouse.sh
./build.sh
```
These are **assembly-only** commands. A technician provisioning a customer Mac should never run these. Yet they appear before the target-Mac instructions.

**Failure:** The target-Mac instructions are buried under "Commands" and lack any context about what the technician should have already done (Xcode CLT, Docker, LM Studio decisions).

**Failure:** The README says "Copy the resulting `dist/` directory to the provisioning pendrive" but **never mentions `tool-packs/`**, even though `./build.sh` creates it by default and `install.sh` attempts to run it. A technician who copies only `dist/` will hit a warning or failure during install because `install-mona-tools.sh` expects the sidecar.

**Failure:** The README says "It does not install GUI apps such as LM Studio or Docker Desktop" but does not explain *when* the technician should install them, or how to decide if they are needed.

### 2. `hatch/docs/provisioning-contract.md` — Correct but Useless to Technicians

**Failure:** Written as a contract between Hatch and the runtime, not as instructions. It lists "Managed By Hatch" and "Manual Or Semi-Manual Prerequisites" but does not sequence them into actions.

**Failure:** Mentions "launchd service lifecycle for MonoClaw-managed processes after finalized plists are shipped" but the code explicitly warns: "launchd service installation is not enabled until bundle plists are finalized." This is misleading—technicians should not expect services to start automatically.

**Failure:** The "Safety Defaults" section says "Dry-run is the default" but then the technician-facing `install.sh` uses `--apply` by default. This contradiction creates confusion about whether the technician needs to pass flags.

### 3. `hatch/docs/runtime-artifacts.md` — Over-Engineered for Technicians

**Failure:** 275 lines of manifest schema, assembly happy path, bundle layout diagrams, and PEP 427 wheel filename rules. A technician needs none of this. This document should live in `docs/assembly-internals.md` and be removed from the technician path.

**Failure:** The "Target Mac Prerequisites" section lists Homebrew as auto-installed but then notes "Set `HATCH_SKIP_HOMEBREW_INSTALL=1` to skip this step for offline bench tests or technician-managed installs." There is no guidance on *when* a technician should skip Homebrew, or what breaks if they do.

**Failure:** The "Verification Contract" lists `hatch verify` checks but buries them in manifest terminology. Technicians need a simple pass/fail checklist, not a description of how SHA-256 verification works.

### 4. `hatch/docs/verification-gates.md` — Entirely Wrong Audience

**Failure:** This document lists repo gates, assembly gates, runtime gates, web gates, and physical bench gates. **None of these are technician-facing.** A technician does not run `bash tests/run_tests.sh` on a customer Mac. This document should be moved to `docs/release-engineering.md`.

### 5. `skills/technician-provisioning.md` — Too Thin to Be Useful

**Failure:** Only 22 lines. It states principles ("Show one next action at a time") but does not actually show the next action. It is a design manifesto, not a handbook.

**Failure:** Does not mention the `install.sh` wrapper, the Mona tools sidecar, model packs, or the `monoclaw setup` handoff.

## Proposed Structural Changes

### Separate Assembly Docs from Technician Docs

The `hatch/docs/` directory should be split into two audiences:

```
hatch/docs/
  technician-handbook.md      # NEW — the only doc technicians read
  assembly-internals.md       # RENAMED from runtime-artifacts.md
  release-engineering.md      # RENAMED from verification-gates.md
  provisioning-contract.md    # Keep as engineering contract, link from handbook
```

`hatch/README.md` should become a **landing page** with two links: "Technician Provisioning Guide" and "Assembly & Release Engineering."

### Rewrite `hatch/README.md` as a Landing Page

- Remove all assembly commands from the top-level view.
- Add a prominent warning: "If you are provisioning a customer Mac, read the Technician Handbook. If you are building the installer bundle, read Assembly Internals."

### Create `hatch/docs/technician-handbook.md`

This should be a **ruthlessly sequential, decision-tree-driven workflow**:

1. **Pre-flight checklist** — what to verify before inserting the pendrive.
2. **Pendrive contents** — what should be on the medium (`dist/`, `tool-packs/`, optional `model-packs/`).
3. **Install decision tree**:
   - Standard office worker (hosted provider): run `./install.sh`, then `monoclaw setup`.
   - Local inference customer: also install LM Studio + model pack.
   - Sandbox tools customer: also install Docker Desktop.
4. **Verification steps** — what commands to run and what "ok" looks like.
5. **Failure recovery** — what to do if `install.sh` warns, fails, or partially succeeds.
6. **Handoff to customer** — what to tell the customer before leaving.

### Remove or Relocate Misplaced Content

- Move manifest schema details, wheelhouse build instructions, and bundle layout diagrams to `assembly-internals.md`.
- Move all test gates, bench expectations, and SHA-256 capture instructions to `release-engineering.md`.
- Keep `provisioning-contract.md` as the engineering contract but strip it of any "how-to" framing.

### Fix Specific Inaccuracies

1. **Clarify `install.sh` behavior:** The handbook must state that `install.sh` auto-runs Mona tools installation by default, and that skipping it requires setting `HATCH_INSTALL_MONA_TOOLS=0`.
2. **Clarify Homebrew:** Explain that Homebrew is auto-installed for technician convenience but is **not** required for MonoClaw to run. If the Mac is offline, set `HATCH_SKIP_HOMEBREW_INSTALL=1`.
3. **Remove launchd service expectations:** Explicitly state that services are **not** started by Hatch; they are configured after `monoclaw setup` when plists are finalized.
4. **Add the `hatch doctor` command:** This is the single most useful diagnostic for technicians and is not mentioned in any current doc.
5. **Add rerun guidance:** Explain that rerunning `./install.sh` is safe (preserves `.env`, `config.yaml`, `customer/`, and technician-created skills), but a full reset requires `MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1`.

## Proposed `technician-handbook.md`

See the accompanying proposed rewrite at `hatch/docs/technician-handbook.md` for the full sequential workflow.
