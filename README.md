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
```

## What It Does

For each selected skill group, the installer:
1. **Installs the software** (e.g. `cargo install unity-cli`, `pip install comfy-cli`)
2. **Symlinks skills** into `~/.claude/skills/`
3. **Symlinks agents** into `~/.claude/agents/`
4. **Appends trigger phrases** to `~/.claude/CLAUDE.md`
5. **Runs a smoke test** to verify the software works

## Skill Groups

| Group | Software | Install Method | Skills | Agent |
|-------|----------|---------------|--------|-------|
| `unity-cli` | [unity-cli](https://github.com/arghhhhh/unity-cli) | `cargo install` | 13 skills (scene, prefab, C#, assets, etc.) | `unity` |
| `comfyui` | [comfy-cli](https://github.com/Comfy-Org/comfy-cli) + [comfy-pilot](https://github.com/ConstantineB6/comfy-pilot) | `pip install` | `comfy-cli`, `comfy-pilot` | `comfyui` |
| `obs-studio` | [gobs-cli](https://github.com/muesli/obs-cli) | `go install` / binary | `obs-cli` | `obs-studio` |
| `blender` | [Blender](https://www.blender.org/) + [blender-mcp](https://github.com/ahujasid/blender-mcp) | manual / `brew` | `blender-mcp` | `blender` |

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

## Machine-Specific Configuration

Some skills have `{{PLACEHOLDER}}` variables for machine-specific paths (binary locations, workspaces, etc.). After installing:

1. Copy `config.example.sh` to `~/.claude/skills-config.sh`
2. Fill in your machine's paths
3. Re-run the installer or manually edit the skill files

## Cross-Platform Notes

- **macOS/Linux**: Symlinks work natively
- **Windows**: Requires Developer Mode enabled for symlinks, falls back to junction points or copies
- All skill files use `~/.claude/skills/` paths internally

## Adding a New Skill Group

1. Create `skill-groups/<name>/manifest.json` (see existing ones for format)
2. Add skill `.md` files under `skill-groups/<name>/skills/`
3. Add agent `.md` files under `skill-groups/<name>/agents/`
4. Add a CLAUDE.md snippet to `shared/claude-md/<name>.md`
5. The installer reads the manifest to know what to install and test
