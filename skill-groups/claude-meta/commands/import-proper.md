---
description: Import a claude-convo-export zip from CWD into ~/.claude/projects/, retargeted to this machine's CWD
allowed-tools: Bash, PowerShell, Read, Glob, Edit
---

Import a `claude-convo-export-*.zip` archive sitting in the current working directory into `~/.claude/projects/`, renaming the project folder to match the **current** CWD so Claude Code recognizes it. Pairs with `/export-proper`.

Steps:

1. Glob the CWD for `claude-convo-export-*.zip`.
   - If none: stop and report.
   - If multiple: list them with sizes/mtimes and ask the user which to import.

2. Detect the **source CWD and OS** from the archive name (or by peeking inside).
   - Archive name format: `claude-convo-export-<source-encoded>-<timestamp>.zip`.
   - If `<source-encoded>` starts with a drive letter followed by `--` (e.g. `C--Users-joss-...`): source was **Windows**, original CWD = `C:\Users\joss\...` (first `-` after the drive is `:\`, remaining `-` are `\`).
   - If `<source-encoded>` starts with `-` (e.g. `-Users-joss-work-Mine`): source was **macOS/Linux**, original CWD = `/Users/joss/work/Mine` (every `-` is `/`).

3. Compute the encoded folder name for the **current** CWD (same rule as `/export-proper`: Windows replaces `:` `\` `/` with `-`; macOS/Linux replaces `/` with `-`).

4. Target: `~/.claude/projects/<new-encoded>/`.

5. If the target already exists, rename it to `<new-encoded>.bak-<YYYYMMDD-HHMMSS>` (do not delete). Tell the user it was backed up and that they will need to manually merge anything they want to keep — specifically:
   - `memory/MEMORY.md` (index) and any `memory/*.md` files
   - Any `.jsonl` sessions from the backup not present in the imported set

6. Create the target folder fresh and extract the zip into it:
   - Windows (PowerShell): `Expand-Archive -Path "<zip>" -DestinationPath "<target>" -Force`
   - macOS/Linux (Bash): `mkdir -p "<target>" && unzip -q "<zip>" -d "<target>"`

7. **Cross-OS path rewrite** — if the source OS (from step 2) differs from the current OS, OR the decoded source CWD differs from the current CWD, rewrite path prefixes in every `.jsonl` file under the target folder:
   - Replace every occurrence of the **source CWD** (e.g. `C:\Users\joss\Desktop\Projects\Mine`) with the **current CWD** (e.g. `/Users/joss/work/Mine`).
   - JSON-encoded form too: Windows backslashes appear as `\\` inside JSON strings, so also replace the JSON-escaped form (`C:\\Users\\joss\\Desktop\\Projects\\Mine` → `/Users/joss/work/Mine`).
   - Use platform-native tools: `sed -i` on macOS/Linux (`sed -i ''` on macOS), or PowerShell `(Get-Content … -Raw) -replace … | Set-Content` on Windows.
   - Scope the rewrite to `.jsonl` files only. Do not touch `memory/` markdown (already portable).
   - Skip rewriting if source CWD equals current CWD (same path on both machines — no-op).
   - Do **not** attempt to rewrite arbitrary other paths (home dir refs outside the project CWD, system paths, etc.) — those would break either way and broad rewrites are too risky.

8. Report:
   - target path
   - number of `.jsonl` session files imported
   - whether `memory/` was imported
   - backup path (if any) and the manual-merge reminder
   - whether a cross-OS / path rewrite happened, with the substitution applied (`<source-cwd>` → `<current-cwd>`) and the count of `.jsonl` files modified
   - a note that file references *outside* the project CWD (e.g. paths into the source user's home dir, system paths) were not rewritten and will still 404 on this machine

Do not delete the source zip.
