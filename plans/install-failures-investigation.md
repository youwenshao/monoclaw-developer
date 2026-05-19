# Install / Provision / Doctor Failure Investigation

**Trigger**: A fresh Hatch install on a clean Mac (`/Users/test/...`) crashed
with two distinct Python errors during `monoclaw provision`, and `monoclaw
doctor --fix` reported a half-dozen unfixable warnings. This plan is the
post-mortem and the implementation roadmap to make a fresh Hatch install
green-on-green without manual intervention.

This is **not** a curl-bash `monoclaw-runtime/scripts/install.sh` issue — the
user is on the **Hatch / pendrive** path. Symptom paths reference
`~/.monoclaw/vendor/runtime/venv/...` which is the Hatch layout. Both
installer paths have similar gaps but the diagnosis below focuses on the
Hatch path as that is the one that failed end-to-end.

---

## 1. Symptom Inventory (verbatim)

### 1.1 Provision crash A — model round-trip probe

```
✗ Model round-trip FAILED
✗   Import error: cannot import name 'resolve_api_key_for_provider'
    from 'monoclaw_cli.auth' (/Users/test/.monoclaw/vendor/runtime/venv/
    lib/python3.13/site-packages/monoclaw_cli/auth.py)

Model round-trip failed. Continue anyway? [y/N]
```

### 1.2 Provision crash B — sub-wizard registry import

```
ModuleNotFoundError: No module named 'monoclaw_cli.subwizards'
  warning: provision finished with issues.
```

Crash B is **fatal** — the provision wizard exited mid-flight via
`apply_reviewed_system_changes` → `module.apply` →
`from monoclaw_cli.subwizards._base import …`.

### 1.3 `monoclaw doctor --fix` — unfixable warnings

| Doctor finding                         | Auto-fixed? |
|----------------------------------------|-------------|
| No API key found in `~/.monoclaw/.env` | No          |
| Venv entry point not found             | No          |
| ripgrep (`rg`) not found               | No          |
| `agent-browser` not installed          | No          |
| `tinker-atropos` not found             | No          |
| Skills Hub directory not initialized   | No          |

---

## 2. Root Cause Analysis

### 2.1 Crash B — `subwizards/` is not in the wheel (build bug)

`monoclaw-runtime/pyproject.toml` line 180:

```toml
[tool.setuptools.packages.find]
include = [
  "agent", "agent.*",
  "tools", "tools.*",
  "monoclaw_cli",                     # <-- subpackages NOT included
  "gateway", "gateway.*",
  "tui_gateway", "tui_gateway.*",
  "cron", "acp_adapter",
  "plugins", "plugins.*",
  "providers", "providers.*",
]
```

Every other package has a `pkg.*` glob to include subpackages, **but
`monoclaw_cli` does not**. Result: `monoclaw_cli/subwizards/` exists in the
git checkout but is **excluded from the built wheel**.

Direct evidence — inspecting the wheel actually shipped to the customer Mac
(`/Users/admin/Projects/monoclaw-developer/hatch/dist/runtime/monoclaw_runtime-0.1.0-py3-none-any.whl`):

```
$ unzip -l ...whl | grep subwizard
(no output)
```

The wheel has `monoclaw_cli/auth.py`, `monoclaw_cli/setup.py`, etc., but no
`monoclaw_cli/subwizards/__init__.py`. So the moment `system_setup.py:975`
runs `from monoclaw_cli.subwizards._base import …`, Python raises
`ModuleNotFoundError`.

This is a **packaging regression**, not a code bug. The subwizards code is
correct; it's simply never delivered to the target machine.

**Why the existing test suite did not catch this**: every test that
exercises subwizards imports them from the *git checkout* (where `subwizards/`
is on the source path), not from an installed wheel. There is no test that
asserts a freshly built wheel contains every Python subpackage that
`monoclaw_cli` imports. The Hatch verify probes (`bin/hatch verify`) only
import the top-level `monoclaw_runtime` module to check that the wheel is
loadable — they don't exercise `monoclaw provision`'s import graph.

### 2.2 Crash A — `provision.py` imports a phantom symbol (source bug)

`monoclaw-runtime/monoclaw_cli/provision.py` line 99:

```python
from monoclaw_cli.auth import resolve_api_key_for_provider
```

There is no symbol named `resolve_api_key_for_provider` anywhere in
`monoclaw-runtime`. The actual function in `auth.py` line 4054 is
`resolve_api_key_provider_credentials`. Searching the entire repo:

```
$ rg resolve_api_key_for_provider
monoclaw_cli/provision.py:99:        from monoclaw_cli.auth import resolve_api_key_for_provider
```

— exactly one occurrence: the broken import. The imported name is **never
used** inside `probe_model_round_trip` (the function falls back to a
hard-coded list of env vars at lines 122-127). It is a dead import that
crashes the entire probe with `ImportError`.

**Why the existing test suite did not catch this**: `tests/monoclaw_cli/test_provision.py:35`
monkey-patches `probe_model_round_trip` to a stub. The real function body
is never imported during the test, so the broken import inside its
`try:` block never fires.

### 2.3 Doctor's "Venv entry point not found" — wrong assumption about layout

`doctor.py:838-866`:

```python
_venv_bin = None
for _venv_name in ("venv", ".venv"):
    _candidate = PROJECT_ROOT / _venv_name / "bin" / "monoclaw"
    if _candidate.exists():
        _venv_bin = _candidate
        break
```

`PROJECT_ROOT` is `Path(__file__).parent.parent.resolve()`. In a Hatch
install:

- `monoclaw_cli/doctor.py` lives at
  `~/.monoclaw/vendor/runtime/venv/lib/python3.13/site-packages/monoclaw_cli/doctor.py`
- so `PROJECT_ROOT` resolves to
  `~/.monoclaw/vendor/runtime/venv/lib/python3.13/site-packages/`
- `PROJECT_ROOT/venv/bin/monoclaw` and `PROJECT_ROOT/.venv/bin/monoclaw`
  do not exist — neither path is the actual venv.

The actual venv is at `~/.monoclaw/vendor/runtime/venv/`, four levels up.
Doctor was written under the assumption that `PROJECT_ROOT` is a
git-cloned repo with `venv/` or `.venv/` as a sibling of the `monoclaw_cli/`
source directory. That assumption is **only valid for the
`scripts/install.sh` (curl-bash editable-install) path**. It does not hold
for any wheel-based install: Hatch, pip from PyPI, `pipx install`, or
Homebrew. Hatch already correctly installs the shim at
`~/.local/bin/monoclaw → ~/.monoclaw/vendor/runtime/venv/bin/monoclaw`,
but doctor never finds the venv to compare against, so it falls into the
`_venv_bin is None` branch and emits a misleading "Reinstall entry point"
hint.

**This is a doctor design bug, not a Hatch install bug** — the install
itself is fine. Doctor needs to know about the wheel-install layout.

### 2.4 Doctor's "ripgrep not found" — Hatch never installs `rg`

Looking at `hatch/bin/hatch:1615-1652` (`run_install_core_deps`): Hatch's
brew-first / bundle-fallback core-deps installer covers `node`, `uv`, `opus`,
and `ffmpeg`, but **omits `ripgrep`**. The Hatch CLAUDE.md and the
provision-sub-wizards plan list these four; nobody added `rg` to the list.

Symptom: `monoclaw doctor` correctly warns; `monoclaw doctor --fix` has no
fixer for it; the user has to `brew install ripgrep` manually.

`scripts/install.sh:657-826` (the curl-bash path) **does** install ripgrep
via `install_system_packages` — so this gap is unique to the Hatch path.

### 2.5 Doctor's "agent-browser not installed" — npm install never runs in Hatch

`scripts/install.sh:1301-1392` (the curl-bash path) explicitly runs
`npm install` from `INSTALL_DIR` (which has `package.json` declaring
`agent-browser ^0.26.0`) and `npx playwright install --with-deps chromium`
to wire up the browser stack.

Hatch's `bin/hatch install` does **none** of this. Hatch installs the
runtime venv from the wheel + wheelhouse and stages skills/tools, then
hands off to `install.sh` (the **template** at `hatch/templates/install.sh`,
which is a thin wrapper around `bin/hatch install`, not the runtime
`scripts/install.sh`). The template installer adds Mona pack +
skill-deps pack but never runs `npm install` against the runtime's
`package.json`, so `node_modules/agent-browser` never appears.

Doctor's check (`doctor.py:1042-1055`) compounds the issue by looking at
`PROJECT_ROOT / "node_modules" / "agent-browser"` — but in the Hatch
layout `PROJECT_ROOT` is a `site-packages` directory and there is no
`package.json` there to install dependencies into. Even if Hatch ran
`npm install`, doctor wouldn't find the modules at this path.

This is **two stacked bugs**:

1. Hatch never runs `npm install` for browser tools.
2. Doctor looks in the wrong place even if it had been run.

### 2.6 Doctor's "tinker-atropos not found" — RL-only, false positive

`tinker-atropos` is the optional RL training submodule. In a wheel install
it cannot exist as a sibling of `PROJECT_ROOT` (there is no submodule
checkout in `site-packages/`). The check at `doctor.py:1299-1312` is
git-checkout-only and emits a misleading warning on every wheel install.

Per `pyproject.toml:130-136`, `tinker-atropos` is part of the `[rl]`
extra. The Hatch local-office bundle installs only `[local-office]`, so
RL is intentionally absent. Doctor should detect "wheel install + no `[rl]`
extra" and either silence the warning or downgrade it to info.

### 2.7 Doctor's "Skills Hub directory not initialized" — first-run ordering

`~/.monoclaw/skills/.hub/` is created on the first invocation of
`monoclaw skills list` (or any `skills_hub` API call). On a fresh install
nothing has triggered that yet.

Hatch already does `install_bundled_skills` (`bin/hatch:638-672`) which
creates `~/.monoclaw/skills/<skill>` per bundled skill, but never seeds
`~/.monoclaw/skills/.hub/`. Either the directory should be created during
install, or doctor's check should be silent on a true fresh install.

### 2.8 Doctor's "No API key found" — provision crash cascade

The provision wizard is *supposed* to write either a real key or an
LM Studio dummy key into `~/.monoclaw/.env` during the model section. The
Hatch local-office bundle defaults to `LM_BASE_URL=http://127.0.0.1:1234/v1`
+ `LM_API_KEY=dummy-lm-api-key`, which would satisfy the doctor's check
(see `_PROVIDER_ENV_HINTS` — these are the keys it scans for).

Because crash A and crash B occur during provision, the wizard never
reaches the `.env` write. Doctor then correctly reports the missing
keys. **Fixing crashes A and B should make this finding disappear on a
clean install.** No standalone fix is required for `.env`.

---

## 3. Fix Plan (ordered by blast radius)

### Phase 1 — Stop the bleeding (P0, ship before any new install)

#### 3.1 Add `monoclaw_cli.*` to `pyproject.toml`

File: `monoclaw-runtime/pyproject.toml`

```diff
 [tool.setuptools.packages.find]
-include = ["agent", "agent.*", "tools", "tools.*", "monoclaw_cli", "gateway", "gateway.*", "tui_gateway", "tui_gateway.*", "cron", "acp_adapter", "plugins", "plugins.*", "providers", "providers.*"]
+include = ["agent", "agent.*", "tools", "tools.*", "monoclaw_cli", "monoclaw_cli.*", "gateway", "gateway.*", "tui_gateway", "tui_gateway.*", "cron", "acp_adapter", "plugins", "plugins.*", "providers", "providers.*"]
```

Audit at the same time: confirm there are no other monoclaw_cli subpackages
that need to ship. As of this audit, `monoclaw_cli/subwizards/` and
`monoclaw_cli/web_dist/` are the only sub-trees. `web_dist` is already
covered by `[tool.setuptools.package-data] monoclaw_cli = ["web_dist/**/*"]`
(non-Python data), so no further changes needed there.

#### 3.2 Add a packaging regression test

File: `monoclaw-runtime/tests/test_wheel_packaging.py` (new)

```python
"""Regression test: every monoclaw_cli subpackage must ship in the wheel.

This catches the May 2026 packaging regression where
`pyproject.toml` listed `monoclaw_cli` but not `monoclaw_cli.*`,
silently excluding `monoclaw_cli.subwizards` from every built wheel and
breaking `monoclaw provision` on clean installs.
"""

import subprocess
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_wheel_includes_every_python_subpackage(tmp_path):
    """Build a wheel and verify all source subpackages are present."""
    subprocess.check_call(
        [sys.executable, "-m", "build", "--wheel", "--outdir", str(tmp_path), str(REPO_ROOT)]
    )
    wheels = list(tmp_path.glob("monoclaw_runtime-*.whl"))
    assert len(wheels) == 1, f"expected one wheel, got {wheels}"
    wheel = wheels[0]

    expected_subpackages = []
    for pkg_dir in ("monoclaw_cli", "agent", "gateway", "tools", "plugins"):
        root = REPO_ROOT / pkg_dir
        for init in root.rglob("__init__.py"):
            rel = init.relative_to(REPO_ROOT)
            expected_subpackages.append(rel.as_posix())

    with zipfile.ZipFile(wheel) as zf:
        names = set(zf.namelist())
    missing = [p for p in expected_subpackages if p not in names]
    assert not missing, f"wheel is missing source subpackages: {missing}"
```

This test must FAIL on the current `main` to prove it catches the regression
before the `pyproject.toml` fix lands.

#### 3.3 Fix the dead `provision.py` import

File: `monoclaw-runtime/monoclaw_cli/provision.py`

```diff
     try:
-        from monoclaw_cli.auth import resolve_api_key_for_provider
         from monoclaw_cli.config import load_config
         from run_agent import AIAgent
```

The function is never used inside `probe_model_round_trip`. Drop the line.

If a future change actually wants programmatic key resolution, use the
existing public function name `resolve_api_key_provider_credentials` from
`monoclaw_cli.auth` (line 4054). Do not "rename to fit the import" —
the existing name is correct and is referenced in 13+ other files.

#### 3.4 Add a real probe-import test (no mocking)

File: `monoclaw-runtime/tests/monoclaw_cli/test_provision.py`

```python
def test_probe_model_round_trip_imports_resolve(monkeypatch, tmp_path):
    """probe_model_round_trip must import successfully, not just under mock.

    The May 2026 regression had a phantom `resolve_api_key_for_provider`
    import inside the try-block; tests previously stubbed the whole
    function so the import was never exercised. This test calls into
    the real function and asserts the import path is clean.
    """
    from monoclaw_cli import provision

    # Force a known-bad provider so the function returns early but
    # only AFTER the imports succeed.
    config = {"model": {"provider": "lmstudio", "default": "test-model"}}
    result = provision.probe_model_round_trip(config, timeout=1.0)
    # We don't assert ok=True (no real LM Studio in CI); we assert the
    # import error path was not hit.
    assert "Import error" not in result.get("error", ""), (
        f"phantom import in probe_model_round_trip: {result['error']}"
    )
```

#### 3.5 Build & smoke a real bundle as part of CI for the fix branch

Per `hatch/CLAUDE.md` "Required Verification For Dependency Changes":

```bash
cd hatch && bash build.sh
# verify subwizards is now in the wheel
unzip -l dist/runtime/monoclaw_runtime-*.whl | grep subwizards/__init__.py
# real install simulation
bash dist/install.sh
~/.local/bin/monoclaw provision  # must not crash
```

Until these steps pass on a clean Mac, the fix is not done.

---

### Phase 2 — Make `doctor --fix` actually fix things (P1)

#### 3.6 Teach doctor about wheel-install layouts

File: `monoclaw-runtime/monoclaw_cli/doctor.py`

The "Command Installation" section currently assumes a git-checkout layout.
Split it into two layouts:

```python
def _detect_install_layout() -> dict:
    """Return install layout metadata.

    Layout is one of:
      'git-editable'  — git clone + venv/.venv as sibling (PROJECT_ROOT/venv)
      'wheel-hatch'   — Hatch install (~/.monoclaw/vendor/runtime/venv/)
      'wheel-pipx'    — pipx install
      'wheel-pip'     — generic pip install (sys.prefix is the venv)
      'unknown'       — none of the above; fall back to PATH discovery
    """
    # 1) git-editable: PROJECT_ROOT/venv/bin/monoclaw or .venv
    for name in ("venv", ".venv"):
        candidate = PROJECT_ROOT / name / "bin" / "monoclaw"
        if candidate.exists():
            return {"layout": "git-editable", "venv_bin": candidate, "venv_root": candidate.parent.parent}
    # 2) wheel-hatch: walk up from this file to find venv/bin/monoclaw
    cur = Path(__file__).resolve()
    for ancestor in cur.parents:
        candidate = ancestor / "bin" / "monoclaw"
        if candidate.exists() and (ancestor / "pyvenv.cfg").exists():
            return {"layout": "wheel-hatch", "venv_bin": candidate, "venv_root": ancestor}
    # 3) sys.prefix is the venv root
    venv_bin = Path(sys.prefix) / "bin" / "monoclaw"
    if venv_bin.exists():
        return {"layout": "wheel-pip", "venv_bin": venv_bin, "venv_root": Path(sys.prefix)}
    # 4) fall back to PATH
    found = shutil.which("monoclaw")
    if found:
        return {"layout": "unknown", "venv_bin": Path(found), "venv_root": None}
    return {"layout": "unknown", "venv_bin": None, "venv_root": None}
```

Then replace lines 838-866 with a call to `_detect_install_layout()` and use
the returned `venv_bin` for the symlink check.

This single change fixes "Venv entry point not found" on every wheel
install (Hatch, pipx, pip from PyPI).

#### 3.7 Silence false positives on wheel installs

In `doctor.py`, gate the following checks on `layout != "git-editable"`:

- `tinker-atropos not found` — RL submodule cannot exist in a wheel install.
  Convert to `check_info("tinker-atropos not applicable for wheel installs")`
  or skip entirely.
- `agent-browser not installed` — when `PROJECT_ROOT` is a `site-packages`
  directory, `node_modules/agent-browser` will never exist there. Look in
  the right place (see 3.8) or skip.

#### 3.8 Add ripgrep to Hatch's core-deps

File: `monoclaw-developer/hatch/bin/hatch`

In `run_install_core_deps`, append `ripgrep` to the formula list:

```diff
   for entry in \
       "node|Node.js LTS (+npm)" \
       "uv|Astral uv (Python env manager)" \
       "opus|Opus codec (Discord voice)" \
+      "ripgrep|ripgrep (fast file search)" \
       "ffmpeg|ffmpeg (TTS playback, voice mode)"; do
```

Add a regression test under `hatch/tests/hatch_core_deps_tests.sh` asserting
that `ripgrep` is one of the brewed formulas in dry-run output.

#### 3.9 Wire `agent-browser` into the Hatch path

There are two reasonable options. **Option A** is preferred because it does
not require a network round-trip on the customer Mac.

**Option A — bundle agent-browser as a tool-pack**

Add `agent-browser` to the `bundle-inputs/vendor/browser/` payload. Stage
the `node_modules/` directory under `~/.monoclaw/vendor/browser/node_modules/`
during `install_runtime_assets`. Add a `MONOCLAW_BROWSER_NODE_MODULES`
env hint so `tools/browser_*.py` can find it without a global `npm
install`. Update doctor's check to look at the bundled location too.

**Option B — run `npm install -g agent-browser` from `bin/hatch`**

Cheaper to implement but requires online installs and pollutes the user's
global npm prefix. Add a new helper in `bin/hatch`:

```bash
install_agent_browser_global() {
  if [[ "${HATCH_INSTALL_OFFLINE:-0}" == "1" ]]; then
    log_step "agent-browser" "HATCH_INSTALL_OFFLINE=1; skipping"
    return
  fi
  if ! have_command npm; then
    log_warn "agent-browser: npm not on PATH; skipping (install Node first)"
    return
  fi
  if [[ "${HATCH_DRY_RUN}" == "true" ]]; then
    printf '  dry-run: npm install -g agent-browser@^0.26.0\n'
    return
  fi
  if npm install --silent -g agent-browser@^0.26.0; then
    log_ok "agent-browser installed via npm -g"
  else
    log_warn "agent-browser install failed; browser tools may not work"
  fi
}
```

Call it from `run_install` after `install_class_a_brew_formulas` /
`run_install_core_deps`.

Either option requires a doctor change (3.10).

#### 3.10 Make doctor's agent-browser check layout-aware

Replace the `PROJECT_ROOT / "node_modules" / "agent-browser"` lookup with a
multi-location probe:

```python
agent_browser_paths = [
    PROJECT_ROOT / "node_modules" / "agent-browser",                  # git-editable
    MONOCLAW_HOME / "vendor" / "browser" / "node_modules" / "agent-browser",  # Hatch (Option A)
    Path(shutil.which("agent-browser")) if shutil.which("agent-browser") else None,  # global npm (Option B)
]
if any(p and p.exists() for p in agent_browser_paths):
    check_ok("agent-browser", "(browser automation)")
else:
    check_warn("agent-browser not installed", ...)
```

#### 3.11 Pre-create `~/.monoclaw/skills/.hub/` during Hatch install

In `bin/hatch:install_bundled_skills`, after `mkdir -p "${target_dir}"`:

```bash
mkdir -p "${target_dir}/.hub"
if [[ ! -f "${target_dir}/.hub/lock.json" ]]; then
  printf '{"installed": {}}\n' > "${target_dir}/.hub/lock.json"
fi
```

This makes doctor's check `check_ok` instead of `check_warn` on a fresh
install. It also unblocks the first `monoclaw skills` invocation from
having to bootstrap the directory.

---

### Phase 3 — Make doctor `--fix` self-heal more (P2)

#### 3.12 Auto-create empty `.env` on first run

Already partially done at `doctor.py:390-395`, but only when the file is
*completely missing*. Extend this to also detect "file exists but is
empty / has no provider hints" and write the local-office defaults:

```python
elif not _has_provider_env_config(content):
    if should_fix:
        with env_path.open("a", encoding="utf-8") as f:
            f.write("\n# Default LM Studio local-office configuration\n")
            f.write("LM_BASE_URL=http://127.0.0.1:1234/v1\n")
            f.write("LM_API_KEY=dummy-lm-api-key\n")
            f.write("MONOCLAW_MODEL=local:gemma4:e4b\n")
        check_ok(f"Wrote LM Studio defaults to {_DHH}/.env")
        fixed_count += 1
    else:
        check_warn(...)
```

Gate this on the LM Studio bundle being present
(`MONOCLAW_HOME/vendor/lm-studio/` or `vendor/models/gemma-4-e4b/`). If
the bundle isn't present, fall back to the existing "run monoclaw setup"
hint.

#### 3.13 Auto-fix the venv shim symlink

`doctor.py:889-898` already handles "create missing symlink". Extend
it to also handle "shim exists but `~/.local/bin` is not on PATH" by
appending the export to the user's shell rc, mirroring `bin/hatch`'s
`ensure_local_bin_on_path` logic.

---

## 4. Verification Plan

A fresh-Mac install must pass the following on the user's identified
branch before merge:

1. `cd hatch && bash build.sh` — succeeds, wheel contains
   `monoclaw_cli/subwizards/__init__.py`.
2. New `tests/test_wheel_packaging.py` — passes (was failing on `main`
   before 3.1).
3. New `tests/monoclaw_cli/test_provision.py::test_probe_model_round_trip_imports_resolve`
   — passes.
4. From the dist directory, `bash install.sh` against an empty
   `~/.monoclaw/` on a Mac that has never seen MonoClaw:
   - exits 0,
   - `~/.local/bin/monoclaw provision` runs to completion without
     `ImportError` or `ModuleNotFoundError`,
   - `~/.monoclaw/skills/.hub/lock.json` exists,
   - `~/.monoclaw/.env` contains LM Studio defaults,
   - `command -v rg` succeeds,
   - `command -v agent-browser` succeeds (or
     `~/.monoclaw/vendor/browser/node_modules/agent-browser` exists).
5. `monoclaw doctor --fix` reports zero `⚠` and zero `✗`.
6. `bash hatch/tests/run_tests.sh` — all dry-run + provisioning + verify
   probes pass.
7. `bash monoclaw-runtime/scripts/run_tests.sh` — full Python suite
   passes; in particular the new packaging + provision import tests pass.

---

## 5. Sequencing & Ownership

| Phase | Work item                                              | Repo                | P  |
|-------|--------------------------------------------------------|---------------------|----|
| 1     | Add `monoclaw_cli.*` to packages.find                  | monoclaw-runtime    | P0 |
| 1     | Drop dead `resolve_api_key_for_provider` import        | monoclaw-runtime    | P0 |
| 1     | New wheel-packaging regression test                    | monoclaw-runtime    | P0 |
| 1     | New non-mocked provision-import test                   | monoclaw-runtime    | P0 |
| 1     | Real-bundle install smoke on a fresh Mac               | monoclaw-developer  | P0 |
| 2     | Doctor: detect wheel-install layout                    | monoclaw-runtime    | P1 |
| 2     | Doctor: silence tinker-atropos on wheel installs       | monoclaw-runtime    | P1 |
| 2     | Hatch: add ripgrep to core-deps brew list              | monoclaw-developer  | P1 |
| 2     | Hatch: wire agent-browser (Option A or B)              | monoclaw-developer  | P1 |
| 2     | Doctor: layout-aware agent-browser lookup              | monoclaw-runtime    | P1 |
| 2     | Hatch: pre-create skills/.hub/lock.json                | monoclaw-developer  | P1 |
| 3     | Doctor `--fix`: write LM Studio defaults to .env       | monoclaw-runtime    | P2 |
| 3     | Doctor `--fix`: ensure ~/.local/bin on PATH            | monoclaw-runtime    | P2 |

The Phase 1 items must ship as a single PR (or coordinated PR pair across
the two repos) — landing only the import fix without the packaging fix
still leaves the wheel broken; landing only the packaging fix still leaves
provision crashing on the dead import. Both gates must clear at once.

Phase 2 and Phase 3 are quality-of-life improvements that can land in
later PRs but should not slip past the next bundle release.

---

## 6. Open Questions / Risks

- **Q1 — Option A vs Option B for `agent-browser`**: bundling
  `node_modules` adds ~80 MB to the pendrive image; global `npm install`
  fails on offline customer Macs. The "right" answer depends on whether
  Hatch's commercial customers are guaranteed to be online during install.
  **Recommendation**: implement both, gate Option B on
  `HATCH_INSTALL_OFFLINE != 1` so air-gapped installs use Option A only.

- **Q2 — `tinker-atropos` user expectations**: silencing the warning on
  wheel installs is correct, but RL training is a real product surface for
  the developer-facing curl-bash path. Make sure the change distinguishes
  "wheel layout, RL out of scope" from "git-editable layout, RL extra not
  installed (run `pip install -e '.[rl]'`)".

- **Q3 — Scope creep on `doctor --fix`**: the user's symptoms suggest they
  expect `doctor --fix` to be a one-shot install repair tool. That is a
  reasonable contract but worth socialising before Phase 3 lands. If
  agreed, the fix surface should also include "`monoclaw doctor --fix
  --reinstall-skill-deps`" delegating to the Hatch skill-deps installer
  when the bundle is on disk.

- **Q4 — Why was the `subwizards` regression not caught by the existing
  `tests/monoclaw_cli/subwizards/`** suite (13 test files)? Those tests
  import the modules from the source path during a `pytest` run, which
  always works because the repo is on `sys.path`. They never assert that
  the modules are present in the **distribution artefact**. Phase 1's
  packaging test fills that gap. Reviewers should be alert to the same
  shape of bug for any future subpackage added under `monoclaw_cli/`.
