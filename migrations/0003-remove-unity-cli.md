---
title: Remove the unity-cli group (use upstream's plugin and installer)
---

The `unity-cli` group was removed from claude-skills. Upstream covers everything it
did: the Claude Code plugin ships the skills and `unity-helper` agent, upstream's
installer fetches a checksum-verified release binary, and the binary keeps itself
current. The group instead built a pinned commit with cargo, held it there with
`UNITY_CLI_NO_AUTO_UPDATE`, and copied the skills. Every step checks first, so it is
safe to re-run.

Steps 1-5 remove what claude-skills installed. Steps 6-7 set up upstream's version,
so **ask the user first** whether they still use unity-cli, and whether they build it
from source (contributors use the fork's `scripts/install-from-source.sh` instead,
and keep `UNITY_CLI_NO_AUTO_UPDATE=1`).

1. **CLAUDE.md section.** If `~/.claude/CLAUDE.md` contains the line
   `## Unity CLI - Unity Editor Automation`, back the file up to
   `~/.claude/CLAUDE.md.bak-unity-cli`, then delete that line through the next line that
   is exactly `---` (inclusive). Keep the file's line endings.
2. **Skills.** For each `~/.claude/skills/unity-*` entry:
   - A symlink: remove it.
   - Listed in `~/.claude/skills/.unity-cli-skills.json`: leave it. unity-cli's own
     `skills install` owns it.
   - Otherwise delete the folder only if claude-skills put it there: its `SKILL.md`
     blob (`git hash-object <dir>/SKILL.md`) appears in the 4th column of
     `git -C <repo> log --all --format= --raw --no-abbrev -- <path>` for any of
     `~/.claude/.skill-repos/akiojin-unity-cli` and `~/.claude/.skill-repos/arghhhhh-unity-cli`
     (path `.claude-plugin/plugins/unity-cli/skills/<name>/SKILL.md`) or
     `~/.claude/.skill-repos/claude-skills` (path
     `skill-groups/unity-cli/overlays/skills/<name>/SKILL.md`). If no match, keep it and
     tell the user.
3. **Agent.** Remove `~/.claude/agents/unity.md` if it is a symlink, or if its blob
   appears in the claude-skills history of
   `skill-groups/unity-cli/overlays/agents/unity-helper.md` (same check as step 2).
4. **Clones.** After steps 2-3, delete `~/.claude/.skill-repos/akiojin-unity-cli/` and
   `~/.claude/.skill-repos/arghhhhh-unity-cli/` if present.
5. **Ledgers.** Remove the line `unity-cli` from `~/.claude/.skills-meta/known-groups`
   and lines starting with `unity-cli ` from `~/.claude/.skills-meta/group-revs`.
6. **Binary.** If `cargo install --list` lists `unity-cli`, stop the daemon
   (`unity-cli unityd stop`) and run `cargo uninstall unity-cli`. If the user still uses
   unity-cli and does not build from source, install the release:
   - macOS / Linux: `curl -fsSL https://raw.githubusercontent.com/akiojin/unity-cli/main/scripts/install.sh | sh`
   - Windows: `powershell -NoProfile -Command "irm https://raw.githubusercontent.com/akiojin/unity-cli/main/scripts/install.ps1 | iex"`

   Then remove the `UNITY_CLI_NO_AUTO_UPDATE` override so it keeps itself current: on
   Windows `[Environment]::SetEnvironmentVariable('UNITY_CLI_NO_AUTO_UPDATE',$null,'User')`;
   in shell profiles, delete the block between `# >>> claude-skills user_env (unity-cli) >>>`
   and `# <<< claude-skills user_env (unity-cli) <<<`. Contributors keep it.
7. **Plugin.** Tell the user to run, in Claude Code, `/plugin marketplace add akiojin/unity-cli`
   then `/plugin install unity-cli@unity-cli` (contributors can use
   `unity-cli skills install claude-code` from their own build instead), and to restart
   Claude Code.
8. Run `bash ~/.claude/.skill-repos/claude-skills/install.sh --mark-migration 0003`.
