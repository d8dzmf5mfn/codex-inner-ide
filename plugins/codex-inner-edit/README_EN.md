# Codex Inner Edit

Companion plugin for Codex Inner IDE. It sends the active Python file or selection to an isolated read-only Codex turn, then displays the proposal as an inline Monaco diff.

- `Enter`: apply to the editor buffer without writing the file.
- `Esc`: reject the proposal.
- `⌘S`: explicitly save after acceptance.
- MCP tool results never return source code to the originating Codex task.

Install and launch Codex Inner IDE v0.3.0 or later first. The launcher searches `~/Applications` and `/Applications`; set `CODEX_INNER_IDE_APP` for another location.

For development, register this repository marketplace with Codex and install `codex-inner-edit@codex-inner-ide`. Start a new task after plugin updates so Codex reloads the Skill and MCP tools.
