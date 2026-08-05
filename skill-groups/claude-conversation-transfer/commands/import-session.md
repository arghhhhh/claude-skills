---
description: Merge a single-session claude-convo-session zip from CWD into this machine's project, without touching other chats
allowed-tools: Bash, PowerShell, Glob
---

Import a `claude-convo-session-*.zip` (produced by `/export-session`) sitting in the current working directory into `~/.claude/projects/`, **merging** the one conversation into the project folder for the **current** CWD. Unlike `/import-proper`, this does **not** back up and replace the whole folder — every other session already on this machine is left untouched. Pairs with `/export-session`.

Use this to add a single chat that was exported from another machine. If a session with the same id already exists here, the old copy is moved aside to a `.bak-<timestamp>` (never deleted), not silently overwritten.

This delegates to the `claude-conversation-transfer` binary — installed by the `claude-skills` installer under `~/.local/share/claude-conversation-transfer/`. The binary handles the historically-brittle work: in-archive source-CWD detection, encoded-folder-name computation, same-id collision backup, in-process byte-level path rewriting (no shell argv → no backslash-collapse bug), tail-separator conversion scoped to path tokens only, add-only `memory/` merge, and post-merge JSON verification. **Do not** re-derive any of this from prose.

Steps:

1. Glob the CWD for the archive — both hyphen and underscore prefix variants, case-insensitive: `claude-convo-session-*.zip` and `claude_convo_session_*.zip`.
   - None: stop and report. (If the user meant a full-project zip, `claude-convo-export-*.zip`, point them at `/import-proper` instead.)
   - Multiple: list with sizes/mtimes and ask which to import.

2. Locate the binary:
   - macOS/Linux: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer`
   - Windows: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer.exe`
   - If missing: tell the user to run the `claude-skills` installer and pick the `claude-conversation-transfer` group.

3. Run it from the shell CWD with `--json` against the chosen zip:
   - Bash: `"$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer" import-session "<zip>" --json`
   - PowerShell: `& "$HOME\.local\share\claude-conversation-transfer\claude-conversation-transfer.exe" import-session "<zip>" --json`

4. Report from the JSON fields:
   - `target` path and the `session_id` merged in
   - `target_preexisted`: if true, other sessions on this machine were kept; if false, a fresh project folder was created for this CWD
   - `session_backup` (if non-empty): a session with this id already existed and was moved aside to this `.bak-*` path — tell the user it was preserved, not overwritten
   - `memory_conflicts` (if non-empty): these memory files already existed and the incoming copies were written alongside as `<name>.incoming-*` — the user should merge them manually
   - Source vs target: `source_cwd` (`source_os`) → `target_cwd` (`target_os`)
   - If `files_rewritten > 0`: report the count, and `tail_conversions` with `tail_direction` for cross-OS imports
   - Verification: `verification.total_ok` and `verification.total_bad` — if `total_bad > 0`, surface the failing file (the binary will also have exited non-zero). **Do not** declare success when verification fails — the Claude Code session list can populate even with corrupted `.jsonl` files.

Do not delete the source zip.
