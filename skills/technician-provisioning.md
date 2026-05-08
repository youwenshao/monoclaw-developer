# Technician Provisioning Skill

Use this when designing technician-facing flows or documentation.

## Audience

Technicians are provisioning Macs for non-technical office workers. The flow
should be fast, explicit, and easy to recover during on-site setup.

## Principles

- Show one next action at a time.
- Separate automatic terminal work from manual macOS prompts.
- Prefer readiness checks with clear remediation over long logs.
- Record machine-local diagnostics outside git.
- Never ask technicians to paste secrets into public issue trackers or commits.

## Expected Manual Prerequisites

- Xcode Command Line Tools may require a macOS prompt.
- Docker Desktop may require a GUI install, launch, and permission approval.
- Some privacy permissions may require System Settings interaction.
