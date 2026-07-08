---
version: 1.1.0
name: obsidian-cli
description: Control a running Obsidian instance from the command line — search, read, create, and append notes, open daily notes, list tags/tasks/unresolved links, and run editor commands or JavaScript. Use whenever the user wants an agent to read from or drive their Obsidian vault(s) programmatically.
---

# Obsidian CLI Skill

Drive a **running** Obsidian desktop app from the shell. "Anything you can do in Obsidian you can do from the command line." The CLI is built into Obsidian 1.9+ — there is no separate binary to download.

## Hard Requirements

1. **Obsidian must be running.** Every command talks to the live app. If commands hang or error with no connection, the app is closed.
2. **The CLI must be registered once** (GUI step the agent cannot do): Settings → General → enable **Obsidian CLI**, then click **Register** and follow the OS dialog.
   - macOS: symlink at `/usr/local/bin/obsidian` (asks for admin).
   - Linux: binary copied to `~/.local/bin/obsidian` (ensure it's on PATH).
   - Windows: a console redirector (`Obsidian.com`, next to `Obsidian.exe`) is installed and takes PATHEXT priority over the GUI `.exe`; restart the shell afterwards. **Requires the installer `.exe` shell to be ≥ 1.11.7** — the app package (`.asar`) auto-updates but the installer shell does NOT, so an old shell has no redirector and every `obsidian <cmd>` just focuses/opens the GUI window (see Troubleshooting). Fix by rerunning the current installer from https://obsidian.md, then re-Register.
3. Verify it's wired up with `obsidian version`.

## Global Conventions

- **Pick a vault**: append `vault="VaultName"` to any command. Omit to use the active/last vault — for agent work, **always pass `vault=` explicitly** so you don't act on the wrong vault.
- **JSON output**: append `format=json` for machine-readable results (prefer this when parsing).
- **Copy to clipboard**: append `--copy`.
- **Interactive TUI**: running bare `obsidian` opens an interactive terminal UI with autocomplete — not useful for non-interactive agent calls; always pass an explicit subcommand instead.
- Arguments use `key="value"` form. Quote any value containing spaces.

## Reading & Searching

```bash
obsidian search query="meeting notes" vault="Planning" format=json   # full-text search
obsidian read vault="Planning"                                       # read the current/active file
obsidian files sort=modified limit=5 vault="Planning" format=json    # list files (sort=modified|created|name)
obsidian tags counts vault="Planning" format=json                    # all tags with frequencies
obsidian unresolved vault="Planning" format=json                     # unresolved (broken) links
obsidian diff file=README from=1 to=3 vault="Planning"               # compare file versions
```

## Daily Notes & Tasks

```bash
obsidian daily vault="Planning"                          # open today's daily note
obsidian daily:append content="- did the thing" vault="Planning"   # append to today's daily note
obsidian tasks daily vault="Planning" format=json        # list tasks from the daily note
```

## Creating Notes

```bash
obsidian create name="2026 Q3 Plan" template="Meeting" vault="Planning"   # new note from a template
```

## Developer / Power Commands

```bash
obsidian eval "app.vault.getMarkdownFiles().length" vault="Planning"   # run arbitrary JS in the app context
obsidian plugin:reload obsidian-sonar vault="LLMS"                     # reload a plugin (great after editing plugin files)
obsidian dev:errors vault="LLMS"                                       # review JS errors
obsidian dev:screenshot file=shot.png vault="Planning"                 # capture a screenshot
obsidian dev:css selector=".workspace" vault="Planning"                # inspect computed CSS
obsidian dev:dom selector=".nav-files-container" vault="Planning"      # query DOM
obsidian devtools vault="Planning"                                     # open DevTools
```

`obsidian eval` exposes the full Obsidian API (`app`, `app.vault`, `app.workspace`, `app.metadataCache`). It's the escape hatch for anything without a dedicated subcommand — e.g. bulk metadata reads, programmatic note edits, triggering commands via `app.commands.executeCommandById("...")`.

## Operational Rules for Agents

1. **Confirm connectivity first** with `obsidian version` (and a cheap read like `obsidian tags counts ... format=json`). If it fails, tell the user to launch Obsidian / register the CLI rather than retrying blindly.
2. **Always pass `vault=`** explicitly. Never assume the active vault is the one the user means.
3. **Prefer `format=json`** whenever you'll parse the output.
4. **Treat writes as real edits to the user's notes.** Creating/appending notes or `eval` that mutates the vault changes durable user data — confirm intent before destructive or bulk mutations, and prefer append over overwrite.
5. After editing a plugin's files on disk, `obsidian plugin:reload <id>` picks up changes without restarting the app.

## Troubleshooting

- **No response / connection error** → Obsidian isn't running, or the CLI was never registered (Settings → General → Register).
- **`obsidian: command not found`** → registration didn't add it to PATH; on Windows restart the terminal; on Linux ensure `~/.local/bin` is on PATH.
- **The GUI window pops open on every `obsidian <cmd>` (Windows)** → the installer `.exe` shell is older than 1.11.7, so no redirector exists and commands hit the GUI exe, whose single-instance handler just focuses/opens the window. Check with `(Get-Item 'C:\Program Files\Obsidian\Obsidian.exe').VersionInfo.ProductVersion` (or wherever installed). Fix: rerun the current installer from https://obsidian.md (UAC if under Program Files), then Settings → General → Obsidian CLI → Register, then restart the shell. Afterward `obsidian` resolves to `Obsidian.com` and commands round-trip over the named pipe without opening a window.
- **Wrong vault affected** → you omitted `vault=`; the CLI fell back to the active vault.
