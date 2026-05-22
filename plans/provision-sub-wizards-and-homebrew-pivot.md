# Provision Sub-Wizards & Brew-First / Bundle-Fallback Pivot

> **Superseded for Himalaya (May 2026):** The Himalaya section of this plan
> (§4.1 and §6 sub-wizard mechanism) was superseded by
> `plans/himalaya-keychain-fix.plan.md`. The "delegate to `himalaya account
> configure` then react" architecture was found to be structurally broken:
> the bundled v1.2.0 binary lacks the `keyring` cargo feature, and even with
> it, `keyring-rs` historically falls back to a silent mock on macOS. Email
> account setup now lives in `monoclaw_cli.setup_email` (`monoclaw setup email`
> / `monoclaw setup himalaya`), which owns password collection, Keychain seeding
> with `-T` ACLs, round-trip verification, TOML generation, and a real IMAP
> probe. `HimalayaSubWizard.run()` now redirects to `monoclaw setup email`
> instead of spawning the upstream wizard. The rest of this plan (other
> secretary tools, core-deps sub-wizards, brew-first policy) is still in force.

Plan for fixing the Himalaya regression, harmonising bundled tool installs, and
making `monoclaw provision` drive each tool's **official** wizard as a
sub-wizard rather than re-implementing setup ourselves.

User-approved direction (recorded 2026-05-18):

- **Install policy**: brew-first when online; bundled binaries as the offline
  fallback (drop the strict bundle-first stance documented in
  `hatch/CLAUDE.md`, replace with documented hybrid).
- **Scope**: all secretary tools (`remindctl`, `memo`, `imsg`, `himalaya`) +
  missing core deps (`node`/`npm`, `uv`, `opus`, `ffmpeg`) + credential-only
  tools (Twilio, TTS providers).
- **Sub-wizard mechanism**: hybrid — TTY-attached to upstream wizards when
  stdin is a real TTY, printed step-by-step instructions otherwise (CI,
  headless, SSH-without-PTY).
- **Hatch hand-off**: `./install.sh` prompts `Run monoclaw provision now? [Y/n]`
  (default Yes) and launches it if accepted.
- **Credentials**: macOS Keychain via Himalaya's `backend.auth.keyring` is the
  default; `.env`-plaintext passwords are dropped from the wizard.

### Phase 1 follow-up decisions (recorded 2026-05-18)

- **Deprecation cycle for orphan `.env` keys** (`HIMALAYA_IMAP_PASSWORD`,
  `HIMALAYA_SMTP_PASSWORD`): **warn + auto-remove with backup** on the first
  `monoclaw provision` after this lands. The himalaya sub-wizard backs up
  `~/.monoclaw/.env` to `~/.monoclaw/.env.bak-<ISO-timestamp>` before stripping
  the dead keys, prints what was removed, and surfaces the backup path in the
  provision summary. Rationale: the keys are inert and quietly misleading;
  silent retention costs technician time without buying behaviour. The `.bak`
  file is the audit trail.
- **Linux support**: out of scope for v1. All sub-wizards gate on
  `sys.platform == "darwin"` and emit a single "not supported on this
  platform" `SubWizardResult` on non-Mac hosts. Linux behaviour will be a
  separate plan once we have a concrete deployment target.
- **Diagnostic note on the affected machines**: today's developer Mac has
  Himalaya installed via brew + a hand-edited `~/.config/himalaya/config.toml`,
  so the symptoms are *partly* masked. The **factory test-bench Mac** is where
  Himalaya is truly absent — that's the canonical failure mode this plan must
  fix end-to-end. All Phase 2 verification work is anchored to a clean
  test-bench run, not the developer's personal Mac.

---

## 1. Diagnostic: what was actually broken on this Mac

The user's reported symptom — "Himalaya is not installed at all" — is **not
literally true**; the truth is more interesting and explains the perceived
regression.

### What is on disk

| Tool        | Bundled path                                            | Brew path                       | `command -v` resolves to                                          |
|-------------|---------------------------------------------------------|---------------------------------|--------------------------------------------------------------------|
| `himalaya`  | `~/.monoclaw/vendor/skill-deps/bin/himalaya` (v1.2.0)   | `/opt/homebrew/bin/himalaya` v1.2.0 | brew (PATH precedence)                                            |
| `remindctl` | `~/.monoclaw/vendor/skill-deps/bin/remindctl` (v0.2.0)  | `/opt/homebrew/bin/remindctl` v0.2.0 | brew                                                              |
| `memo`      | `~/.monoclaw/vendor/skill-deps/python/memo/...`         | `/opt/homebrew/bin/memo` v0.5.2 | brew                                                              |
| `imsg`      | `~/.monoclaw/vendor/skill-deps/bin/imsg` (v0.5.0)       | *(not on brew)*                 | **NOT FOUND** on user PATH (only on Mona's tool-PATH)             |
| `node`/`npm`| not bundled for runtime                                  | not via brew                    | `~/.local/bin/node`, `~/.local/bin/npm` (manually installed)      |
| `uv`        | not bundled                                              | not via brew                    | `~/.local/bin/uv` (manually installed)                            |
| `opus`      | n/a (system library, not a CLI)                          | `brew opus 1.6.1`               | library installed, no CLI binary expected                         |
| `ffmpeg`    | not bundled                                              | `brew ffmpeg 8.1.1`             | brew                                                              |

### What `monoclaw setup system` is actually doing today

In `monoclaw_cli/system_setup.py`:

1. Detects the bundled skill-deps pack at `~/.monoclaw/vendor/skill-deps`.
2. Offers to run the activation probe (writes
   `~/.monoclaw/vendor/skill-deps/.activations.json`).
3. **If the user accepts** and `himalaya` is in the pack, prompts for
   `HIMALAYA_IMAP_PASSWORD` + `HIMALAYA_SMTP_PASSWORD` and writes them to
   `~/.monoclaw/.env`.

What is **wrong** with step 3:

- Himalaya **does not read those environment variables**. Nothing in the
  upstream binary cares about `HIMALAYA_IMAP_PASSWORD`. Wiring them through
  requires the user to hand-edit `~/.config/himalaya/config.toml` to set
  `backend.auth.cmd = "echo $HIMALAYA_IMAP_PASSWORD"` (or equivalent), which
  the wizard never explains. **The current prompts are inert theatre.**
- The wizard never offers to run `himalaya account configure`, which is the
  upstream wizard that knows about Gmail / Outlook / iCloud / Proton bridge
  presets, can talk to the system keyring, and walks the user through IMAP/SMTP
  ports + auth method.
- The wizard never writes or backs up `~/.config/himalaya/config.toml`. The
  user is silently expected to know they have to do this themselves.

### Why "himalaya is not installed" *feels* true

- `.activations.json` is missing on this Mac, so any code that interprets
  "activated = installed" reports false (the activation step was declined or
  the wizard exited before it).
- The user's interactive shell PATH resolves `himalaya` to brew, so the
  bundled binary feels invisible.
- The wizard left the user with passwords in `.env` that don't connect to
  anything, no working account, and no signal of what to do next.

### Adjacent confirmations

- The user's existing `~/.config/himalaya/config.toml` configures Gmail with
  `backend.auth.type = "password"` and `backend.auth.raw = <plaintext
  app-password>` — **rotate this when convenient**; it's also a perfect case
  study for why the plan needs a Keychain migration step.
- `monoclaw-runtime/tools/environments/local.py` (~line 247) already prepends
  `~/.monoclaw/vendor/skill-deps/bin` and `~/.monoclaw/vendor/mona-tools/bin`
  onto `PATH` for any *tool* spawned by Mona. So agents call the bundled
  binaries even though the user's interactive shell sees brew's. This means
  "brew vs bundle" mostly matters for **technician troubleshooting**, not for
  Mona's runtime behaviour.

### Root cause classification

| Cause | Severity | Today's installer's responsibility |
|-------|---------|------------------------------------|
| Wizard prompts for `.env` secrets that don't reach himalaya | Severe — user-visible bug | yes, fix |
| Wizard doesn't drive `himalaya account configure` | Severe — UX regression vs engine | yes, fix |
| `.activations.json` never written because user-flow exits early | Medium — observability/diagnostic gap | yes, fix |
| Bundled tools shadowed by brew copies on user PATH | Low — runtime PATH is OK | document, don't fight |
| `node`/`npm`/`uv` not installed by Hatch | Medium — needed for many skills | yes, add |
| `imsg` invisible to interactive shell (no brew path) | Low — agent PATH is fine; technicians should know where it lives | document + brew-publish later |
| Plaintext app passwords stored in `config.toml` and offered in `.env` | Medium — security regression | yes, fix via Keychain default |

---

## 2. Architecture: brew-first, bundle-fallback

### Per-tool classification

| Class | Source of truth | Fallback | Tools |
|-------|-----------------|----------|-------|
| A. Cross-distro CLI on Homebrew | `brew install <pkg>` | bundled binary from skill-deps pack | `himalaya`, `remindctl`, `memo` |
| B. Mac-only Swift binary, not on brew | bundled binary | technician-only `brew tap` (later) | `imsg` |
| C. Language runtime | `brew install <pkg>` | technician install script for offline (`scripts/install_node_offline.sh` etc., out of scope for this plan) | `node`/`npm`, `uv` |
| D. System library | `brew install <pkg>` | none (libraries can't be safely bundled without `install_name_tool` gymnastics) | `opus`, `ffmpeg` |
| E. Cloud service, no binary | environment vars only | n/a | Twilio, OpenAI/Mistral TTS, Bland.ai, Vapi |
| F. Pip package | runtime venv `pip install` | wheelhouse | `ddgs`, `twilio`, `kittentts`, `piper-tts` |

### Decision rules at install time

`install-skill-deps.sh` and `monoclaw provision` will both implement the same
decision tree per Class-A tool:

1. If `brew install <pkg>` is available **and** the user did not pass
   `HATCH_INSTALL_OFFLINE=1`:
   - Run `brew install --quiet <pkg>` (idempotent).
   - Verify `command -v <pkg> && <pkg> --version` is satisfied.
2. Otherwise (offline, or brew unavailable, or brew install failed):
   - Fall through to the existing bundled-binary copy into
     `~/.monoclaw/vendor/skill-deps/bin/<pkg>`.
3. Record the resolution in `~/.monoclaw/vendor/skill-deps/.activations.json`:
   `{ "<tool>": { "status": "verified", "source": "brew"|"bundle", "version": "<vN>" } }`.

For Class-B (`imsg`): always bundle (no brew tap today).

For Class-C and D: this plan **adds** brew-installed `node`, `npm` (via node),
`uv`, `opus`, `ffmpeg` as part of provisioning. The runtime venv is **not
affected** (Hatch's runtime Python contract still holds — that is bundle-first
forever, per its existing CLAUDE.md, because we can't trust system Python
versions).

### Hatch's CLAUDE.md needs an explicit amendment

`hatch/CLAUDE.md` currently says:

> Homebrew may be installed for technician tooling, but it is not the provider
> for the core MonoClaw runtime Python.

That stays true. We **add** a new section:

> Non-Python binaries (`himalaya`, `remindctl`, `memo`, `node`, `uv`, `opus`,
> `ffmpeg`) are brew-first on online Macs. Bundles still ship offline copies of
> the Class-A tools so `HATCH_INSTALL_OFFLINE=1` works; `monoclaw provision`
> records which source resolved each tool.

This is **not** a reversal of "no lazy target-Mac fixups" — those lazy fixups
were `DYLD_*` workarounds for the *runtime Python*. Brew-installed CLIs are
boring and well-trodden, and their resolution is deterministic via PATH +
manifest.

---

## 3. Sub-wizards: pattern and surface

### The contract

A sub-wizard is a Python module under
`monoclaw_cli/subwizards/<tool>.py` exposing:

```python
@dataclass
class SubWizardResult:
    ok: bool
    detail: str
    error: str
    artifacts: dict  # e.g. {"config_path": "~/.config/himalaya/config.toml"}

def required(config: dict, home: Path) -> bool: ...
def detect_state(home: Path) -> dict: ...
def run(*, tty: bool, home: Path, config: dict) -> SubWizardResult: ...
def verify(home: Path, config: dict) -> SubWizardResult: ...
```

`monoclaw provision` (and `monoclaw setup system`) iterate the registered
sub-wizards, calling `detect_state` to decide whether to skip, `run` to
configure, then `verify` to record the outcome.

### Hybrid TTY behaviour

Each sub-wizard's `run()` checks `sys.stdin.isatty() and sys.stdout.isatty()`:

- **TTY available**: spawn the upstream wizard with stdio inherited
  (`subprocess.run([...], check=False)` — no capture, no PTY indirection
  needed because we're already on a real terminal). Capture only exit code.
- **No TTY**: print exact commands + a numbered checklist to stdout, wait for
  the caller to confirm by re-running provision later. Sub-wizard returns
  `SubWizardResult(ok=False, error="non-interactive: run <cmd> manually then
  re-run `monoclaw provision --resume`")`.

### Skipping when already-configured

Each `detect_state()` returns a dict describing existing config. The framework
prints the detected state and asks `Re-run <wizard> anyway? [y/N]`. This
prevents re-running `himalaya account configure` on a Mac that already has
working accounts (which is the user's current Mac).

---

## 4. Tool-by-tool plan

### 4.1 `himalaya` (Class A)

**Install step**

- If `command -v brew` and online: `brew install --quiet himalaya`.
- Else: keep current bundled-copy path under
  `~/.monoclaw/vendor/skill-deps/bin/himalaya`.

**Sub-wizard (`subwizards/himalaya.py`)**

`detect_state()`:
- Read `~/.config/himalaya/config.toml` if it exists.
- Parse with a tolerant TOML reader; enumerate `[accounts.*]` sections.
- For each account, classify auth: `password` (raw plaintext — **flag**),
  `cmd`, `keyring`, `oauth2`.

`run()` (TTY mode):
- If no `config.toml`: spawn `himalaya account configure` (the wizard offers
  Gmail / Outlook / iCloud / generic presets; supports `--keyring` on the
  built-in keyring feature). Inherit stdio. After it returns, re-read
  `config.toml` and confirm at least one `[accounts.*]` block.
- If `config.toml` exists with `backend.auth.type = "password"` and
  `backend.auth.raw` set: offer **Keychain migration** —
  1. Read the existing plaintext password.
  2. Store via `security add-generic-password -a <login> -s
     "himalaya-<account>"` (or via `python-keyring`).
  3. Rewrite the section to `backend.auth.type = "keyring"` and
     `backend.auth.keyring = "himalaya-<account>"`.
  4. Back up the original file to
     `~/.config/himalaya/config.toml.bak-<timestamp>`.
- If config already uses keyring / oauth2: skip with "✓ already secure".

`run()` (no TTY):
- Print:
  > Detected himalaya v1.2.0 but no configured account.
  > Run `himalaya account configure` in a terminal, then re-run
  > `monoclaw provision --resume`.

`verify()`:
- `himalaya account list` exit 0 with ≥1 account → ok.
- `himalaya envelope list --account <default> --page 1 --page-size 1
  --output json` → records connectivity (network probe, ≤15s timeout).
- Failures: record `{"status": "config_present_but_unreachable", ...}`.

**Removed from `system_setup.py`**

- `_SKILL_DEP_REGISTRY["himalaya"]["manual"]` (the `{bin} account configure`
  hint string) is replaced by the real sub-wizard.
- The `HIMALAYA_IMAP_PASSWORD` / `HIMALAYA_SMTP_PASSWORD` prompts at lines
  1205–1222 of `system_setup.py` are **deleted**. They were inert.
- `OPTIONAL_ENV_VARS` in `monoclaw_cli/config.py` loses the himalaya entries
  (deprecation warning preserved for one release so existing `.env` files
  still load but a `monoclaw doctor` line says "deprecated; remove from
  .env").

### 4.2 `remindctl` (Class A)

**Install step**

- If `brew install --quiet steipete/tap/remindctl` (the upstream brew tap) is
  reachable: prefer brew.
- Else: bundled copy.

`detect_state()`:
- Run `remindctl status` (fast). Parse JSON if available, else exit-code only.

`run()` (TTY mode):
- If status says "authorization required": run `remindctl authorize`
  attached to TTY (it triggers the macOS Reminders permission prompt).
- If status says "no Reminders account": print the iCloud sign-in steps,
  wait for Enter, re-probe.

`verify()`:
- `remindctl status` → `authorized`, AND
- `remindctl list --limit 1` exit 0.

### 4.3 `memo` (Class A)

**Install step**

- `brew install --quiet memo` if available.
- Else: bundled Python-wheelhouse install (existing path).

`detect_state()`:
- `memo --version`.

`run()` (TTY mode):
- First run of `memo notes` triggers the Notes.app Automation prompt; we
  capture the user's confirmation that they clicked OK in System Settings.
- If automation is denied, print the exact System Settings deeplink
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`).

`verify()`:
- `memo notes --limit 1` exit 0.

### 4.4 `imsg` (Class B — bundle-only for now)

**Install step**

- Bundled copy is canonical. Document that no brew tap exists today.
- Open a follow-up ticket to publish a brew tap for `imsg` (out of scope for
  this plan, but tracked).

`detect_state()`:
- `imsg health --json`.

`run()` (TTY mode):
- If health says "Full Disk Access denied": open
  `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
  and wait for user confirmation.
- If health says "Automation denied": same flow with the Automation pane.

`verify()`:
- `imsg health --json` reports both grants OK and `imsg chats --limit 1
  --json` exit 0.

### 4.5 `node` / `npm` (Class C)

**Install step**

- `brew install --quiet node` (npm comes with it).
- Offline fallback: print "install Node ≥20 manually from nodejs.org" — we
  don't bundle Node for the *target* in this iteration. (Hatch already
  bundles Node for the build host's Mona-tools packing step; that's a
  separate scope.)

`detect_state()`:
- `node --version`, `npm --version`. Require Node ≥ 20 (LTS).

`run()`:
- If versions too old: `brew upgrade node`.

`verify()`:
- `node -e "console.log('ok')"` exit 0 and `npm --version` exit 0.

### 4.6 `uv` (Class C)

**Install step**

- `brew install --quiet uv`.
- Offline fallback: `curl -LsSf https://astral.sh/uv/install.sh | sh` is
  documented; we don't run it automatically without network.

`verify()`:
- `uv --version` exit 0.

### 4.7 `opus` (Class D, Discord voice)

**Install step**

- `brew install --quiet opus` on macOS.
- Verify via `/opt/homebrew/lib/libopus*.dylib` (Apple Silicon) or
  `/usr/local/lib/libopus*.dylib` (Intel) exists.
- discord.py's voice support uses `discord.opus.load_opus()`; the runtime
  should call this once during `monoclaw provision` to confirm the library
  loads.

### 4.8 `ffmpeg` (Class D, TTS / voice mode)

**Install step**

- `brew install --quiet ffmpeg`.

`verify()`:
- `ffmpeg -version` exit 0.

### 4.9 Twilio (Class E, API-only)

**Install step**

- pip-install `twilio` into the runtime venv (already a transitive dep via
  the telephony optional-skill; we make it a default dep of the
  `[local-office]` extra so `monoclaw provision` finds it pre-installed).

`detect_state()`:
- Look for `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN` in `~/.monoclaw/.env`.

`run()` (TTY mode):
- Prompt for SID + auth token (password-style for the token).
- Make a single `accounts(sid).fetch()` call to validate.
- Save to `.env`.
- Optionally: walk the user through buying a Twilio number (the existing
  `optional-skills/productivity/telephony/scripts/telephony.py` already has
  this flow — wire it into the sub-wizard).

`verify()`:
- `twilio_client.api.v2010.accounts(sid).fetch().status == 'active'`.

### 4.10 TTS / voice mode (Class E + F mix)

**Install step**

- API-provider TTS (OpenAI, ElevenLabs, Mistral): API-key prompt only.
- Local TTS (`kittentts`, `piper-tts`): `pip install` from runtime venv.

`run()`:
- Per-provider sub-wizard collecting the right credentials and pinning the
  voice model.

`verify()`:
- A 1-second test synthesis to a temp file (`/tmp/monoclaw-tts-probe.wav`)
  and check the file's mtime + non-zero size.

---

## 5. Hatch changes

### 5.1 `templates/install.sh` — prompt to run provision

At the end of `install.sh`, after the existing skill-deps step, append:

```bash
if [[ -t 0 ]] && [[ -t 1 ]]; then
  printf '\n  MonoClaw is installed. Run "monoclaw provision" now to configure your\n'
  printf '  email account, secretary tools, and credentials? [Y/n] '
  read -r answer
  if [[ -z "${answer}" ]] || [[ "${answer}" =~ ^[Yy] ]]; then
    monoclaw provision || printf '\n  warning: provision finished with issues; run "monoclaw doctor" to investigate\n' >&2
  else
    printf '  ok: run "monoclaw provision" later when ready\n'
  fi
else
  printf '\n  Install complete. Run "monoclaw provision" interactively to finish setup.\n'
fi
```

### 5.2 `bin/hatch run_install_skill_deps` — brew-aware decision tree

For each Class-A tool in `source-lock.json`:

1. If online + brew available + `HATCH_INSTALL_OFFLINE` is unset:
   - Try `brew install --quiet <tool>` (with the right tap for tools like
     remindctl).
   - On success, record `{"source": "brew"}` in `.activations.json`.
2. Else: existing copy-from-pack flow with `{"source": "bundle"}`.

For Class-C and Class-D adds (`node`, `uv`, `opus`, `ffmpeg`):

- A new `run_install_core_deps()` step that runs only on macOS, gated on
  brew availability, idempotent. Skipped entirely with
  `HATCH_INSTALL_OFFLINE=1`.

### 5.3 `bin/hatch verify-skill-deps` — recognise brew-resolved tools

Currently `verify-skill-deps` only probes `~/.monoclaw/vendor/skill-deps/bin/`.
Update it to read `.activations.json` and, when a tool's `source == "brew"`,
probe the brew path via `command -v <tool>`. This keeps the probe meaningful
even when bundled binaries weren't copied.

### 5.4 `bin/hatch-diagnostics` gets the escape hatches

`HATCH_INSTALL_OFFLINE=1` is documented here, alongside the existing
`HATCH_ALLOW_*` diagnostic flags. The production install script never sets it
automatically.

### 5.5 `hatch/CLAUDE.md` amendment

A new section "Hybrid Brew / Bundle Resolution For Non-Python Tools" documents
the decision tree from §2 and explicitly says this **does not** loosen the
Python rule.

---

## 6. Runtime changes (monoclaw-runtime)

### 6.1 New module: `monoclaw_cli/subwizards/`

- `__init__.py` — register-by-import discovery (the same pattern as
  `tools/*.py`), exposing `list_subwizards()` and `resolve(name)`.
- `_base.py` — `SubWizardResult`, common helpers (TTY detection, Keychain
  helpers, brew-vs-bundle path resolution).
- One file per tool in §4: `himalaya.py`, `remindctl.py`, `memo.py`,
  `imsg.py`, `node.py`, `uv.py`, `opus.py`, `ffmpeg.py`, `twilio.py`,
  `tts.py`.

### 6.2 `monoclaw_cli/provision.py` — add steps 6 + 7

Today `run_provision` has 5 steps. Add:

- Step 6: **Core dependencies** — runs the Class-C / Class-D sub-wizards
  before secretary tools (because secretary tools may depend on Node for
  Mona, ffmpeg for voice mode, opus for Discord, etc.).
- Step 7: **Sub-wizards for installed tools** — iterates the registry and
  runs each tool's `run()` if `required()` returns true.

The existing Step 4 ("System Configuration") **delegates** to the new
sub-wizard registry rather than re-implementing himalaya/imsg/etc. behaviour
inline. `monoclaw setup system` keeps the per-tool sub-wizards but trims to
the macOS-permissions + Mona-plugin enable bits.

### 6.3 `monoclaw_cli/system_setup.py` — drop inert prompts

- Remove the `HIMALAYA_IMAP_PASSWORD` / `HIMALAYA_SMTP_PASSWORD` prompts
  (lines 1205–1222).
- Remove `"himalaya"` and any related entries from `OPTIONAL_ENV_VARS`
  (`monoclaw_cli/config.py`), with a one-release deprecation message that
  `monoclaw doctor` surfaces if the user has those keys lingering in `.env`.
- Replace the existing `_SKILL_DEP_REGISTRY` per-tool `manual` hints with
  calls to the new sub-wizard registry: `_SKILL_DEP_REGISTRY[name]["wizard"]
  = "monoclaw_cli.subwizards.<name>"`.

### 6.4 Keychain helpers

A small `monoclaw_cli/keychain.py` wrapping macOS `security` CLI:

- `set_password(service, account, password)` →
  `security add-generic-password -U -s <service> -a <account> -w <pw>`
- `get_password(service, account)` →
  `security find-generic-password -s <service> -a <account> -w`
- `delete_password(service, account)`
- Linux fallback: `python-keyring` if installed; otherwise return an explicit
  "no secure store available" error and refuse plaintext fallback (the user
  can use himalaya's own `auth.cmd` with `pass`).

### 6.5 `monoclaw doctor` integration

`monoclaw doctor` already exists. Extend its JSON output with a
`provision_status` block populated from `.activations.json`:

```json
{
  "provision_status": {
    "himalaya": {"source": "brew", "version": "1.2.0", "verified": true,
                  "config_path": "~/.config/himalaya/config.toml",
                  "auth": "keyring", "accounts": ["gmail"]},
    "remindctl": {"source": "brew", "verified": true, "authorized": true},
    "imsg":      {"source": "bundle", "verified": false,
                   "error": "Full Disk Access denied",
                   "fix": "monoclaw provision --resume imsg"},
    ...
  }
}
```

### 6.6 Migrate plaintext `backend.auth.raw` to Keychain (one-time)

The `himalaya` sub-wizard's `detect_state()` flags any plaintext
`backend.auth.raw` in `config.toml`. The first `monoclaw provision` after this
plan ships **offers** (does not force) to migrate every such password into the
Keychain — see §4.1 `run()` mode.

### 6.7 `tools/environments/local.py` — PATH order is fine, leave it

`local.py` already prepends both `vendor/skill-deps/bin` and
`vendor/mona-tools/bin`. No change.

Add a single new entry: prepend `/opt/homebrew/bin` and `/usr/local/bin` as
**lower priority** than the bundle dirs but above the user PATH, so an agent
spawned via Modal/Docker/remote backends still finds brew-installed CLIs on a
host that doesn't bundle them. This is a tiny one-line change.

---

## 7. Order of work / phases

### Phase 1 — Diagnostic and contract (this PR)

- Land this plan + diagnostic report.
- Update `hatch/CLAUDE.md` with the hybrid resolution policy.
- Add `SubWizardResult` + the registry scaffold under
  `monoclaw_cli/subwizards/`. Empty stubs only.
- Tests: registry discovery + `SubWizardResult` shape.

### Phase 2 — Himalaya end-to-end (the regression fix)

- Implement `subwizards/himalaya.py` fully (detect, run, verify).
- Hook into `monoclaw provision` Step 4 and `monoclaw setup system`.
- Remove the inert `.env` prompts in `system_setup.py`.
- Keychain helper module.
- Migration path from plaintext `backend.auth.raw`.
- Tests:
  - Detection on a Mac with no config → triggers wizard.
  - Detection on a Mac with plaintext password → offers migration.
  - Detection on a Mac with keyring auth → skips.
  - Mock `himalaya account list` for verify.
  - Mock `security add-generic-password` for Keychain (CI is Linux).

### Phase 3 — Other Class-A tools

- `subwizards/remindctl.py`, `subwizards/memo.py`, `subwizards/imsg.py`.
- Wire brew-first / bundle-fallback in `bin/hatch run_install_skill_deps`.

### Phase 4 — Core deps (Class C, D)

- `subwizards/node.py`, `subwizards/uv.py`, `subwizards/opus.py`,
  `subwizards/ffmpeg.py`.
- New `run_install_core_deps` in `bin/hatch`.
- Provision Step 6.

### Phase 5 — Credential-only tools (Class E)

- `subwizards/twilio.py`, `subwizards/tts.py`.
- Reuse `optional-skills/productivity/telephony/scripts/telephony.py` as
  the implementation surface; the sub-wizard is the **shell** that calls
  into it.

### Phase 6 — `./install.sh` hand-off

- Append the `monoclaw provision` prompt to `templates/install.sh`.
- Update Hatch's tail message to say
  `next: monoclaw provision` instead of `monoclaw setup system`.

### Phase 7 — Documentation

- Rewrite `website/docs/user-guide/skills/bundled/email/email-himalaya.md`
  to drop the "Use `REMINDCTL=...`" verbose path; just call the binary by
  name once provision has finished.
- Document the brew-first / bundle-fallback choice in the technician
  handbook.
- Update the runtime AGENTS.md / monoclaw-developer plans/ to point at this
  plan as the canonical record.

---

## 8. Risk register

| Risk | Mitigation |
|------|-----------|
| `brew install himalaya` lands a different feature set than the bundled binary (no `+oauth2`, no `+wizard`) | The bundled binary is built via Nix with `+wizard +imap +smtp +sendmail +pgp-commands`; brew ships `+wizard +imap +smtp +sendmail +pgp-commands` too (verified on this Mac via `himalaya --version`). For OAuth 2.0 users we recommend building from source — document. |
| User declines the "Re-run wizard?" prompt and ends up with a broken Keychain migration half-done | Migration is transactional: write to Keychain first, then rewrite `config.toml`, then keep the `.bak` file. If any step fails, restore from `.bak` and leave Keychain entry orphaned (we can clean orphans later). |
| Non-Mac Linux users see degraded provisioning (no brew, no Keychain) | The provision flow already gates `_macos_permissions_plan` and similar on `sys.platform == "darwin"`. We add the same gate to all macOS-specific sub-wizards. Linux falls through to `pip` / `apt` instructions; we don't auto-`apt install` (different distros, sudo etc.). |
| Existing users' `.env` files have orphan `HIMALAYA_IMAP_PASSWORD` keys | Deprecation warning in `monoclaw doctor` for one release. Then auto-remove with backup. |
| Sub-wizards regress when the upstream binary changes its CLI | Each `verify()` step is the contract. CI runs a `tests/subwizards/test_verify_smoke.py` that hits real binaries when available. |
| Twilio sub-wizard re-implements work already in `optional-skills/productivity/telephony/scripts/telephony.py` | Don't re-implement — call the existing script and parse its JSON output. The sub-wizard is only the orchestrator. |
| Plaintext password discovery in users' `config.toml` leaks if logs are shared | Sub-wizard logs the **fact** that plaintext was found, never the value. The migration step doesn't log the password text. |

---

## 9. Out of scope (named explicitly so we don't drift)

- Publishing a brew tap for `imsg`. Useful, but not in this plan.
- Air-gapped install of `node`/`uv` (Class C) on customer Macs. We require
  online for those in this iteration; an offline Class-C bundle is a
  separate ticket.
- Changing how the runtime venv resolves Python (still bundle-only).
- Replacing `monoclaw setup system` with `monoclaw provision`. They both
  exist; `provision` calls `setup system` as one step. Consolidation can come
  later.
- Reworking `web_search`'s missing-backend story. That belongs in the
  separate `plans/mona-tool-availability-investigation.md`; **this plan does
  not touch it**, intentionally.
