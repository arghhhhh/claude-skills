---
description: Export just THIS conversation (a single session) as a zip in the CWD, for merging into another machine
allowed-tools: Bash, PowerShell
---

Export a **single** conversation from `~/.claude/projects/` into the current working directory as a zip archive. Bundles only this session's `<id>.jsonl` and its `<id>/` sidecar subdir (e.g. `subagents/`) — **not** every session in the project. `memory/` is excluded by default (opt in with `--with-memory`). Pairs with `/import-session`, which **merges** the session into the target machine's project without disturbing its other conversations.

Use this instead of `/export-proper` when you only want to move one chat, not the whole project history.

This delegates to the `claude-conversation-transfer` binary — installed by the `claude-skills` installer under `~/.local/share/claude-conversation-transfer/`. **Do not** re-derive the logic from prose; just invoke the binary. It handles encoded-folder-name computation, session selection, archive naming (`claude-convo-session-<encoded>-<YYYYMMDD-HHMMSS>.zip`), and subset bundling.

Steps:

1. Locate the binary:
   - macOS/Linux: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer`
   - Windows: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer.exe`
   - If missing: tell the user to run the `claude-skills` installer and pick the `claude-conversation-transfer` group.

2. Determine which session to export:
   - **Default = the current conversation.** Pass its id via `--session "$CLAUDE_CODE_SESSION_ID"` (this env var holds the running session's uuid, which is the `<id>.jsonl` filename). If the env var is somehow empty, omit `--session` — the binary then defaults to the most-recently-modified session in the folder, which is the active one.
   - If the user asks to export a *different* chat, pass that uuid as `--session <id>` instead.
   - If the user wants the shared memory bundled too, add `--with-memory`.

3. Run it from the shell CWD with `--json` and parse the report:
   - Bash: `"$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer" export-session --session "$CLAUDE_CODE_SESSION_ID" --json`
   - PowerShell: `& "$HOME\.local\share\claude-conversation-transfer\claude-conversation-transfer.exe" export-session --session $env:CLAUDE_CODE_SESSION_ID --json`

4. Report from the JSON fields: `archive` path, `size_bytes`, the `session_id` bundled, `has_sidecar` (whether an `<id>/` subdir came along), and `has_memory`. Tell the user to move the zip to the other machine and run `/import-session` there.

Do not delete or modify the original project folder.
