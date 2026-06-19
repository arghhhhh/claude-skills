---
description: Export the current conversation's full project folder (all sessions + memory) as a zip in the CWD
allowed-tools: Bash, PowerShell
---

Export the active project folder from `~/.claude/projects/` into the current working directory as a zip archive. Bundles every session `.jsonl`, session subdir (including `subagents/`), and the `memory/` dir for this project. Pairs with `/import-proper`.

This delegates to the `claude-conversation-transfer` binary — installed by the `claude-skills` installer under `~/.local/share/claude-conversation-transfer/`. **Do not** re-derive the export logic from prose; just invoke the binary. The binary handles encoded-folder-name computation, archive naming (`claude-convo-export-<encoded>-<YYYYMMDD-HHMMSS>.zip`), and bundling.

Steps:

1. Locate the binary:
   - macOS/Linux: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer`
   - Windows: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer.exe`
   - If missing: tell the user to run the `claude-skills` installer and pick the `claude-conversation-transfer` group.

2. Run it from the shell CWD with `--json` and parse the report:
   - Bash: `"$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer" export --json`
   - PowerShell: `& "$HOME\.local\share\claude-conversation-transfer\claude-conversation-transfer.exe" export --json`

3. Report the archive path, size, `.jsonl` count, and whether `memory/` was bundled, from the JSON fields (`archive`, `size_bytes`, `jsonl_files`, `has_memory`).

Do not delete or modify the original project folder.
