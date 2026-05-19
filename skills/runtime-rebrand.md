# Runtime Rebrand Skill

Use this when modifying `../monoclaw-runtime`.

## Checklist

- Preserve `LICENSE`, `NOTICE.md`, and `UPSTREAM.md`.
- Treat remaining Hermes references as bugs unless they are in legal attribution,
  upstream audit notes, or third-party license text.
- Keep public commands on the MonoClaw surface: `monoclaw`, `monoclaw-agent`,
  `monoclaw-acp`, and `monoclaw-gateway`.
- Prefer local-first defaults and avoid adding cloud-only provider assumptions.
- **Never rename third-party package identifiers (npm, PyPI, etc.).** Some
  upstream Hermes deps have "hermes" in their name but are published by
  Meta or other third parties and we do not own them. Renaming any of
  them silently produces shipped lock files that 404 at customer
  `npm install` / `pip install` time, because no MonoClaw-namespaced
  equivalent exists. Today the known-immutable npm packages are:

  - `hermes-parser` (Meta — <https://www.npmjs.com/package/hermes-parser>)
  - `hermes-estree` (Meta)
  - any other package whose `resolved` URL is on
    `https://registry.npmjs.org/` — third-party by definition

  When in doubt, check `https://registry.npmjs.org/<name>`: if it
  returns 200, it is a third-party identifier and must not be renamed
  in any `package.json`, `package-lock.json`, or equivalent.

  See `plans/tui-npm-monoclaw-parser-404-investigation.md` for the
  May 2026 incident where this rule was violated.

- Run **both** audits before handing off. The forward audit catches
  forgotten renames; the inverse audit catches over-eager renames that
  hit third-party identifiers.

  **Forward audit** (leftover upstream references that should have been
  rebranded):

  ```bash
  rg -i "hermes|ai\\.hermes|~/.hermes|hermes-agent" ../monoclaw-runtime
  ```

  **Inverse audit** (fake MonoClaw npm identifiers that the rebrand
  blindly invented; should always return zero hits outside legitimate
  `file:` deps like `@monoclaw/ink`):

  ```bash
  rg -n '"(monoclaw-[a-z][a-z0-9-]*|@monoclaw/[a-z][a-z0-9-]*)":' \
    ../monoclaw-runtime --type json \
    | rg -v "/node_modules/" \
    | rg -v '"file:'
  ```

  ```bash
  rg -n 'registry\.npmjs\.org/(monoclaw-|@monoclaw/)' ../monoclaw-runtime
  ```

  Every remaining hit from either audit must be classified in the
  handoff. Untriaged `monoclaw-*` identifiers in shipped lock files
  are bugs and will be caught by
  `tests/test_npm_lockfile_no_fake_monoclaw_packages.py` in CI.
