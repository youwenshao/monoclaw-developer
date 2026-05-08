# Website Refresh Skill

Use this when modifying `../monoclaw-web`.

## Positioning

The website should speak to Hong Kong white-collar office workers buying a
personal executive secretary service on a provisioned Mac mini or iMac. Assume
non-technical readers and explain complicated software through outcomes,
examples, screenshots, and step-by-step documentation.

## Guardrails

- Do not reuse old engine claims that no longer apply.
- Emphasize local inference, technician provisioning, privacy, and practical
  office workflows.
- Keep checkout/admin functionality separate from marketing copy changes.
- Preserve multilingual structure unless a plan explicitly changes it.

## Verification

```bash
cd ../monoclaw-web
npm run test
npm run build
```
