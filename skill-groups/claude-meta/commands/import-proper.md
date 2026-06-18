---
description: Import a claude-convo-export zip from CWD into ~/.claude/projects/, retargeted to this machine's CWD
allowed-tools: Bash, PowerShell, Read, Glob
---

Import a `claude-convo-export-*.zip` archive sitting in the current working directory into `~/.claude/projects/`, renaming the project folder to match the **current** CWD so Claude Code recognizes it. Pairs with `/export-proper`.

Steps:

1. Glob the CWD for `claude-convo-export-*.zip`.
   - If none: stop and report.
   - If multiple: list them with sizes/mtimes and ask the user which to import.

2. Compute the encoded folder name for the **current** CWD (same rule as `/export-proper`: Windows replaces `:` `\` `/` with `-`; macOS/Linux replaces `/` with `-`).

3. Target: `~/.claude/projects/<new-encoded>/`.

4. If the target already exists, rename it to `<new-encoded>.bak-<YYYYMMDD-HHMMSS>` (do not delete). Tell the user it was backed up and that they will need to manually merge anything they want to keep — specifically:
   - `memory/MEMORY.md` (index) and any `memory/*.md` files
   - Any `.jsonl` sessions from the backup not present in the imported set

5. Create the target folder fresh and extract the zip into it:
   - Windows (PowerShell): `Expand-Archive -Path "<zip>" -DestinationPath "<target>" -Force`
   - macOS/Linux (Bash): `mkdir -p "<target>" && unzip -q "<zip>" -d "<target>"`

6. Report:
   - target path
   - number of `.jsonl` session files imported
   - whether `memory/` was imported
   - backup path (if any) and the manual-merge reminder
   - a note that absolute paths inside the `.jsonl` files still reference the source machine — resuming a session works, but file references in the transcript point at the old paths

Do not delete the source zip.
