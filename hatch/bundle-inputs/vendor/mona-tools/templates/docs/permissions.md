# Mona Secretary Tools Permissions

Hatch can copy verified artifacts, but macOS and third-party service permissions
must remain explicit user actions.

Do not auto-grant or script these permissions:

- Full Disk Access or Files and Folders access for WhatsApp, Slack, browser, or
  other app containers.
- Automation and Accessibility access for `macos-automator-mcp`.
- Microphone access for wake-word or transcription daemons.
- Local CA trust for browser daemons.
- Slack, GitHub, Google, OpenAI, Twilio, X/Twitter, or other service tokens.
- Call recording, disclosure, or telecom consent workflows.
- Public tunnel or HTTPS exposure for `vox` phone bridge callbacks.

Recommended enablement order:

1. Install the pack with `install-mona-tools.sh`.
2. Run the relevant tool's `doctor` or `--help` command.
3. Add customer secrets through MonoClaw setup or a reviewed config file.
4. Enable MCP servers only after reviewing their path allow-lists and macOS
   permission prompts.
5. Enable the `vox` phone bridge only after configuring call disclosure,
   `VOX_PUBLIC_BASE_URL`, and exactly one reviewed agent callback
   (`VOX_AGENT_URL` or `VOX_AGENT_CMD`).
6. Keep write-capable social, browser, and telecom tools disabled unless the
   customer has explicitly opted in.
