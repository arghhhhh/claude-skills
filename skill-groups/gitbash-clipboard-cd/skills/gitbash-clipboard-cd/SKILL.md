---
version: 1.0.0
name: gitbash-clipboard-cd
description: Windows Git Bash helpers (cdc / cdh) that cd into folder paths copied from Explorer, fixing backslash-path mangling and reading clipboard history. Use when a user on Windows wants to jump to a copied/dragged folder without manually quoting or fixing slashes.
---

# Git Bash Clipboard cd (Windows)

Two shell functions that let you `cd` into a folder you copied in Windows Explorer, without the usual Git Bash friction.

## The problem they solve

| Friction | Why it happens |
|---|---|
| `cd C:\Users\Joss\Foo` → `No such file or directory` (path shows as `C:UsersJossFoo`) | `\` is bash's escape char; unquoted backslashes are eaten at parse time. |
| Pasted paths only get auto-quoted when they contain spaces | Quoting is added by mintty/Windows only for spaces — not for backslashes or other specials. |

## Commands

| Command | What it does |
|---|---|
| `cdc` | `cd` into the path **currently** on the clipboard. Strips quotes/newlines, converts `\` → `/`. |
| `cdh` | Scans Windows **clipboard history** (Win+V) and `cd`s into the **most recent entry that is an existing directory** — use when you copied something else after the path. |

**Usage:** in Explorer, copy the folder (`Ctrl+C`) or right-click → *Copy as path*, then type `cdc` (or `cdh`) and press Enter. No manual quoting, no slash-fixing.

## How it works

- `cdc` reads `/dev/clipboard` (mintty's view of the Windows clipboard), trims CR/LF, strips a surrounding `"..."` (from *Copy as path*), and runs `tr '\134' '/'` to turn backslashes into forward slashes — which Git Bash's `cd` accepts. Command substitution re-quotes the result, so spaces are handled too.
- `cdh` shells out to `~/.cdh-cliphist.ps1`, which reads clipboard history via the WinRT `Clipboard.GetHistoryItemsAsync` API, walks newest→oldest, and returns the first entry that is an existing directory. Slightly slower (spawns PowerShell), so prefer `cdc` for the common case.

## Requirements / caveats

- **Windows + Git Bash (mintty) only.** `/dev/clipboard` and the WinRT API are Windows-specific.
- `cdh` needs **Clipboard History enabled**: Settings → System → Clipboard, or Win+V → turn on.
- `cdh` only returns paths that **currently exist** as directories — stale/deleted paths are skipped.
- After install, open a new Git Bash window or run `source ~/.bashrc` to load the functions.

## Files

The installer copies:
- `~/.clipboard-cd.sh` — the `cdc` / `cdh` function definitions (sourced from `~/.bashrc`).
- `~/.cdh-cliphist.ps1` — the clipboard-history reader used by `cdh`.
