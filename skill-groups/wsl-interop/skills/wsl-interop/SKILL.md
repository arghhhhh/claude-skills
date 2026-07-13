---
version: 1.2.0
name: wsl-interop
description: Reuse the Windows host toolchain from a WSL2 Claude session via interop instead of reinstalling on Linux. Use when running inside WSL and about to install a package, run a claude-skills CLI, open a GUI app, pass file paths between Linux and Windows tools, or set up the claude-skills repo / hands-off long-horizon in WSL. Covers the .exe-suffix rule, wslpath translation, CRLF/CWD gotchas, the interop-vs-native decision, and reusing the Windows claude-skills repo.
---

# WSL ⇄ Windows Interop

Guidance for a Claude session running **inside WSL2 on a Windows host** (`grep -qi microsoft /proc/version` is true). Goal: reuse what Windows already has instead of rebuilding the toolchain on Linux — the reinstall is what saturates context.

## Core rule: check Windows before installing on Linux

```bash
command -v <tool>.exe        # is the Windows binary on the appended PATH?
where.exe <tool>             # Windows-side lookup (prints C:\... paths)
```

If it resolves, **use the `.exe`**. Only install Linux-native when the tool is genuinely absent on Windows, or when the fast-path/native-fs reasons below apply. Never take "bare name not found" as "not installed."

## Why the trap happens (the `.exe` suffix)

WSL2 interop appends the Windows PATH, so any Windows executable on it is callable — **but Linux needs the extension**. Bare names miss; `<name>.exe` hits. The claude-skills SKILL.md files were written for Windows/mac and call bare names, so on WSL they look uninstalled:

| SKILL.md calls | WSL bare name | WSL working call | Typically resolves to |
|---|---|---|---|
| `ghidra …`     | ✗ MISS | `ghidra.exe …`     | `/mnt/c/Users/<you>/.local/bin/ghidra.exe` |
| `unity-cli …`  | ✗ MISS | `unity-cli.exe …`  | `/mnt/c/Users/<you>/.local/bin/unity-cli.exe` |
| `ilspy …`      | ✗ MISS | `ilspy.exe …`      | `/mnt/c/Users/<you>/.cargo/bin/ilspy.exe` |
| `comfy …`      | ✗ MISS | `comfy.exe …`      | `.../Python311/Scripts/comfy.exe` |
| `td-cli …`     | ✗ MISS | `td-cli.exe …`     | `/mnt/c/Users/<you>/go/bin/td-cli.exe` |
| `magick …`     | ✗ MISS | `magick.exe …`     | `.../ImageMagick-*/magick.exe` |
| `gh` / `jq` / `node` / `python` | ✗ MISS | `gh.exe` / `jq.exe` / `node.exe` / `python.exe` | on Windows PATH |

Some tools ship without `.exe` (e.g. a Deno-shim like `linear`) and resolve under their bare name — always confirm with `command -v`.

Optional: alias the ones you'll reuse so the skill's bare-name commands just work this session:
```bash
for t in ghidra unity-cli ilspy comfy td-cli gobs-cli magick gh jq; do
  command -v "$t.exe" >/dev/null && alias "$t"="$t.exe"
done
```
(Aliases apply to your interactive commands, not to sub-scripts — for those, call `.exe` explicitly.)

## Paths: Windows `.exe` want Windows paths

A Windows executable receives its arguments as a raw string — it does **not** understand `/mnt/c/...`. Convert with `wslpath`:

```bash
wslpath -w /mnt/c/Users/Joss/file.png   # → C:\Users\Joss\file.png   (Linux → Windows, for passing TO an .exe)
wslpath -u 'C:\Users\Joss\file.png'     # → /mnt/c/Users/Joss/file.png (Windows → Linux, for reading its output)
```

- Passing a `/mnt/c/...` path straight to a Windows `.exe` fails: PowerShell reads `/mnt/c/foo` as `C:\mnt\c\foo`. Always `wslpath -w` first.
- **CWD gotcha:** running a Windows `.exe` while `cd`'d into a Linux-native dir (`~`, i.e. a `\\wsl.localhost\...` UNC) prints *"UNC paths are not supported. Defaulting to Windows directory."* and silently uses `C:\Windows`. So `cd` under `/mnt/c/...` before invoking a Windows tool, or pass absolute `wslpath -w` paths for every file arg.
- Keep files you hand to Windows tools under `/mnt/c/...` (Explorer-visible, no UNC pain). Linux-native files are reachable from Windows only via the slow `\\wsl.localhost\<distro>\...` share.

## Other gotchas

- **CRLF on stdout.** Windows tools emit `\r\n`. When capturing/parsing their output, strip it: `powershell.exe -c "…" | tr -d '\r'`. Unstripped `\r` breaks `[ "$x" = "y" ]`, path building, and JSON parsing.
- **Git line-endings across the boundary — match `git` to the checkout.** A repo cloned on Windows (esp. under `/mnt/c`) with `core.autocrlf=true` has CRLF in its working tree. Running **WSL's native `git`** against it can flag dozens of files as "modified" that differ only by CRLF↔LF — pure noise, and a commit through it may capture line-ending churn. Symptom: `git status`/`git diff` in WSL shows a huge "modified" set you didn't touch. Fix: use **`git.exe`** for that repo so line-ending handling matches how it was checked out — it correctly sees only the real change. Rule of thumb: **Windows-checked-out repo (under `/mnt/c`) → `git.exe`; Linux-native repo (under `~`) → WSL `git`.** (A Linux-native clone of `claude-skills` under `~` is LF-clean — use WSL `git` there. But if `~/.claude/.skill-repos/claude-skills` is a **symlink into the Windows repo** under `/mnt/c` — the recommended single-source setup, see below — treat it as a Windows-checked-out repo and use `git.exe` for git ops on it.)
- **PowerShell.** `powershell.exe` (Windows PowerShell 5.1) is present; `pwsh.exe` (7+) usually isn't. Use `-NoProfile -Command`. Quoting through bash→powershell is fiddly — prefer single-quoted bash wrapping a double-quoted PS command, or write a `.ps1` under `/mnt/c` and run it.
- **Opening files/URLs.** `wslview` (wslu) is often absent; use `explorer.exe .`, `explorer.exe "$(wslpath -w file)"`, or `powershell.exe -c "Start-Process …"`.
- **Clipboard.** Read: `powershell.exe -NoProfile -c Get-Clipboard | tr -d '\r'`. Write: `… | clip.exe`. (The `cdw` helper from the `wsl-clipboard-cd` group uses this.)
- **MCP-backed skills are different.** Interop is for CLIs. Skills driven by an MCP server (blender, comfy-pilot, claude-mermaid, TouchDesigner's MCP) need the server registered in *this* WSL `~/.claude/.mcp.json` — the Windows-side registration doesn't carry over. Either add the entry pointing at the running Windows app's port, or run those skills on the Windows session. The MCP mermaid/notch servers are standalone and can be `npx`'d natively.

## Interop vs. install Linux-native

| Use Windows interop (`.exe`) | Install Linux-native |
|---|---|
| Tool already installed on Windows (claude-skills CLIs, `gh`, `jq`, `magick`) | Tool genuinely absent on Windows |
| GUI apps: Blender, OBS, Unity, ComfyUI server, TouchDesigner | Heavy iterative I/O on a **Linux-native** repo (npm/cargo/git) — crossing `/mnt/c` is slow; keep the working copy under `~` and use Linux tools there |
| Operating on files already under `/mnt/c/...` | Software that only exists on Linux (certain ELF-only tooling, some Docker setups) |
| One-off invocations where startup cost doesn't matter | A tool you'll call thousands of times in a tight loop (interop per-call overhead adds up) |

When unsure: reuse Windows to avoid a second install and version skew; drop to Linux-native only for a concrete perf or availability reason — and say which.

## The claude-skills repo: reuse Windows, don't re-clone

If the **Windows** host already has `claude-skills` installed, do NOT `git clone` a second copy into the WSL home — that leaves two drifting repos. The installer hardcodes the canonical repo path as `~/.claude/.skill-repos/claude-skills` (it symlinks skills there regardless of where `install.sh` lives), so the clean single-source setup is to make that path a **symlink into the Windows copy**:

```bash
WINREPO=/mnt/c/Users/<you>/.claude/.skill-repos/claude-skills
rm -rf ~/.claude/.skill-repos/claude-skills           # only if it's a redundant fresh clone
ln -sfn "$WINREPO" ~/.claude/.skill-repos/claude-skills
```

Every WSL skill symlink (`~/.claude/skills/<name>`) then resolves through to the one Windows repo — pull once on Windows, both sides updated. WSL still keeps its **own** `~/.claude/skills`, `settings.json`, and `hooks` (those are per-environment); only the *repo source* is shared.

- Installer's global gate: `install.sh` requires `node`. The `.exe` interop node can't run it (it passes Linux paths Windows node won't resolve), so install a Linux-native node (`nvm`) once. Pure-guidance/shell groups (`wsl-interop`, `wsl-clipboard-cd`) still trip this gate even though they need no node at runtime.
- Trade-off vs. a native clone: symlinking reads over `/mnt/c` (fine for symlink resolution + occasional installer runs; the installer's JSON edits land in the native WSL `~/.claude`). Only prefer a separate Linux-native clone if you'll do **heavy git iteration** on the repo from WSL — then you own two copies and must sync them.

**Hands-off long-horizon (auto-`/clear`) runs in WSL** (Git Bash has no tmux). Full one-time setup — native node+claude, auth copy, `wire.sh` from the `/mnt/c` repo, session/config sharing — is in `context-rotation/references/wsl-setup.md`. Set `model` in the WSL `settings.json` (or pin `CR_WINDOW`) so a 1M-context model isn't measured against the 200k default and rotated early.

## Layout reference

- Windows drives: `/mnt/c`, `/mnt/d`. Windows profile: `/mnt/c/Users/<you>`.
- Windows Claude config + `skills-config.sh` + tool bins: under `/mnt/c/Users/<you>/.claude` and `~/.local/bin`, `~/.cargo/bin`, `~/go/bin` (all on the appended PATH).
- This WSL session has its **own** Linux `~/.claude` (separate settings/hooks); only the sessions store (and, for long-horizon, the rotation `config`) is typically symlinked back to Windows. So Windows `~/.claude` settings/MCP/hooks are **not** in effect here unless separately wired. The `.skill-repos/claude-skills` **repo** can still be shared as a symlink into `/mnt/c` (see "The claude-skills repo" above) — that's the source tree, not the active config.
