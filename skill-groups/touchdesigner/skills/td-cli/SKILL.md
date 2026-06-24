---
version: 2.0.0
name: td-cli
description: Drive a live TouchDesigner session from the terminal via td-cli — operator/parameter editing, Python exec, screenshots, shader templates, harness loop with backup/rollback.
---

# TouchDesigner CLI Skill

Use this skill to inspect and modify a running TouchDesigner project via `td-cli` (HTTP to `TDCliServer.tox` on port 9500).

## Setup

- **Binary**: `{{TD_CLI}}`
- **Requires**: TouchDesigner running with `TDCliServer.tox` loaded in the root network, `webserver1` on port 9500
- **Auto-discovery**: TD writes heartbeat files to `~/.td-cli/instances/`; `td-cli` reads them
- **Auth (optional)**: set `TD_CLI_TOKEN` in both shell and TD process env for HMAC-verified requests

For brevity, `td-cli` below refers to the full path to the binary.

## Not Installed?

- **TouchDesigner**: https://derivative.ca/download
- **td-cli**: https://github.com/arghhhhh/td-cli — `git clone` + `go install ./cmd/td-cli/` (no prebuilt releases yet). This is the `--opaque`-enabled fork; revert to `0dot77/td-cli` only once PR https://github.com/0dot77/td-cli/pull/2 merges upstream.
- **TDCliServer.tox**: drag from the cloned repo's `tox/` folder into your TD project root

## Always Start Here

```bash
td-cli status                              # confirm connection (project name, TD version)
td-cli context --depth 2                   # full project summary: tree, families, harness history
td-cli describe /project1                  # AI-friendly network description
```

If `status` fails: TD isn't running, or `TDCliServer.tox` isn't loaded, or port 9500 is wrong.

## Connection & Discovery

| Command | Purpose |
|---|---|
| `td-cli status` | Check TD connection |
| `td-cli context [--depth N]` | Project summary (tree, families, activity, harness) |
| `td-cli instances` | List running TD instances |
| `td-cli describe [path]` | AI-friendly network description |
| `td-cli doctor` | Full diagnostics |

## Operators

| Command | Purpose |
|---|---|
| `td-cli ops list [path] [--depth N] [--family TYPE]` | List operators |
| `td-cli ops create <type> <parent> [--name N] [--x X] [--y Y]` | Create operator |
| `td-cli ops delete <path>` | Delete |
| `td-cli ops info <path>` | Operator details |
| `td-cli ops rename <path> <new-name>` | Rename |
| `td-cli ops copy/move/clone <src> <parent>` | Duplicate/move |
| `td-cli ops search <parent> <pattern> [--family TYPE]` | Search by name |

## Parameters

| Command | Purpose |
|---|---|
| `td-cli par get <op> [names...]` | Read parameters |
| `td-cli par set <op> <name> <val> [...]` | Set (key-value pairs) |
| `td-cli par pulse <op> <name>` | Pulse a button parameter |
| `td-cli par reset <op> [names...]` | Reset to default |
| `td-cli par expr <op> <name> [expression]` | Get/set an expression |
| `td-cli par export <op>` | Export all params as JSON |
| `td-cli par import <op> <json>` | Import from JSON |

## Connections

| Command | Purpose |
|---|---|
| `td-cli connect <src> <dst> [--src-index N] [--dst-index N]` | Wire operators |
| `td-cli disconnect <src> <dst>` | Unwire |

## Python Execution

| Command | Purpose |
|---|---|
| `td-cli exec "<code>"` | Inline Python in TD |
| `td-cli exec -f <file>` | Execute Python file |
| `td-cli exec ... --verify <path>` | Verify node graph after |
| `td-cli exec ... --screenshot <path>` | Capture TOP to `.tmp/preview.png` |

Inside exec: `td` is pre-imported; `_T('nullTOP')` is a shortcut for `getattr(td, 'nullTOP')`.

## Data Access

| Command | Purpose |
|---|---|
| `td-cli dat read <path>` | Read DAT content |
| `td-cli dat write <path> <content> [-f file]` | Write DAT |
| `td-cli chop info/channels/sample <path>` | Channel data |
| `td-cli sop info/points <path>` | Geometry data |
| `td-cli pop info/points/bounds <path>` | POP data |
| `td-cli table rows/cell <path>` | Table read/write |

## Visual & Media

| Command | Purpose |
|---|---|
| `td-cli screenshot [path] [-o file] [--opaque]` | Capture TOP as PNG (default `.tmp/preview.png`) |
| `td-cli media info <path>` | TOP metadata |
| `td-cli media export <path> <file>` | Export media |
| `td-cli watch [path] [--interval ms]` | Real-time monitor |

**Always screenshot + Read the file after a visual change** — the only way to know whether a render actually looks right.

**⚠ Always pass `--opaque` when capturing for your own visual inspection.** Many TD shaders write `fragColor` with `alpha = 0` (sky/atmospheric shaders, GLSL templates that omit alpha, anything using alpha as a compositing flag). The PNG is technically correct but image viewers composite RGBA over white when alpha=0 — you'll see a blank-white image and reach wrong conclusions, while TD's node thumbnail shows the actual sky because its viewer ignores alpha. `--opaque` forces alpha=255 in the saved PNG so what you Read matches what the artist sees. Omit `--opaque` only when you genuinely need the alpha channel preserved for downstream compositing.

## Harness — Safe Mutation Loop

| Command | Purpose |
|---|---|
| `td-cli harness capabilities` | List supported features |
| `td-cli harness observe [path] [--depth N]` | Snapshot state |
| `td-cli harness verify [path] [--assert JSON]` | Run assertions |
| `td-cli harness apply <path> [--goal TEXT] [--op JSON]` | Apply ops with auto-backup |
| `td-cli harness rollback <id>` | Restore prior state |
| `td-cli harness history [--limit N]` | List iterations |

Use this loop for any restructuring — backups are automatic, rollback is one command.

## Project, Timeline, Cook

| Command | Purpose |
|---|---|
| `td-cli project info` / `td-cli project save [path]` | Metadata / save |
| `td-cli timeline [info\|play\|pause]` | Timeline control |
| `td-cli timeline seek <time>` | Jump to frame |
| `td-cli cook node <path>` | Force-cook an operator |

## Templates & Docs

| Command | Purpose |
|---|---|
| `td-cli pop av [--root path] [--name NAME]` | Build audio-reactive POP scene |
| `td-cli shaders list [--cat CAT]` | List GLSL shader templates |
| `td-cli shaders apply <name> <top>` | Apply shader to GLSL TOP |
| `td-cli docs <operator>` | Offline operator docs |
| `td-cli docs search <keyword>` | Search operators |
| `td-cli docs api [class]` | Python API reference |

## Batch & Network Snapshots

| Command | Purpose |
|---|---|
| `td-cli batch exec <file.json>` | Batch-execute commands |
| `td-cli batch parset <file.json>` | Batch-set parameters |
| `td-cli network export [path] [-o file]` | Export network snapshot |
| `td-cli network import <file> [target]` | Import snapshot |
| `td-cli tox export <comp> -o <file>` | Export component as .tox |
| `td-cli tox import <file> [parent]` | Import .tox |

## Global Flags

- `--port N` — connect to a non-default port
- `--project <path>` — target a specific TD project
- `--json` — raw JSON (pipe-friendly)
- `--timeout <ms>` — request timeout (default 30000)

## References — read these for deeper topics

- **`~/.claude/skills/td-cli/references/gotchas.md`** — read **before writing any `exec` Python**. The TD-099 silent-failure traps: operator-type access, POP/render pipeline, `geometryCOMP` cook loops, GLSL `premultrgbbyalpha`, `feedbackTOP` wiring, audio calibration, parameter-name gotchas table, node layout, handler recovery.
- **`~/.claude/skills/td-cli/references/network-checklist.md`** — read when building an operator network from scratch. A 14-point end-to-end checklist, each item mapping to a trap in `gotchas.md`.
