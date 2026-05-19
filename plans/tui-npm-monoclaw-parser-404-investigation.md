# `monoclaw --tui` npm 404 — Rebrand Find/Replace Corruption Investigation

**Trigger**: On a fresh test-bench Mac (`/Users/test/...`), after `./install.sh`
completes successfully, the next `monoclaw --tui` invocation aborts during
the lazy "Installing TUI dependencies…" step with:

```
npm error code E404
npm error 404 Not Found - GET https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz - Not found
```

`monoclaw-parser` is not a real npm package. The real package the TUI's
dev dependencies pull in is `hermes-parser@0.25.1` — Meta's JavaScript
parser for the Hermes JS engine, used by `eslint-plugin-react-compiler`
and `eslint-plugin-react-hooks@^7` for AST work. It has 44.7M weekly
downloads on npm; we did not fork or replace it.

The TUI is shipped broken because the original Hermes → MonoClaw rebrand
in `monoclaw-runtime`'s initial squash commit performed a **blanket
literal-string find/replace** across the entire repo (including the npm
lock file) and turned `hermes-parser` → `monoclaw-parser` and
`hermes-estree` → `monoclaw-estree`. The sibling `web/package-lock.json`
was later partially undone (commit `6daa2d7`), but
`ui-tui/package-lock.json` was not, and the only reason the corruption
did not surface during Hatch's `./build.sh` is that the build host's
`ui-tui/node_modules/` was renamed in place at the same time the lock
file was — so `npm ci` was either skipped or short-circuited by an
already-present (renamed) tree.

This is the third "lazy implementation" install regression in two weeks
(after the wheel-packaging exclusion of `monoclaw_cli.subwizards` and
the dead `resolve_api_key_for_provider` import in `provision.py`,
documented in `plans/install-failures-investigation.md`). The pattern is
the same: ship something that *looks* correct, defer the only check
that would have caught the failure (a real install against a clean
machine) to the customer.

---

## 1. Symptom Inventory (verbatim)

### 1.1 Customer-visible failure

```
test@tests-iMac ~ % monoclaw --tui
Installing TUI dependencies…
✗ Installing TUI dependencies failed (exit 1).
  command: /opt/homebrew/bin/npm install --loglevel=error --no-fund --no-audit --progress=false
  cwd:     /Users/test/.monoclaw/vendor/tui
  --- npm output ---
  npm error code E404
  npm error 404 Not Found - GET https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz - Not found
  npm error 404
  npm error 404  The requested resource 'monoclaw-parser@https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz' could not be found or you do not have permission to access it.
```

The error message itself is *actionable* (good — that's
plans/tui-npm-install-error-handling.md Phase 3 working as intended).
The problem is the install can never succeed: the lock file points at a
package that does not exist on npm.

### 1.2 Verbose log confirms the package is genuinely missing

```
npm verbose stack HttpErrorGeneral: 404 Not Found - GET https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz - Not found
npm verbose statusCode 404
npm verbose pkgid monoclaw-parser@https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz
```

npm tried the public registry, got an HTTP 404, gave up. No private
registry is configured (there is no `.npmrc` in `vendor/tui/`, no
`MONOCLAW_NPM_REGISTRY` env var in the runtime). The package simply
does not exist.

---

## 2. Root Cause Analysis

### 2.1 The lock file we ship is corrupted at the source

`monoclaw-runtime/ui-tui/package-lock.json` contains exactly four
sentinel lines that prove the corruption:

```
3321:        "monoclaw-parser": "^0.25.1",
3364:        "monoclaw-parser": "^0.25.1",
4107:    "node_modules/monoclaw-estree": {
4109:      "resolved": "https://registry.npmjs.org/monoclaw-estree/-/monoclaw-estree-0.25.1.tgz",
4114:    "node_modules/monoclaw-parser": {
4116:      "resolved": "https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz",
4121:        "monoclaw-estree": "0.25.1"
```

Two facts make these lines diagnostic, not aspirational:

1. The `resolved` URLs point at `https://registry.npmjs.org/` (the
   public registry), not at a private MonoClaw registry. The repo has
   never configured a private registry — `rg -n 'registry' ui-tui/` and
   `ls ui-tui/.npmrc` both confirm.
2. The integrity hashes on those lines
   (`sha512-6pEjquH3rqaI6cYAXYPcz9MS4rY6R4ngRgrgfDshRptUZIc3lw0MCIJIGDj9++mfySOuPTHB4nrSW99BCvOPIA==`
   for "monoclaw-parser@0.25.1") match the **real `hermes-parser@0.25.1`**
   tarball published by Meta. A truly different package would have a
   different hash.

The lock file is therefore a renamed Hermes lock file — same hashes,
same versions, but with the package name string substituted.

### 2.2 The top-level `ui-tui/package.json` is clean — corruption is transitive only

```
$ rg -n 'hermes|monoclaw-parser|monoclaw-estree' ui-tui/package.json
(no output)
```

The user-authored devDependencies are correct:

```json
"eslint-plugin-react-compiler": "^19.1.0-rc.2",
"eslint-plugin-react-hooks": "^7"
```

Both pull `hermes-parser` in transitively. Confirmed against npm's
catalog page for both packages.

So this is purely a **lock-file regeneration problem**, not a
dependency-graph problem. Running `npm install` from a clean
`node_modules/` against the current `package.json` will produce a
correct lock file with `hermes-parser`/`hermes-estree`.

### 2.3 The rebrand-by-find/replace pattern is the upstream cause

`monoclaw-developer/skills/runtime-rebrand.md` is the canonical playbook
for this kind of work. Its audit rule is:

```bash
rg -i "hermes|ai\\.hermes|~/.hermes|hermes-agent" ../monoclaw-runtime
```

"Every remaining hit must be classified in the handoff." The skill
explicitly tells the assistant to treat remaining "hermes" references
as bugs unless they are in legal attribution. **This audit, applied to
a third-party-package name, is wrong** — `hermes-parser` and
`hermes-estree` are Meta-published npm identifiers that the rebrand
must NOT touch, the same way the rebrand must not rename `react` to
`monoclaw-react` or `eslint` to `monoclaw-lint`.

The skill currently has no enumerated allowlist of third-party
identifiers and no inverse audit ("any `monoclaw-` package name with a
`registry.npmjs.org/` resolved URL is a rebrand bug"), so an LLM
following the skill end-to-end will keep recreating this class of
corruption every time it touches a new file with "hermes" in it.

### 2.4 The host build machine is not a check — `node_modules` was renamed in place

`hatch/build.sh::stage_runtime_tui` (line 386) runs `npm ci` against
the source tree before rsync-staging it into `dist/vendor/tui/`:

```bash
(cd "${tui_src}" && npm ci --no-fund --no-audit --progress=false >/dev/null)
```

`npm ci` is *supposed* to fail against a corrupted lock file. It did
not, because the developer's `ui-tui/node_modules/` already contains
`monoclaw-parser/` and `monoclaw-estree/` directories — **renamed in
place** by the same blanket find/replace that hit the lock file:

```
$ ls ui-tui/node_modules/ | rg -i "hermes|monoclaw-pars|monoclaw-estree"
monoclaw-estree
monoclaw-parser

$ cat ui-tui/node_modules/monoclaw-parser/package.json | rg '"name"'
  "name": "hermes-parser",
```

The directory name was renamed; the `package.json` inside (which npm
matches against the lock file by hash + name) was not, because npm
identifies packages by the `name` field, not the directory name. So:

- `npm ci` against this tree sees `node_modules/monoclaw-parser/package.json`
  with `name: hermes-parser` and either skips it (lock mismatch) or
  honours `--prefer-offline` cache hits keyed off integrity hashes.
- More likely, the developer ran `HATCH_SKIP_RUNTIME_BUILD=1` (line
  382, which short-circuits the build steps entirely and just uses the
  pre-staged `dist/`), since the timestamps under `ui-tui/dist/` match
  the initial squash, not a recent build.

Either way the build host succeeds because it is operating on a
post-rebrand artefact that was already laundered into a working state.
The customer Mac, which has a cold npm cache and an empty
`vendor/tui/node_modules/`, hits the cold-cache path that nobody
exercises and 404s.

### 2.5 The sibling `web/package-lock.json` was already fixed — the precedent confirms this is a bug

Commit `6daa2d7` ("cli/tui: branding and setup; provisioning audit and
tests") explicitly reverses the corruption **only** in
`web/package-lock.json`:

```
$ git show 6daa2d7 -- web/package-lock.json | rg "hermes-parser|monoclaw-parser"
-        "monoclaw-parser": "^0.25.1",
+        "hermes-parser": "^0.25.1",
-    "node_modules/monoclaw-parser": {
+    "node_modules/hermes-parser": {
-      "resolved": "https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz",
+      "resolved": "https://registry.npmjs.org/hermes-parser/-/hermes-parser-0.25.1.tgz",
```

That commit's stat reorganised 627 lines of `web/package-lock.json` but
made *no* edits to `ui-tui/package-lock.json`. Whoever fixed `web/`
either did not realise the same corruption existed in `ui-tui/`, or
considered the TUI lock file out of scope. The fix is identical in
shape; we just need to apply it.

### 2.6 The lazy first-launch `npm install` is where the corruption surfaces, not where it lives

`monoclaw-runtime/monoclaw_cli/main.py::_make_tui_argv` (line 1302)
runs `npm install` against the staged `vendor/tui/` whenever
`_tui_need_npm_install` returns True (i.e., always on a fresh customer
Mac, because Hatch deliberately does not stage `node_modules` —
`hatch/build.sh:399-404`). `_preflight_tui_install` (line 1249) only
checks writability of the directory; it does not parse the lock file.

This is not the bug — the bug is in the lock file — but it is the
catastrophic-failure point because:

1. The customer cannot fix it (the lock file is owned by the runtime
   bundle).
2. The error message correctly tells the customer to retry
   `npm install --loglevel=verbose`, which will fail the same way.
3. There is no automated fallback (e.g. "drop the lock file and try
   `npm install` so npm resolves fresh"), which would mask the
   regression on the next test bench too but at least keep the customer
   unblocked.

We will treat this as a defense-in-depth surface (Phase 3 of the fix),
not as the primary fix.

### 2.7 The bundled `dist/vendor/tui/package-lock.json` is bit-identical to the source

```
$ rg -n 'monoclaw-parser|monoclaw-estree' hatch/dist/vendor/tui/package-lock.json
3321:        "monoclaw-parser": "^0.25.1",
3364:        "monoclaw-parser": "^0.25.1",
4107:    "node_modules/monoclaw-estree": {
4109:      "resolved": "https://registry.npmjs.org/monoclaw-estree/-/monoclaw-estree-0.25.1.tgz",
4114:    "node_modules/monoclaw-parser": {
4116:      "resolved": "https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz",
4121:        "monoclaw-estree": "0.25.1"
```

Confirmed — `hatch/dist/` is downstream of `monoclaw-runtime/ui-tui/`
via `stage_runtime_tui`'s `rsync`. Fixing the source lock file and
rebuilding Hatch is sufficient; we never need to edit `dist/` directly.

---

## 3. Why Every Existing Guard Missed It

| Guard                                                     | What it checks                                                                  | Why it missed the corruption                                                                                       |
|-----------------------------------------------------------|---------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| `runtime-rebrand.md` audit (`rg -i hermes`)               | Any leftover "hermes" string                                                    | Inverse problem — the audit only catches forgotten renames, not over-eager ones.                                   |
| `web/package-lock.json` revert in `6daa2d7`               | Manual cleanup of one lock file                                                 | Author missed the sibling `ui-tui/package-lock.json`; no programmatic enforcement that the fix covers every shipped lock. |
| `hatch/build.sh::stage_runtime_tui` (`npm ci` precheck)   | Reproducible install                                                            | Either `HATCH_SKIP_RUNTIME_BUILD=1` skipped it, or the pre-renamed `node_modules/` made `npm ci` short-circuit on the dev box. |
| `monoclaw_cli/main.py::_preflight_tui_install`            | Writability of `vendor/tui/`                                                    | Doesn't parse the lock file; no scan for `registry.npmjs.org/monoclaw-` URLs.                                      |
| `hatch/CLAUDE.md` "real bundle smoke test before release" | `vendor/python/current/bin/python3 -m venv <tmp>` + `pip --version`             | Python-only — doesn't touch the bundled TUI's npm graph.                                                           |
| `monoclaw-runtime` test suite                             | Runtime semantics                                                               | No test scans shipped lock files for fake-MonoClaw npm package names.                                              |

Every guard is correct as far as it goes; none of them have
"third-party npm identifiers that should not have been rebranded" as
their explicit responsibility. We need that guard, and we need it in
at least two layers (the rebrand skill that *prevents* the corruption
and a lockfile sentinel test that *detects* it).

---

## 4. Fix Plan

### Phase 1 — Stop the bleeding (P0, must ship before any new install bundle)

#### 4.1 Regenerate `ui-tui/package-lock.json` from a clean state

File: `monoclaw-runtime/ui-tui/package-lock.json` (regenerate, do not
hand-edit).

```bash
cd monoclaw-runtime/ui-tui
rm -rf node_modules package-lock.json
npm install --no-fund --no-audit
git diff --stat package-lock.json   # expect a big diff (renames + reorders)
rg -n 'monoclaw-parser|monoclaw-estree' package-lock.json   # expect: no output
rg -n '"hermes-parser"|"hermes-estree"' package-lock.json   # expect: hits in both transitive + node_modules sections
```

Rationale for full regeneration vs. surgical `sed`:

- `sed -i '' 's/monoclaw-parser/hermes-parser/g; s/monoclaw-estree/hermes-estree/g' package-lock.json` *would* fix
  the four sentinel lines but leaves us in a state where the lock file's
  on-disk shape is whatever the original rebrand left, including any
  other now-unknown corruption. A clean regeneration is the only way
  to guarantee no rebrand-script artefacts remain.
- The transitive dependency closure may have drifted since May (e.g.
  patch bumps to react / eslint). A regeneration picks up any
  legitimate security fixes that have shipped in the meantime under
  the current `^` ranges, which is desirable.

If we want to keep transitive versions pinned across the regeneration
to minimise reviewer noise, run `npm install --no-fund --no-audit
--prefer-offline` against a populated npm cache and then verify
`git diff package-lock.json` does not show unexpected version bumps
unrelated to `hermes-*`.

Also rename the on-disk `node_modules/` directories on the dev host
to keep future `npm ci` runs consistent with the corrected lock:

```bash
cd monoclaw-runtime/ui-tui/node_modules
mv monoclaw-parser hermes-parser 2>/dev/null || true
mv monoclaw-estree hermes-estree 2>/dev/null || true
```

(Optional — `npm install` will produce the correct directories on its
own; the rename above only avoids an interactive prompt about an
existing tree.)

#### 4.2 Add a shipped-lockfile sentinel test

File: `monoclaw-runtime/tests/test_npm_lockfile_no_fake_monoclaw_packages.py` (new)

```python
"""Regression test: no shipped npm lock file may claim that a fake
``monoclaw-*`` package can be fetched from the public npm registry.

This catches the May 2026 rebrand-corruption class of bug, where the
initial Hermes -> MonoClaw blanket find/replace renamed third-party
npm identifiers like ``hermes-parser`` -> ``monoclaw-parser`` inside
``ui-tui/package-lock.json``. The corrupted lock made the lazy
``monoclaw --tui`` first-launch ``npm install`` fail with HTTP 404 on
every fresh customer Mac, because no such MonoClaw npm package exists.

The rule is: if a package name starts with ``monoclaw-`` (no scope,
no slash) AND its resolved URL is on the public npm registry, the
lock file lies. We do not publish to npm under that prefix.

The companion rule covers ``@monoclaw/*`` — scoped packages we own
either resolve to a local ``file:`` dep (``@monoclaw/ink``) or are
absent from the lock file. Any ``@monoclaw/*`` entry with a public
``registry.npmjs.org/`` URL is also a corruption indicator and should
fail the test.
"""

import json
import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]

_LOCK_FILES = [
    REPO_ROOT / "ui-tui" / "package-lock.json",
    REPO_ROOT / "web" / "package-lock.json",
    REPO_ROOT / "scripts" / "whatsapp-bridge" / "package-lock.json",
]

_PUBLIC_REGISTRY = "https://registry.npmjs.org/"
_FAKE_NAME = re.compile(r"^(monoclaw-[a-z][a-z0-9-]*|@monoclaw/[a-z][a-z0-9-]*)$")


def _iter_lock_packages(lock_path: Path):
    """Yield (lock_key, name, resolved_url) for every npm-lock package entry."""
    if not lock_path.is_file():
        pytest.skip(f"{lock_path} not present in this checkout")
    data = json.loads(lock_path.read_text(encoding="utf-8"))
    for key, pkg in (data.get("packages") or {}).items():
        if not isinstance(pkg, dict):
            continue
        # The empty-string key is the workspace root; "name" lives at the top level.
        if key == "":
            continue
        # npm 9+ records the package name as the key's trailing path segment
        # under node_modules. Prefer pkg["name"] when present (it can disagree
        # with the directory name for aliases / scoped packages).
        name = pkg.get("name") or key.rsplit("node_modules/", 1)[-1]
        resolved = pkg.get("resolved") or ""
        yield key, name, resolved


@pytest.mark.parametrize("lock_path", _LOCK_FILES, ids=lambda p: str(p.relative_to(REPO_ROOT)))
def test_no_fake_monoclaw_packages_on_public_registry(lock_path: Path) -> None:
    offenders: list[str] = []
    for key, name, resolved in _iter_lock_packages(lock_path):
        if not _FAKE_NAME.match(name):
            continue
        if resolved.startswith(_PUBLIC_REGISTRY):
            offenders.append(f"{key} (name={name}, resolved={resolved})")

    assert not offenders, (
        f"{lock_path.relative_to(REPO_ROOT)} claims the following packages "
        f"are published on the public npm registry under a MonoClaw name, "
        f"but no such packages exist. This is the signature of a "
        f"Hermes -> MonoClaw rebrand find/replace that hit third-party "
        f"npm package names by mistake; see "
        f"plans/tui-npm-monoclaw-parser-404-investigation.md.\n\n"
        + "\n".join(f"  - {entry}" for entry in offenders)
    )
```

This test must FAIL on `main` before 4.1 lands and PASS after, so we
have proof the regression check is real.

#### 4.3 Rebuild the Hatch bundle and verify the corruption is gone

```bash
cd monoclaw-developer/hatch
HATCH_SKIP_RUNTIME_BUILD=                  # explicit empty to force prebuild
bash build.sh
rg -n 'monoclaw-parser|monoclaw-estree' dist/vendor/tui/package-lock.json
# expect: no output
```

Then end-to-end smoke per `hatch/CLAUDE.md` "Required Verification For
Dependency Changes":

```bash
# On a Mac with an empty ~/.monoclaw/ that has never seen MonoClaw:
rm -rf ~/.monoclaw
bash dist/install.sh
monoclaw --tui   # must reach the Ink banner; npm install must succeed.
```

The TUI install warmup (`hatch/bin/hatch::warm_tui_install`, line 541)
runs at `bash dist/install.sh` time too, so the corruption now fails
**at install time** with the same clear error rather than at first
launch. That is the canonical place to surface it.

---

### Phase 2 — Harden the rebrand skill (P0, ships with Phase 1)

#### 4.4 Update `runtime-rebrand.md` with an explicit third-party identifier carve-out

File: `monoclaw-developer/skills/runtime-rebrand.md`

Append to the `## Checklist`:

```markdown
- **Never rename third-party npm or PyPI package identifiers.** The
  Hermes upstream pulls in dependencies whose names contain "hermes"
  but are Meta-published packages we do not own. Treat the following
  as **immutable** during any rebrand pass; they must remain
  unchanged in every `package.json`, `package-lock.json`,
  `pyproject.toml`, `Cargo.toml`, and equivalent dependency manifest:

  - `hermes-parser` (Meta, https://www.npmjs.com/package/hermes-parser)
  - `hermes-estree` (Meta)
  - any future package matching `^hermes(-[a-z][a-z0-9-]*)*$` that
    resolves on the public npm registry

  When in doubt, check `registry.npmjs.org/<name>`: if it returns 200,
  it is a third-party identifier and must not be renamed.

- **Inverse audit** — run before declaring the rebrand done:

  ```bash
  rg -n '"monoclaw-[a-z][a-z0-9-]*":|"@monoclaw/[a-z][a-z0-9-]*":' \
    ../monoclaw-runtime --type json | rg -v "/node_modules/"
  ```

  Every hit must be either (a) a real MonoClaw-published name (today:
  only `@monoclaw/ink` as a `file:` dep) or (b) a known-bad rebrand
  artefact that the rebrand must revert. Untriaged `monoclaw-*`
  identifiers in shipped lock files are bugs.
```

The forward audit (current `rg -i "hermes|..."`) stays, but it is no
longer the only check. The inverse audit is what catches over-zealous
renames.

#### 4.5 Add the same carve-out to `monoclaw-runtime/AGENTS.md` Known Pitfalls

So future contributors who edit `ui-tui/` or `web/` see the rule
without having to consult the rebrand skill:

```markdown
### DO NOT rebrand third-party npm package identifiers

Meta's `hermes-parser` and `hermes-estree` (transitive deps of
`eslint-plugin-react-compiler` and `eslint-plugin-react-hooks@^7`) are
**not** MonoClaw packages and must keep their upstream names in every
`package.json` / `package-lock.json` we ship. A blanket
`s/hermes/monoclaw/g` rebrand on `ui-tui/package-lock.json` will
silently produce a lock file that 404s at customer `npm install` time
because no `monoclaw-parser` exists on the npm registry. This regressed
the May 2026 fresh-Mac TUI install (see
`plans/tui-npm-monoclaw-parser-404-investigation.md`); the
regression-guard test is
`tests/test_npm_lockfile_no_fake_monoclaw_packages.py`.
```

---

### Phase 3 — Defense in depth (P1, can land same PR or follow-up)

#### 4.6 Hatch build-side guard in `stage_runtime_tui`

File: `monoclaw-developer/hatch/build.sh`

Inside `stage_runtime_tui`, after the rsync into
`dist/vendor/tui/`, before `stage_runtime_tui` returns, run the same
sentinel scan as the runtime regression test but in shell:

```bash
# Refuse to ship a TUI bundle whose lock file claims that a non-existent
# monoclaw-* npm package can be fetched from the public registry. This
# guards against a recurrence of the May 2026 Hermes->MonoClaw blanket
# find/replace bug (see plans/tui-npm-monoclaw-parser-404-investigation.md).
local lock="${HATCH_DIST_ROOT}/vendor/tui/package-lock.json"
if [[ -f "${lock}" ]]; then
  if grep -Eq '"(monoclaw-[a-z][a-z0-9-]*|@monoclaw/[a-z][a-z0-9-]*)": "\^?[0-9]' "${lock}" \
     || grep -Eq 'registry\.npmjs\.org/(monoclaw-[a-z][a-z0-9-]*|@monoclaw/[a-z][a-z0-9-]*)/' "${lock}"; then
    die "vendor/tui/package-lock.json references fake monoclaw-* packages on the public npm registry — regenerate the lock file from ui-tui/package.json (see plans/tui-npm-monoclaw-parser-404-investigation.md)"
  fi
fi
```

Apply the same probe to `stage_runtime_whatsapp_bridge` since it has
the same shape. Generalise into a `_assert_lock_clean()` helper in
`build.sh` so the two call sites share one implementation.

#### 4.7 Runtime preflight in `_make_tui_argv`

File: `monoclaw-runtime/monoclaw_cli/main.py`

Extend `_preflight_tui_install` (line 1249) with a lock-file probe
that runs *before* `npm install` is invoked:

```python
def _preflight_tui_install(tui_dir: Path) -> Optional[str]:
    """Return an error message when the npm install will obviously fail,
    or ``None`` when it's worth trying.

    ...existing writability check...

    Also scans ``package-lock.json`` for fake MonoClaw npm packages
    that point at the public registry. Catches the May 2026 rebrand
    corruption (see plans/tui-npm-monoclaw-parser-404-investigation.md).
    """
    try:
        writable = os.access(tui_dir, os.W_OK)
    except OSError:
        return None
    if not writable:
        return (
            f"TUI sources at {tui_dir} are not writable. Check ownership ..."
        )

    lock = tui_dir / "package-lock.json"
    if lock.is_file():
        try:
            data = json.loads(lock.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            data = None
        if isinstance(data, dict):
            for key, pkg in (data.get("packages") or {}).items():
                if key == "" or not isinstance(pkg, dict):
                    continue
                name = pkg.get("name") or key.rsplit("node_modules/", 1)[-1]
                resolved = pkg.get("resolved") or ""
                if (
                    name.startswith(("monoclaw-", "@monoclaw/"))
                    and resolved.startswith("https://registry.npmjs.org/")
                ):
                    return (
                        f"{lock} claims '{name}' is published on the public "
                        f"npm registry, but no such MonoClaw package exists. "
                        f"This is a corrupted bundle — re-run the Hatch "
                        f"installer or regenerate the TUI lock file with "
                        f"`cd ui-tui && rm -rf node_modules package-lock.json "
                        f"&& npm install`."
                    )
    return None
```

This converts the npm 404 (which costs 30+ seconds and dumps
unactionable HTTP traces) into a 50ms local check with a one-line
remediation hint pointing at the actual fix.

Add a companion test in `tests/monoclaw_cli/test_tui_npm_install.py`:

```python
def test_preflight_rejects_fake_monoclaw_packages_on_public_registry(tmp_path):
    """_preflight_tui_install must reject corrupted lock files instead of
    handing them to npm and producing a 404."""
    (tmp_path / "package.json").write_text("{}")
    (tmp_path / "package-lock.json").write_text(
        '{"packages": {"node_modules/monoclaw-parser": {'
        '"name": "monoclaw-parser", '
        '"resolved": "https://registry.npmjs.org/monoclaw-parser/-/monoclaw-parser-0.25.1.tgz"'
        '}}}'
    )
    err = _preflight_tui_install(tmp_path)
    assert err is not None
    assert "monoclaw-parser" in err
    assert "regenerate" in err.lower() or "re-run" in err.lower()
```

---

## 5. Verification Plan

A fresh-Mac install must pass the following on the user's fix branch
before merge:

1. **Source lock is clean**:
   `rg -n 'monoclaw-parser|monoclaw-estree' monoclaw-runtime/ui-tui/package-lock.json`
   → no output.
2. **Sentinel test passes**:
   `cd monoclaw-runtime && scripts/run_tests.sh tests/test_npm_lockfile_no_fake_monoclaw_packages.py`
   → exits 0 (was failing before 4.1).
3. **Hatch build is clean**:
   `cd monoclaw-developer/hatch && bash build.sh` →
   `rg -n 'monoclaw-parser|monoclaw-estree' dist/vendor/tui/package-lock.json`
   → no output.
4. **Build-side guard works**:
   manually re-insert `"monoclaw-parser": "^0.25.1"` into the dist's
   `package-lock.json`, re-run `bash build.sh` → expect `die` from the
   `_assert_lock_clean` helper added in 4.6.
5. **End-to-end install succeeds**: on a Mac with `rm -rf ~/.monoclaw/`,
   - `bash dist/install.sh` exits 0,
   - `monoclaw --tui` launches the Ink TUI without printing
     "Installing TUI dependencies failed".
6. **Runtime preflight is exercised**: on the same Mac, manually
   corrupt the staged `~/.monoclaw/vendor/tui/package-lock.json` to
   re-introduce `monoclaw-parser`, run `monoclaw --tui`, expect the
   new preflight error (not the npm 404).
7. **Full runtime suite passes**: `scripts/run_tests.sh` exits 0,
   including the new packaging + preflight tests.
8. **Hatch tests pass**: `bash hatch/tests/run_tests.sh` exits 0,
   including the new `_assert_lock_clean` assertion (if covered).

---

## 6. Sequencing & Ownership

| Phase | Work item                                                                                | Repo                | P  |
|-------|------------------------------------------------------------------------------------------|---------------------|----|
| 1     | Regenerate `ui-tui/package-lock.json`                                                    | monoclaw-runtime    | P0 |
| 1     | New `tests/test_npm_lockfile_no_fake_monoclaw_packages.py` sentinel test                 | monoclaw-runtime    | P0 |
| 1     | Rebuild Hatch bundle + fresh-Mac smoke (per `hatch/CLAUDE.md`)                           | monoclaw-developer  | P0 |
| 2     | Update `skills/runtime-rebrand.md` with third-party carve-out + inverse audit            | monoclaw-developer  | P0 |
| 2     | Add DO-NOT pitfall to `monoclaw-runtime/AGENTS.md`                                       | monoclaw-runtime    | P0 |
| 3     | `_assert_lock_clean` helper in `hatch/build.sh::stage_runtime_*`                         | monoclaw-developer  | P1 |
| 3     | Lock-file preflight in `monoclaw-runtime/monoclaw_cli/main.py::_preflight_tui_install`   | monoclaw-runtime    | P1 |

Phase 1 + Phase 2 must ship together (one PR pair across the two
repos). Phase 3 can land in a follow-up but should not slip past the
next bundle release. The Phase 2 documentation changes are P0 because
without them the next rebrand pass will silently re-introduce the
same corruption in some other lock file.

---

## 7. Open Questions / Risks

- **Q1 — Lock-file noise vs. correctness in 4.1**. Regenerating
  `ui-tui/package-lock.json` will likely pick up patch-version bumps
  on unrelated transitive deps because the lock has been frozen since
  May. Reviewers will see a large diff. Recommend: in the PR, gate the
  regenerated lock through `npm install --prefer-offline` against a
  cache that was warmed *immediately before* the regeneration, so the
  diff shows only `hermes-parser`/`hermes-estree` restoration plus
  whatever npm chooses to reorder. If a clean reviewer-friendly diff
  is required, do a separate "drift" PR after this one to pick up the
  patch-version bumps in isolation.

- **Q2 — Should we ban any other "branded third-party" identifier
  proactively?** The current carve-out names `hermes-parser` and
  `hermes-estree` explicitly. We could generalise to "any package
  whose `resolved` URL is on `registry.npmjs.org` keeps its upstream
  name no matter what". That stronger rule is what 4.6 and 4.7
  enforce mechanically; the skill text in 4.4 should mirror it.
  Risk: someone publishes a real `@monoclaw/foo` package to npm in
  the future. The check is then a false positive for that one
  package. Resolution: maintain a short allowlist
  (`_PUBLISHED_MONOCLAW_NAMES: set[str] = set()`, currently empty)
  in both the sentinel test and the preflight; grow it deliberately
  as we actually start publishing.

- **Q3 — Do we need to audit the `monoclaw-runtime` Python side for
  the same class of bug?** The skill's audit (`rg -i "hermes"`)
  catches forgotten renames in source files but does not catch
  over-eager renames in third-party identifiers anywhere outside the
  npm lock files. There is no analogous risk in `requirements.txt`
  / `pyproject.toml` because no PyPI package with "hermes" in the
  name is currently a runtime dep. If a future PyPI dep brings one
  in (e.g. `hermes-eth`), the same class of bug is possible — the
  sentinel test in 4.2 should be extended to scan `pyproject.toml`
  and `requirements*.txt` for `monoclaw-*` package names that
  Don't Exist On PyPI. Out of scope for this PR but worth a
  follow-up issue.

- **Q4 — Why is `HATCH_SKIP_RUNTIME_BUILD` defaulting to skipping
  the rebuild on the dev box?** If `build.sh` had run `npm ci`
  against a fresh `node_modules/`, the corruption would have been
  caught at build time, not customer-install time. Worth a separate
  audit of when and why `HATCH_SKIP_RUNTIME_BUILD=1` is the default
  in the dev environment (it shouldn't be in CI). Adjacent issue,
  but the immediate fix here does not depend on resolving it.
