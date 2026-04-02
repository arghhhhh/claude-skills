# claude-skills

Portable Claude Code skills, agents, and rules — shareable across machines via a single CLI installer.

## Quick Start

```bash
# macOS/Linux
./install.sh

# Windows (Git Bash or WSL)
bash install.sh
```

## What This Does

The installer:
1. Lists available skill groups (e.g. `unity-cli`, `comfyui`, `obs-studio`, `blender`)
2. Lets you pick which to install (or pass `--skills unity-cli,obs-studio`)
3. For each skill group: installs the software dependency, symlinks skills/agents into `~/.claude/`, and runs a smoke test
4. Copies shared rules and CLAUDE.md entries

## Skill Groups

| Group | Software | Skills | Agent |
|-------|----------|--------|-------|
| `unity-cli` | [unity-cli](https://github.com/arghhhhh/unity-cli) (Rust CLI) | 14 skills (scene, prefab, C#, assets, testing, etc.) | `unity` |
| `comfyui` | [ComfyUI](https://github.com/comfyanonymous/ComfyUI) + comfy-cli | `comfy-cli`, `comfy-pilot` | `comfyui` |
| `obs-studio` | [OBS Studio](https://obsproject.com/) + obs-cli | `obs-cli` | `obs-studio` |
| `blender` | [Blender](https://www.blender.org/) + blender-mcp | `blender-mcp` | `blender` |

## Directory Structure

```
claude-skills/
├── install.sh              # Cross-platform CLI installer
├── skill-groups/
│   ├── unity-cli/
│   │   ├── manifest.json   # Dependencies, skills list, test command
│   │   ├── skills/         # Skill files to symlink
│   │   └── agents/         # Agent files to symlink
│   ├── comfyui/
│   ├── obs-studio/
│   └── blender/
├── shared/
│   ├── rules/              # Shared rules (optional)
│   └── claude-md/          # CLAUDE.md snippets per skill group
└── README.md
```

## Adding a New Skill Group

1. Create `skill-groups/<name>/manifest.json`
2. Add skill files under `skill-groups/<name>/skills/`
3. Add agent files under `skill-groups/<name>/agents/`
4. The installer reads the manifest to know what to install and test

## Cross-Platform Notes

- Symlinks work natively on macOS/Linux
- On Windows, the installer uses `mklink` (may require Developer Mode or admin for symlinks) with a fallback to junction points for directories
- All paths use forward slashes internally; the installer handles conversion
