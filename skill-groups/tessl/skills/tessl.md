---
version: 0.1.0
---

# Tessl CLI Skill

Use this skill when working with **Tessl** — the package manager for agent skills. Tessl lets you search, install, publish, version, and evaluate skills (and rules/docs) from the Tessl Registry, so coding agents can reuse versioned context across projects.

Trigger phrases: "tessl", "tessl install", "tessl skill", "tessl registry", "agent skill package", "publish skill to tessl".

## Setup

- **Binary**: `tessl` (installed to `~/.local/bin/tessl`)
- **Install**: `curl -fsSL https://get.tessl.io | sh`
- **Self-update**: `tessl cli update`
- **Diagnose**: `tessl doctor`
- **Auth**: `tessl login` (or `tessl auth login`) — required for publishing, workspaces, and private registry access. Searching/installing public skills works unauthenticated.
- **Who am I**: `tessl whoami`

If `tessl` is not on PATH, ensure `~/.local/bin` is in `$PATH`.

## Core Concepts

- **Tile**: A versioned package containing one or more skills, rules, or docs.
- **Skill**: A unit of agent context/instructions (typically a `SKILL.md` file with a `tile.json`).
- **Workspace**: An org-scoped namespace (`workspace/tile-name`) for publishing.
- **Project**: A directory with a `tessl.json` manifest, created via `tessl init`.

## Common Commands

### Project setup
```bash
tessl init                          # Create tessl.json in current dir
tessl init --agent claude-code      # Wire MCP config for Claude Code
tessl init --agent cursor --agent codex
```
Supported agents: `claude-code`, `cursor`, `gemini`, `codex`, `openhands`, `openclaw`, `copilot`, `copilot-vscode`, `agents`.

### Search & discover
```bash
tessl search                        # Browse interactively
tessl search "react testing"        # Keyword search
tessl search --type skills "auth"   # Filter by type (skills|docs|rules)
tessl search --json "firebase"      # Scriptable output
```

### Install
```bash
tessl install workspace/tile             # Latest version
tessl install workspace/tile@1.2.0       # Specific version
tessl install github:user/repo           # From GitHub
tessl install --global workspace/tile    # Install to ~/.tessl/ globally
tessl install --skill foo --skill bar github:user/repo  # Pick specific skills
tessl install --agent claude-code workspace/tile         # Override target agent
tessl install --yes --accept-warnings workspace/tile     # Non-interactive
```

### Manage installed tiles
```bash
tessl list                          # List installed tiles
tessl list --global
tessl outdated                      # Check for updates
tessl update                        # Update all
tessl update workspace/tile         # Update one
tessl uninstall workspace/tile
```

### Authoring skills
```bash
tessl skill new --name my-skill --description "..."   # Scaffold new skill
tessl skill import ./path/to/SKILL.md                  # Wrap existing SKILL.md as a tile
tessl skill lint ./tile.json                           # Validate structure
tessl skill review ./path                              # Quality/compliance review
tessl skill review --optimize ./path                   # Auto-improve
tessl skill publish --workspace myorg --public         # Publish to registry
tessl skill publish --bump minor --dry-run             # Preview version bump
```

### Tiles (lower-level)
```bash
tessl tile new
tessl tile lint
tessl tile pack
tessl tile publish
tessl tile info <tile>
tessl tile unpublish <tile>
tessl tile archive <tile>
```

### Evaluations
```bash
tessl eval run                                   # Run evals from current tile
tessl eval run --agent claude-code:opus-4 ./skill
tessl eval list --mine
tessl eval view --last
tessl eval retry --last
tessl scenario generate                          # Generate eval scenarios
```

### Workspaces & org
```bash
tessl org list
tessl workspace list
tessl workspace create <name>
tessl workspace add-member <workspace> <user>
```

### Config & API keys
```bash
tessl config list
tessl config set <key> <value>
tessl api-key create
tessl api-key list
```

## Typical Workflows

- **Add a public skill to a project**:
  `tessl init --agent claude-code` → `tessl search <topic>` → `tessl install workspace/tile`
- **Publish your own skill**:
  `tessl skill new --name foo` → edit `SKILL.md` → `tessl skill lint` → `tessl skill review` → `tessl skill publish --workspace myorg --public`
- **Keep installed skills fresh**:
  `tessl outdated` → `tessl update`
- **Install ad-hoc from GitHub**:
  `tessl install github:owner/repo --skill <name>`

## Tips

- Use `--json` on `search`, `list`, `outdated`, `eval list`, `doctor` for scripting.
- `tessl install --watch-local` reinstalls automatically when editing a local file-source tile during authoring.
- `tessl doctor` is the first thing to run when something looks off — checks auth + manifest health.
- `tessl skill review --optimize` will iteratively edit the skill file; commit first.
- Global installs (`--global`) live in `~/.tessl/`; per-project installs are tracked in `tessl.json`.

## Docs

- Site: https://tessl.io/
- Docs: https://docs.tessl.io/
- Registry: https://tessl.io/registry
