---
description: Export the current conversation's full project folder (all sessions + memory) as a zip in the CWD
allowed-tools: Bash, PowerShell, Read, Glob
---

Export the active project folder from `~/.claude/projects/` into the current working directory as a zip archive. This is the portable version of yesterday's manual copy — it bundles every session jsonl, session subdir, and the `memory/` dir for this project.

Steps:

1. Determine the current CWD.
   - Windows: encoded folder name is the CWD with `:`, `\`, and `/` each replaced by `-`. Example: `C:\Users\joss\Desktop\Projects\Mine` → `C--Users-joss-Desktop-Projects-Mine`.
   - macOS/Linux: replace `/` with `-`. Example: `/home/joss/work` → `-home-joss-work`.

2. Locate the project folder: `~/.claude/projects/<encoded>/`. If it does not exist, stop and report that there is nothing to export for this CWD.

3. Build a timestamped archive name: `claude-convo-export-<encoded>-<YYYYMMDD-HHMMSS>.zip` and place it in the CWD.

4. Zip the project folder's *contents* (not the wrapping folder itself) into the archive:
   - Windows (PowerShell): `Compress-Archive -Path "<project-folder>\*" -DestinationPath "<cwd>\<archive>" -Force`
   - macOS/Linux (Bash): `(cd "<project-folder>" && zip -r "<cwd>/<archive>" .)`

5. Report: archive path, size, count of `.jsonl` files inside, and whether `memory/` was bundled.

Do not delete or modify the original project folder.
