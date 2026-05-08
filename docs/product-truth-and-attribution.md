# MonoClaw Product Truth And Attribution

## Purpose

MonoClaw is a technician-provisioned executive secretary service for office
workers in Hong Kong. The customer experience is a managed Mac mini or iMac
running MonoClaw locally, with documentation and operator support designed for
non-technical users.

This document is the cross-repository rule for the current refresh. It keeps the
runtime, Hatch installer, website, legal content, and operator documentation in
sync while the old engine story is replaced.

## Product Truth

- User-facing names, commands, documentation, screenshots, contracts, support
  copy, and operator checklists must say **MonoClaw**.
- Hatch is the technician-facing installer and provisioning workflow for the
  refreshed service.
- Customer Macs should be described as local-first systems: bundled runtime,
  bundled local inference support, bundled skills, and explicit opt-in for any
  cloud provider or third-party integration.
- The default customer story is practical office assistance: messages, calendar,
  documents, research, browser-assisted workflows, reminders, and guided
  administrative work.
- Claims must distinguish assembly-time requirements from target-Mac
  requirements. Homebrew or network fetches used to build a prepared bundle are
  not customer-runtime dependencies.

## Attribution Rule

MonoClaw Runtime is derived from Nous Research Hermes Agent under the MIT
license. That provenance must remain in legal and upstream attribution files.

Allowed Hermes/Nous references:

- `monoclaw-runtime/LICENSE`
- `monoclaw-runtime/NOTICE.md`
- `monoclaw-runtime/UPSTREAM.md`
- Third-party license files and immutable upstream audit notes

Disallowed Hermes/Nous references:

- Marketing pages, onboarding, docs, screenshots, support copy, and operator
  handbooks
- CLI banners, help text, setup copy, installer prompts, and gateway messages
- Website checkout copy, contracts, translations, and admin UI labels
- New Hatch logs, unless detecting a legacy install; use `legacy runtime` in
  technician-facing messages

## Repository Responsibilities

- `monoclaw-developer` owns this policy, Hatch scaffolding, operator plans, and
  cross-repository coordination.
- `monoclaw-runtime` owns the MonoClaw runtime, CLI, gateway, toolsets,
  packaging metadata, bundled skills, and runtime docs.
- `monoclaw-web` owns the product website, checkout/admin UI, legal HTML,
  Supabase migrations, and public/operator documentation.
- `scuttle-reference` remains a private historical reference for bundle,
  launchd, reset, and bench-test patterns. Do not expose Scuttle as a product
  name in refreshed customer copy.

## Change Control

When product claims, installer behavior, legal copy, or contract-shaped data
change, update all affected surfaces in the same branch:

1. This policy or the more specific implementation contract.
2. Runtime behavior and docs.
3. Hatch installer behavior and operator docs.
4. Website marketing, legal source HTML, translations, and Supabase seed data.
5. Verification gates proving the claim.

Do not ship a claim that is only true in one repository.
