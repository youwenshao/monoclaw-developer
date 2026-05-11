# Mona Secretary Tools Pack

This optional pack installs local secretary-oriented tools under
`~/.monoclaw/vendor/mona-tools`.

Default V1 tools:

- `wacrawl`: local WhatsApp Desktop archive/search.
- `slacrawl`: local Slack archive/search/digest.
- `summarize`: URL, file, PDF, audio, and video summarization CLI.
- `macos-automator-mcp`: opt-in macOS AppleScript/JXA MCP server.

Optional modules may be present but disabled by default:

- `conduit-mcp`
- `ghcrawl`

Deferred modules require separate product gates:

- `vox`
- `brabble`
- `sweetlink`
- `birdclaw`

The pack does not grant host permissions or write customer secrets. Review
`permissions.md` before enabling host automation, browser, social, telecom, or
workspace integrations.
