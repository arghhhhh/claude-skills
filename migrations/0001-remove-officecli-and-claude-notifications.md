---
title: Stop managing officecli and claude-notifications (groups removed)
---

The `officecli` and `claude-notifications` groups were removed from claude-skills.
officecli installs and refreshes its own skills (`officecli skills`, `officecli install`),
so the vendored copy only duplicated them. claude-notifications is a Claude Code plugin
with its own installer. This removes what claude-skills set up for them. It leaves the
officecli binary, its skill folders and the notifications plugin installed. Every step
checks first, so the migration is safe on machines that never had these groups.

1. **CLAUDE.md section.** If `~/.claude/CLAUDE.md` contains the line
   `## OfficeCLI - Office Document Creation & Editing`, back the file up to
   `~/.claude/CLAUDE.md.bak-officecli`, then delete that line through the next line that
   is exactly `---` (inclusive). Keep the file's line endings. claude-notifications never
   had a section.
2. **Vendored clone.** Delete `~/.claude/.skill-repos/iOfficeAI-OfficeCLI/` if it exists.
3. **Skill links.** For each entry in `~/.claude/skills/` named `officecli`, `officecli-*`,
   `morph-ppt` or `morph-ppt-*`: if it is a symlink (it pointed into the clone from
   step 2 and is now broken), remove it. Leave real folders alone: officecli writes and
   refreshes those itself. If the user still uses officecli and those folders are
   missing, `officecli skills` reinstalls them.
4. **Ledgers.** Remove the lines `officecli` and `claude-notifications` from
   `~/.claude/.skills-meta/known-groups`, and the lines starting with `officecli ` or
   `claude-notifications ` from `~/.claude/.skills-meta/group-revs`, if present.
5. Tell the user the software is still installed and how to remove it if they want:
   `claude plugin uninstall claude-notifications-go@claude-notifications-go` for the
   plugin, and officecli's own uninstall instructions
   (https://github.com/iOfficeAI/OfficeCLI) for the binary.
6. Run `bash ~/.claude/.skill-repos/claude-skills/install.sh --mark-migration 0001`.
