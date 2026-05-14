# MonoClaw Technician Provisioning Handbook

> **Audience:** Technicians provisioning Mac mini or iMac devices for non-technical office workers.
> **Goal:** One correct path from factory-reset Mac to working MonoClaw runtime, with clear recovery at every step.
> **What this is not:** Build instructions for the installer bundle. If you need to build or modify the bundle, see `assembly-internals.md`.

---

## 1. Pre-Flight Checklist (Do This Before Opening the Terminal)

Answer three questions. They determine what you must do before running the installer.

| Question | If Yes | If No |
|---|---|---|
| Does the customer contract include **local inference** (on-device AI, not a hosted provider)? | Install **LM Studio** from the official `.dmg` before running the installer. | Skip LM Studio. |
| Does the customer contract include **sandboxed tools** or containerized workflows? | Install **Docker Desktop** from the official `.dmg` and launch it once to approve permissions. | Skip Docker Desktop. |
| Is the Mac connected to the **internet**? | Standard path. Proceed normally. | Set `HATCH_SKIP_HOMEBREW_INSTALL=1` before running `./install.sh`. Homebrew is optional technician tooling, not a runtime dependency. |

**Always required:**
- **Apple Silicon Mac** (M1 or newer).
- **Xcode Command Line Tools.** Run `xcode-select --install` if `xcode-select -p` fails. This may trigger a macOS GUI prompt—complete it before proceeding.

**What should be on your provisioning medium:**
```text
<VOLUME>/
  dist/                           ← required core bundle
  tool-packs/
    mona-secretary-tools/         ← required by default (copy it unless you explicitly disabled it at build time)
  model-packs/
    gemma-4-e4b/                  ← only if local inference is in the customer contract
```

> ⚠️ **Critical:** If `tool-packs/mona-secretary-tools/` is missing, `install.sh` will emit a warning and continue, but the customer will not have the default secretary tools (WhatsApp search, Slack search, macOS automation). Copy it unless the work order explicitly says to skip Mona tools.

---

## 2. The Install (One Command)

Open Terminal on the target Mac and run:

```bash
cd /Volumes/<YOUR_PENDRIVE>/dist
./install.sh
```

`install.sh` does two things automatically:
1. Installs the core MonoClaw runtime, skills, and command shim.
2. Installs the Mona secretary tools sidecar (unless `HATCH_INSTALL_MONA_TOOLS=0`).

**You do not need to pass `--apply`.** The generated `install.sh` already applies changes.

### Expected Output

You should see a sequence of `[install]` and `[ok]` lines, ending with:

```
[install] Technician handoff
  next: open a new terminal or run: export PATH="$HOME/.local/bin:$PATH"
  next: verify runtime with: monoclaw --version
  next: run monoclaw setup
```

If you see `[warn]` instead of `[ok]`, read the warning. Common benign warnings:
- "Homebrew missing; installing with the official Homebrew installer" — normal on a fresh Mac.
- "No bundled skills staged" — the bundle was built without curated skills; runtime defaults will be used.
- "launchd service installation is not enabled until bundle plists are finalized" — expected. Services start later.

If you see `[fail]`, stop. Do not run `monoclaw setup` until the failure is resolved. See Section 5: Recovery.

---

## 3. Post-Install Verification (Never Skip)

Open a **new Terminal window** (so `~/.local/bin` is on PATH), then run:

```bash
monoclaw --version
```

Expected: a version string is printed. If you get `command not found`, run:

```bash
export PATH="$HOME/.local/bin:$PATH"
monoclaw --version
```

If it still fails, the shim was not written correctly. See Section 5: Recovery.

**Full diagnostic sweep (optional but recommended on first bench or when something feels wrong):**

```bash
bash /Volumes/<YOUR_PENDRIVE>/dist/bin/hatch doctor
```

This runs `preflight` + `verify` + `verify-local-inference` in one pass and tells you exactly what is missing.

---

## 4. Customer-Specific Setup

Run the setup wizard:

```bash
monoclaw setup
```

This is where you or the customer chooses:
- AI provider (hosted vs. LM Studio local inference).
- Messaging platforms (Telegram, Slack, WhatsApp).
- Secrets and API keys.
- Customer-specific configuration.

**Hatch does not collect secrets.** Do not paste tokens into the terminal outside of `monoclaw setup`, and never commit `.env` or `config.yaml` to git.

### If Local Inference Was Configured

1. Install LM Studio from the official `.dmg` (if you have not already).
2. Launch LM Studio once and complete its first-run setup.
3. If the model pack is on the pendrive, run:
   ```bash
   cd /Volumes/<YOUR_PENDRIVE>/dist
   ./install-gemma-model.sh
   ```
4. In LM Studio, import the model from:
   ```
   ~/.monoclaw/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf
   ```
5. Run `monoclaw setup` again (or edit `~/.monoclaw/.env`) to point to the local endpoint:
   ```
   LM_BASE_URL=http://127.0.0.1:1234/v1
   LM_API_KEY=dummy-lm-api-key
   MONOCLAW_MODEL=local:gemma4:e4b
   ```

### If Mona Secretary Tools Were Installed

Review the permission scope before enabling host automation:

```bash
cat ~/.monoclaw/vendor/mona-tools/docs/permissions.md
```

Copy MCP config examples **only after** reviewing path and permission scopes:

```bash
cp ~/.monoclaw/vendor/mona-tools/config/mcp_servers.mona.example.yaml ~/.monoclaw/mcp_servers.mona.yaml
```

Then merge into `~/.monoclaw/config.yaml` manually or via `monoclaw setup`.

---

## 5. Recovery & Reruns

### Safe to Rerun

`./install.sh` is idempotent for runtime assets. It preserves:
- `~/.monoclaw/.env`
- `~/.monoclaw/config.yaml`
- `~/.monoclaw/customer/`
- Technician-created skills in `~/.monoclaw/skills/`

If the install was interrupted or a post-install check failed, simply rerun `./install.sh`.

### Full Reset (Wipe Everything)

Only do this if the work order explicitly requests a clean reinstall, or if you suspect corrupted vendor files:

```bash
export MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1
./install.sh
```

This removes and replaces `~/.monoclaw/vendor/` but still preserves `customer/`, `.env`, and `config.yaml` unless they were manually deleted.

### Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| `monoclaw: command not found` after install | `~/.local/bin` not on PATH in current shell | Open a new terminal, or run `export PATH="$HOME/.local/bin:$PATH"` |
| `Python 3.11+ runtime interpreter missing` | The bundle was copied without `vendor/python/` | Rebuild or recopy the bundle from the assembly machine |
| `Bundled wheelhouse is required for production runtime bootstrap` | The bundle was built without `bash scripts/build_wheelhouse.sh` | Return to assembly machine and rebuild |
| `Mona secretary tools installation failed; core MonoClaw runtime remains installed` | `tool-packs/mona-secretary-tools/` was not copied to the pendrive | Copy the sidecar and rerun `./install.sh`, or set `HATCH_INSTALL_MONA_TOOLS=0` to skip intentionally |
| `Xcode Command Line Tools are missing` | CLT not installed or macOS prompt not completed | Run `xcode-select --install`, complete the GUI prompt, then rerun `./install.sh` |
| `LM Studio app is missing` | Customer contract includes local inference but LM Studio was not installed | Install LM Studio from `.dmg`, then rerun `monoclaw setup` |

### Offline or Air-Gapped Macs

If the target Mac has no internet:
1. Ensure Xcode CLT is already installed before you arrive (or install from a local `.pkg`).
2. Set `HATCH_SKIP_HOMEBREW_INSTALL=1` so Hatch does not attempt to download Homebrew:
   ```bash
   export HATCH_SKIP_HOMEBREW_INSTALL=1
   ./install.sh
   ```
3. The bundle must contain a populated `vendor/wheelhouse/` (this is the assembly operator's responsibility). If the install fails with a wheelhouse error, the bundle was built incorrectly—do not attempt network fallbacks on a customer Mac.

### When to Call Assembly / Engineering

Do not improvise fixes on the target Mac. Escalate when:
- The bundle manifest fails verification (`hatch-manifest.json` SHA mismatch).
- `vendor/python/current/bin/python3` is missing or is not Python 3.11+.
- The wheelhouse is empty or missing.
- `monoclaw --version` fails after two install attempts.

---

## 6. Handoff Checklist (Sign Off Before Leaving)

- [ ] `monoclaw --version` prints a version in a fresh Terminal window.
- [ ] `monoclaw setup` has been run and the customer can launch it again.
- [ ] If local inference: LM Studio is installed, the model is imported, and `hatch verify-local-inference` passes.
- [ ] If Mona tools: `~/.monoclaw/vendor/mona-tools/docs/permissions.md` has been reviewed with the customer.
- [ ] No secrets were pasted into public issue trackers, commits, or chat logs.
- [ ] `~/.monoclaw/logs/` exists and is writable (check with `touch ~/.monoclaw/logs/test && rm ~/.monoclaw/logs/test`).
- [ ] The customer knows how to restart MonoClaw if needed (relevant once launchd plists are finalized in a future release).

---

## Quick Reference: Technician Commands

| Command | When to use |
|---|---|
| `./install.sh` | Every provision or rerun. |
| `monoclaw --version` | Verify the runtime is reachable. |
| `monoclaw setup` | Configure provider, messaging, and secrets. |
| `bash dist/bin/hatch doctor` | Full diagnostic when something feels wrong. |
| `bash dist/bin/hatch verify` | Check core runtime integrity only. |
| `bash dist/bin/hatch verify-local-inference` | Check LM Studio + model readiness. |
| `./install-gemma-model.sh` | Stage the model pack when local inference is enabled. |
