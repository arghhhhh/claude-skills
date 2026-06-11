# claude-skills

Portable Claude Code skills, agents, and rules — shareable across machines via a single CLI installer.

> **New machine? Paste this into Claude Code:**
>
> *Set up my Claude skills from https://github.com/arghhhhh/claude-skills — ask me which groups to install, then handle the rest including software installation and path configuration.*

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

Use the prompt at the top of this README to kick off setup. Here's what the agent will do:

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
5. **Symlinks slash commands** into `~/.claude/commands/` (e.g. `/models-list` from the `claude-meta` group)
6. **Configures placeholders** from `~/.claude/skills-config.sh`
7. **Appends trigger phrases** to `~/.claude/CLAUDE.md`
8. **Runs a smoke test** to verify the software works

Across all runs, the installer also:
- **Installs shell aliases** for the `claude` CLI — `--chr` → `--chrome`, `--dsp` → `--dangerously-skip-permissions` (added to `~/.zshrc` / `~/.bashrc` / PowerShell profile)
- **Sweeps orphan symlinks** — symlinks under `~/.claude/{skills,agents,commands}/` that no longer correspond to any manifest entry are pruned at the end of each install/update run. Hand-authored files and symlinks pointing outside the managed dir are left alone.

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

The full current list (with descriptions) is the source of truth in `skill-groups/*/manifest.json`. To see it from the CLI:

```bash
bash install.sh --list      # group names
bash install.sh --status    # group + skill versions, plus what's installed locally
```

Notable categories:

- **MCPorter-based skills** (e.g. `comfyui`, `blender`, `houdini`, `claude-mermaid`) also need [mcporter](https://github.com/steipete/mcporter) (`npx mcporter` — auto-installed via npx)
- **Vendored groups** (e.g. `officecli`, `unity-cli`) ship skills sourced from upstream repos rather than authored here. See each group's `manifest.json` for the `source` block. Local customizations live in an `overlays/` subfolder; everything else is pulled fresh on install
- **Meta groups** (e.g. `claude-meta`) install slash commands and agents that operate on Claude itself rather than external software

## Directory Structure

```
claude-skills/
├── install.sh                          # Cross-platform CLI installer
├── config.example.sh                   # Machine-specific config template
├── skill-groups/<group>/               # One dir per group; see install.sh --list
│   ├── manifest.json                   # Software + prerequisites + skills/agents/commands arrays
│   ├── skills/   <name>.md             # Skill content (or directory with SKILL.md)
│   ├── agents/   <name>.md             # Agent definitions (subagent_type prompts)
│   ├── commands/ <name>.md             # Slash command bodies (optional)
│   └── overlays/                       # Local customizations for vendored groups
├── shared/
│   ├── skills/                         # Cross-group skills (always installed)
│   └── claude-md/                      # CLAUDE.md trigger-phrase snippets per group
└── README.md
```

After installation, the following is created in `~/.claude/`:

```
~/.claude/
├── skills/                 # Symlinks (or copies with configured placeholders)
├── agents/                 # Symlinks to agent definitions
├── commands/               # Symlinks to slash-command bodies
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

```bash
bash install.sh --verify             # Check symlinks, files, CLAUDE.md, prerequisites
bash install.sh --status             # Version table (local vs repo)
bash install.sh --test-integration   # Test live connections (software must be running)
```

Prerequisites and integration test commands are defined per group in each `manifest.json` — run `--verify` to see what's missing.

## Adding a New Skill Group

1. Create `skill-groups/<name>/manifest.json` (see existing ones for format)
2. Add skill `.md` files under `skill-groups/<name>/skills/` — include `version: 1.0.0` in YAML frontmatter
3. Add agent `.md` files under `skill-groups/<name>/agents/`
4. Add a CLAUDE.md snippet to `shared/claude-md/<name>.md`
5. The installer reads the manifest to know what to install and test
