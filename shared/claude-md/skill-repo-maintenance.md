## Skill Repo Maintenance

When editing, updating, adding skills/agents, or setting up Claude on a new machine, read `~/.claude/skills/skill-repo-maintenance/SKILL.md` first. It ensures changes are versioned, committed, pushed, and synced across machines. It also covers first-time setup including auto-resolving machine-specific paths.

**Always pull before editing skills** — another machine may have pushed changes.

**"Update claude-skills" means update EVERYTHING it installed, not only the group mentioned.** After pulling, run `install.sh --preview-update`, ask the user before adding anything it lists as `NEW-*` (new groups, skills, agents, commands, env vars), then `install.sh --update --yes`. A pull alone leaves copied hooks and commands stale. Full procedure: "Updating claude-skills" in the SKILL.md.

**Before answering "do we have a skill for X" or "can I install Y" questions:** the local skills repo at `~/.claude/.skill-repos/claude-skills` may be behind origin. Run `git -C ~/.claude/.skill-repos/claude-skills fetch --quiet && git -C ~/.claude/.skill-repos/claude-skills log --oneline HEAD..origin/main` first. If commits are listed, the repo is behind — pull (or at least check `origin/main:skill-groups/`) before claiming a skill doesn't exist. Don't auto-pull if there are uncommitted local changes; surface them to the user instead.

Trigger phrases: "update claude-skills", "update my skills", "update skill", "add skill", "edit skill", "new skill group", "sync skills", "skill version", "bump version", "set up my skills", "install claude-skills", "set up Claude", "do we have a skill", "is there a skill", "available skill", "skill installed"
