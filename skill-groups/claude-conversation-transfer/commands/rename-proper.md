---
description: Rename a Claude Code project in place — migrate its conversation history to a new path, verify, and delete the old data
allowed-tools: Bash, PowerShell
---

Rename a project **on this machine**: migrate its full conversation history from the old CWD's encoded folder in `~/.claude/projects/` to the new one, rewrite embedded paths, verify, and — only after verification passes — delete the old folder. Collapses the old `/export-proper` → rename folder → new session → `/import-proper` → manual cleanup dance into one call.

This delegates to the `claude-conversation-transfer` binary — installed by the `claude-skills` installer under `~/.local/share/claude-conversation-transfer/`. The binary composes the same tested export + import + verify path (in-process byte-level rewriting, no shell argv → no backslash-collapse bug) and handles old-folder deletion and preexisting-target backup. **Do not** re-derive any of this from prose.

Steps:

1. Establish the two paths:
   - **new path** (`--to`, required): where the project lives now / will live. Ask the user if not given.
   - **old path** (`--from`, optional): the project's previous CWD. Defaults to the current shell CWD — so if the shell is already sitting in the renamed folder, `--from` must be given explicitly (the old path no longer matches the shell CWD).
   - Clarify with the user which folder the shell is in before running, so `--from`/`--to` aren't swapped.

2. Decide whether the on-disk directory still needs moving:
   - If the user **already renamed the folder** themselves (the common, safe case) → omit `--rename-dir`.
   - If the user wants the tool to also move the working directory from `--from` to `--to` → add `--rename-dir`. Warn that on Windows this fails if any process (including the current shell) has the folder open as its CWD; in that case, rename it manually and re-run without the flag.

3. Locate the binary:
   - macOS/Linux: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer`
   - Windows: `$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer.exe`
   - If missing: tell the user to run the `claude-skills` installer and pick the `claude-conversation-transfer` group.

4. Run it with `--json`:
   - Bash: `"$HOME/.local/share/claude-conversation-transfer/claude-conversation-transfer" rename --from "<old>" --to "<new>" [--rename-dir] --json`
   - PowerShell: `& "$HOME\.local\share\claude-conversation-transfer\claude-conversation-transfer.exe" rename --from "<old>" --to "<new>" [--rename-dir] --json`

5. Report from the JSON fields:
   - `old_project` → `new_project` (the encoded folders), and `old_cwd` → `new_cwd`.
   - `jsonl_files` migrated, `has_memory`, `dir_renamed`.
   - `files_rewritten` / `tail_conversions` / `tail_direction` if any rewriting happened.
   - **Verification**: `verification.total_ok` and `verification.total_bad`. If `total_bad > 0`, the binary exited non-zero, the old folder was **kept** (not deleted), and this is a FAILURE — surface the failing files and **do not** declare success. The Claude Code session list can populate even with corrupted `.jsonl` files.
   - `old_data_deleted`: true means the old encoded folder was removed after a clean verify; false with a clean verify means it was left in place.
   - `preexisting_target_backup` (if non-empty): a project folder already existed at the new path and was backed up to this `.bak-<timestamp>` path. It was **NOT** deleted — tell the user to review it and merge anything worth keeping (`memory/MEMORY.md`, per-memory `.md` files, any sessions not in the migrated set), then remove it themselves.

6. Exit codes: `0` success · `1` verification failed (old data preserved) · `2` usage · `3` I/O · `4` `--rename-dir` directory move failed (Claude-side data left untouched — rename the folder manually and re-run without the flag).

Do not delete the `preexisting_target_backup` folder for the user.
