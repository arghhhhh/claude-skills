## Obsidian CLI - Vault Control from the Command Line

When the user wants an agent to read from or drive their Obsidian vault(s) — search/read/create/append notes, open daily notes, list tags/tasks/unresolved links, reload a plugin, or run editor commands or JavaScript against a running Obsidian instance — read `~/.claude/skills/obsidian-cli/SKILL.md`.

The CLI is built into the Obsidian desktop app (1.9+); every command talks to the desktop app (launching it if closed), and the CLI must be **registered** once via Settings → General. Always pass `vault="Name"` explicitly and add `format=json` when parsing.

Trigger phrases: "obsidian", "obsidian cli", "my vault", "daily note", "obsidian search", "obsidian eval", "reload plugin", "obsidian note", "append to daily"
