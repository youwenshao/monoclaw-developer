# Vox Phone Bridge

`vox` is packaged as an opt-in service recipe, not as a default MonoClaw agent
tool. It bridges Twilio Media Streams to OpenAI Realtime and can call back into a
local MonoClaw-facing endpoint through either `VOX_AGENT_URL` or
`VOX_AGENT_CMD`.

Use this only after the operator has reviewed telecom consent, call disclosure,
recording rules, and the public HTTPS route that Twilio will reach.

## Required Operator Inputs

- `OPENAI_API_KEY`
- `VOX_PUBLIC_BASE_URL`
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- One of:
  - `VOX_AGENT_URL`
  - `VOX_AGENT_CMD`

## Local Smoke Check

```bash
~/.monoclaw/vendor/mona-tools/bin/vox serve --host 127.0.0.1 --port 3000
curl http://127.0.0.1:3000/health
```

Configure Twilio voice webhooks only after the health check passes and the public
HTTPS tunnel maps to the same local server.
