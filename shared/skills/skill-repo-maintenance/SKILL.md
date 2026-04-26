---
version: 1.3.0
name: skill-repo-maintenance
description: Maintain the claude-skills repo — update skill versions, add new skills, sync across machines. Use when editing skill files, creating new skill groups, or when a skill needs updating. Ensures changes are versioned, committed, and pushed so all machines stay in sync.
---

# Skill Repo Maintenance

This skill governs how to keep the `claude-skills` repo (`arghhhhh/claude-skills`) synchronized when skills are added, updated, or modified.

## Repo Location

The repo lives at `~/.claude/.skill-repos/claude-skills/`. All skill edits should happen in this directory, not directly in `~/.claude/skills/` (those are symlinks).

## Before Any Skill Edit

**Always pull first** to avoid conflicts with changes made from other machines:

```bash
cd ~/.claude/.skill-repos/claude-skills && git pull origin main
```

For unity-cli skills (sourced from a separate repo):

```bash
cd ~/.claude/.skill-repos/unity-cli && git pull origin main
```

If the pull has changes, re-run the installer to update local symlinks:

```bash
cd ~/.claude/.skill-repos/claude-skills && bash install.sh --skills <affected-group> --skip-software
```

## Updating an Existing Skill

### 1. Edit the source file

Skills live in `skill-groups/<group>/skills/<skill-name>/`. Edit the file there, NOT the symlink in `~/.claude/skills/`.

For unity-cli skills, edit in `~/.claude/.skill-repos/unity-cli/.claude-plugin/plugins/unity-cli/skills/<skill-name>/SKILL.md`.

### 2. Bump the version

Update the `version:` field in the skill's frontmatter. Use semver:
- **Patch** (1.0.0 → 1.0.1): Typo fixes, clarifications, minor wording changes
- **Minor** (1.0.0 → 1.1.0): New commands, new sections, expanded guidance
- **Major** (1.0.0 → 2.0.0): Restructured skill, changed tool names, breaking workflow changes

```yaml
---
version: 1.1.0
name: my-skill
description: ...
---
```

### 3. Commit and push

```bash
cd ~/.claude/.skill-repos/claude-skills
git add skill-groups/<group>/skills/<skill-name>/
git commit -m "Update <skill-name> to v1.1.0 — <what changed>"
git push origin main
```

For unity-cli skills:

```bash
cd ~/.claude/.skill-repos/unity-cli
git add .claude-plugin/plugins/unity-cli/skills/<skill-name>/
git commit -m "Update <skill-name> to v1.1.0 — <what changed>"
git push origin main
```

### 4. Verify

```bash
cd ~/.claude/.skill-repos/claude-skills && bash install.sh --status
```

## Adding a New Skill to an Existing Group

### 1. Create the skill file

```bash
mkdir -p ~/.claude/.skill-repos/claude-skills/skill-groups/<group>/skills/<new-skill>/
```

Write `SKILL.md` with frontmatter:

```yaml
---
version: 1.0.0
name: new-skill
description: What this skill does and when to use it.
---
```

### 2. Add to manifest

Edit `skill-groups/<group>/manifest.json` and add the skill name to the `"skills"` array.

### 3. Add CLAUDE.md snippet (if needed)

If the skill has unique trigger phrases not covered by the group's existing snippet, update `shared/claude-md/<group>.md`.

### 4. Commit, push, reinstall

```bash
cd ~/.claude/.skill-repos/claude-skills
git add skill-groups/<group>/ shared/claude-md/<group>.md
git commit -m "Add <new-skill> to <group>"
git push origin main
bash install.sh --skills <group> --skip-software
```

## Adding a New Skill Group

### 1. Create directory structure

```bash
mkdir -p skill-groups/<name>/skills/<skill-name>/
mkdir -p skill-groups/<name>/agents/  # if the group has an agent
```

### 2. Create manifest.json

Must include: `name`, `description`, `version`, `prerequisites`, `install`, `test`, `skills`, `agents`.
See any existing manifest for the template.

Optional fields:
- **`mcp_servers`**: Object mapping server names to `{ "command": "...", "args": [...] }`. The installer auto-generates `~/.mcporter/mcporter.json` and `~/.claude/.mcp.json` entries. Use `{{PLACEHOLDER}}` for machine-specific paths (resolved from `skills-config.sh`). Commands are auto-resolved to full paths on Windows.
- **`post_install_hints`**: Array of strings printed after install. Use for optional setup steps the installer can't automate (e.g., API keys, browser auth, manual addon installation).
- **`agent_renames`**: Object mapping source filenames to agent names when they differ.

### 3. Create CLAUDE.md snippet

```bash
# shared/claude-md/<name>.md
## Group Name - Description
When [trigger conditions], read `~/.claude/skills/<skill-name>/SKILL.md`.
Trigger phrases: "keyword1", "keyword2", ...
```

### 4. Commit, push, install

```bash
git add skill-groups/<name>/ shared/claude-md/<name>.md
git commit -m "Add <name> skill group"
git push origin main
bash install.sh --skills <name>
```

## Syncing Another Machine

On any other machine, just pull and reinstall:

```bash
cd ~/.claude/.skill-repos/claude-skills
git pull origin main
bash install.sh --update --sync
```

Or for a fresh machine:

```bash
git clone https://github.com/arghhhhh/claude-skills.git ~/.claude/.skill-repos/claude-skills
cd ~/.claude/.skill-repos/claude-skills
bash install.sh
```

## First-Time Setup on a New Machine

When the user asks to "set up my skills", "install claude-skills", or "set up Claude on this machine", follow this workflow:

### 1. Clone the repo (if not already present)

```bash
if [ -d ~/.claude/.skill-repos/claude-skills ]; then
  cd ~/.claude/.skill-repos/claude-skills && git pull origin main
else
  mkdir -p ~/.claude/.skill-repos
  git clone https://github.com/arghhhhh/claude-skills.git ~/.claude/.skill-repos/claude-skills
fi
```

### 2. Run the installer

```bash
cd ~/.claude/.skill-repos/claude-skills && bash install.sh -y
```

The `-y` flag runs non-interactively (installs all groups, skips manual-install prompts).

### 3. Resolve {{PLACEHOLDER}} variables

After install, run `bash install.sh --verify` and check for `{{PLACEHOLDER}}` warnings. If any exist, **you** (the agent) should resolve them by searching the machine for the correct paths:

**Strategy for finding paths:**
- `which <binary>` or `command -v <binary>` — finds executables on PATH
- `find / -name "<binary>" -type f 2>/dev/null | head -5` — broader search (use sparingly)
- On Windows Git Bash: `where.exe <binary>` or search common locations
- Check common install locations:
  - Miniconda: `~/miniconda3/Scripts/`, `~/miniconda3/bin/`
  - Homebrew: `/opt/homebrew/bin/`, `/usr/local/bin/`
  - Cargo: `~/.cargo/bin/`
  - Go: `~/go/bin/`
  - npm global: check `npm root -g`
  - Windows tools: `C:/Users/*/tools/`, `C:/Program Files/`

**Once you find the paths**, write `~/.claude/skills-config.sh`:

```bash
# Example — fill in paths you actually found on this machine
COMFY_CLI="/path/to/comfy"
COMFYUI_WORKSPACE="/path/to/ComfyUI"
COMFYUI_PYTHON=""  # leave empty if not using Windows standalone
GOBS_CLI="/path/to/gobs-cli"
OBS_CONFIG_DIR="$HOME/.config/obs-studio"  # or AppData/Roaming on Windows
```

Then re-run the installer to apply the config:

```bash
cd ~/.claude/.skill-repos/claude-skills && bash install.sh --update
```

### 4. Verify and report

```bash
cd ~/.claude/.skill-repos/claude-skills && bash install.sh --verify
```

Report the results to the user. If any software smoke tests failed, let them know what needs manual attention (e.g., "OBS Studio needs to be installed from obsproject.com").

### 5. Register MCP servers (if applicable)

Some skills require MCP server registration. Check post-install hints in the installer output. Common ones:
- `officecli mcp claude` — registers OfficeCLI MCP server

## Key Rules

1. **Always pull before editing** — other machines may have pushed changes
2. **Always bump the version** — even for small changes; `--status` depends on it
3. **Edit source files, not symlinks** — `~/.claude/skills/` contains symlinks pointing to the repo
4. **Push after every change** — unpushed changes won't sync to other machines
5. **Unity-cli skills live in a separate repo** — `arghhhhh/unity-cli`, not `arghhhhh/claude-skills`
6. **Run `--verify` after changes** — catches broken symlinks, missing files, version mismatches
