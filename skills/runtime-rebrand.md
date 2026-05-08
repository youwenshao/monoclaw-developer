# Runtime Rebrand Skill

Use this when modifying `../monoclaw-runtime`.

## Checklist

- Preserve `LICENSE`, `NOTICE.md`, and `UPSTREAM.md`.
- Treat remaining Hermes references as bugs unless they are in legal attribution,
  upstream audit notes, or third-party license text.
- Keep public commands on the MonoClaw surface: `monoclaw`, `monoclaw-agent`,
  `monoclaw-acp`, and `monoclaw-gateway`.
- Prefer local-first defaults and avoid adding cloud-only provider assumptions.
- Run an identity audit before handing off:

```bash
rg -i "hermes|ai\\.hermes|~/.hermes|hermes-agent" ../monoclaw-runtime
```

Every remaining hit must be classified in the handoff.
