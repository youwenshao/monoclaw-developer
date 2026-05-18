# Mona Tools Pack `verify_command` — Implementation Plan

## Context

`hatch/build.sh` emits one warning per Mona-secretary tool that lacks a
`verify_command` in its manifest entry:

```text
[tools-pack] Checking optional Mona secretary tools pack
  warn: wacrawl has no verify_command in manifest (add one for behavioral verification)
  warn: slacrawl has no verify_command in manifest (add one for behavioral verification)
  warn: summarize has no verify_command in manifest (add one for behavioral verification)
  warn: macos-automator-mcp has no verify_command in manifest (add one for behavioral verification)
  warn: conduit-mcp has no verify_command in manifest (add one for behavioral verification)
  warn: ghcrawl has no verify_command in manifest (add one for behavioral verification)
  ok: Tools pack verified for mona-secretary-tools (62681 files)
```

The verifier in `hatch/lib/common.sh::verify_tools_pack_manifest` looks for a
`verify_command` list per tool entry in `tools-pack-manifest.json`. The field is
**never written today** because the manifest pipeline strips everything not in
its fixed allow-list:

```text
bundle-inputs/vendor/mona-tools/source-lock.json
  └─ prepare_mona_tools_inputs.sh           (clones, builds, copies to prebuilt/)
       └─ writes tool-lock.json via lock_common()  ← drops unknown fields
           └─ build_mona_tools_pack.sh
                └─ encodes each tool as "name:version:path:activation:permissions"
                     └─ generate_tools_pack_manifest.py::parse_tool()
                          └─ writes tools-pack-manifest.json (no verify_command)
                               └─ lib/common.sh verifier ⇒ "no verify_command... warn"
```

The same `verify-tools-pack` verifier is also invoked at install time on the
customer Mac (via `bin/hatch verify`), so the contract change must hold in
both contexts.

## Locked decisions

| Decision | Locked to |
|---|---|
| Source reconnaissance | Clone all three uncertain tools at pinned refs into `/Users/admin/Projects/steipete-tool-eval/` and inspect entrypoints |
| Wire format | `--tools-file <path>` — single JSON list argument; deprecate legacy `--tool name:…` colon args after one release |
| Failure semantics | Per-tool `verify_strict` boolean (default `false`) + `HATCH_TOOLS_PACK_STRICT_VERIFY=1` env gate set by `build.sh` |
| MCP server handling | `verify_skip_reason: "<text>"` silences the "no verify_command" warning honestly when no non-blocking probe exists |
| Scope | Mona tools pack + skill-deps pack + `monoclaw --version` / `monoclaw doctor` probes wired into `hatch run_verify` |
| Delivery | Phase 0 (reconnaissance) lands first; remaining phases gated on Phase 0 report review |

## Schema changes

### `source-lock.json` per tool

```jsonc
{
  "name": "wacrawl",
  "version": "0.2.0",
  // ... existing fields ...
  "verify_command": ["{bin}", "--version"],
  "verify_strict": true,
  "verify_env": { "GHCRAWL_NODE_REEXEC": "1" },  // optional, env injected at probe time
  // OR, when no non-blocking probe exists:
  "verify_skip_reason": "MCP server has no non-blocking probe; verified via integration test"
}
```

- `{bin}` is substituted with the staged binary's absolute path by
  `lib/common.sh`.
- `verify_command` and `verify_skip_reason` are mutually exclusive; the
  verifier rejects manifests that set both.
- `verify_env` is optional and **additive** to the process environment used
  at probe time. Required today for `ghcrawl` (to short-circuit a `nodenv`
  reexec path in the upstream `apps/cli/bin/ghcrawl.js` that can otherwise
  pick a non-bundled Node when the build host has `nodenv` installed). Kept
  as a generic mechanism for future env-sensitive CLIs.

### `tools-pack-manifest.json` per tool entry

Same fields, passed through verbatim.

### Compatibility

- Manifests without any of the new fields keep emitting the existing
  "no verify_command" warn (one release of deprecation), then the verifier
  upgrades that to an error in a later release once every shipped pack carries
  either `verify_command` or `verify_skip_reason`.
- `generate_tools_pack_manifest.py` retains the legacy `--tool name:version:…`
  colon arg for one release with a deprecation warning, then it is removed.

## Strictness model

| Context | Mode | Behavior |
|---|---|---|
| `build.sh` build host | strict (`HATCH_TOOLS_PACK_STRICT_VERIFY=1`) | `verify_strict: true` non-zero exit ⇒ hard fail. `verify_strict: false` non-zero ⇒ warn (current text). No-probe + no-skip-reason ⇒ hard fail. |
| `install.sh` customer Mac | lenient (env unset) | `verify_strict: true` non-zero ⇒ hard fail (the binary should be self-contained). `verify_strict: false` non-zero ⇒ warn with the current "permissions may require monoclaw setup system" text. |

`FileNotFoundError` (binary not executable) already fails the build at both
contexts and is kept as-is.

## Tool-by-tool probe table (Phase 0 complete)

Determinations after cloning each Mona tool at the pinned `source-lock.json`
ref into `/Users/admin/Projects/steipete-tool-eval/` and inspecting source.

| Tool | Mode | Probe | Strict | Env | Skip reason | Evidence |
|---|---|---|---|---|---|---|
| `wacrawl` | go-binary | `["{bin}", "--version"]` | true | — | — | `internal/cli/version.go` exists; README documents `--version` as a Global Flag. No host permissions needed for `--version`. |
| `slacrawl` | go-binary | `["{bin}", "--version"]` | true | — | — | `internal/cli/render.go:74` documents `--version`; `.github/workflows/ci.yml:97` tests `./bin/slacrawl --version` exits zero. |
| `summarize` | node-app | `["{bin}", "--version"]` | true | — | — | `src/run/runner.ts:54` early-exits via `handleVersionFlag` before any LLM / daemon work; `src/run/help.ts:174` declares `-V, --version` via commander. |
| `ghcrawl` | node-app | `["{bin}", "--version"]` | true | `{"GHCRAWL_NODE_REEXEC": "1"}` | — | `apps/cli/src/main.ts:164` short-circuits on `--version`/`-v`; `apps/cli/src/main.test.ts:166` asserts it. The wrapper `apps/cli/bin/ghcrawl.js` attempts `nodenv which node` reexec when `.node-version` is present — `GHCRAWL_NODE_REEXEC=1` skips that branch and keeps the probe pinned to the bundled `node/current/bin/node`. |
| `macos-automator-mcp` | node-app | — | — | — | `"MCP server has no non-blocking argv probe; entrypoint immediately calls main() → StdioServerTransport. Behavioral verification deferred to a runtime MCP integration check."` | `src/server.ts` has zero `process.argv` handling; `main()` instantiates `McpServer` then awaits `transport.connect()`. No `--help` short-circuit. |
| `conduit-mcp` | node-app | — | — | — | `"MCP server has no non-blocking argv probe; entrypoint constructs Server at module scope and binds StdioServerTransport. Behavioral verification deferred to a runtime MCP integration check."` | `src/mcp-server.ts:29` constructs `new Server(...)` at module load; no `process.argv` handling anywhere in `src/`. |

### Skill-deps pack audit (Phase 5 scope correction)

The skill-deps pack uses a **different and simpler** packaging pipeline than
the Mona pack:

- `scripts/build_skill_deps_pack.sh` only validates `tool-lock.json` SHAs and
  copies prebuilt artifacts into `tool-packs/skill-deps-pack/`.
- It does **not** generate `tools-pack-manifest.json` and does **not** call
  `verify-tools-pack`. There is no `[skill-deps] Checking ...` step in
  `build.sh` output, which is why no warnings appear today.
- The pack is consumed at install time directly by
  `templates/install-skill-deps.sh`, with no Hatch-side behavioral
  verification of the bundled binaries.

This means **Phase 5 as originally scoped is materially bigger than Phases
1–4**: it requires teaching skill-deps to (a) generate a parallel manifest
format and (b) wire a verifier. Recommendation: split Phase 5 into a
separate plan (`plans/skill-deps-verification-parity.md`) and ship Phases
1–4 (Mona) + Phase 6 (`run_verify`) first. The original Phase 5 in this
plan is deferred.

`remindctl` / `memo` / `imsg` / `himalaya` all support `--version` / `status`
per their published docs and skill READMEs — the probe semantics are easy;
the missing piece is the manifest scaffolding.

## Phased implementation

### Phase 0 — Reconnaissance (read-only)

Output: a per-tool determination table (probe argv + strict flag + optional
skip-reason), posted in chat for review before Phase 1.

```bash
mkdir -p /Users/admin/Projects/steipete-tool-eval
cd /Users/admin/Projects/steipete-tool-eval

git clone https://github.com/steipete/summarize.git
git -C summarize checkout f4a72c2109939eea83c4673d0be1b1599d17f17d

git clone https://github.com/steipete/macos-automator-mcp.git
git -C macos-automator-mcp checkout 6a9ba83d157d9d47639cc621b03488e3b71b7670

git clone https://github.com/steipete/conduit-mcp.git
git -C conduit-mcp checkout b6aceabb101ca961fe749137c9bd42cc201b5c66
```

For each: inspect `package.json` `bin:` entry + entrypoint source for
`--version` / `--help` short-circuit handling. Identify any daemon side
effects. Audit
`bundle-inputs/vendor/skill-deps/source-lock.json` (or the equivalent) for
the same `verify_command` gap. Do NOT touch any repo files.

### Phase 1 — Generator + verifier contract change (no tool data yet)

- `hatch/scripts/generate_tools_pack_manifest.py`:
  - Accept `--tools-file <path>` reading a JSON list. Each entry carries
    `name`, `version`, `path`, `activation`, `required_permissions`,
    `verify_command?`, `verify_strict?`, `verify_skip_reason?`.
  - Keep legacy `--tool name:…` colon args for one release with a
    `DeprecationWarning` on stderr.
  - Emit the new fields verbatim into `tools-pack-manifest.json`.
- `hatch/lib/common.sh::verify_tools_pack_manifest`:
  - Implement `verify_strict` (default false) — non-zero exit ⇒ `SystemExit`
    when strict, warn when lenient.
  - Implement `verify_skip_reason` — silences the "no verify_command" warn,
    prints a one-line `info: <name> verify skipped: <reason>` instead.
  - Reject manifests that set both `verify_command` and `verify_skip_reason`.
  - Honor `HATCH_TOOLS_PACK_STRICT_VERIFY=1` env var to enable strict mode.
- Tests in `tests/hatch_mona_tools_pack_tests.sh` (or new file):
  - JSON `--tools-file` round-trips all fields.
  - Strict-true + non-zero exit ⇒ hard fail; strict-false + non-zero ⇒ warn.
  - `verify_skip_reason` set ⇒ no warn.
  - Legacy colon `--tool` still works (with deprecation warning).

### Phase 2 — Propagate through prepare + build (Mona pack)

- `prepare_mona_tools_inputs.sh::lock_common()` carries
  `verify_command` / `verify_strict` / `verify_skip_reason` from
  `source-lock.json` into `tool-lock.json`.
- `build_mona_tools_pack.sh`:
  - Replace the colon-encoded heredoc with a JSON file written from
    `.mona-tools-active.json`.
  - Call `generate_tools_pack_manifest.py --tools-file <path>`.
- Tests: source-lock with probe fields ⇒ probe lands in
  `tools-pack-manifest.json`.

### Phase 3 — Real probes (Mona pack)

- Apply Phase 0 determinations to `bundle-inputs/vendor/mona-tools/source-lock.json`
  and `bundle-inputs/vendor/mona-tools/tool-lock.example.json`.
- Run real build (`bash build.sh`); confirm zero "no verify_command" warnings.

### Phase 4 — Build-time strictness gate

- `build.sh` exports `HATCH_TOOLS_PACK_STRICT_VERIFY=1` for the
  `verify-tools-pack` step.
- Test: fixture with `verify_strict: true` + exit-1 binary ⇒ build fails in
  strict, warns in lenient.

### Phase 5 — Skill-deps pack parity (deferred — needs its own plan)

After Phase 0 audit, this is a bigger contract change than Phases 1–4. The
skill-deps pack today **does not generate a manifest and does not call
`verify-tools-pack`**. Adding probes requires:

- Designing a parallel manifest contract for the skill-deps pack (or
  retrofitting it into the same `tools-pack-manifest.json` shape Mona uses).
- A separate `verify_skill_deps_pack` function in `lib/common.sh`, or
  generalizing `verify_tools_pack_manifest` to span both packs.
- Updating `templates/install-skill-deps.sh` to call the new verifier.

Recommendation: ship this as a follow-up plan
(`plans/skill-deps-verification-parity.md`) once Phases 1–4 + Phase 6 are
stable.

### Phase 6 — Hatch `run_verify` upgrade

`hatch/bin/hatch::run_verify` currently is all `test -e` / `test -x`. Add
behavioral probes:

- `~/.monoclaw/vendor/python/current/bin/python3 -c "import monoclaw_runtime"`
  (proves the runtime venv is importable).
- `monoclaw --version` (proves the CLI entrypoint works).
- For each installed pack, run its bundled `verify_command` from the
  install-time location (re-uses Phase 1's verifier function).
- Hook `monoclaw doctor` if/when it exists (per
  `plans/mona-tool-availability-investigation.md` Part F item 6 the
  doctor command is a follow-up of its own).
- Tests: assert each probe runs and that any failure aborts `run_verify`
  with a clear actionable message.

### Phase 7 — Docs

- Update `hatch/docs/verification-gates.md` with the new schema + the
  build-vs-install strictness rules.
- Update `bundle-inputs/vendor/mona-tools/README.md` and
  `bundle-inputs/vendor/skill-deps/README.md` to document the contract for
  newly added tools.
- Add an entry to `hatch/CLAUDE.md` under "Required Verification For
  Dependency Changes" mandating a probe for every new go-binary / node-app
  tool.

## Risk register

| Risk | Mitigation |
|---|---|
| `summarize --version` runs the autostart daemon as a side effect | **Resolved in Phase 0**: `src/run/runner.ts:54` early-exits via `handleVersionFlag` before any daemon / LLM work |
| MCP servers don't have a `--help` short-circuit and we ship with no real probe | **Resolved in Phase 0** (confirmed for both `macos-automator-mcp` and `conduit-mcp`): use `verify_skip_reason` — honest, doesn't pretend to verify. Adding real MCP-initialize probes is a separate, larger feature |
| `ghcrawl` probe accidentally uses a non-bundled Node when the build host has `nodenv` installed | **Resolved in Phase 0**: probe must pass `GHCRAWL_NODE_REEXEC=1` via the new `verify_env` field, which short-circuits the nodenv reexec branch in `apps/cli/bin/ghcrawl.js` |
| Probe takes >10s on cold first run (node startup on the bundled runtime) | Current `subprocess.run(..., timeout=10)` is generous; bump to 15s for `node-app` if observed during Phase 1 |
| Legacy callers in CI / other scripts pass colon strings | Backward compatibility in `parse_tool()` keeps them working for one release; deprecation warning surfaces them |
| Strict mode in `build.sh` breaks the release pipeline if Phase 0 misidentifies a probe | Land Phase 4 only after Phase 3 ships and one green release with the new probes in lenient mode |
| Build host doesn't have Node installed but `node-app` probes need it | The pack ships `node/current/bin/node` and the `bin/<name>` wrappers shebang into it — already self-contained at pack root |
| Stale-branch squash merge silently reverts other fixes (per `hatch/CLAUDE.md` known pitfalls) | Rebase any feature branch onto `main` and verify `git diff HEAD~1..HEAD` before squash |

## Out of scope here

- Other "lazy target-mac fixup" issues called out in
  `plans/mona-tool-availability-investigation.md` (web-search backend, Hatch
  DYLD path manipulation).
- Promoting `vox` / `brabble` / `sweetlink` / `birdclaw` from `mode: deferred`.
- Implementing a `monoclaw doctor` command from scratch — Phase 6 only hooks
  it if it exists.

## Test plan summary

| Phase | New tests |
|---|---|
| 1 | JSON tools-file round-trip; strict-true fail; strict-false warn; skip-reason silence; legacy colon path |
| 2 | source-lock with probe fields ⇒ probe in built manifest |
| 3 | Real `bash build.sh` produces zero warnings |
| 4 | Fixture strict-true + exit-1 binary ⇒ build fails |
| 5 | Skill-deps pack: same coverage |
| 6 | `hatch run_verify` runs probes and fails on bad state |

All tests live under `hatch/tests/` and run via `bash tests/run_tests.sh` per
`hatch/CLAUDE.md`. Per `monoclaw-runtime/AGENTS.md`, runtime-side changes
(Phase 6 if it touches the runtime CLI) also need
`scripts/run_tests.sh` on the runtime side.
