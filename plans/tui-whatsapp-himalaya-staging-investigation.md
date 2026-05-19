# TUI / WhatsApp / Himalaya Staging & Wizard Failure Investigation

**Trigger**: On a fresh customer Mac that already cleared the `subwizards`
packaging regression (see `install-failures-investigation.md`), the next round
of provisioning surfaces three distinct failures:

1. `monoclaw --tui` crashes with `FileNotFoundError: ... site-packages/ui-tui`.
2. `monoclaw whatsapp` exits at "✗ Bridge script not found at … site-packages/scripts/whatsapp-bridge/bridge.js".
3. `monoclaw provision` prints `⚠ tools  binary not found: …/skill-deps/bin/tools` and `⚠ himalaya  himalaya account configure exited 2` (with upstream `error: the following required arguments were not provided: <ACCOUNT>`).

These are not regressions in `provision`; they are pre-existing latent bugs that
became visible once the subwizards packaging fix landed and provisioning could
get past the earlier `ModuleNotFoundError`. All three share the same root cause
shape: **the wheel install layout was never reconciled with code paths that
assumed a git-checkout layout, and the Himalaya CLI changed its CLI surface in
v1.0.0 without our subwizard catching up.**

This plan is the post-mortem and the implementation roadmap to make a fresh
Hatch install land with a working TUI, a working WhatsApp setup wizard, a
clean `monoclaw provision` summary (no spurious `tools` warning), and a
Himalaya wizard that actually completes its upstream account-configure step.

---

## 1. Symptom Inventory (verbatim)

### 1.1 TUI launch crash

```
test@tests-iMac ~ % monoclaw --tui
Installing TUI dependencies…
Traceback (most recent call last):
  File "/Users/test/.monoclaw/vendor/runtime/venv/bin/monoclaw", line 6, in <module>
    sys.exit(main())
  ...
  File "/Users/test/.monoclaw/vendor/runtime/venv/lib/python3.13/
        site-packages/monoclaw_cli/main.py", line 1276, in _launch_tui
    argv, cwd = _make_tui_argv(tui_dir, tui_dev)
  File ".../monoclaw_cli/main.py", line 1083, in _make_tui_argv
    result = subprocess.run(
        [npm, "install", "--silent", "--no-fund", "--no-audit",
         "--progress=false"],
        ...
        cwd=str(tui_dir),
        ...
    )
  ...
FileNotFoundError: [Errno 2] No such file or directory:
  '/Users/test/.monoclaw/vendor/runtime/venv/lib/python3.13/
   site-packages/ui-tui'
```

### 1.2 WhatsApp setup wizard crash

```
⚕ WhatsApp Setup
==================================================
...
✓ WhatsApp enabled
  Who should be allowed to message the bot?
  Phone numbers (comma-separated, or * for anyone): *
  ✓ Allowed users set: *

✗ Bridge script not found at /Users/test/.monoclaw/vendor/runtime/venv/
  lib/python3.13/site-packages/scripts/whatsapp-bridge/bridge.js
```

### 1.3 `monoclaw provision` — spurious "tools" warning + Himalaya exit 2

```
Verify and record skill dependency activation now? [y/N]: y
  Himalaya: run `monoclaw provision` to configure email accounts via the
  upstream wizard, and migrate any plaintext passwords in
  ~/.config/himalaya/config.toml into the macOS Keychain.
Skill dependency activation state saved to
  /Users/test/.monoclaw/vendor/skill-deps/.activations.json

  ⚠ tools  binary not found:
    /Users/test/.monoclaw/vendor/skill-deps/bin/tools

  ── Core dependencies (Node, uv, opus, ffmpeg) ──

  ── Secretary tools (email, reminders, notes, messages) ──
error: the following required arguments were not provided:
  <ACCOUNT>

Usage: himalaya account configure <ACCOUNT>
```

The downstream provision summary then carries `himalaya: himalaya account
configure exited 2` as an issue.

---

## 2. Root Cause Analysis

### 2.1 TUI: `ui-tui/` is never shipped to the customer Mac

`monoclaw-runtime/monoclaw_cli/main.py:1185`:

```python
def _launch_tui(...):
    tui_dir = PROJECT_ROOT / "ui-tui"
    ...
    argv, cwd = _make_tui_argv(tui_dir, tui_dev)
```

`PROJECT_ROOT` (`main.py:88`) is computed as
`Path(__file__).parent.parent.resolve()`. In a git-editable checkout that
resolves to the repo root, where `ui-tui/` is a real directory. In a Hatch
install — and any wheel install — `__file__` is at
`…/site-packages/monoclaw_cli/main.py`, so `PROJECT_ROOT` is the
`site-packages/` directory and `tui_dir` is `site-packages/ui-tui` which does
not exist.

`_make_tui_argv` (`main.py:1083`) then immediately tries
`subprocess.run([npm, "install", ...], cwd=str(tui_dir))`. Python's `Popen`
fails with `FileNotFoundError` on the **cwd** (not on `npm`) the moment the
child is forked, because POSIX `chdir()` cannot enter a non-existent
directory. The user sees the traceback before any npm output.

`ui-tui/` is a Node/TypeScript project (`ui-tui/package.json`,
`ui-tui/src/entry.tsx`, etc.). It is intentionally **not** declared in
`pyproject.toml` (`setuptools.packages.find` only picks up Python packages).
The build path is:

```
monoclaw-runtime/ui-tui/          ← source tree (with node_modules)
   |
   |  hatch/build.sh: stage_bundle()  ← does NOT copy ui-tui/
   v
dist/                              ← no ui-tui anywhere
   |
   |  bin/hatch install ($HOME/.monoclaw/vendor)
   v
~/.monoclaw/vendor/runtime/venv/lib/python3.13/site-packages/   ← no ui-tui
```

So **the customer's machine has no `ui-tui` directory at all**, and our code
unconditionally tries to `cd` into a phantom one.

`MONOCLAW_TUI_DIR` is an env-var override but no part of Hatch or
`bin/hatch install` ever sets it. The fall-through behaviour is exactly what
fires on a clean install.

This is one bug split across **three** files:

| File | Line | Symptom |
|------|------|---------|
| `monoclaw_cli/main.py` | 1185 | `tui_dir = PROJECT_ROOT / "ui-tui"` |
| `monoclaw_cli/main.py` | 1012 | `helper = PROJECT_ROOT / "scripts" / "lib" / "node-bootstrap.sh"` — silent no-op in wheel installs |
| `hatch/build.sh` | 446 | `stage_bundle()` vendor list does not include the TUI |

`_ensure_tui_node` quietly returns when the node-bootstrap helper isn't
present, so on this Mac (where node/npm were already on PATH) the missing
helper is invisible. But on a Mac without node it would fail just as
mysteriously without a remediation hint.

### 2.2 WhatsApp: `scripts/whatsapp-bridge/` is never shipped

Same root cause in two more places:

- `monoclaw-runtime/gateway/platforms/whatsapp.py:223`:

  ```python
  _DEFAULT_BRIDGE_DIR = Path(__file__).resolve().parents[2] / "scripts" / "whatsapp-bridge"
  ```

  In a wheel install `parents[2]` is `site-packages/`, so this becomes
  `site-packages/scripts/whatsapp-bridge` — missing.

- `monoclaw-runtime/monoclaw_cli/main.py:1591` (`cmd_whatsapp`):

  ```python
  project_root = Path(__file__).resolve().parents[1]
  bridge_dir = project_root / "scripts" / "whatsapp-bridge"
  bridge_script = bridge_dir / "bridge.js"
  ```

  Same site-packages problem.

- `monoclaw-runtime/monoclaw_cli/doctor.py:1584` also probes
  `PROJECT_ROOT / "scripts" / "whatsapp-bridge"` and only avoids a false
  warning because it skips the audit when `node_modules` is missing.

The `scripts/whatsapp-bridge/` tree (`bridge.js`, `allowlist.js`,
`package.json`, `package-lock.json`) is in the git checkout, but
`pyproject.toml`'s `setuptools.packages.find` ignores it, and `hatch/build.sh`
never copies it into `dist/`. The `cmd_whatsapp` setup wizard further
*depends* on running `npm install` against this directory, so even an env-var
override (e.g. `MONOCLAW_WHATSAPP_BRIDGE_SCRIPT`) is insufficient — it needs
the whole project on disk, in a writable location.

There is **no** env-var override surface for the setup wizard
(`gateway/platforms/whatsapp.py` honours `bridge_script` from
`PlatformConfig.extra`, but the setup wizard in `main.py` hard-codes the
path). So even a technician who knows where the bridge lives cannot point the
wizard at it without code edits.

### 2.3 Himalaya: upstream v1.0.0 made `<ACCOUNT>` required

`monoclaw-runtime/monoclaw_cli/subwizards/himalaya.py:702-708`:

```python
def _spawn_account_configure(self, binary_path, artifacts):
    proc = subprocess.run(
        [str(binary_path), "account", "configure"],
        stdin=sys.stdin, stdout=sys.stdout, stderr=sys.stderr,
        check=False,
    )
```

Upstream Himalaya v1.0.0 (December 2024) refactored `account configure` to
take a positional account name. Verifying against the canonical source:

> `src/account/command/configure.rs`:
> ```rust
> /// Configure the given account.
> ///
> /// This command allows you to configure an existing account or to
> /// create a new one, using the wizard.
> pub struct AccountConfigureCommand {
>     #[command(flatten)]
>     pub account: AccountNameArg,
> }
> ```
>
> `src/account/arg/name.rs`:
> ```rust
> pub struct AccountNameArg {
>     #[arg(name = "account_name", value_name = "ACCOUNT")]
>     pub name: String,  // NOT Option<String>
> }
> ```

The bundled binary at `~/.monoclaw/vendor/skill-deps/bin/himalaya` is **v1.2.0**
(see `hatch/bundle-inputs/vendor/skill-deps/source-lock.json:119`), so the
positional argument is required. Without it, clap exits 2 with the message
in the symptom log. The same applies to the brew binary (also v1.2.0+).

The subwizard never asks the user for an account name, so it never has one to
pass. This is a straightforward upstream-CLI drift; the existing test
(`tests/monoclaw_cli/subwizards/test_himalaya.py:319`) asserts the wrong
shape:

```python
assert cmd == [str(binary), "account", "configure"]
```

— it's a perfect change-detector locking us into the broken pre-v1.0 surface.

### 2.4 `tools` binary not found: `probe_skill_deps` reads the wrong shape

`monoclaw_cli/system_setup.py:967-1023` writes the activation manifest as:

```json
{
  "updated_at": "2026-05-19T12:00:00",
  "tools": {
    "remindctl": {...},
    "memo": {...},
    "imsg": {...},
    "himalaya": {...}
  }
}
```

`monoclaw_cli/provision.py:370-418` reads it as a flat dict:

```python
for name, state in manifest.items():        # iterates {"updated_at", "tools"}
    if not isinstance(state, dict):
        continue                            # skips "updated_at"
    bin_path_str = state.get("bin_path")    # also wrong: writer uses "path"
                  or str(home / "vendor" / "skill-deps" / "bin" / name)
    bin_path = Path(bin_path_str)
    if not bin_path.exists():
        results.append({"name": name, "ok": False,
                        "error": f"binary not found: {bin_path}"})
```

So the function:

1. Sees `("updated_at", "<iso>")`, skips it as non-dict.
2. Sees `("tools", {...})`, treats it as a tool named `tools`.
3. Falls back to `~/.monoclaw/vendor/skill-deps/bin/tools` because the
   `tools` "entry" has no `bin_path`.
4. That path doesn't exist → emits the warning the user saw.

Two bugs stacked:

| # | Bug | Fix shape |
|---|-----|-----------|
| 1 | Iterates top-level instead of `manifest["tools"]` | `for name, state in manifest.get("tools", {}).items():` |
| 2 | Reads `bin_path` but writer uses `path` | `state.get("path") or state.get("bin_path")` for back-compat |

The combination means `probe_skill_deps` has *never* actually probed a single
skill-dep binary on a real install — the loop has been silently emitting a
fake warning since the activation-manifest shape changed, and every real
binary check has been skipped.

### 2.5 Why none of these were caught by existing tests

| Symptom | Test gap |
|---------|----------|
| 2.1 TUI launch | `_launch_tui` is never exercised against a wheel install. `tests/` covers `_normalize_tui_toolsets` and `_tui_need_npm_install` but not the cwd-existence assumption. |
| 2.2 WhatsApp bridge | `tests/gateway/test_whatsapp_connect.py` constructs the adapter with `config.extra["bridge_script"]` set to a temp file. The default path is never exercised. `cmd_whatsapp` has no tests at all. |
| 2.3 Himalaya `<ACCOUNT>` | `test_himalaya.py:319` hard-codes the broken pre-v1.0 invocation as the "correct" command. The test passes because it mocks `subprocess.run` — the real upstream CLI never runs. |
| 2.4 `probe_skill_deps` shape | `tests/monoclaw_cli/test_provision.py` does not write a representative activation manifest before calling `probe_skill_deps`. It returns `[]` (no manifest) or stubs the result. The "iterate top-level" bug never fires under test. |

---

## 3. Fix Plan (ordered by blast radius)

### Phase 1 — Stop the bleeding (P0)

#### 3.1 Fix `probe_skill_deps` manifest-shape bug

File: `monoclaw-runtime/monoclaw_cli/provision.py`

```diff
 def probe_skill_deps(home: Path) -> list[dict]:
-    """Run verify sub-commands for each skill-dep binary in the activation manifest.
+    """Run verify sub-commands for each skill-dep binary in the activation manifest.
+
+    The manifest at ``vendor/skill-deps/.activations.json`` has the shape
+    ``{"updated_at": "...", "tools": {<name>: <entry>}}`` (written by
+    ``monoclaw_cli.system_setup._write_skill_deps_activations``). Iterate
+    the ``tools`` sub-dict, not the top-level keys.
+    """
     activation_path = home / "vendor" / "skill-deps" / ".activations.json"
     if not activation_path.exists():
         return []
     try:
         import json as _json
         manifest = _json.loads(activation_path.read_text(encoding="utf-8"))
     except Exception:
         return []

     results: list[dict] = []
-    for name, state in manifest.items():
+    tools = manifest.get("tools") if isinstance(manifest, dict) else None
+    if not isinstance(tools, dict):
+        return []
+    for name, state in tools.items():
         if not isinstance(state, dict):
             continue
-        bin_path_str = state.get("bin_path") or str(home / "vendor" / "skill-deps" / "bin" / name)
+        # Writer key is "path"; tolerate the historical "bin_path" alias.
+        bin_path_str = (
+            state.get("path")
+            or state.get("bin_path")
+            or str(home / "vendor" / "skill-deps" / "bin" / name)
+        )
         bin_path = Path(bin_path_str)
```

Regression test (`tests/monoclaw_cli/test_provision.py`):

```python
def test_probe_skill_deps_iterates_tools_subdict(tmp_path):
    """The May 2026 bug iterated top-level keys, surfacing a fake tool
    named 'tools' that pointed at a non-existent binary. Lock the shape."""
    home = tmp_path / ".monoclaw"
    activations = home / "vendor" / "skill-deps" / ".activations.json"
    activations.parent.mkdir(parents=True)
    activations.write_text(json.dumps({
        "updated_at": "2026-05-19T00:00:00",
        "tools": {
            "himalaya": {
                "path": str(tmp_path / "fake-himalaya"),
                "installed": False,
                "status": "missing",
            },
        },
    }))
    results = provision.probe_skill_deps(home)
    names = {r["name"] for r in results}
    assert "tools" not in names, (
        "probe_skill_deps must iterate manifest['tools'], not the top level"
    )
    assert "himalaya" in names
```

This test must fail on `main` before the fix lands.

#### 3.2 Fix the Himalaya subwizard's `account configure` invocation

File: `monoclaw-runtime/monoclaw_cli/subwizards/himalaya.py`

Upstream `himalaya account configure <ACCOUNT>` will create the account
record if it doesn't exist; the wizard then walks the user through
email/IMAP/SMTP/auth. We must collect an account name from the user
before invoking it.

```diff
+_ACCOUNT_NAME_RE = re.compile(r"[A-Za-z0-9._-]{1,64}")
+
+
+def _prompt_account_name() -> str | None:
+    """Ask the user for the alias they want to use for the new account.
+
+    Returns ``None`` if the user just hit return, sent EOF, or typed
+    something that isn't a safe TOML key / Keychain service suffix. Callers
+    must treat ``None`` as "skip the subwizard" rather than passing an
+    empty argv element to himalaya. There is intentionally NO default:
+    the alias becomes a TOML key and a Keychain service-name suffix, so
+    auto-picking ``gmail`` for an Outlook user would create rename pain
+    later.
+    """
+    try:
+        raw = input(
+            "  Account alias (e.g. gmail, work, personal) — required: "
+        ).strip()
+    except (EOFError, KeyboardInterrupt):
+        print()
+        return None
+    if not raw:
+        print("  ✗ No alias provided; skipping himalaya wizard.")
+        return None
+    if not _ACCOUNT_NAME_RE.fullmatch(raw):
+        print(
+            "  ✗ Account alias must be 1-64 chars of [A-Za-z0-9._-]; aborting.",
+        )
+        return None
+    return raw


-    def _spawn_account_configure(self, binary_path, artifacts):
+    def _spawn_account_configure(self, binary_path, artifacts):
+        account_name = _prompt_account_name()
+        if account_name is None:
+            return SubWizardResult(
+                ok=False,
+                detail="skipped — no account alias provided",
+                error=(
+                    "Re-run `monoclaw provision` (or `himalaya account "
+                    "configure <alias>` directly) to set up email."
+                ),
+                artifacts=artifacts,
+            )
         try:
             proc = subprocess.run(
-                [str(binary_path), "account", "configure"],
+                [str(binary_path), "account", "configure", account_name],
                 stdin=sys.stdin, stdout=sys.stdout, stderr=sys.stderr,
                 check=False,
             )
         except (OSError, subprocess.SubprocessError) as exc:
             ...
         if proc.returncode != 0:
             return SubWizardResult(
                 ok=False,
-                error=f"himalaya account configure exited {proc.returncode}",
+                error=(
+                    f"himalaya account configure {account_name} exited "
+                    f"{proc.returncode}"
+                ),
                 artifacts=artifacts,
             )
         return SubWizardResult(
             ok=True,
-            detail="himalaya account configured via upstream wizard",
+            detail=(
+                f"himalaya account '{account_name}' configured via upstream "
+                "wizard"
+            ),
             artifacts={**artifacts, "configured_account": account_name},
         )
```

Update the existing test to assert the new shape (not a change-detector;
it's pinning a behavioral contract with the upstream CLI):

```diff
 def test_spawns_account_configure_when_no_account(...):
     binary = _stage_bundled_himalaya(fake_home)
     spawn = MagicMock(return_value=subprocess.CompletedProcess(["himalaya"], 0))
     monkeypatch.setattr(himalaya_mod.subprocess, "run", spawn)
+    monkeypatch.setattr(himalaya_mod, "_prompt_account_name", lambda: "gmail")
     wiz = HimalayaSubWizard()
     ...
     cmd = spawn.call_args.args[0]
-    assert cmd == [str(binary), "account", "configure"]
+    assert cmd == [str(binary), "account", "configure", "gmail"]
```

Add a new test that locks in the upstream contract:

```python
def test_account_configure_requires_positional_argument(monkeypatch):
    """Upstream Himalaya v1.0.0+ requires <ACCOUNT> as a positional arg.
    Test that we never invoke `himalaya account configure` bare —
    that exits 2 and breaks `monoclaw provision`."""
    captured = []
    def fake_run(cmd, **kwargs):
        captured.append(cmd)
        return subprocess.CompletedProcess(cmd, 0)
    monkeypatch.setattr(himalaya_mod.subprocess, "run", fake_run)
    monkeypatch.setattr(himalaya_mod, "_prompt_account_name", lambda: "gmail")
    wiz = HimalayaSubWizard()
    wiz._spawn_account_configure(Path("/usr/bin/himalaya"), artifacts={})
    assert captured, "subprocess.run was never called"
    assert captured[0][-2:] != ["account", "configure"], (
        "must not invoke bare `account configure` (clap exits 2)"
    )
    assert "configure" in captured[0]
    # last argv element is the account alias
    assert captured[0][-1] not in ("configure",)
```

#### 3.3 Stage `ui-tui/` and `scripts/whatsapp-bridge/` under `~/.monoclaw/vendor/`

This is the architectural fix. Two parallel Node-shaped subsystems need
homes that survive a wheel install. The cleanest pattern, mirroring how
`bundle-inputs/vendor/browser` already works, is:

```
~/.monoclaw/vendor/
├── tui/                       (NEW — staged by Hatch)
│   ├── package.json
│   ├── package-lock.json
│   ├── packages/monoclaw-ink/dist/entry-exports.js   (prebuilt)
│   ├── dist/entry.js                              (prebuilt)
│   └── (no node_modules — installer or first-run does npm ci)
├── whatsapp-bridge/           (NEW — staged by Hatch)
│   ├── package.json
│   ├── package-lock.json
│   ├── bridge.js
│   ├── allowlist.js
│   └── (no node_modules — npm install on first WhatsApp setup)
└── ...
```

##### 3.3.a Hatch build.sh — copy the trees into `dist/vendor/`

File: `monoclaw-developer/hatch/build.sh`

```diff
 stage_runtime_optional_skills() {
   ...
 }

+stage_runtime_tui() {
+  local tui_src="${HATCH_RUNTIME_ROOT}/ui-tui"
+  if [[ ! -d "${tui_src}" ]]; then
+    log "warn: runtime ui-tui directory missing; TUI will not be bundled"
+    return 0
+  fi
+  if [[ "${HATCH_SKIP_RUNTIME_BUILD:-0}" != "1" ]]; then
+    log "Building TUI ink bundle + dist/entry.js"
+    (cd "${tui_src}" && npm ci && npm run build)
+  fi
+  log "Staging vendor/tui (sources + prebuilt dist; no node_modules)"
+  mkdir -p "${HATCH_DIST_ROOT}/vendor/tui"
+  # Copy everything except node_modules — install-time `npm ci` rebuilds.
+  rsync -a --delete \
+    --exclude '/node_modules' \
+    --exclude '/.cache' \
+    --exclude '/coverage' \
+    "${tui_src}/" "${HATCH_DIST_ROOT}/vendor/tui/"
+}

+stage_runtime_whatsapp_bridge() {
+  local bridge_src="${HATCH_RUNTIME_ROOT}/scripts/whatsapp-bridge"
+  if [[ ! -d "${bridge_src}" ]]; then
+    log "warn: runtime whatsapp-bridge directory missing; bridge will not be bundled"
+    return 0
+  fi
+  log "Staging vendor/whatsapp-bridge (sources only; npm install on demand)"
+  mkdir -p "${HATCH_DIST_ROOT}/vendor/whatsapp-bridge"
+  rsync -a --delete \
+    --exclude '/node_modules' \
+    "${bridge_src}/" "${HATCH_DIST_ROOT}/vendor/whatsapp-bridge/"
+}
```

And call them inside `stage_bundle()`:

```diff
   log_step "stage runtime skills catalogs"
   stage_runtime_skills
   stage_runtime_optional_skills
+  stage_runtime_tui
+  stage_runtime_whatsapp_bridge
```

##### 3.3.b Hatch bin/hatch — copy from `dist/` into `~/.monoclaw/vendor/`

File: `monoclaw-developer/hatch/bin/hatch`

```diff
   for asset in python support lm-studio models browser skills optional-skills \
-              launchd wheelhouse provisioning; do
+              launchd wheelhouse provisioning tui whatsapp-bridge; do
     if [[ -d "${HATCH_BUNDLE_ROOT}/vendor/${asset}" ]]; then
       log_action rm -rf "${home_dir}/vendor/${asset}"
       log_action cp -R "${HATCH_BUNDLE_ROOT}/vendor/${asset}" \
         "${home_dir}/vendor/${asset}"
     fi
   done
```

##### 3.3.c Runtime — find the staged trees before falling back to the source path

File: `monoclaw-runtime/monoclaw_cli/main.py` (`_launch_tui`)

```diff
+def _resolve_tui_dir() -> Path:
+    """Locate the ui-tui source tree.
+
+    Resolution order:
+      1. ``MONOCLAW_TUI_DIR`` env override (technician/dev escape hatch).
+      2. ``$MONOCLAW_HOME/vendor/tui`` (Hatch / wheel install staging).
+      3. ``PROJECT_ROOT/ui-tui`` (git-editable checkout).
+
+    Never returns a non-existent path; callers should still verify a
+    ``package.json`` is present before invoking npm.
+    """
+    env = os.environ.get("MONOCLAW_TUI_DIR", "").strip()
+    if env:
+        p = Path(env).expanduser()
+        if p.is_dir():
+            return p
+    staged = get_monoclaw_home() / "vendor" / "tui"
+    if (staged / "package.json").is_file():
+        return staged
+    return PROJECT_ROOT / "ui-tui"


 def _launch_tui(...):
-    tui_dir = PROJECT_ROOT / "ui-tui"
+    tui_dir = _resolve_tui_dir()
+    if not (tui_dir / "package.json").is_file():
+        print(
+            "✗ TUI sources not found at "
+            f"{tui_dir} (set MONOCLAW_TUI_DIR or reinstall).",
+            file=sys.stderr,
+        )
+        sys.exit(1)
```

`_make_tui_argv` already calls `_tui_need_npm_install(tui_dir)`; since the
staged tree ships *without* `node_modules`, the first `monoclaw --tui`
invocation on a customer Mac will trigger `npm ci`-equivalent
(`npm install --silent --no-fund …`) inside `~/.monoclaw/vendor/tui/`. That
location is user-writable, unlike `site-packages/`. The prebuilt
`dist/entry.js` + `packages/monoclaw-ink/dist/entry-exports.js` mean
`_tui_build_needed(tui_dir)` returns False, so no full build runs on the
customer Mac.

File: `monoclaw-runtime/gateway/platforms/whatsapp.py`

```diff
+def _resolve_bridge_dir() -> Path:
+    """Locate scripts/whatsapp-bridge.
+
+    Order:
+      1. ``MONOCLAW_WHATSAPP_BRIDGE_DIR`` env override.
+      2. ``$MONOCLAW_HOME/vendor/whatsapp-bridge`` (Hatch staging).
+      3. ``Path(__file__).resolve().parents[2] / "scripts" / "whatsapp-bridge"``
+         (git-editable).
+    """
+    env = os.environ.get("MONOCLAW_WHATSAPP_BRIDGE_DIR", "").strip()
+    if env:
+        p = Path(env).expanduser()
+        if (p / "bridge.js").is_file():
+            return p
+    home = get_monoclaw_home()
+    staged = home / "vendor" / "whatsapp-bridge"
+    if (staged / "bridge.js").is_file():
+        return staged
+    return Path(__file__).resolve().parents[2] / "scripts" / "whatsapp-bridge"


 class WhatsAppPlatform(...):
-    _DEFAULT_BRIDGE_DIR = Path(__file__).resolve().parents[2] / "scripts" / "whatsapp-bridge"
+    @classmethod
+    def _default_bridge_dir(cls) -> Path:
+        return _resolve_bridge_dir()

     def __init__(self, config):
         ...
         self._bridge_script: Optional[str] = config.extra.get(
             "bridge_script",
-            str(self._DEFAULT_BRIDGE_DIR / "bridge.js"),
+            str(self._default_bridge_dir() / "bridge.js"),
         )
```

File: `monoclaw-runtime/monoclaw_cli/main.py` (`cmd_whatsapp`)

```diff
-    project_root = Path(__file__).resolve().parents[1]
-    bridge_dir = project_root / "scripts" / "whatsapp-bridge"
+    from gateway.platforms.whatsapp import _resolve_bridge_dir
+    bridge_dir = _resolve_bridge_dir()
     bridge_script = bridge_dir / "bridge.js"
```

File: `monoclaw-runtime/monoclaw_cli/doctor.py:1584`

Replace the hardcoded `PROJECT_ROOT / "scripts" / "whatsapp-bridge"` with
the same resolver so the doctor's npm-audit step probes the actually-staged
location.

#### 3.4 Hatch verify hook — refuse releases without the new trees

File: `monoclaw-developer/hatch/scripts/verify_skill_bundle.py` (or a sibling
that runs in `stage_bundle` after the new copies)

Add asserts:

```python
required_subtrees = [
    ("vendor/tui/package.json", "TUI sources"),
    ("vendor/tui/dist/entry.js", "TUI prebuilt dist/entry.js"),
    ("vendor/whatsapp-bridge/bridge.js", "WhatsApp bridge script"),
    ("vendor/whatsapp-bridge/package.json", "WhatsApp bridge package.json"),
]
missing = [
    (rel, label)
    for rel, label in required_subtrees
    if not (bundle_root / rel).is_file()
]
if missing:
    raise SystemExit(
        "hatch bundle is missing required Node subsystems:\n  - "
        + "\n  - ".join(f"{rel} ({label})" for rel, label in missing)
    )
```

#### 3.5 Regression tests for the wheel-layout assumption

Two new test files. Both can run without a real wheel — they patch
`PROJECT_ROOT` and `MONOCLAW_HOME` to simulate the wheel layout.

File: `tests/monoclaw_cli/test_tui_dir_resolution.py`

```python
def test_resolve_tui_dir_prefers_env(tmp_path, monkeypatch):
    monkeypatch.setenv("MONOCLAW_TUI_DIR", str(tmp_path))
    (tmp_path / "package.json").write_text("{}")
    from monoclaw_cli.main import _resolve_tui_dir
    assert _resolve_tui_dir() == tmp_path


def test_resolve_tui_dir_falls_back_to_vendor(tmp_path, monkeypatch):
    """In a wheel install, $MONOCLAW_HOME/vendor/tui must win over the
    phantom PROJECT_ROOT/ui-tui. Locks the symptom from May 2026."""
    monkeypatch.delenv("MONOCLAW_TUI_DIR", raising=False)
    monkeypatch.setenv("MONOCLAW_HOME", str(tmp_path))
    staged = tmp_path / "vendor" / "tui"
    staged.mkdir(parents=True)
    (staged / "package.json").write_text("{}")
    from monoclaw_cli.main import _resolve_tui_dir
    assert _resolve_tui_dir() == staged
```

File: `tests/gateway/test_whatsapp_bridge_resolution.py`

Mirror the same shape for `_resolve_bridge_dir`.

### Phase 2 — Doctor + provision visibility (P1) — **LANDED 2026-05-19**

Status note: items 3.6, 3.7, 3.8 are all shipped. 3.7 (friendlier
WhatsApp bridge missing message) and 3.8 (legacy-shape compat for stale
activation manifests) were already implemented as part of Phase 1's
wire-up and `probe_skill_deps` fix respectively. Item 3.6 was extracted
into a standalone helper for testability and a dedicated test file:

- `monoclaw_cli/doctor.py`:
  - new `_whatsapp_enabled_from_config()` — best-effort YAML probe that
    never raises; falls back to "treat as disabled" on any error.
  - new `_check_node_subsystem_staging(layout, manual_issues)` — wheel-only
    helper that reports TUI / WhatsApp bridge staging via the layout-aware
    resolvers. Silent on git-editable layouts (the source-tree fallback
    always exists for developers).
- Per-check policy: TUI is always-warn when missing (canonical
  interactive surface); WhatsApp bridge is warn-when-opted-in,
  info-otherwise so single-platform Macs aren't nagged about a feature
  they aren't using.
- New test file `tests/monoclaw_cli/test_doctor_node_subsystems.py`
  (12 cases) locking in the four contracts: silent on git-editable,
  green-on-green when both staged, TUI-missing → warn + manual issue,
  bridge-missing → info / warn gated by `gateway.whatsapp.enabled`.
  Also covers resolver-import failure (degrades to warn, not stack
  trace) and env-override interaction.

Implementation notes carried over below for archival.

#### 3.6 Doctor — surface bundle-staging gaps

`monoclaw doctor` should already warn when the TUI / WhatsApp bridge is
missing from a Hatch install, not when the user actually runs the feature.
Add checks gated on layout (see `install-failures-investigation.md` 3.6 for
the layout-detection helper):

```python
if layout != "git-editable":
    tui_dir = _resolve_tui_dir()
    if not (tui_dir / "package.json").is_file():
        check_warn(
            "TUI sources not staged",
            f"expected at {get_monoclaw_home()}/vendor/tui (run `hatch install` to repair)"
        )
    bridge_dir = _resolve_bridge_dir()
    if not (bridge_dir / "bridge.js").is_file():
        check_warn(
            "WhatsApp bridge not staged",
            f"expected at {get_monoclaw_home()}/vendor/whatsapp-bridge"
        )
```

#### 3.7 `monoclaw whatsapp` — print the staged path on success

The setup wizard currently prints
`✗ Bridge script not found at <path>` and exits. Make the message include a
remediation hint:

```
✗ Bridge script not found at <path>
  Re-run `bin/hatch install` to stage vendor/whatsapp-bridge,
  or set MONOCLAW_WHATSAPP_BRIDGE_DIR to a local checkout for development.
```

#### 3.8 Provision — call out the spurious `tools` warning when the manifest is stale

Until every install runs the new code, surface a friendlier message if a
pre-fix `.activations.json` is found. In `probe_skill_deps`, if the
top-level dict has a key `"tools"` *and* `"updated_at"` *and* the entries
under `"tools"` look like the v2 shape, just iterate the sub-dict (already
covered by 3.1). If we detect the *legacy* flat shape (no `"tools"` key but
entries with `"path"`/`"status"`), fall back to iterating top-level keys
(skipping `"updated_at"`-style strings). Keep both shapes alive for one
release so users with a stale manifest aren't forced to rerun
`monoclaw setup system`:

```python
if "tools" in manifest and isinstance(manifest["tools"], dict):
    tools = manifest["tools"]
else:
    tools = {
        k: v for k, v in manifest.items()
        if isinstance(v, dict) and ("path" in v or "status" in v)
    }
```

Add a test covering both shapes.

### Phase 3 — Cleanup & hardening (P2) — **LANDED 2026-05-19**

All three items shipped:

- **3.9** — `provision.himalaya.account_name` added to `DEFAULT_CONFIG`
  (empty string by default = preserve interactive prompt). New helper
  `_account_name_from_config` reuses the same validation regex as the
  interactive prompt so a bad value silently falls through to prompting
  (interactive) or to the placeholder-aware "run himalaya account
  configure `<alias>` in a terminal" hint (non-interactive). The
  non-tty error message now echoes the configured alias verbatim so
  operators can copy/paste the exact command. Tests:
  `TestAccountNameFromConfig` (9 cases) + 4 `TestRun` extensions +
  `TestProvisionHimalayaConfig` (2 cases) covering DEFAULT_CONFIG
  plumbing + deep-merge survival.
- **3.10** — `_ensure_tui_node` is now layout-aware. Git-editable
  checkouts retain the existing bash bootstrap helper path; wheel
  installs print a one-line remediation hint pointing at `bin/hatch
  install` (Hatch's `run_install_core_deps` installs Node via Homebrew)
  and at `brew install node` as a manual fallback. Pre-fix behaviour
  was a silent no-op when the helper was missing, leaving the user to
  see a bare "node not found" exit later. Tests:
  `tests/monoclaw_cli/test_ensure_tui_node.py` (5 cases) including
  `MONOCLAW_QUIET` suppression of the hint.
- **3.11** — `hatch/docs/runtime-artifacts.md` extended with the
  `vendor/tui/` and `vendor/whatsapp-bridge/` rows in both the
  Prepared Bundle Layout and Installed Runtime Layout sections, plus a
  prose section describing the Hatch staging contract, the runtime's
  layout-aware resolvers, and the `verify_node_subsystems.py` bundle
  gate.

Implementation notes carried over below for archival.

#### 3.9 Make Himalaya's account name source pluggable

For non-interactive provision (CI, ACP, headless installs), the subwizard
should accept an account name from `config.yaml` instead of prompting:

```yaml
provision:
  himalaya:
    account_name: gmail
```

`_spawn_account_configure` would read `config["provision"]["himalaya"]["account_name"]`
first, fall back to `_prompt_account_name()` only when tty *and* unset.

#### 3.10 Drop the dead `scripts/lib/node-bootstrap.sh` lookup or stage it

`_ensure_tui_node` references `PROJECT_ROOT / "scripts" / "lib" / "node-bootstrap.sh"`,
which is also missing in wheel installs. Either:

- **A**: stage `scripts/lib/` into `~/.monoclaw/vendor/scripts/` alongside the TUI
  and resolve the helper via the same lookup pattern, or
- **B**: drop the auto-bootstrap path entirely on wheel installs and rely on
  Hatch's `run_install_core_deps` to provide node.

Option B is preferred — Hatch is already the right authority to install
node/npm on customer Macs, and `_ensure_tui_node` was originally written for
dev-mode installs.

#### 3.11 Document the new vendor subtrees in `hatch/docs/runtime-artifacts.md`

Add the `vendor/tui/` and `vendor/whatsapp-bridge/` rows to the bundle layout
table so the next person debugging "where does X live?" doesn't have to
re-derive it from `build.sh`.

---

## 4. Verification Plan

A fresh-Mac install must pass the following on the user's identified branch
before merge:

1. `cd hatch && bash build.sh` — succeeds; bundle contains
   `dist/vendor/tui/dist/entry.js`, `dist/vendor/tui/package.json`,
   `dist/vendor/whatsapp-bridge/bridge.js`.
2. New `tests/monoclaw_cli/test_provision.py::test_probe_skill_deps_iterates_tools_subdict`
   — passes.
3. New `tests/monoclaw_cli/test_tui_dir_resolution.py` — passes.
4. New `tests/gateway/test_whatsapp_bridge_resolution.py` — passes.
5. Updated `tests/monoclaw_cli/subwizards/test_himalaya.py::test_spawns_account_configure_when_no_account`
   — passes against the new `account configure <ACCOUNT>` signature.
6. New `test_account_configure_requires_positional_argument` — passes.
7. From `dist/`, `bash install.sh` against an empty `~/.monoclaw/` on a
   Mac that has never seen MonoClaw:
   - `~/.monoclaw/vendor/tui/package.json` exists,
   - `~/.monoclaw/vendor/whatsapp-bridge/bridge.js` exists,
   - `~/.local/bin/monoclaw --tui` launches the TUI without
     `FileNotFoundError`,
   - `~/.local/bin/monoclaw whatsapp` reaches the QR pairing step (or the
     `npm install` of the bridge if Node tools weren't already cached),
   - `~/.local/bin/monoclaw provision` does NOT print
     `⚠ tools  binary not found`,
   - `~/.local/bin/monoclaw provision` reaches Himalaya, prompts for an
     account alias, and successfully launches `himalaya account configure <alias>`.
8. `monoclaw doctor` reports zero false positives related to TUI / WhatsApp
   bridge presence.
9. `bash hatch/tests/run_tests.sh` — all dry-run + verify probes pass.
10. `bash monoclaw-runtime/scripts/run_tests.sh` — full Python suite passes.

---

## 5. Sequencing & Ownership

| Phase | Work item                                                              | Repo                | P  |
|-------|------------------------------------------------------------------------|---------------------|----|
| 1     | Fix `probe_skill_deps` manifest-shape bug + test                       | monoclaw-runtime    | P0 |
| 1     | Fix Himalaya `account configure <ACCOUNT>` + update tests              | monoclaw-runtime    | P0 |
| 1     | Add `_resolve_tui_dir` + `_resolve_bridge_dir` resolvers + tests       | monoclaw-runtime    | P0 |
| 1     | Stage `vendor/tui` and `vendor/whatsapp-bridge` in `hatch/build.sh`    | monoclaw-developer  | P0 |
| 1     | Add `vendor/tui` + `vendor/whatsapp-bridge` to `install_runtime_assets`| monoclaw-developer  | P0 |
| 1     | Hatch verify hook refuses bundles missing the new subtrees             | monoclaw-developer  | P0 |
| 2     | Doctor — layout-aware TUI / bridge staging checks                      | monoclaw-runtime    | P1 |
| 2     | `monoclaw whatsapp` — friendlier missing-bridge message                | monoclaw-runtime    | P1 |
| 2     | `probe_skill_deps` legacy-shape compatibility for stale manifests      | monoclaw-runtime    | P1 |
| 3     | Himalaya account name from config (non-interactive provision)          | monoclaw-runtime    | P2 |
| 3     | Drop or stage `scripts/lib/node-bootstrap.sh`                          | monoclaw-runtime    | P2 |
| 3     | Document new vendor subtrees in `runtime-artifacts.md`                 | monoclaw-developer  | P2 |

Phase 1 ships as a coordinated PR pair (runtime + developer/hatch). Without
the staging changes, the new resolvers fall through to the original phantom
path; without the resolver changes, the staged trees are invisible. Both
gates must clear at once.

The Himalaya CLI fix and the `probe_skill_deps` shape fix are independent
of the staging work and can land separately on the runtime side, but
they're cheap enough to bundle into the same Phase 1 PR.

---

## 6. Decisions Recorded (2026-05-19)

- **D1 — TUI: prebuild + ship sources, no `node_modules`**. Hatch already runs
  `npm ci && npm run build` for the web dashboard during `build.sh`, so Node
  is a build-time prereq. We prebuild `dist/entry.js` and
  `packages/monoclaw-ink/dist/entry-exports.js` on the Hatch host and ship them
  alongside the sources. First-run `monoclaw --tui` on the customer Mac does
  `npm install` (dependency resolution only) into
  `~/.monoclaw/vendor/tui/node_modules/`, never `npm run build`. Saves
  ~150 MB pendrive footprint vs. shipping `node_modules`. Air-gapped customer
  support is a follow-up (bundled npm cache, tracked separately).

- **D2 — WhatsApp bridge: stage sources + run `npm install` during Hatch
  install** (not on first WhatsApp wizard run). `bin/hatch install` is the
  natural place because (a) the technician already expects a slow setup
  step, (b) Node is verified during `run_install_core_deps`, and (c) by the
  time the customer launches `monoclaw whatsapp` the bridge is hot. The
  setup wizard keeps its on-demand `npm install` fallback for git-editable
  dev installs only. Idempotent: `npm install` against an up-to-date
  `node_modules` is a no-op.

- **D3 — Himalaya account alias: no default**. The prompt suggests
  `gmail / work / personal` as examples but `""` (or EOF) aborts the
  subwizard with a remediation hint, rather than silently picking a
  contestable default. Rationale: the alias becomes a TOML key and a
  Keychain service-name suffix; auto-picking `gmail` for an Outlook user
  would create rename pain later. The prompt accepts alphanumerics + `._-`,
  rejects everything else with a hard error.

- **D4 — Keychain orphan handling**: out of scope for v1. The plaintext
  migration path already documents the service-name shape
  (`himalaya-<account>-imap` / `-smtp`); a future `monoclaw himalaya
  prune-keychain` subcommand can scan for orphans. Not a Phase 1 blocker.

- **D5 — Shared "wheel-install layout" doc**: defer to a follow-up PR.
  Both this plan and `install-failures-investigation.md` already cite the
  symptom shape; promoting it to `AGENTS.md` is a docs PR, not a fix PR.

## 7. Open Questions / Risks

- **R1 — Hatch build host requires `npm` in `$PATH`**: the new TUI prebuild
  step assumes the Hatch operator has Node installed. This is already true
  in practice (web dashboard build also needs it) and CI uses
  `actions/setup-node`. The `build.sh` step gates on `HATCH_SKIP_RUNTIME_BUILD`
  so air-gapped rebuilds can use a pre-staged `dist/` directly.

- **R2 — WhatsApp `npm install` failure mode during `bin/hatch install`**:
  if the customer Mac is offline at install time, the bridge install will
  fail. **Mitigation**: make the step non-fatal by default; log a warning
  and let the setup wizard's fallback `npm install` retry when the customer
  later runs `monoclaw whatsapp`. `HATCH_REQUIRE_WHATSAPP_BRIDGE_INSTALL=1`
  upgrades the warning to a hard fail for environments that want
  install-time guarantees.

- **R3 — `~/.monoclaw/vendor/tui/node_modules` first-run cost**: TUI startup
  becomes a 30-90s first-launch wait on a cold npm cache. We surface
  `Installing TUI dependencies…` (existing message) and rely on the user
  to wait. A future enhancement could pre-warm during `bin/hatch install`
  the same way WhatsApp does (Phase 3 candidate, but not blocking).

- **R4 — Stale `vendor/tui/` after a runtime upgrade**: if Hatch installs
  a newer runtime wheel but skips re-staging the TUI subtree, the
  prebuilt `dist/entry.js` may drift behind the runtime's protocol. The
  `install_runtime_assets` step does `rm -rf` then `cp -R`, so a full
  Hatch install never leaves stale TUI sources; partial in-place upgrades
  (`pip install --upgrade monoclaw-runtime` only) would. **Mitigation**:
  the runtime's `_tui_build_needed` check compares mtimes of `*.ts(x)`
  and meta files against `dist/entry.js`; if the staged tree's sources
  are older than the runtime, it triggers a local `npm run build` (and
  prints a hint that the user should run `bin/hatch install` to refresh).
