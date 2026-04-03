# claude-skills

Portable Claude Code skills, agents, and rules — shareable across machines via a single CLI installer.

## Quick Start

```bash
# Clone
git clone https://github.com/arghhhhh/claude-skills.git
cd claude-skills

# Interactive — pick which groups to install
bash install.sh

# Or install specific groups
bash install.sh --skills unity-cli,blender

# Skills only (skip software installation)
bash install.sh --skills comfyui --skip-software

# List available groups
bash install.sh --list

# Verify everything is correctly installed
bash install.sh --verify

# See version status of all skills
bash install.sh --status

# Update installed skills from repo
bash install.sh --update

# Bidirectional sync (also push local improvements back to repo)
bash install.sh --update --sync

# Test live connections (software must be running)
bash install.sh --test-integration --skills unity-cli
```

## Agent-Driven Setup (Recommended)

The easiest way to set up on a new machine is to point Claude at this repo and let it handle everything.

**Prompt for a fresh machine (no skills installed yet):**

> Set up my Claude skills from https://github.com/arghhhhh/claude-skills — ask me which groups to install, then handle the rest including software installation and path configuration.

**What the agent will do:**
1. Clone the repo to `~/.claude/.skill-repos/claude-skills/`
2. Show you the available skill groups and ask which to install (or all)
3. Ask whether to also install the software dependencies
4. Run the installer
5. Search the machine for any `{{PLACEHOLDER}}` paths (binary locations, workspace dirs) and auto-resolve them into `~/.claude/skills-config.sh`
6. Re-run the installer to apply the config
7. Run `--verify` and report results

**After first-time setup, the `skill-repo-maintenance` skill is installed and teaches agents how to update/add/sync skills going forward.** From that point on, the agent can reference that skill directly.

**Other useful prompts:**
- "Sync my skills" — pulls latest from repo and updates
- "Add a new skill for X" — creates skill files, bumps versions, pushes
- "Check my skill versions" — runs `--status`

## What It Does

For each selected skill group, the installer:
1. **Checks prerequisites** (cargo, pip, npx, etc.)
2. **Installs the software** (e.g. `cargo install unity-cli`, `pip install comfy-cli`)
3. **Symlinks skills** into `~/.claude/skills/` (with version tracking)
4. **Symlinks agents** into `~/.claude/agents/`
5. **Configures placeholders** from `~/.claude/skills-config.sh`
6. **Appends trigger phrases** to `~/.claude/CLAUDE.md`
7. **Runs a smoke test** to verify the software works

On first run from a temporary directory (e.g. `/tmp`), the repo is automatically copied to `~/.claude/.skill-repos/claude-skills/` so symlinks survive reboots.

## Skill Versioning

Every skill file includes a `version` field in its YAML frontmatter:

```yaml
---
version: 1.2.0
---

# My Skill
...
```

The installer tracks versions to enable:
- **`--status`**: See which skills are up to date, have updates available, or are newer locally
- **`--update`**: Pull newer versions from the repo into your local install
- **`--update --sync`**: Also push locally-improved skills back into the repo

When updating, the installer automatically backs up your existing skills to `~/.claude/.skill-backups/`.

## Skill Groups

| Group | Software | Install Method | Skills | Agent |
|-------|----------|---------------|--------|-------|
| `unity-cli` | [unity-cli](https://github.com/arghhhhh/unity-cli) | `cargo install` (requires Rust) | 13 skills | `unity` |
| `comfyui` | [comfy-cli](https://github.com/Comfy-Org/comfy-cli) + [comfy-pilot](https://github.com/ConstantineB6/comfy-pilot) | `pip install` | `comfy-cli`, `comfy-pilot` | `comfyui` |
| `obs-studio` | [gobs-cli](https://github.com/muesli/obs-cli) | `go install` / brew / binary | `obs-cli` | `obs-studio` |
| `blender` | [Blender](https://www.blender.org/) + [blender-mcp](https://github.com/ahujasid/blender-mcp) | manual / `brew` | `blender-mcp` | `blender` |
| `app-ui` | [Unity App UI](https://docs.unity3d.com/Packages/com.unity.dt.app-ui@2.2/manual/index.html) | Unity Package Manager | 5 skills | — |

MCPorter-based skills (comfyui, blender) also need [mcporter](https://github.com/steipete/mcporter) (`npx mcporter` — auto-installed via npx).

## Directory Structure

```
claude-skills/
├── install.sh                          # Cross-platform CLI installer
├── config.example.sh                   # Machine-specific config template
├── skill-groups/
│   ├── unity-cli/
│   │   └── manifest.json               # Points to arghhhhh/unity-cli repo
│   ├── comfyui/
│   │   ├── manifest.json
│   │   ├── skills/                     # comfy-cli.md, comfy-pilot.md
│   │   └── agents/                     # comfyui.md
│   ├── obs-studio/
│   │   ├── manifest.json
│   │   ├── skills/                     # obs-cli.md
│   │   └── agents/                     # obs-studio.md
│   └── blender/
│       ├── manifest.json
│       ├── skills/mcp/                 # blender-mcp.md
│       └── agents/                     # blender.md
├── shared/
│   ├── skills/                         # mcp-setup.md (shared across groups)
│   └── claude-md/                      # CLAUDE.md snippets per group
└── README.md
```

After installation, the following is created in `~/.claude/`:

```
~/.claude/
├── skills/                 # Symlinks (or copies with configured placeholders)
├── agents/                 # Symlinks to agent definitions
├── .skill-repos/
│   └── claude-skills/      # Canonical repo copy (symlinks point here)
├── .skills-meta/
│   └── repo-path           # Stored repo location
├── .skill-backups/         # Timestamped backups (created on update)
├── skills-config.sh        # Machine-specific config (you create this)
└── CLAUDE.md               # Trigger phrases appended here
```

## Machine-Specific Configuration

Some skills have `{{PLACEHOLDER}}` variables for machine-specific paths. The installer will automatically substitute values from your config file:

1. Copy `config.example.sh` to `~/.claude/skills-config.sh`
2. Fill in your machine's paths
3. Re-run the installer — placeholders are replaced automatically

When a skill has placeholders and a config value is available, the symlink is replaced with a configured copy (the repo original stays as a template).

## Updating Skills Across Machines

The typical workflow for keeping skills in sync:

```bash
# Machine A: improve a skill, bump its version
# (edit ~/.claude/skills/comfy-cli.md, change version: 1.0.0 → 1.1.0)

# Sync the improvement back to the repo
bash install.sh --update --sync
cd ~/.claude/.skill-repos/claude-skills
git add -A && git commit -m "Bump comfy-cli to 1.1.0" && git push

# Machine B: pull and update
cd ~/.claude/.skill-repos/claude-skills
git pull
bash install.sh --update
```

## Cross-Platform Notes

- **macOS/Linux**: Symlinks work natively
- **Windows**: Requires Developer Mode enabled for symlinks, falls back to junction points or copies
- All skill files use `~/.claude/skills/` paths internally

## Verification & Testing

### `--verify` — Post-install health check (no runtime needed)
Checks all layers for each group:
- **Prerequisites**: Are required tools (cargo, pip, npx, etc.) available?
- **Software**: Is the CLI binary installed and callable?
- **Skills/Agents**: Are files symlinked, non-empty, versioned, and free of broken links?
- **CLAUDE.md**: Are trigger phrases present?
- **Configuration**: Any `{{PLACEHOLDER}}` vars left unconfigured?

```bash
bash install.sh --verify
# 23 passed  1 warnings  0 failed
```

### `--status` — Version overview
Shows a table of all skills with local vs repo versions:

```bash
bash install.sh --status
# Skill                     Local   Repo    Status
# comfyui/comfy-cli         1.1.0   1.2.0   update available
# blender/mcp/blender-mcp   1.0.0   1.0.0   up to date
# obs-studio/obs-cli        1.1.0   1.0.0   local newer
```

### `--test-integration` — Live connection test (software must be running)
Tests that the software actually responds to commands:

| Group | What it tests |
|-------|--------------|
| `unity-cli` | `unity-cli system ping` — Unity Editor + bridge package |
| `comfyui` | `curl http://127.0.0.1:8188/system_stats` — ComfyUI server |
| `obs-studio` | `gobs-cli obs-version` — OBS + obs-websocket |
| `blender` | `npx mcporter call blender.get_scene_info` — Blender + MCP addon |

### Prerequisites per group

| Group | Required | Optional |
|-------|----------|----------|
| `unity-cli` | `cargo` (Rust), `git` | — |
| `comfyui` | `pip` (Python) | `npx` (Node.js, for comfy-pilot) |
| `obs-studio` | — | `go` (only if building from source) |
| `blender` | `npx` (Node.js) | — |
| `app-ui` | — | — |

## Adding a New Skill Group

1. Create `skill-groups/<name>/manifest.json` (see existing ones for format)
2. Add skill `.md` files under `skill-groups/<name>/skills/` — include `version: 1.0.0` in YAML frontmatter
3. Add agent `.md` files under `skill-groups/<name>/agents/`
4. Add a CLAUDE.md snippet to `shared/claude-md/<name>.md`
5. The installer reads the manifest to know what to install and test
