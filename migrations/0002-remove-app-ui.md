---
title: Remove the app-ui group (Unity's App UI package ships these skills)
---

The `app-ui` group was removed from claude-skills. Unity's App UI package (2.2.0-pre.7
and later) ships the same five skills: in Unity, open **Window > Package Manager**,
select **App UI**, expand **AI Agent Skills** and click **Install All**. That installs
them into the project's `.claude/skills`, so they load only in App UI projects and update
with the package. This removes the global copies claude-skills installed and their
CLAUDE.md section. Every step checks first, so it is safe to re-run.

1. **CLAUDE.md section.** If `~/.claude/CLAUDE.md` contains the line
   `## App UI - Unity UI Framework`, back the file up to `~/.claude/CLAUDE.md.bak-app-ui`,
   then delete that line through the next line that is exactly `---` (inclusive). Keep
   the file's line endings.
2. **Global skill copies.** For each of `app-ui`, `app-ui-mvvm`, `app-ui-navigation`,
   `app-ui-redux`, `app-ui-theming` in `~/.claude/skills/`:
   - Missing: skip it.
   - A symlink: remove it (it pointed into the claude-skills repo and is now broken).
   - A folder: delete it only if claude-skills put it there, meaning its `SKILL.md` is
     a version the repo shipped. Check with
     `git -C ~/.claude/.skill-repos/claude-skills log --format= --raw --no-abbrev -- skill-groups/app-ui/skills/<name>/SKILL.md`,
     which lists every blob hash that file ever had (the 4th column), and compare against
     `git hash-object ~/.claude/skills/<name>/SKILL.md`. If the hash isn't in that list
     (Unity's installer or the user wrote it), leave the folder and tell the user.
3. **Ledgers.** Remove the line `app-ui` from `~/.claude/.skills-meta/known-groups`, and
   lines starting with `app-ui ` from `~/.claude/.skills-meta/group-revs`, if present.
4. Tell the user how to get the skills back per project (the Package Manager steps above).
5. Run `bash ~/.claude/.skill-repos/claude-skills/install.sh --mark-migration 0002`.
