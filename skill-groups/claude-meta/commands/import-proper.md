---
description: Import a claude-convo-export zip from CWD into ~/.claude/projects/, retargeted to this machine's CWD
allowed-tools: Bash, PowerShell, Glob
---

Import a `claude-convo-export-*.zip` (or `claude_convo_export_*.zip`) sitting in the current working directory into `~/.claude/projects/`, renaming the project folder to match the **current** CWD so Claude Code recognizes it. Pairs with `/export-proper`.

This delegates to the `claude-conversation-transfer` binary — installed by the `claude-skills` installer under `~/.local/share/claude-conversation-transfer/`. The binary handles all of the historically-brittle work: in-archive CWD detection, encoded-folder-name computation, backup-on-existing-target, in-process byte-level path rewriting (no shell argv → no backslash-collapse bug), tail-separator conversion scoped to path tokens only, and post-rewrite JSON verification. **Do not** re-derive any of this from prose.

Steps:

1. Glob the CWD for the archive — both hyphen and underscore prefix variants, case-insensitive: `claude-convo-export-*.zip` and `claude_convo_export_*.zip`.
   - None: stop and report.
   - Multiple: list with sizes/mtimes and ask which to import.

2. Locate the binary:
   - macOS/Linux: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer`
   - Windows: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer.exe`
   - If missing: tell the user to run the `claude-skills` installer and pick the `claude-conversation-transfer` group.

3. Run it from the shell CWD with `--json` against the chosen zip:
   - Bash: `"$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer" import "<zip>" --json`
   - PowerShell: `& "$HOME\.local\share\claude-conversation-transfer\claude-conversation-transfer.exe" import "<zip>" --json`

4. Report from the JSON fields:
   - `target` path
   - `jsonl_files` imported, `has_memory`
   - `backup` (if non-empty): tell the user it was backed up and they need to manually merge `memory/MEMORY.md`, any per-memory `.md` files, and any `.jsonl` sessions from the backup not present in the imported set
   - Source vs target: `source_cwd` (`source_os`) → `target_cwd` (`target_os`)
   - If `files_rewritten > 0`: report the count, and `tail_conversions` with `tail_direction` for cross-OS imports
   - Verification: `verification.total_ok` and `verification.total_bad` — if `total_bad > 0`, surface the failing files (the binary will also have exited non-zero). **Do not** declare success when verification fails — the Claude Code session list can populate even with corrupted `.jsonl` files.
   - Pass through the `out_of_cwd_ignored` note about paths outside the project CWD.

Do not delete the source zip.
