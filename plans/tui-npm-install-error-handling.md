# TUI `npm install failed.` — Lazy Error Handling Investigation

**Trigger**: On a fresh test-bench Mac, after `install.sh` completes, running
`monoclaw --tui` prints:

```
Installing TUI dependencies…
npm install failed.
```

…and exits 1. The user has zero actionable context — no exit code, no
preview of npm's error output, no log file path, no command to reproduce,
no remediation hint. This is a Phase 1+2+3 architectural follow-up:
staging now works (Phase 1), the doctor surfaces missing staging
(Phase 2), and Phase 3 hardened a sibling subsystem (WhatsApp bridge
warmup) — but `_make_tui_argv` still hides the real failure when the
on-demand `npm install` against `~/.monoclaw/vendor/tui/` exits non-zero.

This plan documents every lazy implementation responsible for the empty
error, names the architectural gap that puts the install on the
customer's critical path in the first place, and lays out a fix.

---

## 1. Symptom Reproduced

The customer-visible output is two lines and nothing else:

```
Installing TUI dependencies…
npm install failed.
```

That's the entire diagnostic surface. There is nothing more — no
preview, no exit code, no log path. The customer has to either:

1. Manually `cd ~/.monoclaw/vendor/runtime/venv/lib/python3.13/
   site-packages/...` to find the npm command, OR
2. Read MonoClaw's source to discover that npm was invoked with
   `--silent`, OR
3. Hand-rerun `cd ~/.monoclaw/vendor/tui && npm install` and hope the
   second run surfaces what the first hid.

None of those are reasonable expectations for a customer install.

---

## 2. Root Cause Analysis

### 2.1 Five lazy implementations in `_make_tui_argv`

`monoclaw-runtime/monoclaw_cli/main.py:1126-1172` (extract):

```python
result = subprocess.run(
    [npm, "install", "--silent", "--no-fund", "--no-audit", "--progress=false"],
    cwd=str(tui_dir),
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env={**os.environ, "CI": "1"},
)
if result.returncode != 0:
    combined = f"{result.stdout or ''}\n{result.stderr or ''}".strip()
    preview = "\n".join(combined.splitlines()[-30:])
    print("npm install failed.")
    if preview:
        print(preview)
    sys.exit(1)
```

Five distinct lazinesses stacked into 14 lines:

| # | Lazy implementation | Customer-visible consequence |
|---|---------------------|-------------------------------|
| L1 | `--silent` flag on npm | npm suppresses error messages, warnings, deprecation notices, peer-dep conflicts. Silent mode is documented as "logs nothing except errors" but in practice on npm v9-10 it eats most errors too — see npm/cli#5099. |
| L2 | `if preview:` gate | When stdout+stderr are both empty (which `--silent` virtually guarantees on success or failure), `splitlines()[-30:]` is `[]`, `"\n".join([])` is `""`, the print is skipped. Customer sees no preview at all. |
| L3 | Exit code dropped | `result.returncode` is right there. Printing it would tell the customer "exit 243 = network unreachable" vs "exit 1 = peer-dep conflict" vs "exit 134 = OOM during install". The current message gives them nothing to google. |
| L4 | Working directory dropped | The customer has no idea WHICH `tui_dir` was being installed into. With `_resolve_tui_dir`'s three-level fallback they can't even guess: was it `~/.monoclaw/vendor/tui/`? The PROJECT_ROOT fallback? An env-override path? Reproducing the failure manually requires opening a file and reading code. |
| L5 | npm log file path dropped | npm **always** writes a full debug log to `~/.npm/_logs/<timestamp>-debug-0.log` (739 lines in my reproduction, including full HTTP traces, lockfile resolution, native-binary download attempts). The customer has no idea this file exists, and we have no code to surface its path. |

### 2.2 Verification: `--silent` is the prime offender

Reproduced on a dev Mac against the freshly-staged
`hatch/dist/vendor/tui/`:

```
$ npm install --silent --no-fund --no-audit --progress=false
$ echo $?
0
$ # exact same install, only --silent → --loglevel=error
$ npm install --no-fund --no-audit --progress=false --loglevel=error
added 437 packages in 2s
$ echo $?
0
```

`--silent` produced zero output on success. `--loglevel=error` produced
exactly one informational line. On failure the difference is even
starker — `--loglevel=error` surfaces the actual diagnostic; `--silent`
gives you nothing.

The misleading comment in our source at `main.py:1154-1157` actually
acknowledges this:

> Capture stdout as well as stderr — some npm errors (notably EACCES on a
> root-owned node_modules in containers) are emitted on stdout, and a
> bare "npm install failed." with no preview defeats debugging. We keep
> the failure-only print path so a successful install stays silent.

…but then immediately passes `--silent` to npm, which makes the stdout
capture moot. The author was aware of the "bare error defeats debugging"
problem and **still kept the flag that causes it**.

### 2.3 The fault repeats in two more places

The same 5-line "capture, tail 30 lines, print bare label" pattern
appears two more times in `_make_tui_argv`:

- Lines 1175-1188: `npm run build --prefix packages/monoclaw-ink`
  (dev-mode rebuild of the Ink bundle). Uses `capture_output=True`
  instead of `--silent`, so the underlying issue is "tail 30 lines,
  print bare label, no exit code, no cwd, no log path".
- Lines 1194-1207: `npm run build` (full TUI build). Same shape.

The bridge-install path in `cmd_whatsapp` (`main.py:1706-1721`) is
slightly better — it uses `stdout=subprocess.DEVNULL,
stderr=subprocess.PIPE` instead of `--silent`, so the bridge install at
least surfaces stderr when it fails. But it still drops the exit code,
log path, and cwd.

### 2.4 Architectural gap: TUI install runs on the customer's critical path

Phase 1 added `warm_whatsapp_bridge_install` in `bin/hatch` so the
WhatsApp bridge's `npm install` runs once at install time (when the
technician expects a slow setup step) instead of at first-`monoclaw
whatsapp`-run (when the customer is mid-flow). The **TUI install was
not given the same treatment** — the comment in
`stage_runtime_tui` says explicitly:

```sh
log "Staging vendor/tui (sources + prebuilt dist; no node_modules)"
```

…and `_make_tui_argv` is left to do the cold `npm install` lazily.

This was a deliberate trade-off (D2 in
`plans/tui-whatsapp-himalaya-staging-investigation.md`: ship sources
only for v1, revisit if a real air-gapped customer materialises). It
makes first-launch slow but keeps the bundle small. The downside is
that **every failure surfaces at the worst possible time** — to the
end-user, on a path where a clear error message becomes critical
because the technician isn't there anymore. The lazy error handling
(L1-L5 above) turns that downside into a brick wall.

### 2.5 What real failures the test bench is probably hiding

Without surfacing the actual npm output we can't be certain, but every
mode below is consistent with the symptom and would all collapse to the
same `npm install failed.` line under `--silent`:

| Failure mode | Why it would show as "npm install failed." with no detail |
|--------------|----------------------------------------------------------|
| Test bench is offline / on captive Wi-Fi | npm can't reach `registry.npmjs.org`. Silent. |
| Corporate proxy + TLS interception | npm errors with `UNABLE_TO_VERIFY_LEAF_SIGNATURE`. Silent. |
| Stale `~/.npmrc` from a previous user/install | `EAUTHIP`/`401` from the registry. Silent. |
| Disk full / quota | esbuild's transitive deps unpack into ~150 MB of files. ENOSPC. Silent. |
| Native-binary platform mismatch | esbuild's `@esbuild/<plat>-<arch>` optionalDependency download fails on an unusual macOS configuration. Silent. |
| `~/.npm/_cacache` permission damage | Mixed-user `npm install` history → EACCES. Silent. |
| Bundled `package-lock.json` written by a newer npm | Older `npm` on the bench gives a `lockfileVersion` mismatch warning that escalates to an error. Silent. |

The point isn't that we know which one fired — it's that **we have no
way to tell**, and the customer is stranded.

### 2.6 Why this wasn't caught by existing tests

`tests/monoclaw_cli/test_tui_npm_install.py` covers `_tui_need_npm_install`
(the staleness probe), `tests/monoclaw_cli/test_tui_dir_resolution.py`
covers `_resolve_tui_dir`, but nothing exercises the failure-printing
path in `_make_tui_argv` — that branch has zero coverage. The author
made each individual decision plausibly (silent is the npm convention,
tail 30 lines is "enough", check `if preview:` to not print nothing)
without ever assembling them into a customer-visible reproduction.

---

## 3. Fix Plan

### Phase 1 — Stop hiding the error (P0, ship immediately) — **LANDED 2026-05-19**

All Phase 1 items shipped. The customer-visible failure went from
the two-line `Installing TUI dependencies… / npm install failed.`
to a structured diagnostic that includes exit code, the exact
quoted command, the cwd, up to 50 trailing lines of npm output, the
newest `~/.npm/_logs/<ts>-debug-0.log` path, and two remediation
hints (manual retry + `MONOCLAW_TUI_NPM_VERBOSE=1` escalation).
Sample failure output verified against a synthetic ENOTFOUND error:

```text
✗ Installing TUI dependencies failed (exit 1).
  command: /opt/homebrew/bin/npm install --loglevel=error --no-fund --no-audit --progress=false
  cwd:     /Users/test/.monoclaw/vendor/tui
  --- npm output ---
  npm error code ENOTFOUND
  npm error errno ENOTFOUND
  npm error network request to https://registry.npmjs.org/ink failed, ...
  full log: /Users/admin/.npm/_logs/2026-05-19T08_43_59_780Z-debug-0.log
  retry manually with verbose output:
    cd /Users/test/.monoclaw/vendor/tui && npm install --loglevel=verbose
  or rerun with MONOCLAW_TUI_NPM_VERBOSE=1 to get verbose output inline.
```

Shipping changes:

- `monoclaw_cli/main.py` — five new helpers
  (`_newest_npm_log`, `_print_npm_failure`, `_npm_install_args`,
  `_npm_install_capture_kwargs`, `_preflight_tui_install`) plus
  rewired install/build sites. `--silent` replaced with
  `--loglevel=error` (and `--loglevel=verbose` under
  `MONOCLAW_TUI_NPM_VERBOSE=1`). All three npm-failure branches in
  `_make_tui_argv` now use the shared diagnostic.
- `tests/monoclaw_cli/test_tui_npm_install_diag.py` (new, **18
  cases**) locks the contract: exit code present, cwd present,
  command quoted-and-pasteable, npm output surfaced (no 30-line
  truncation), npm log path surfaced when available, no crash when
  log dir absent, 50-line tail with explicit truncation header,
  stderr-only (so JSON callers stay clean), `_npm_install_args`
  defaults to `error` and escalates to `verbose`,
  `_npm_install_capture_kwargs` defaults to capture and switches to
  streaming under verbose, `_preflight_tui_install` catches
  read-only `vendor/tui/` and suggests both `bin/hatch install`
  and `chown`.

#### 3.1 Replace `--silent` with `--loglevel=error`

File: `monoclaw-runtime/monoclaw_cli/main.py:1159`

```diff
 result = subprocess.run(
-    [npm, "install", "--silent", "--no-fund", "--no-audit", "--progress=false"],
+    # --loglevel=error keeps the success path quiet (one summary line) while
+    # preserving the npm error / warning channels that --silent eats. The May
+    # 2026 test-bench report ("npm install failed." with no context) traced
+    # to --silent suppressing the npm output we then tried to capture.
+    [npm, "install", "--loglevel=error", "--no-fund", "--no-audit", "--progress=false"],
     cwd=str(tui_dir),
     stdout=subprocess.PIPE,
     stderr=subprocess.PIPE,
     text=True,
     env={**os.environ, "CI": "1"},
 )
```

`--loglevel=error` is npm's lowest non-silent loglevel: it prints errors
(and only errors), so the success path stays as quiet as before but the
failure path actually has output to display.

#### 3.2 Build a useful failure message — exit code, cwd, log path, command

File: `monoclaw-runtime/monoclaw_cli/main.py`

Extract the print-and-exit dance into a helper so all three npm
invocations in `_make_tui_argv` reuse the same diagnostic shape:

```python
def _print_npm_failure(
    label: str,
    cmd: list[str],
    cwd: Path,
    result: subprocess.CompletedProcess,
) -> None:
    """Print a useful diagnostic when an npm subprocess exits non-zero.

    Includes everything the customer needs to (a) understand what
    failed, (b) reproduce it manually, (c) find npm's full debug log,
    and (d) escalate verbosity for self-debugging.
    """
    print(f"✗ {label} (exit {result.returncode}).", file=sys.stderr)
    print(f"  command: {shlex.join(cmd)}", file=sys.stderr)
    print(f"  cwd:     {cwd}", file=sys.stderr)

    combined = f"{result.stdout or ''}\n{result.stderr or ''}".strip()
    if combined:
        # Tail to 50 lines (was 30) so long peer-dep traces survive.
        lines = combined.splitlines()
        if len(lines) > 50:
            print(f"  --- last 50 of {len(lines)} output lines ---", file=sys.stderr)
            lines = lines[-50:]
        else:
            print("  --- npm output ---", file=sys.stderr)
        for line in lines:
            print(f"  {line}", file=sys.stderr)

    log_path = _newest_npm_log()
    if log_path is not None:
        print(f"  full log: {log_path}", file=sys.stderr)

    print(
        "  retry manually with verbose output:\n"
        f"    cd {cwd} && npm install --loglevel=verbose",
        file=sys.stderr,
    )
    print(
        "  or rerun with MONOCLAW_TUI_NPM_VERBOSE=1 to get verbose output inline.",
        file=sys.stderr,
    )


def _newest_npm_log() -> Path | None:
    """Return the most recent npm debug log under ~/.npm/_logs/, or None.

    npm always writes a full debug log to ``~/.npm/_logs/<ts>-debug-0.log``
    for every install (success or failure), even under --silent. Surfacing
    the path is the cheapest way to give a customer a useful error
    transcript without having to re-run anything.
    """
    log_dir = Path.home() / ".npm" / "_logs"
    if not log_dir.is_dir():
        return None
    try:
        logs = sorted(
            log_dir.glob("*-debug-0.log"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return None
    return logs[0] if logs else None
```

And the call site becomes:

```python
if result.returncode != 0:
    _print_npm_failure("Installing TUI dependencies failed", cmd, tui_dir, result)
    sys.exit(1)
```

(Lines 1182-1188 and 1201-1207 get the same treatment for the
`npm run build --prefix packages/monoclaw-ink` and `npm run build`
sites.)

#### 3.3 Add a `MONOCLAW_TUI_NPM_VERBOSE` escalation knob

File: `monoclaw-runtime/monoclaw_cli/main.py`

When the env var is set, swap `--loglevel=error` for `--loglevel=verbose`
AND stream the output live (no capture) so the customer can watch the
install for the failure point in real time.

```python
def _npm_install_args() -> list[str]:
    if os.environ.get("MONOCLAW_TUI_NPM_VERBOSE"):
        return [
            "install", "--loglevel=verbose", "--no-fund", "--no-audit",
            "--progress=false",
        ]
    return [
        "install", "--loglevel=error", "--no-fund", "--no-audit",
        "--progress=false",
    ]


def _npm_install_capture(verbose: bool) -> dict:
    """Return subprocess.run kwargs for the npm install call.

    Verbose mode streams to the terminal (no capture) so customers
    debugging an install can watch the failure point in real time.
    """
    if verbose:
        return {"stdout": None, "stderr": None}
    return {"stdout": subprocess.PIPE, "stderr": subprocess.PIPE, "text": True}
```

Then the call site:

```python
verbose = bool(os.environ.get("MONOCLAW_TUI_NPM_VERBOSE"))
cmd = [npm] + _npm_install_args()
result = subprocess.run(
    cmd,
    cwd=str(tui_dir),
    env={**os.environ, "CI": "1"},
    **_npm_install_capture(verbose),
)
```

When verbose, `result.stdout` / `result.stderr` are `None` because the
output already streamed to the terminal — `_print_npm_failure` handles
both shapes.

#### 3.4 Pre-flight: writability and connectivity

Before invoking npm, check the obvious foot-guns and emit a clearer
message than what npm's own error would say:

```python
def _preflight_tui_install(tui_dir: Path) -> str | None:
    """Return an error string when the npm install will obviously fail,
    or None when it's worth trying. Never raises."""
    if not os.access(tui_dir, os.W_OK):
        return (
            f"TUI sources at {tui_dir} are not writable. Check ownership "
            "(maybe a previous root install left them owned by root?) "
            "and re-run `bin/hatch install`."
        )
    # We could also add a `~/.npm/_cacache` writability check and a
    # DNS probe for registry.npmjs.org here. Both are cheap; both
    # cover real test-bench failure modes. Keep them for Phase 2.
    return None
```

Call before `subprocess.run`:

```python
if _tui_need_npm_install(tui_dir):
    err = _preflight_tui_install(tui_dir)
    if err:
        print(f"✗ {err}", file=sys.stderr)
        sys.exit(1)
    if not os.environ.get("MONOCLAW_QUIET"):
        print("Installing TUI dependencies…")
    ...
```

#### 3.5 Test coverage — lock the diagnostic contract

File: `monoclaw-runtime/tests/monoclaw_cli/test_tui_npm_install_diag.py`
(new)

```python
"""npm install failure diagnostics: every helpful field must survive."""

from __future__ import annotations

import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest


def test_print_npm_failure_includes_exit_code_cwd_command(
    capsys, main_mod, tmp_path
):
    """May 2026 test-bench report: `npm install failed.` with no context.
    Every diagnostic dimension below must be in the printed output."""
    fake_result = SimpleNamespace(
        returncode=243,
        stdout="some stdout\n",
        stderr="EACCES: permission denied\n",
    )
    main_mod._print_npm_failure(
        "Installing TUI dependencies failed",
        ["/usr/local/bin/npm", "install", "--loglevel=error"],
        tmp_path / "vendor" / "tui",
        fake_result,
    )
    err = capsys.readouterr().err
    assert "exit 243" in err
    assert "cwd:" in err
    assert "vendor/tui" in err
    assert "npm install --loglevel=error" in err
    assert "EACCES" in err  # surface the actual error line
    assert "retry manually" in err  # remediation hint
    assert "MONOCLAW_TUI_NPM_VERBOSE" in err  # escalation hint


def test_print_npm_failure_surfaces_log_path_when_present(
    capsys, main_mod, tmp_path, monkeypatch
):
    """npm always writes ~/.npm/_logs/<ts>-debug-0.log even under --silent.
    The failure message must point at the most recent one."""
    log_dir = tmp_path / ".npm" / "_logs"
    log_dir.mkdir(parents=True)
    # Two log files; the helper must surface the newest by mtime.
    old = log_dir / "2026-05-01T00_00_00_000Z-debug-0.log"
    new = log_dir / "2026-05-19T08_30_00_000Z-debug-0.log"
    old.write_text("old log")
    new.write_text("new log")
    import os
    os.utime(old, (1, 1))
    os.utime(new, (1000, 1000))
    monkeypatch.setattr(Path, "home", lambda: tmp_path)

    main_mod._print_npm_failure(
        "Installing TUI dependencies failed",
        ["npm", "install"],
        tmp_path / "vendor" / "tui",
        SimpleNamespace(returncode=1, stdout="", stderr=""),
    )
    err = capsys.readouterr().err
    assert "full log:" in err
    assert str(new) in err


def test_print_npm_failure_survives_no_npm_log_dir(
    capsys, main_mod, tmp_path, monkeypatch
):
    """First-ever install on a Mac has no ~/.npm/_logs/ yet — the helper
    must omit the log line, not crash."""
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    main_mod._print_npm_failure(
        "Installing TUI dependencies failed",
        ["npm", "install"],
        tmp_path / "vendor" / "tui",
        SimpleNamespace(returncode=1, stdout="", stderr=""),
    )
    err = capsys.readouterr().err
    assert "full log:" not in err
    # Still has the essentials.
    assert "exit 1" in err
    assert "retry manually" in err


def test_print_npm_failure_tail_caps_at_50_lines(capsys, main_mod, tmp_path):
    """Don't dump 700 lines of peer-dep noise; tail to 50 with a header."""
    long_output = "\n".join(f"line {i}" for i in range(200))
    main_mod._print_npm_failure(
        "Installing TUI dependencies failed",
        ["npm", "install"],
        tmp_path,
        SimpleNamespace(returncode=1, stdout=long_output, stderr=""),
    )
    err = capsys.readouterr().err
    assert "last 50 of 200" in err
    assert "line 199" in err  # last line present
    assert "line 0" not in err  # head dropped


def test_preflight_rejects_unwritable_tui_dir(main_mod, tmp_path):
    """Read-only tui_dir is the canonical 'previous root install' foot-gun;
    catch it before npm produces an EACCES we'd otherwise mangle."""
    tui = tmp_path / "vendor" / "tui"
    tui.mkdir(parents=True)
    tui.chmod(0o555)  # no write for owner
    try:
        msg = main_mod._preflight_tui_install(tui)
        assert msg is not None
        assert "not writable" in msg
        assert "bin/hatch install" in msg
    finally:
        tui.chmod(0o755)  # restore so tmp_path cleanup works


def test_preflight_returns_none_for_normal_dir(main_mod, tmp_path):
    tui = tmp_path / "vendor" / "tui"
    tui.mkdir(parents=True)
    assert main_mod._preflight_tui_install(tui) is None


@pytest.fixture
def main_mod():
    import monoclaw_cli.main as m
    return m
```

#### 3.6 Apply the same treatment to the dev-mode ink rebuild and full-TUI rebuild

Same `_print_npm_failure` helper, two more call sites. Lines 1175-1188
and 1194-1207 in current `main.py`. Three independent error branches
must not silently regress to the bare-label shape.

---

### Phase 2 — Warm the TUI install at Hatch install time (P1) — **LANDED 2026-05-19**

Both items shipped, plus an opportunistic bonus refactor and two
pre-existing-test-fixture fixes that fell out of running the full hatch
suite:

- **3.7 `warm_tui_install` in `bin/hatch`** — added, with three knobs
  for the operator: default non-fatal warning on failure,
  `HATCH_REQUIRE_TUI_INSTALL=1` for lab provisioning (escalates to
  `die`), and `HATCH_SKIP_TUI_WARMUP=1` for tight provisioning windows
  (full opt-out before any check, including before the staging-presence
  check, so a customer who opts out doesn't get the "not staged"
  warning either). Wired into `run_install` immediately after
  `warm_whatsapp_bridge_install`.

- **3.8 `hatch_warm_tui_install_tests.sh`** — 8 cases covering:
  `HATCH_SKIP_TUI_WARMUP=1` short-circuit, TUI-not-staged soft-skip,
  idempotent re-run, npm-missing default-mode warning,
  `HATCH_REQUIRE_TUI_INSTALL=1` strict-mode `die`, dry-run plan output
  (with cwd preview), npm-failure stderr surfacing + log-path hint,
  plus a regression case for `warm_whatsapp_bridge_install` confirming
  it now surfaces npm stderr too (was `>/dev/null 2>&1` swallow before).

- **Bonus: `_run_warm_npm_install` shared helper** — both warm
  functions now go through one diagnostic-rich runner. Phase 1's runtime
  fix gave the runtime side the
  `--silent` → `--loglevel=error` + exit code + log path + retry hint
  treatment; this brings the install-time path to the same standard.
  The old `>/dev/null 2>&1` swallow in `warm_whatsapp_bridge_install`
  is gone. Pasted format on a synthetic ENOTFOUND, exit code 1:

  ```text
    --- npm stderr (exit 1) ---
    npm error code ENOTFOUND
    npm error errno ENOTFOUND
    npm error network request to https://registry.npmjs.org/ink failed
    full log: /Users/test/.npm/_logs/2026-05-19T08_43_59_780Z-debug-0.log
    retry manually with verbose output:
      cd /Users/test/.monoclaw/vendor/tui && npm install --loglevel=verbose
    warn: TUI npm install failed; TUI will retry on first use
  ```

- **Test fixture fix: `hatch_build_tests.sh` +
  `hatch_bundle_atomicity_tests.sh`** — both create synthetic
  `RUNTIME` checkouts with only `pyproject.toml` + `skills/`. After
  Phase 1's `verify_node_subsystems.py` gate landed, those tests
  silently started failing because the synthetic checkouts have no
  `ui-tui/` or `scripts/whatsapp-bridge/` for staging, so the gate
  rejected the produced bundle. Both tests now stage minimal fixture
  trees via a small `_stage_runtime_node_subsystems_fixture` helper
  (six small files: `package.json`, `dist/entry.js`, ink
  `entry-exports.js`, bridge `bridge.js` + `package.json` +
  `package-lock.json`). This was a Phase 1 verification gap, surfaced
  while running the suite in Phase 2.

Verification:

- New `hatch_warm_tui_install_tests.sh`: **8/8 passing**.
- Existing `hatch_node_subsystems_tests.sh`: **8/8 still passing**.
- Full hatch suite (19 test files): **18/19 passing**. Only remaining
  failure is `hatch_dry_run_tests.sh` — pre-existing, unrelated, caused
  by an older commit (`8cdcf7b`) removing the "run monoclaw provision"
  string from the install dry-run output without updating the test
  assertion. Tracked in the staging plan's verification notes.
- `./build.sh` against the real monoclaw-runtime: **passes**,
  Published bundle at `dist/`.
- `bin/hatch --dry-run --bundle-root dist install`: warm steps fire in
  the right order, both correctly skip in dry-run mode because the
  staging step's dry-run doesn't actually copy files.
- Runtime regression: **76/76 TUI + WhatsApp + doctor tests passing**.

#### 3.7 `warm_tui_install` in `bin/hatch`

Mirror `warm_whatsapp_bridge_install` (added in the prior PR). Run
`npm install --loglevel=error` against
`~/.monoclaw/vendor/tui/` after `install_runtime_assets`.

```sh
warm_tui_install() {
  local home_dir
  home_dir="$(monoclaw_home)"
  local tui_dir="${home_dir}/vendor/tui"

  if [[ ! -f "${tui_dir}/package.json" ]]; then
    log_warn "TUI sources not staged at ${tui_dir}; skipping npm install warmup"
    return 0
  fi

  if [[ -d "${tui_dir}/node_modules" ]]; then
    log_ok "TUI node_modules already present"
    return 0
  fi

  if ! have_command npm; then
    if [[ "${HATCH_REQUIRE_TUI_INSTALL:-0}" == "1" ]]; then
      die "TUI npm install required but npm is not on PATH"
    fi
    log_warn "npm not on PATH; skipping TUI install (run \`monoclaw --tui\` later to install)"
    return 0
  fi

  if [[ "${HATCH_DRY_RUN}" == "true" ]]; then
    printf '  dry-run: npm install --loglevel=error in %s\n' "${tui_dir}"
    return 0
  fi

  log_step "install" "Warming TUI dependencies (one-time, ~30-90s on cold cache)"
  if (cd "${tui_dir}" && npm install --loglevel=error --no-fund --no-audit --progress=false); then
    log_ok "TUI dependencies installed at ${tui_dir}/node_modules"
  else
    if [[ "${HATCH_REQUIRE_TUI_INSTALL:-0}" == "1" ]]; then
      die "TUI npm install failed (HATCH_REQUIRE_TUI_INSTALL=1)"
    fi
    log_warn "TUI npm install failed; \`monoclaw --tui\` will retry on first run"
  fi
}
```

Call it from `run_install` right after `warm_whatsapp_bridge_install`:

```diff
   warm_whatsapp_bridge_install
+  # Same logic as the bridge: warm the TUI's node_modules so the
+  # customer's first ``monoclaw --tui`` invocation isn't a 30-90s blackout
+  # plus a likely error surface. Non-fatal by default; strict-mode flag
+  # ``HATCH_REQUIRE_TUI_INSTALL=1`` for lab provisioning.
+  warm_tui_install
   print_manual_local_inference_handoff
```

Trade-off: install.sh gets ~30-90s longer (cold-cache npm install of
~430 transitive packages over network). That's acceptable: it happens
once per Mac at a time when the technician is watching, and any
failure can be diagnosed and re-run without the customer ever seeing
it.

#### 3.8 Tests for `warm_tui_install`

Mirror the existing `hatch_node_subsystems_tests.sh` patterns:

- Case A: tui not staged → soft-skip with warning.
- Case B: `node_modules` already present → idempotent no-op.
- Case C: npm missing + default mode → warn but return 0.
- Case D: npm missing + `HATCH_REQUIRE_TUI_INSTALL=1` → die.
- Case E: dry-run prints the planned command without executing it.

---

### Phase 3 — Defence in depth (P2) — **LANDED 2026-05-19**

Both items shipped:

- **3.9 Doctor: `node_modules` populated probe** — extends
  `_check_node_subsystem_staging` (Phase 2 of the staging plan) with a
  new `_node_modules_populated` helper that uses npm's hidden lockfile
  (`node_modules/.package-lock.json`) as the canonical "install
  completed" signal, with a defensive directory-non-empty fallback for
  forward compatibility. Per-subsystem policy:
  - **TUI ready** (sources staged + node_modules populated) — `check_ok`.
  - **TUI half-warmed** (sources, no node_modules) — `check_info`
    pointing at `cd <tui> && npm install`. Not `check_warn` because the
    runtime's `_make_tui_argv` has a lazy-install fallback (now with
    Phase 1 diagnostics), so a half-warmed state is recoverable and
    nagging about it on every doctor run is noise.
  - **WhatsApp bridge ready** — `check_ok`.
  - **WhatsApp bridge half-warmed + enabled** — `check_warn` + queued
    manual issue. WhatsApp's gateway adapter has no pre-launch lazy
    install, so a half-warmed bridge at gateway start is a runtime
    failure.
  - **WhatsApp bridge half-warmed + disabled** — `check_info` only.
    Don't nag operators about an unused feature.

  Tests: `TestNodeModulesPopulated` (5 cases) + `TestCheckHalfWarmedInstall`
  (3 cases) added to `test_doctor_node_subsystems.py`, plus existing
  `TestCheckNodeSubsystemStaging` cases updated to the new "ready"
  wording (defaulted to warmed via a `warm=True` kwarg on the staging
  helpers). 20/20 doctor tests passing.

- **3.10 `runtime-artifacts.md`** — extended the `vendor/tui/` section
  with the two-path install model (`warm_tui_install` at install time;
  runtime fallback on first launch), all three operator knobs
  (`HATCH_REQUIRE_TUI_INSTALL`, `HATCH_SKIP_TUI_WARMUP`, plus the
  Phase 1 `MONOCLAW_TUI_NPM_VERBOSE`), and a new paragraph documenting
  doctor's three-state model (ready / half-warmed / not staged). The
  shared `_run_warm_npm_install` helper is also described so future
  maintainers know both warm functions go through one diagnostic
  pipeline. Updated the Installed Runtime Layout tree to show
  `vendor/tui/node_modules/` is populated by `warm_tui_install` (or
  lazily by `monoclaw --tui` if skipped).

Live verification against `/tmp/doctor-demo/`:

```text
=== HALF-WARMED ===
    → TUI sources staged but node_modules not yet populated at .../vendor/tui;
      will install on first `monoclaw --tui` launch. Run
      `cd .../vendor/tui && npm install` to warm it now.
    → WhatsApp bridge staged at .../vendor/whatsapp-bridge
      (node_modules not populated; will install when `monoclaw whatsapp`
      is first run)

=== FULLY WARMED ===
  ✓ TUI ready (.../vendor/tui)
  ✓ WhatsApp bridge ready (.../vendor/whatsapp-bridge)
```

Final verification: **84/84 runtime tests** (TUI + doctor + bridge),
**8/8 hatch warm-TUI tests**, **8/8 hatch node-subsystems tests**.

#### 3.9 Doctor probe: `node_modules` populated under `~/.monoclaw/vendor/tui/`

Today `_check_node_subsystem_staging` only verifies that
`package.json` is present. After Phase 2 we should also surface "TUI
sources staged but `node_modules` missing" as a warning, so doctor
catches a half-warmed install (e.g. install.sh failed mid-flight).

#### 3.10 Cross-reference the TUI warm path in `runtime-artifacts.md`

Add a section mirroring the WhatsApp bridge prose: `vendor/tui/
node_modules` is populated at install time by `warm_tui_install` and
created lazily by `monoclaw --tui` for git-editable installs.

---

## 4. Verification Plan

1. **L1-L5 diagnostic contract** — `tests/monoclaw_cli/test_tui_npm_install_diag.py` (six new cases) all pass.
2. **Manual reproduction**: on a clean Mac with the new Hatch bundle,
   run `install.sh`; observe install.sh emit
   `Warming TUI dependencies (one-time, ~30-90s on cold cache)` and a
   success or failure line. If failure, the failure is logged at
   install time, the technician sees the full npm error, and the customer
   later runs `monoclaw --tui` against a hot cache.
3. **Manual reproduction of the symptom path**: deliberately break the
   warmed install (e.g. `rm -rf ~/.monoclaw/vendor/tui/node_modules`,
   then `npm config set registry http://does-not-exist`) and run
   `monoclaw --tui`. Expected output:
   ```
   Installing TUI dependencies…
   ✗ Installing TUI dependencies failed (exit 1).
     command: /usr/local/bin/npm install --loglevel=error --no-fund --no-audit --progress=false
     cwd:     /Users/test/.monoclaw/vendor/tui
     --- npm output ---
     npm error code ENOTFOUND
     npm error errno ENOTFOUND
     npm error network request to http://does-not-exist/... failed, ...
     full log: /Users/test/.npm/_logs/2026-05-19T08_43_01_605Z-debug-0.log
     retry manually with verbose output:
       cd /Users/test/.monoclaw/vendor/tui && npm install --loglevel=verbose
     or rerun with MONOCLAW_TUI_NPM_VERBOSE=1 to get verbose output inline.
   ```
4. **Verbose mode**: `MONOCLAW_TUI_NPM_VERBOSE=1 monoclaw --tui`
   streams npm output live; on failure the exit-summary helper still
   prints (with `stdout=None / stderr=None` shape).
5. **Doctor**: `monoclaw doctor` reports
   `TUI sources staged + node_modules populated` on a healthy install,
   and `TUI sources staged but node_modules missing` after `rm -rf
   ~/.monoclaw/vendor/tui/node_modules`.
6. `bash hatch/tests/run_tests.sh` — passes including the new
   `hatch_warm_tui_install_tests.sh`.
7. `bash monoclaw-runtime/scripts/run_tests.sh tests/monoclaw_cli/` —
   passes including the new diagnostic tests.

---

## 5. Sequencing & Ownership

| Phase | Work item                                                         | Repo                | P  |
|-------|-------------------------------------------------------------------|---------------------|----|
| 1     | Drop `--silent`, switch to `--loglevel=error`                     | monoclaw-runtime    | P0 |
| 1     | `_print_npm_failure` helper (exit code, cwd, command, log path)   | monoclaw-runtime    | P0 |
| 1     | `MONOCLAW_TUI_NPM_VERBOSE` escalation knob                        | monoclaw-runtime    | P0 |
| 1     | `_preflight_tui_install` (writability check)                      | monoclaw-runtime    | P0 |
| 1     | Apply helper to ink-rebuild and full-TUI-rebuild branches         | monoclaw-runtime    | P0 |
| 1     | `test_tui_npm_install_diag.py` (6 cases) — lock the contract      | monoclaw-runtime    | P0 |
| 2     | `warm_tui_install` in `bin/hatch`                                 | monoclaw-developer  | P1 |
| 2     | `hatch_warm_tui_install_tests.sh` (5 cases)                       | monoclaw-developer  | P1 |
| 3     | Doctor: `node_modules` populated probe under `vendor/tui`         | monoclaw-runtime    | P2 |
| 3     | `runtime-artifacts.md`: document `warm_tui_install`               | monoclaw-developer  | P2 |

Phase 1 lands as a single PR. The minimum viable customer fix is L1+L3+L5
(drop `--silent`, print exit code, print log path) — even without the
rest, the customer goes from "npm install failed." to an actionable
message in ~30 lines of code. Everything else is bonus.

Phase 2 is a coordinated PR pair across both repos (the runtime change
to handle hot `node_modules` correctly + the Hatch change to populate
it). Should ship within a release of Phase 1 because it's the
architectural fix — Phase 1 just makes the bleeding visible.

---

## 6. Decisions Recorded

- **D1 — `--silent` is gone, replaced with `--loglevel=error`**. Yes,
  the success path is now one extra line (`added N packages in Ms`).
  Worth it.
- **D2 — Tail at 50 lines, not 30**. npm peer-dep traces and native
  binary download errors routinely run 40+ lines. The current 30-line
  tail cuts off the actionable part of the output.
- **D3 — Surface `~/.npm/_logs/<ts>-debug-0.log` path**. npm always
  writes one; it's the gold mine. Pointing at it is free and saves the
  customer from re-running with `--loglevel=verbose` just to see what
  happened.
- **D4 — `MONOCLAW_TUI_NPM_VERBOSE=1` streams live**. Capture mode is
  fine for the default failure message, but a customer self-debugging
  wants to see what npm is doing in real time. Streaming + skipped
  capture is the standard escape hatch.
- **D5 — `_preflight_tui_install` is a small check, not a full health
  probe**. Just writability for now (catches the most common test-bench
  failure: previously-root-owned `node_modules`). DNS probe / npmrc
  audit / disk-space check are deferred to Phase 3 if they prove
  necessary.
- **D6 — Warm at install time, with same strict-mode escalation as the
  bridge**. `HATCH_REQUIRE_TUI_INSTALL=1` for lab provisioning;
  otherwise non-fatal warning. Customer-visible runtime fallback stays
  in place either way.

---

## 7. Open Questions / Risks

- **R1 — Loglevel=error and CI=1 interaction**. npm in CI mode +
  loglevel=error still suppresses most warnings, which is exactly
  what we want. Verified locally; needs to be re-verified after the
  helper lands in case a future npm release shifts the boundary.

- **R2 — `_preflight_tui_install` writability check uses `os.access`**,
  which is not strictly accurate on macOS with ACLs (returns True
  even when an ACL denies write). Acceptable: a stricter probe would
  need to `mkdir` a temp file. False positives are rare; false
  negatives just defer the diagnosis by one extra line of npm output.

- **R3 — Warming adds 30-90s to `install.sh`**. Real cost for a real
  benefit. If customers complain, gate the warmup behind a flag (e.g.
  `HATCH_SKIP_TUI_WARMUP=1`) instead of removing it.

- **R4 — Air-gapped customer Macs cannot warm the install**. The
  warmup would always fail. Two options: (a) ship `node_modules`
  pre-built in the bundle (adds ~150 MB); (b) ship an npm offline cache
  / `npm pack` tarballs and configure `--offline`. Both are Phase 4
  candidates if a real air-gapped customer materialises (D1 in the
  staging plan already calls this out as deferred).
