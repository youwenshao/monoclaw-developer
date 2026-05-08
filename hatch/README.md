# Hatch

Hatch is the MonoClaw provisioning installer for technician-operated Mac setup.
It is designed for fresh factory-configured Mac mini and iMac devices, while
also supporting rapid repeated test runs on CI or bench machines by detecting
and stopping existing runtimes before installation.

This initial scaffold is intentionally dry-run-first. It establishes the
operator contract, preflight detection, and lifecycle hooks that future tasks
will expand into dependency installation, model staging, runtime installation,
and readiness verification.

## Commands

```bash
bash hatch/bin/hatch --dry-run preflight
bash hatch/bin/hatch --dry-run cleanup-existing
bash hatch/bin/hatch --dry-run install
```

Hatch defaults to dry-run. Pass `--apply` only when running on a machine intended
for provisioning.

## Runtime Artifact Contract

Hatch is bundle-first. The target Mac install path is defined in
`docs/runtime-artifacts.md`: assembly machines create a prepared `dist/` bundle,
Hatch verifies `hatch-manifest.json`, and customer Macs receive managed files
under `~/.monoclaw/vendor` while preserving `~/.monoclaw/customer`.

## Verification

```bash
bash hatch/tests/run_tests.sh
```

Release evidence and physical bench expectations are listed in
`docs/verification-gates.md`.

## Design Goals

- Make terminal-manageable setup automatic.
- Explain manual prerequisites such as Xcode CLT prompts and Docker Desktop.
- Keep local model weights and vendor bundles in managed directories.
- Stop and uninstall existing MonoClaw or legacy runtime services before
  replacing runtime files.
- Produce clear readiness checks for technicians instead of requiring them to
  read long logs.

## Non-Goals For This Scaffold

- It does not download LLM weights yet.
- It does not install Homebrew packages yet.
- It does not mutate launchd services unless dry-run is disabled and a future
  implementation fills in the install steps.
