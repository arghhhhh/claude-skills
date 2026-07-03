---
version: 1.0.0
name: linear-cli
description: Manage Linear.app from the terminal via the `linear` CLI (schpet/linear-cli) — issues, projects, milestones, cycles, initiatives, labels, documents, teams, and raw GraphQL. Use when the user mentions Linear, a Linear issue (e.g. ENG-123), starting/creating/updating issues, or Linear projects/cycles/documents.
---

# Linear CLI Skill

Drive [Linear.app](https://linear.app) from the terminal with `linear` ([schpet/linear-cli](https://github.com/schpet/linear-cli)). Git/jj-aware and agent-friendly (structured `--json` on most read commands).

## Setup

- **Binary**: `linear` — on this machine installed via Deno at `C:\Users\joss\.deno\bin\linear`. Ensure `C:\Users\joss\.deno\bin` is on PATH (Git Bash: `export PATH="$PATH:/c/Users/joss/.deno/bin"`).
- **Auth**: `linear auth login` — prompts for an API key (create one at https://linear.app/settings/account/security). Stored in the system keyring by default; add `--plaintext` to use the credentials file, or pass `-k <key>`.
- **Check auth**: `linear auth whoami`
- **Configure project defaults**: `linear config` (interactive) writes `.linear.toml` with `team_id`, `workspace`, `vcs`, etc.
- **Env override**: `LINEAR_API_KEY`, `LINEAR_TEAM_ID`, `LINEAR_WORKSPACE`, `LINEAR_VCS` (`git`|`jj`), `LINEAR_ISSUE_SORT`. `LINEAR_DEBUG=1` for full stack traces.
- **Multi-workspace**: `--workspace <slug>` on any command; manage with `linear auth list` / `linear auth default <slug>`.

## Not Installed?

`linear --version` fails → reinstall (Deno is present on this machine):
```bash
deno install -A --reload -f -g -n linear jsr:@schpet/linear-cli
```
Other methods: `brew install schpet/tap/linear` (macOS/Linux), prebuilt binaries at https://github.com/schpet/linear-cli/releases/latest, or `npm install -D @schpet/linear-cli`.

## Agent-friendly conventions

- Add `--json` (`-j`) to read commands for machine-parseable output.
- Add `--no-pager` to avoid interactive paging in non-TTY contexts.
- Add `--no-interactive` to `issue create`/`update` so it never blocks on a prompt (supply all fields via flags).
- Issue IDs accept full keys (`ENG-123`), bare numbers (`123`, uses default team), or are inferred from the current git branch when omitted.

## Commands

### Auth
```bash
linear auth login [-k <key>] [--plaintext]   # add a workspace credential
linear auth whoami                           # authenticated user info
linear auth list                             # configured workspaces
linear auth default [workspace]              # set default workspace
linear auth token                            # print configured API token
linear auth logout [workspace]
```

### Issues (`linear issue` / `linear i`)
```bash
linear issue list [-s <state>] [--team ENG] [--project "Name"] [--label bug] [-j]
                  # your issues; default state=unstarted. --all-states for everything.
linear issue query --search "oauth timeout" [--team ENG] [--all-teams] [-j] [--limit 0]
                  # structured full-text search. --limit 0 = no cap. --search-comments to include comments.
linear issue view [ISSUE] [-w|-a]            # details (default); -w web, -a Linear.app
linear issue create [-t "title"] [-d "desc" | --description-file spec.md] \
                    [--team ENG] [--project "Name"] [--milestone "Phase 1"] \
                    [-p 1-4] [-a self] [-l bug] [-s "In Progress"] [--start] [--no-interactive]
linear issue update [ISSUE] [--milestone "Phase 2"] [-s <state>] [-a <user>] [...]
linear issue start [ISSUE]                   # create/switch branch + mark Started
linear issue delete [ISSUE]
linear issue id | title | url | describe     # print field for branch/given issue
linear issue pr [ISSUE]                      # create GitHub PR (via gh) with issue details
linear issue comment list [ISSUE]
linear issue comment add [ISSUE] [-p <parentCommentId>]   # -p to reply
linear issue comment update <commentId>
linear issue attach <ISSUE> <filepath>       # attach a file
linear issue link <urlOrIssueId> [url]       # link a URL to an issue
linear issue relation ...                    # manage dependencies/relations
linear issue commits [ISSUE]                 # commits for issue (jj only)
```

### Teams (`linear team` / `linear t`)
```bash
linear team list [-j]
linear team id                               # configured team id
linear team members [teamKey]
linear team create
linear team delete <teamKey>
linear team autolinks                         # configure GitHub repo autolinks for the team prefix
```

### Projects (`linear project` / `linear p`)
```bash
linear project list [-j]
linear project view <projectId>
linear project create
linear project update <projectId>
linear project delete <projectId>            # moves to trash
linear project-update ...                     # (alias `pu`) manage project status updates
```

### Milestones (`linear milestone` / `linear m`)
```bash
linear milestone list --project <projectId> [-j]
linear milestone view <milestoneId>
linear milestone create --project <projectId> --name "Q1 Goals" --target-date 2026-03-31
linear milestone update <milestoneId> --name "New Name"
linear milestone delete <milestoneId> [--force]
```

### Cycles (`linear cycle` / `linear cy`)
```bash
linear cycle list [--team ENG]
linear cycle view <cycleRef>                 # cycle number, name, or 'active'
```

### Initiatives (`linear initiative` / `linear init`)
```bash
linear initiative list
linear initiative view <initiativeId>
linear initiative create
linear initiative update <initiativeId>
linear initiative add-project <initiative> <project>
linear initiative remove-project <initiative> <project>
linear initiative archive|unarchive|delete <initiativeId>
linear initiative-update ...                  # (alias `iu`) status timeline posts
```

### Labels (`linear label` / `linear l`)
```bash
linear label list [-j]
linear label create
linear label delete <nameOrId>
```

### Documents (`linear document` / `linear docs` / `linear doc`)
```bash
linear document list [--project <id>] [--issue ENG-123] [-j]
linear document view <slug> [--raw] [--web] [--json]
linear document create --title "Spec" (--content "# Hi" | --content-file spec.md) \
                       [--project <id>] [--issue ENG-123]
cat spec.md | linear document create --title "Spec"
linear document update <slug> [--title "..."] [--content-file f.md] [--edit]
linear document delete <slug> [--permanent] [--bulk <s1> <s2>]
```

### Escape hatch — raw GraphQL
```bash
linear api '<graphql query>'                 # raw request for anything not covered
linear schema                                # print the GraphQL schema to stdout
linear completions                           # shell completions
```

## Common Workflows

- **Start work on an issue**: `linear issue start ENG-123` → branch created + marked Started → implement → `linear issue pr`.
- **Triage / find issues**: `linear issue query --search "..." --all-teams -j` or `linear issue list -s started`.
- **File a bug non-interactively**: `linear issue create -t "..." --description-file bug.md --team ENG -l bug -p 2 --no-interactive`.
- **Add a comment to the current branch's issue**: `linear issue comment add -d "..."` (issue inferred from branch).
- **Spec doc attached to an issue**: `linear document create --title "Spec" --content-file spec.md --issue ENG-123`.

## Tips

- Omit the issue ID on `view`/`update`/`comment`/`pr` etc. inside a git worktree — it infers from the branch name (created by `issue start`).
- Prefer `--description-file` / `--content-file` over inline `-d`/`--content` for markdown to avoid shell-quoting pain.
- `--limit 0` on `issue query` fetches all matches (no 50-cap).
- Use `linear api` + `linear schema` when a needed field isn't exposed by a dedicated command.
