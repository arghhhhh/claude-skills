# Migrations

Instructions for an **agent**, for repo changes `install.sh --update` can't make by
itself: moving files the installer doesn't own, hand-edited config that needs
rewriting, renamed settings, one-off cleanup on machines that installed an older
layout. Anything the installer *can* do idempotently belongs in `install.sh`, not here.

## File format

`migrations/NNNN-<slug>.md`, numbered in order. The 4-digit prefix is the id.

```markdown
---
title: One line saying what changes
groups: unity-cli, blender
---

What changed and why, then numbered steps the agent follows. Say how to check
whether the machine already has the new layout, so the steps are safe to re-run.
```

`groups:` is optional. It limits the migration to machines where at least one listed
group is installed; omit it or write `all` to apply everywhere.

## Lifecycle

| Step | Who | What |
|---|---|---|
| Pull | user / updater | New `NNNN-*.md` lands in the repo |
| Detect | `install.sh --preview-update` | `MIGRATION <id> <title>` line per pending migration |
| Remind | `install.sh --update`, install | Lists pending migrations with a ready-to-run `claude "..."` command |
| Apply | agent | Follows the file, then runs `bash install.sh --mark-migration <id>` |

Applied ids live in `~/.claude/.skills-meta/applied-migrations`. When that file is
missing (fresh machine) it's seeded with every current migration, since a fresh
install already has the new layout.
