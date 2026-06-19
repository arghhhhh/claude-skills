---
description: Import a claude-convo-export zip from CWD into ~/.claude/projects/, retargeted to this machine's CWD
allowed-tools: Bash, PowerShell, Read, Glob, Edit
---

Import a `claude-convo-export-*.zip` archive sitting in the current working directory into `~/.claude/projects/`, renaming the project folder to match the **current** CWD so Claude Code recognizes it. Pairs with `/export-proper`.

Steps:

1. Glob the CWD for the export archive. Match **tolerantly** — the literal prefix may use hyphens *or* underscores as word separators (some exporters emit `claude_convo_export_…`), so glob for both: `claude-convo-export-*.zip` **and** `claude_convo_export_*.zip` (treat the match case-insensitively). Do not assume the hyphen form only.
   - If none: stop and report.
   - If multiple: list them with sizes/mtimes and ask the user which to import.

2. Detect the **source CWD and OS**. Prefer reading it from inside the archive — the filename is only a hint and may have been re-encoded (underscores, collapsed `C_` drive prefix, date-only timestamp).
   - **Primary (authoritative):** peek into any session `.jsonl` in the archive and read its `"cwd"` field (e.g. `unzip -p "<zip>" "*.jsonl" | head` then find the first `"cwd":"…"`). That value *is* the source CWD; its shape (`C:\…` with backslashes vs `/…`) tells you the source OS. Use this whenever available.
   - **Fallback (filename parse):** only if no `cwd` can be read. Strip the literal prefix (`claude-convo-export-`/`claude_convo_export_`) and trailing timestamp to get `<source-encoded>`, then decode:
     - Drive-letter prefix (e.g. `C--Users-joss-…` or `C_Users_joss_…`): source was **Windows**, original CWD = `C:\Users\joss\…` (the separator(s) after the drive letter are `:\`, remaining separators are `\`).
     - Leading separator (e.g. `-Users-joss-work-Mine`): source was **macOS/Linux**, original CWD = `/Users/joss/work/Mine` (every `-` is `/`).
   - Note that the brittle filename parse is exactly why the in-archive `cwd` is preferred — separator drift in the name does not affect it.

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
   - **Deeper sub-paths (bidirectional):** a prefix-only swap leaves the *tail* of nested paths using the **source** OS's separator, which is wrong for the target. After the prefix swap, convert the tail separators to the **target** OS's separator, **only within substrings that begin with the now-rewritten current-CWD prefix** — i.e. walk each occurrence of the current-CWD prefix and translate separators until the path token ends (closing quote, whitespace, or other delimiter).
     - **Windows → POSIX:** remaining `\\` (and raw `\`) → `/`. Otherwise e.g. `C:\\…\\Mine\\testing-import\\_mermaid_test\\repro-spawn.mjs` becomes `/Users/joss/work/Mine\\testing-import\\…`, which won't resolve on macOS/Linux.
     - **POSIX → Windows:** remaining `/` → `\\` (JSON-escaped backslash). Windows tolerates forward slashes in most contexts, so this is cosmetic-but-consistent rather than strictly required — do it so a round-trip is symmetric.
     - **Never** do a global separator swap over the whole file: that would corrupt legitimate separators in message text (code blocks, regexes, escape sequences, URLs). Scope strictly to tokens under the current-CWD prefix.
     - No-op when source and target use the same separator (POSIX → POSIX, or Windows → Windows).
   - Use platform-native tools: `sed -i` on macOS/Linux (`sed -i ''` on macOS), or PowerShell `(Get-Content … -Raw) -replace … | Set-Content` on Windows.
   - Scope the rewrite to `.jsonl` files only. Do not touch `memory/` markdown (already portable).
   - Skip rewriting if source CWD equals current CWD (same path on both machines — no-op).
   - Do **not** attempt to rewrite arbitrary other paths (home dir refs outside the project CWD, system paths, etc.) — those would break either way and broad rewrites are too risky.

8. Report:
   - target path
   - number of `.jsonl` session files imported
   - whether `memory/` was imported
   - backup path (if any) and the manual-merge reminder
   - whether a cross-OS / path rewrite happened, with the substitution applied (`<source-cwd>` → `<current-cwd>`), the count of `.jsonl` files modified, and — for cross-OS imports — the count of deeper sub-paths whose tail separators were converted (and which direction, `\`→`/` or `/`→`\`)
   - a note that file references *outside* the project CWD (e.g. paths into the source user's home dir, system paths) were not rewritten and will still 404 on this machine

Do not delete the source zip.
