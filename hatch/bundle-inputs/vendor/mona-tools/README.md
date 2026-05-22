# Mona Secretary Tools Bundle Inputs

This directory is the staging contract for the optional Hatch sidecar pack
`tool-packs/mona-secretary-tools`.

The pack is built by default. Set `HATCH_INCLUDE_MONA_TOOLS=0` only when
intentionally producing a core-runtime-only bundle. When enabled,
`scripts/build_mona_tools_pack.sh` (called from `build.sh`) copies artifacts
named by `tool-lock.json` into the sidecar pack. If `tool-lock.json` is absent
but `source-lock.json` is present, the build runs `scripts/prepare_mona_tools_inputs.sh`
first to generate `tool-lock.json` and `prebuilt/` (you can still run that script by
hand when you want to regenerate without a full bundle build).

The generated `install.sh` runs the core MonoClaw runtime provisioning first and
then invokes `install-mona-tools.sh` as a best-effort post-step. Set
`HATCH_INSTALL_MONA_TOOLS=0` on the target Mac to skip that post-step.

Do not rely on Homebrew on the **customer** Mac—the customer bundle does not invoke
vendor installers during install-time provisioning. Separate **release build**
machines are expected to satisfy `prepare_mona_tools_inputs.sh` prerequisites (`git`,
Go, Node/pnpm, etc.). To reduce friction there, Hatch may run **`brew install go`**
or **`brew install pnpm`** on **macOS build hosts only** when those tools are absent;
disable with **`HATCH_MONA_AUTOINSTALL_GO=0`** or **`HATCH_MONA_AUTOINSTALL_PNPM=0`**. `git` clones, `pnpm`/`go` builds, and
Node package installs still run strictly on those build hosts, not inside the shipped sidecar bundle.

## Preparing Build Inputs

`tool-lock.json` and `prebuilt/` are generated release inputs and are ignored by
git. Running `build.sh` creates them automatically when missing (see prerequisites
below). On **macOS** build hosts Hatch will **`fetch`** the pinned official Node tarball
(from `nodejs.org/dist/v...`) matching `node.version`, cache unpacked trees under **`hatch/.mona-node-dist-cache/`**
(layout `darwin-<arch>/node-v…`), populate `HATCH_MONA_NODE_RUNTIME_SOURCE` unless you override it explicitly.
Redirect the cache directory with **`HATCH_MONA_NODE_DOWNLOAD_CACHE`** (absolute path or path relative to the Hatch checkout root passed as `--hatch-root`). Outside macOS—or offline—provide the unpacked runtime yourself (**`export`** the variable referenced by **`node.source_env`**). Opt out with **`HATCH_MONA_NODE_AUTO_DOWNLOAD=0`**.

You can also generate inputs explicitly before a bundle build:

```bash
cd hatch
# Optional: omit when auto-download suffices on Darwin
HATCH_MONA_NODE_RUNTIME_SOURCE=/path/to/node-26-darwin \
  HATCH_MONA_TOOLS_FORCE=1 \
  bash scripts/prepare_mona_tools_inputs.sh
bash build.sh
```

The checked-in `source-lock.json` pins the upstream repositories and records the
build recipe. The prep script clones those exact refs into `.mona-tools-build/`,
builds Go tools for `darwin/${HATCH_TARGET_ARCH}`, builds Node apps with their
pinned package manager, copies the bundled Node runtime into
`prebuilt/node/current`, and writes the real `tool-lock.json` consumed by
`scripts/build_mona_tools_pack.sh`.

Builder prerequisites are intentionally **build-machine-only**:

- `git`
- Go matching upstream tool versions (Darwin build hosts lacking `go`: auto-install via Homebrew unless **`HATCH_MONA_AUTOINSTALL_GO=0`**)
- **`pnpm`** (Darwin: auto-install via Homebrew unless **`HATCH_MONA_AUTOINSTALL_PNPM=0`**)
- Node 26 runtime directory containing `bin/node` (Darwin auto-fetch documented above)

The target Mac receives only the verified sidecar pack. It does not run Go,
Node package managers, Homebrew, `npx`, or network fetches for these tools.

Recommended V1 contents:

- `wacrawl` darwin binary
- `slacrawl` darwin binary
- bundled Node runtime under `prebuilt/node/current`
- built `summarize` app
- built `macos-automator-mcp` app
- opt-in built `vox` app for an operator-supervised phone bridge service
- optional built `conduit-mcp` and `ghcrawl` apps
- `templates/` docs, config examples, and plugin skeleton (skills ship via `monoclaw-runtime/skills/`)

Keep secrets out of this directory. Slack, WhatsApp, GitHub, Google, OpenAI,
Twilio, and X/Twitter credentials belong in customer configuration, never in
the release bundle.
