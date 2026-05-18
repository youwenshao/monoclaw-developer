# Mona Tool Availability & Spinner Investigation

Investigation memo — not a plan. Written in plan mode at the user's request to
record findings before deciding on scope.

## Symptoms reported

1. **Spinner / "thinking" animation not always triggered** while the LLM is
   generating a response.
2. **Mona acts as if she doesn't remember her tools and skills.**
3. **Web search specifically misbehaves.** When asked for a celebrity's
   birthday, Mona either:
   1. hallucinates a date with no tool call, or
   2. invokes `terminal` and runs `curl -s … | grep -i "birthday"`,
   3. then tells the user she is *"unable to retrieve the information or use
      the tools because they are unavailable to her environment."*

The user's hypothesis: the install path (`hatch`) or the
`monoclaw setup system` wizard isn't doing its job. **Hypothesis is largely
correct, but the root cause is sharper than "the wizard is broken" — the
wizard never had the relevant step in the first place.**

---

## Executive verdict

The three symptoms have **two distinct root causes**:

| # | Root cause | What it explains |
|---|------------|------------------|
| A | **`web_search` is silently dropped from the LLM's tool schema** when no backend is configured, and the wizard that runs at install time (`monoclaw setup system`) never asks about web-search backends. The runtime venv also does not bundle the free `ddgs` fallback as a default dependency. | Symptoms 2 and 3 in full. The "I can't use the tools" wording is reinjected by `run_agent.py`'s `invalid_tool_calls` recovery branch, not by a real tool. |
| B | **The `thinking` callback / spinner is wired through five separate code paths and at least three of them have real bugs or intentional-but-misleading gaps.** | Symptom 1. |

There is also a third, looser layer of concerns: **Hatch's install script
declares success on the basis of file presence + SHA, never on the basis of
the tool actually working** (no `remindctl status`, no `monoclaw --version`,
no probe of any web-search backend). This doesn't directly cause today's
symptom, but it's the reason the failure mode is invisible to the technician
running the bench install.

This memo describes each piece with file citations so the eventual fix is
specific.

---

## Part A — Why Mona behaves as if she has no tools

### A.1 `web_search` is registered, but gated by `check_fn`

The tool is real and registered correctly in
[monoclaw-runtime/tools/web_tools.py](/Users/admin/Projects/monoclaw-runtime/tools/web_tools.py):

```2254:2263:/Users/admin/Projects/monoclaw-runtime/tools/web_tools.py
registry.register(
    name="web_search",
    toolset="web",
    schema=WEB_SEARCH_SCHEMA,
    handler=lambda args, **kw: web_search_tool(args.get("query", ""), limit=args.get("limit", 5)),
    check_fn=check_web_api_key,
    requires_env=_web_requires_env(),
    emoji="🔍",
    max_result_size_chars=100_000,
)
```

`check_web_api_key()` returns True only when **at least one** of these is
available:

```2080:2088:/Users/admin/Projects/monoclaw-runtime/tools/web_tools.py
def check_web_api_key() -> bool:
    """Check whether the configured web backend is available."""
    configured = _load_web_config().get("backend", "").lower().strip()
    if configured in ("exa", "parallel", "firecrawl", "tavily", "searxng", "brave-free", "ddgs"):
        return _is_backend_available(configured)
    return any(
        _is_backend_available(backend)
        for backend in ("exa", "parallel", "firecrawl", "tavily", "searxng", "brave-free", "ddgs")
    )
```

`SERPER_API_KEY` is **not** a backend in this codebase — pointing users at
Serper would not fix the symptom. The backends are: Exa, Parallel,
Firecrawl, Tavily, SearXNG, Brave free tier, or the `ddgs` Python package.

### A.2 `registry.get_definitions()` silently drops tools whose `check_fn` fails

In [monoclaw-runtime/tools/registry.py](/Users/admin/Projects/monoclaw-runtime/tools/registry.py):

```313:344:/Users/admin/Projects/monoclaw-runtime/tools/registry.py
    def get_definitions(self, tool_names: Set[str], quiet: bool = False) -> List[dict]:
        """Return OpenAI-format tool schemas for the requested tool names.

        Only tools whose ``check_fn()`` returns True (or have no check_fn)
        are included. ...
        """
        result = []
        check_results: Dict[Callable, bool] = {}
        entries_by_name = {entry.name: entry for entry in self._snapshot_entries()}
        for name in sorted(tool_names):
            entry = entries_by_name.get(name)
            if not entry:
                continue
            if entry.check_fn:
                if entry.check_fn not in check_results:
                    check_results[entry.check_fn] = _check_fn_cached(entry.check_fn)
                if not check_results[entry.check_fn]:
                    if not quiet:
                        logger.debug("Tool %s unavailable (check failed)", name)
                    continue
            ...
            result.append({"type": "function", "function": schema_with_name})
        return result
```

Notes:

- The tool is **omitted entirely** from the schema. The model does not see
  `web_search` exists.
- In `quiet=True` mode, **no log is emitted at all** — not even at DEBUG.
- The gateway path always passes `quiet=True`. See
  [monoclaw-runtime/gateway/run.py](/Users/admin/Projects/monoclaw-runtime/gateway/run.py)
  around line 9357: agents created there get `quiet_mode=True`. The classic
  CLI does too unless `--verbose` is on (`cli.py` ~3915).
- The startup warning at `run_agent.py` line 1636 — `"🛠️  No tools loaded
  (all tools filtered out or unavailable)"` — is gated on `not self.quiet_mode`,
  so it is suppressed in every messaging session.

### A.3 `monoclaw setup system` never asks about web search

[monoclaw-runtime/monoclaw_cli/system_setup.py](/Users/admin/Projects/monoclaw-runtime/monoclaw_cli/system_setup.py)
`run_system_setup()` (lines 1083–1159) is the interactive wizard a
technician is told to run after install. Its full set of interactive
prompts is:

- "Enable reviewed Mona plugin?"
- "Merge reviewed Mona MCP templates now?"
- "Open macOS Privacy & Security panes for manual permission review now?"
- "Verify and record skill dependency activation now?"
- (Conditional) "Configure Himalaya IMAP/SMTP secret environment variables?"
- "Apply these system configuration changes?"

Zero prompts for `EXA_API_KEY`, `TAVILY_API_KEY`, `FIRECRAWL_API_KEY`,
`BRAVE_SEARCH_API_KEY`, or `SEARXNG_URL`. Confirmed by ripgrep — no matches
for any of those identifiers in `system_setup.py`.

The web-search backend selector exists, but it lives in a **different,
separately-named command**: `monoclaw setup tools` →
[monoclaw_cli/setup.py](/Users/admin/Projects/monoclaw-runtime/monoclaw_cli/setup.py)
`setup_tools` (line 2583) → `tools_command` in
[tools_config.py](/Users/admin/Projects/monoclaw-runtime/monoclaw_cli/tools_config.py).
That is where `_configure_provider` for the `web` category prompts for
backends, including pip-installing `ddgs` on demand
(`monoclaw_cli/tools_config.py` `_run_post_setup`).

**This is the wizard split that breaks users.** Hatch's `bin/hatch`
explicitly tells the technician at install time:

```bash
# bin/hatch line 975
printf '  next: run monoclaw setup system to review Mona permissions, MCP templates, and tool activation\n'
```

So the technician runs `monoclaw setup system`, sees a green wizard, and
walks away — never having opened `monoclaw setup tools`, never having
chosen a web-search backend. Mona launches without `web_search`.

### A.4 The runtime venv does not ship `ddgs` as a default

`ddgs` is the only "no-API-key" backend. If it were a default dependency,
`check_web_api_key()` would return True out-of-the-box and the schema would
include `web_search` on every fresh install. It is not.

- Not in `pyproject.toml` (grep returns no matches).
- Not vendored under `hatch/bundle-inputs/` (grep returns no matches).
- Only pip-installed at user request when they reach the `web` toolset
  inside `monoclaw setup tools` (`tools_config.py` `_run_post_setup`).

This is the cleanest single-step fix candidate.

### A.5 Why Mona's wording is "tools are unavailable to my environment"

When the schema drops `web_search`, the model can still **try to call**
`web_search` in a tool-call response (this is common — the model has prior
context that the tool exists). `run_agent.py` intercepts these as
"invalid tool calls" and injects a recovery message back as a synthetic
user turn:

```13523:13602:/Users/admin/Projects/monoclaw-runtime/run_agent.py
                    # Validate tool call names - detect model hallucinations
                    ...
                        recovery_content = (
                            f"Your previous response attempted to call unavailable tool "
                            f"'{invalid_name}'. Available tools: {available}. "
                            "Retry the task using only the available tool names. ..."
                        )
```

The model reads "unavailable tool" + an availability list, summarizes it
back to the user in its own words, and you get *"I am unable to use these
tools because they are unavailable to my environment."* That is **the
runtime telling the model the tool is unavailable**, then the model
repeating it. No backend was ever actually called.

### A.6 Why specifically `curl … | grep -i birthday`

Two reasons:

1. `terminal` is in `_MONOCLAW_CORE_TOOLS` and its `check_fn`
   ([terminal_tool.py](/Users/admin/Projects/monoclaw-runtime/tools/terminal_tool.py)
   line 2116) returns True for the default `local` backend with no
   conditions. So when web tools are stripped, `terminal` is still in the
   schema and the model reaches for it.
2. The terminal layer is *forgiving by design*: `grep` exit code 1 is
   classified as `"No matches found (not an error)"` and not flagged.
   `subprocess` output combines stdout+stderr, so the model can't easily
   tell whether `curl` actually fetched anything or just got an empty
   pipe. It assumes the lookup happened and reports failure as "I couldn't
   find a birthday."

The terminal tool is acting correctly. The model's behaviour is correct
*for the toolset it sees*. The bug is upstream: `web_search` should never
have been removed from the schema without telling anyone.

### A.7 What is **not** the cause

These were investigated and ruled out:

- **Mona plugin overriding the toolset.** Today's
  `_config_with_mona_enabled` only appends `mona-secretary-tools` to
  `plugins.enabled`; it does not write `platform_toolsets`. The historical
  bug that wrote `platform_toolsets.cli: ["mona_secretary"]` is now
  automatically repaired on read by `_get_platform_tools`
  (`tools_config.py` lines 884–931). Telegram/etc. still inherit
  `_MONOCLAW_CORE_TOOLS` after enabling Mona.
- **`mona_secretary` toolset replacing core tools.** The
  `mona-secretary-tools` plugin's `register()` only adds narrow wrappers
  (`mona_whatsapp_search`, `mona_summarize`, etc.) under a new toolset
  key. It does not declare or replace `web_search` / `terminal`.
- **System prompt mid-conversation rebuild.** `_build_system_prompt` is
  cached on `self._cached_system_prompt` and only rebuilds on
  compression / new session — consistent with the prompt-caching policy
  in `AGENTS.md`. The model is not "forgetting" mid-conversation; it
  literally never saw the tool in the first place.
- **Skills index missing.** Skills enumeration via
  `build_skills_system_prompt` is wired correctly and is gated only on
  the presence of `skills_list` / `skill_view` / `skill_manage` in
  `valid_tool_names`. Those tools are in `_MONOCLAW_CORE_TOOLS` and don't
  depend on external state.

---

## Part B — Why the spinner is intermittent

The spinner is not driven by one source of truth. It is the OR of:
`thinking_callback`, `KawaiiSpinner.start()/stop()`, streaming
`first-delta` events, and TUI's `showReasoning` flag. Each path can
suppress the others.

### B.1 Real bug: retry loop does not re-arm the spinner

In [run_agent.py](/Users/admin/Projects/monoclaw-runtime/run_agent.py),
the thinking spinner is set up **before** the retry `while` loop:

```11447:11467:/Users/admin/Projects/monoclaw-runtime/run_agent.py
            # Thinking spinner for quiet mode (animated during API call)
            thinking_spinner = None

            if not self.quiet_mode:
                ...
            else:
                # Animated thinking spinner in quiet mode
                verb = random.choice(KawaiiSpinner.get_thinking_verbs())
                spinner_message = f"{verb}..."
                if self.thinking_callback:
                    self.thinking_callback(spinner_message)
                elif not self._has_stream_consumers() and self._should_start_quiet_spinner():
                    spinner_type = KawaiiSpinner.random_braille_spinner_type()
                    thinking_spinner = KawaiiSpinner(spinner_message, spinner_type=spinner_type, print_fn=self._print_fn)
                    thinking_spinner.start()
```

Then `while retry_count < max_retries:` starts at line 11496. When a
response is invalid, the spinner is stopped at line 11725 and `continue`
fires at line 11856 — without ever re-entering the setup block:

```11725:11730:/Users/admin/Projects/monoclaw-runtime/run_agent.py
                    if response_invalid:
                        # Stop spinner before printing error messages
                        if thinking_spinner:
                            thinking_spinner.stop("(´;ω;`) oops, retrying...")
                            thinking_spinner = None
                        if self.thinking_callback:
                            self.thinking_callback("")
```

```11854:11856:/Users/admin/Projects/monoclaw-runtime/run_agent.py
                                    f"{int(sleep_end - time.time())}s remaining"
                                )
                        continue  # Retry the API call
```

So on the second through Nth retry, **there is no spinner activity** even
though the LLM is genuinely working. This is a real bug, not a UX choice.

### B.2 Real bug: gateway path never sets `thinking_callback`

In [gateway/run.py](/Users/admin/Projects/monoclaw-runtime/gateway/run.py)
around line 9353, agents are created with `quiet_mode=True` and no
`thinking_callback`. The `else` branch at `run_agent.py` line 11462 then
checks `not self._has_stream_consumers() and self._should_start_quiet_spinner()` —
both conditions are easy to fail in a messaging session, especially when
stdout is not a TTY. Net effect: most gateway sessions have **no spinner
at all** during the wait. Whatever "typing" indicator the platform
adapter shows is the only signal.

### B.3 Design choice that *feels* like a bug: first-delta stop

`_stop_spinner` (the callback installed in the streaming code path at
`run_agent.py` ~7195, ~7275, ~7387, ~7536) fires on the **first** stream
delta: first reasoning chunk, first visible text token, or first tool
name. The spinner disappears even though the model is still generating.
For tool-heavy turns, this leaves long silent gaps with no visible
activity.

### B.4 TUI ToolTrail gated on `showReasoning`

`ui-tui/src/app/turnController.ts` `recordReasoningDelta` (lines 563–566)
is a no-op unless `showReasoning` is true. The default is **false**
(`uiStore.ts`). So legacy `thinking.delta` events never light up the TUI
"Thinking" panel for most users.

### B.5 `KawaiiSpinner` is intentionally inert under `patch_stdout`

[agent/display.py](/Users/admin/Projects/monoclaw-runtime/agent/display.py)
lines 728–736: under prompt_toolkit's `StdoutProxy`, the animation thread
only sleeps; it does not paint frames. This is deliberate (raw `\r`
breaks `patch_stdout`), but any code path that *only* uses `KawaiiSpinner`
without also calling `thinking_callback` will look broken in the
classic CLI.

---

## Part C — Why Hatch makes this invisible

### C.1 `install.sh` warns on optional failure, then exits 0

[hatch/templates/install.sh](/Users/admin/Projects/monoclaw-developer/hatch/templates/install.sh):

```bash
if ! bash "${DIST_ROOT}/install-mona-tools.sh"; then
  printf '  warning: Mona secretary tools installation failed; core MonoClaw runtime remains installed\n' >&2
fi
...
if ! bash "${DIST_ROOT}/install-skill-deps.sh"; then
  printf '  warning: skill dependencies installation failed; core MonoClaw runtime remains installed\n' >&2
fi
```

A technician sees a green tail on the install and assumes everything
works. Mona / skill-deps failures land in stderr and are easily missed.

### C.2 `run_verify` does not run anything

[hatch/bin/hatch](/Users/admin/Projects/monoclaw-developer/hatch/bin/hatch)
`run_verify` lines 766–811: every check is `test -e` / `test -x` /
"manifest present" / "directory writable". The runtime is never executed.
`monoclaw --version` is never called. Importing the wheel is never tried.

### C.3 `verify-skill-deps` does SHA + presence; never `remindctl status`

`hatch/lib/common.sh` `verify_tools_pack_manifest`:

```407:413:/Users/admin/Projects/monoclaw-developer/hatch/lib/common.sh
for tool in data["tools"]:
    for key in ("name", "version", "path", "activation", "required_permissions"):
        if key not in tool:
            raise SystemExit(f"tools pack tool missing field {key}")
    tool_path = safe_path(tool["path"])
    if not tool_path.is_file():
        raise SystemExit(f"tools pack tool file missing: {tool['path']}")
```

The only smoke test is for an optional bundled Node runtime
(`node --version`). Nothing for `remindctl`, `memo`, `imsg`, `himalaya`.

### C.4 Hatch violates its own CLAUDE.md policy

[hatch/CLAUDE.md](/Users/admin/Projects/monoclaw-developer/hatch/CLAUDE.md)
forbids "DYLD path tweaks after [Homebrew] loaded the wrong libexpat" and
"Lazy Target-Mac Fixups". But `bin/hatch` still has:

```161:171:/Users/admin/Projects/monoclaw-developer/hatch/bin/hatch
configure_homebrew_python_library_paths() {
  ...
  prepend_path_var DYLD_LIBRARY_PATH "${prefix_lib}"
  prepend_path_var DYLD_LIBRARY_PATH "${expat_lib}"
  prepend_path_var DYLD_FALLBACK_LIBRARY_PATH "${prefix_lib}"
```

And both escape hatches the policy calls out are still live:

- `HATCH_ALLOW_SYSTEM_RUNTIME_PYTHON=1` (line 394) lets the runtime fall
  back to `python3.13`/`python3.12`/`python3.11`/`python3` on `PATH`.
- `HATCH_ALLOW_RUNTIME_NETWORK_FALLBACK=1` (lines 626 and 649) lets pip
  hit the live network when the bundled wheelhouse is missing.

These are technically "diagnostics flags" but they exist in the same
binary the customer install path runs.

### C.5 The Hatch doc story for `remindctl` contradicts itself

- [hatch/bundle-inputs/vendor/skill-deps/source-lock.json](/Users/admin/Projects/monoclaw-developer/hatch/bundle-inputs/vendor/skill-deps/source-lock.json)
  pins `remindctl` to GitHub release `steipete/remindctl v0.1.1`, copied
  into the bundle at `prebuilt/bin/remindctl`.
- [monoclaw-runtime/skills/apple/apple-reminders/SKILL.md](/Users/admin/Projects/monoclaw-runtime/skills/apple/apple-reminders/SKILL.md)
  says install lives at `~/.monoclaw/vendor/skill-deps/bin/remindctl`.
- The user-facing website doc
  [website/docs/user-guide/skills/bundled/apple/apple-apple-reminders.md](/Users/admin/Projects/monoclaw-runtime/website/docs/user-guide/skills/bundled/apple/apple-apple-reminders.md)
  still tells users to `brew install steipete/tap/remindctl`.

Three repos, three stories. The bundled path is the chosen one, but the
website still tells users to do it the upstream way.

---

## Part D — Comparison to the original engine's "organized config sub-menu system"

The user remembers the older engine wizard as more organized. What I
found:

The old `monoclaw-engine` (Rust) has two commands documented in
[scuttle-reference/AGENT.md](/Users/admin/Projects/scuttle-reference/AGENT.md):

- `monoclaw provision` — narrow 5-step commercial baseline:
  database → security → OpenRouter → default model → Telegram.
- `monoclaw onboard` — full 9-step wizard:
  1. Database (Postgres vs libsql)
  2. Security (secrets master key / OS Keychain)
  3. Inference provider
  4. Model selection
  5. Embeddings
  6. Channels
  7. Extensions
  8. Docker sandbox
  9. Heartbeat

Per the
[scuttle-reference Tier C manual drill](/Users/admin/Projects/scuttle-reference/docs/tier-c-manual-drills.md)
D6, the engine onboard wizard was *expected to verify first-token
round-trip per provider*, store the key in the **encrypted store** (not
plaintext `.env`), then gate completion on `monoclaw status` and
`monoclaw doctor`.

Compare to `monoclaw-runtime`'s current
[`SETUP_SECTIONS`](/Users/admin/Projects/monoclaw-runtime/monoclaw_cli/setup.py)
(line 3069):

| Key | Handler | Behavior |
|-----|---------|----------|
| `model` | `setup_model_provider` | Picker + keys → `.env`; **no live inference probe** |
| `tts` | `setup_tts` | Provider picker; pip-installs `kittentts`/`piper` if local |
| `terminal` | `setup_terminal_backend` | Backend picker; SSH echo test for SSH backend; pip-installs Modal/Daytona SDKs |
| `gateway` | `setup_gateway` | Messaging platform configuration |
| `tools` | `setup_tools` | Per-platform toolset checklist; **this is where `ddgs` is pip-installed if user enables `web`** |
| `skill_profile` | `setup_skill_profile` | Minimal/Standard/Operator selector |
| `system` | `setup_system` | Delegates to `run_system_setup` (Mona, macOS perms, skill-deps activation) |
| `agent` | `setup_agent_settings` | Max turns, compression, etc. |

So the **sub-menu structure already exists**. What was lost from the
original engine model is:

1. **A single canonical entry point that runs all sections in order.**
   `monoclaw setup` without arguments does run a menu (`SETUP_SECTIONS`),
   but Hatch directs users to `monoclaw setup system` specifically, which
   is *only* the System section and bypasses the Tools section where
   web-search backends actually get configured.
2. **Per-step verification.** The engine's onboard ran provider round-trips.
   The Python `setup_tools` only does `import ddgs` and `_chromium_installed()`-style
   presence probes, not actual API calls.
3. **Encrypted secrets store.** Engine wizard wrote to OS Keychain via
   the `secrets_master_key`. Python wizard writes to `.env` plaintext
   plus `config.yaml`.

The "organized sub-menu" structure is not what was lost. What was lost
was **per-step verification** and **a single coherent install flow that
hits every section**.

---

## Part E — Honest take on the "use official install procedures" alternative

The user asked whether pre-bundling is too brittle and whether the wizard
should use Homebrew + each tool's own installer.

**My read:**

- For **macOS CLI binaries** like `remindctl`, `memo`, `imsg`, and
  `himalaya`, the upstream story really is `brew install`. Hatch's
  decision to bundle pinned static binaries is defensible for offline /
  air-gapped bench installs, but it adds a second, parallel installation
  pipeline that has to be kept in sync with each upstream tool's release
  cadence. **This is a real trade-off, not "lazy" — but the docs lie
  about which path applies, which is the underlying problem.**
- For **web search backends**, there is no binary to install. The choice
  is between API providers (Tavily, Brave, etc., requiring a key) or
  the free `ddgs` Python package. **The right fix here is not Homebrew,
  it's to make `ddgs` a default runtime dependency and surface backend
  choice in `monoclaw setup` (or `monoclaw setup system`) as a first-class
  step.**
- For **`bin/hatch`'s Homebrew DYLD path manipulation**, this is the
  one place where "drop the lazy fixup" is unambiguously correct per
  Hatch's own CLAUDE.md.

The honest position: **Don't migrate everything to brew.** Do migrate
the `monoclaw setup system` wizard to either include a Tools step inline
or to redirect-with-warning when web search has no backend configured.
Do add post-install smoke tests. Do ship `ddgs` as a default dep so the
first-launch experience never lands a customer in the schema-dropped
state.

---

## Part F — Smallest fix that would have prevented today's report

If exactly one thing changed in the codebase, ranked by impact:

1. **Add `ddgs` as a default dependency of `monoclaw-runtime`** (in
   `pyproject.toml` and vendored in `hatch/bundle-inputs/vendor/wheelhouse/`).
   This alone makes `check_web_api_key()` return True on every fresh
   install and `web_search` is in the schema. The model never tries
   `curl | grep`. The "tools are unavailable" wording disappears.

2. **Make `registry.get_definitions()` emit a session-startup notice
   when `web_search` (or any commonly-expected tool) is dropped.** Even
   in `quiet_mode`, write to `agent.log` at INFO and to a "needs
   attention" surface the gateway can read. Right now there is a debug
   log gated on `not quiet`, which is doubly hidden.

3. **Fix the retry-loop spinner re-arm in `run_agent.py`.** Move the
   spinner setup (lines 11447–11467) **inside** the `while retry_count <
   max_retries:` loop, or stash a closure that can be called from the
   `continue` path. This is a real bug.

4. **Wire `thinking_callback` from the gateway path.** Gateway agents
   are created with `quiet_mode=True` and `thinking_callback=None`. There
   should be a no-op-safe default callback that the platform adapter can
   override to show a "typing" indicator backed by real LLM-in-flight
   signal.

5. **`monoclaw setup system` should either include a Tools sub-step or
   refuse to declare success when `check_web_api_key()` is False.** The
   wizard sees the world correctly; it's just choosing not to ask.

6. **Hatch should run `monoclaw --version`, `web_search`'s `check_fn`,
   and each skill-dep's `status` subcommand as part of `run_verify`.**
   File presence is not verification.

7. **Resolve the `remindctl` doc contradiction.** Either commit to the
   bundled path or commit to `brew install steipete/tap/remindctl`. The
   website currently teaches the upstream-brew path while Hatch ships a
   pinned binary; pick one.

8. **Delete `configure_homebrew_python_library_paths` from `bin/hatch`,
   or document and gate it behind an explicit diagnostic flag.** It
   violates Hatch's own CLAUDE.md policy.

---

## Loose ends worth checking before any fix

1. **Confirm in a live session** that `monoclaw logs --level DEBUG` for
   Mona's session shows nothing about `web_search` being dropped. The
   `quiet=True` path in `registry.get_definitions` suppresses even debug
   logs; if a user sets `MONOCLAW_LOG_LEVEL=DEBUG`, they should still see
   why. (Today they will not — that's another bug.)
2. **Inspect the actual `config.yaml`** on the affected install for
   `web:` settings. If `web.backend` was hand-edited to one of the paid
   providers but no key was set, `check_web_api_key()` will still return
   False and `monoclaw setup` summaries can misreport availability
   ([monoclaw_cli/setup.py](/Users/admin/Projects/monoclaw-runtime/monoclaw_cli/setup.py)
   line 397 lists EXA/PARALLEL/FIRECRAWL/TAVILY/SEARXNG but **omits
   Brave and `ddgs`**, so the summary itself is inconsistent with the
   real check).
3. **Inspect `~/.monoclaw/plugins/` and `known_plugin_toolsets`** in
   `config.yaml` to confirm Mona is not in an unusual state. The
   historical `platform_toolsets.cli: ["mona_secretary"]` corruption is
   self-repairing, but the legacy entries may still exist on disk.
4. **Decide policy on `monoclaw doctor`.** A `doctor` command exists in
   the engine narrative; the runtime should expose an equivalent that
   walks all tools and reports which are missing why. Today the
   technician has no convenient way to ask "what does Mona think she has
   in this session?"
