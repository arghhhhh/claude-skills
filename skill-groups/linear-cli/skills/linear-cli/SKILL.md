---
version: 2.0.0
name: linear-cli
description: Manage Linear.app from the terminal via the `linear` CLI (schpet/linear-cli) — issues, projects, milestones, cycles, initiatives, labels, documents, teams, and raw GraphQL. Use when the user mentions Linear, a Linear issue (e.g. ENG-123), starting/creating/updating issues, or Linear projects/cycles/documents.
---

# Linear CLI Skill

Drive [Linear.app](https://linear.app) from the terminal with `linear` ([schpet/linear-cli](https://github.com/schpet/linear-cli)). Git/jj-aware and agent-friendly (structured JSON on many read commands). Documented against **CLI v2.0.0** — verify with `linear --version` if flags mismatch.

## Setup

- **Binary**: `linear` — installed via Deno at `<HOME>/.deno/bin/linear`. Deno drops binaries in `~/.deno/bin` but does **not** add it to PATH, so `linear` won't be found by name until you persist it. If `linear` isn't on PATH, do it once (don't rely on a per-session `export`, which agents in fresh shells won't inherit):
  - **Windows** (persist to User PATH registry): `powershell -NoProfile -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); if($p -notlike '*\.deno\bin*'){[Environment]::SetEnvironmentVariable('Path',$p.TrimEnd(';')+';'+$env:USERPROFILE+'\.deno\bin','User')}"` — takes effect in newly launched shells/agents; for the current shell also `$env:PATH += ';'+$env:USERPROFILE+'\.deno\bin'`.
  - **macOS/Linux**: append `export PATH="$HOME/.deno/bin:$PATH"` to `~/.zshrc` / `~/.bashrc`.
- **Auth**: `linear auth login` — prompts for an API key (create one at https://linear.app/settings/account/security). Stored in the system keyring by default; add `--plaintext` to use the credentials file, or pass `-k <key>`.
- **Check auth**: `linear auth whoami`
- **Configure project defaults**: `linear config` (interactive) writes `.linear.toml`. Valid keys: `team_id`, `workspace`, `api_key`, `issue_sort` (`manual`|`priority`), `vcs` (`git`|`jj`), `download_images`, `hyperlink_format`, `attachment_dir`, `auto_download_attachments`. Lookup order: `./linear.toml` / `./.linear.toml` (cwd), git root (also `<gitroot>/.config/linear.toml`), then global `~/.config/linear/linear.toml` (Windows: `%APPDATA%\linear\linear.toml`).
- **Env override**: any config key as `LINEAR_<KEY_UPPERCASE>` — e.g. `LINEAR_API_KEY`, `LINEAR_TEAM_ID`, `LINEAR_WORKSPACE`, `LINEAR_VCS`, `LINEAR_ISSUE_SORT`. `LINEAR_DEBUG=1` for full stack traces. ⚠ `LINEAR_API_KEY` bypasses the keyring entirely — leave it unset for multi-workspace switching to work.
- **Multi-workspace**: `--workspace <slug>` on any command; manage with `linear auth list` / `linear auth default <slug>`. API keys are workspace-scoped — run `linear auth login` once per workspace; credentials accumulate, they don't overwrite.

## Not Installed?

`linear --version` fails → reinstall (Deno is present on this machine):
```bash
deno install -A --reload -f -g -n linear jsr:@schpet/linear-cli
```
After (re)installing, persist `~/.deno/bin` to PATH per the **Setup** section — `deno install` places the binary but never edits PATH, so a fresh agent still won't find `linear` otherwise.

Other methods: `brew install schpet/tap/linear` (macOS/Linux), prebuilt binaries at https://github.com/schpet/linear-cli/releases/latest, or `npm install -D @schpet/linear-cli`.

## Agent-friendly conventions

- **JSON output is NOT universal.** `-j`/`--json` exists on: `issue query`, `issue view`, `issue comment list`, `project list`, `project create`, `initiative list`, `label list`, `document list` (`--json` only), `document view` (`--json` only). It does **not** exist on `issue list`, `team list`, `project view`, `milestone *`, `cycle *` — parse text or use `linear api` for those.
- `issue list` **requires a sort**: pass `--sort priority|manual`, set `issue_sort` in `.linear.toml`, or `LINEAR_ISSUE_SORT` — otherwise it errors. `issue query` defaults to priority.
- `issue list` shows **your** issues only (alias `mine`); use `issue query` for team-wide or others' issues.
- Add `--no-pager` (on `issue list`/`query`/`view`) to avoid interactive paging in non-TTY contexts.
- Add `--no-interactive` (exists on `issue create` and `team create`) so it never blocks on a prompt; supply all fields via flags. Commands with an `-i/--interactive` flag (`project create`, `initiative create`, `label create`, `document create`) only prompt when called with no flags — pass flags to stay non-interactive.
- Issue IDs accept full keys (`ENG-123`), bare numbers (`123`, uses default team), or are inferred from the current git branch when omitted.

## Commands

### Auth
```bash
linear auth login [-k <key>] [--plaintext]   # add a workspace credential (one per workspace)
linear auth whoami                           # authenticated user info
linear auth list                             # configured workspaces (* = default)
linear auth default [workspace]              # set default workspace
linear auth token                            # print configured API token
linear auth logout [workspace]
linear auth migrate                          # move plaintext credentials into system keyring
```

### Issues (`linear issue` / `linear i`)
```bash
linear issue list [--sort priority|manual] [-s <state>] [--all-states] [--team ENG] \
                  [--project "Name"] [--project-label <lbl>] [--cycle active] \
                  [--milestone "Phase 1"] [-l bug] [--limit N] \
                  [--created-after 2026-01-01] [--updated-after 2026-01-01] [--no-pager]
                  # YOUR issues only; default state=unstarted; sort REQUIRED (flag/config/env); no JSON
linear issue query [--search "oauth timeout"] [--team ENG] [--all-teams] [-s started] \
                   [--assignee <user> | -A | -U] [--sort priority|manual] \
                   [--project "Name"] [--cycle active] [--milestone "..."] [-l bug] \
                   [--limit 0] [--created-after <date>] [--updated-after <date>] \
                   [--include-archived] [--search-comments] [-j] [--no-pager]
                   # structured search across teams/assignees. --limit 0 = no cap. -U = unassigned only.
linear issue view [ISSUE] [-w|-a] [-j] [--no-comments] [--show-resolved-threads] \
                  [--no-download] [--no-pager]      # details (default); -w web, -a Linear.app
linear issue create [-t "title"] [-d "desc" | --description-file spec.md] \
                    [--team ENG] [--project "Name"] [--milestone "Phase 1"] [--cycle active] \
                    [-p 1-4] [-a self] [-l bug] [-s "In Progress"] [--parent ENG-100] \
                    [--estimate N] [--due-date <date>] [--start] \
                    [--no-use-default-template] [--no-interactive]
linear issue update [ISSUE] [-t "..."] [-d "..." | --description-file f.md] [--team ENG] \
                    [--project "Name"] [--milestone "Phase 2"] [--cycle active] [-p 1-4] \
                    [-a <user>] [-l bug] [-s <state>] [--parent <id>] [--estimate N] [--due-date <date>]
linear issue start [ISSUE] [-f <fromRef>] [-b <branchName>] [-A|-U]   # create/switch branch + mark Started
linear issue delete [ISSUE] [-y] [--bulk ENG-1 ENG-2 | --bulk-file f.txt | --bulk-stdin]
linear issue id | title | url | describe [--ref]   # print field for branch/given issue
linear issue pr [ISSUE] [--base <branch>] [--head <branch>] [--draft] [-t "title"] [--web]
                  # create GitHub PR (via gh) with issue details
linear issue comment list [ISSUE] [-j]
linear issue comment add [ISSUE] [-b "text" | --body-file f.md] [-p <parentCommentId>] [-a <filepath>]
                  # body flag is -b/--body, NOT -d. -p to reply; -a attaches files (repeatable).
linear issue comment update|delete <commentId>
linear issue attach <ISSUE> <filepath> [-t "title"] [-c "comment body"]
linear issue link <urlOrIssueId> [url] [-t "title"]   # link a URL to an issue
linear issue relation add|delete <ISSUE> <relationType> <RELATED_ISSUE>
linear issue relation list [ISSUE]
linear issue commits [ISSUE]                 # commits for issue (jj only)
linear issue agent-session list [ISSUE]      # Linear agent sessions on an issue
linear issue agent-session view <sessionId>
```

### Teams (`linear team` / `linear t`)
```bash
linear team list [-w|-a]                     # no JSON — use `linear api` for structured team data
linear team id                               # configured team id
linear team members [teamKey] [-a]           # -a includes inactive members
linear team create [-n "Name"] [-d "desc"] [-k KEY] [--private] [--no-interactive]
linear team delete <teamKey>
linear team autolinks                        # configure GitHub repo autolinks for the team prefix
```

### Projects (`linear project` / `linear p`)
```bash
linear project list [--team ENG] [--all-teams] [--status <name>] [-j]
linear project view <projectId>              # no JSON output
linear project create -n "Name" -t ENG [-d "desc"] [-l @me] \
                      [-s planned|started|paused|completed|canceled|backlog] \
                      [--start-date YYYY-MM-DD] [--target-date YYYY-MM-DD] \
                      [--initiative <idOrName>] [-j]
                      # -t repeatable for multi-team projects; prompts only if called with no flags
linear project update <projectId> [-n ...] [-d ...] [-s <status>] [-l <lead>] \
                      [--start-date ...] [--target-date ...] [-t ENG]
linear project delete <projectId> [-f]       # moves to trash; -f skips confirmation
linear project-update create|list <projectId>   # (alias `pu`) project status updates
```

### Milestones (`linear milestone` / `linear m`) — no JSON on any subcommand
```bash
linear milestone list --project <projectId>
linear milestone view <milestoneId>
linear milestone create --project <projectId> --name "Q1 Goals" [--description "..."] [--target-date 2026-03-31]
linear milestone update <id> [--name "..."] [--description "..."] [--target-date <date>] \
                        [--sort-order N] [--project <newProjectId>]
linear milestone delete <id> [-f]
```

### Cycles (`linear cycle` / `linear cy`) — no JSON
```bash
linear cycle list [--team ENG]
linear cycle view <cycleRef> [--team ENG]    # cycle number, name, or 'active'
```

### Initiatives (`linear initiative` / `linear init`)
```bash
linear initiative list [-s active|planned|completed] [--all-statuses] [-o <owner>] [--archived] [-j]
linear initiative view <initiativeId>
linear initiative create -n "Name" [-d "desc"] [-s planned|active|completed] [-o @me] \
                         [--target-date YYYY-MM-DD] [-c "#5E6AD2"] [--icon <name>]
linear initiative update <initiativeId>
linear initiative add-project <initiative> <project>
linear initiative remove-project <initiative> <project>
linear initiative archive|unarchive|delete <initiativeId>
linear initiative-update create|list <initiativeId>   # (alias `iu`) status timeline posts
```

### Labels (`linear label` / `linear l`)
```bash
linear label list [--team ENG | --workspace | --all] [-j]
                  # ⚠ here --workspace is a bare filter (workspace-level labels only),
                  #   NOT the global --workspace <slug> selector
linear label create -n "Name" [-c "#EB5757"] [-d "desc"] [-t ENG]   # omit -t for workspace label
linear label delete <nameOrId>
```

### Documents (`linear document` / `linear docs` / `linear doc`)
```bash
linear document list [--project <slugOrName>] [--issue ENG-123] [--limit N] [--json]
linear document view <id> [--raw] [-w] [--json]
linear document create -t "Spec" (-c "# Hi" | -f spec.md) \
                       [--project <slugOrId>] [--issue ENG-123] [--icon 📄]
                       # content flags are -c/--content and -f/--content-file
linear document update <id> [-t "..."] [-c "..." | -f f.md] [--icon 📄] [-e]   # -e opens $EDITOR
linear document delete [id] [-y] [--bulk <s1> <s2> | --bulk-file f.txt | --bulk-stdin]
```

### Escape hatch — raw GraphQL
```bash
linear api '<graphql query>' [--variable key=value] [--variables-json '{...}'] [--paginate] [--silent]
                  # --variable coerces booleans/numbers/null; @file reads value from a path
linear schema                                # print the GraphQL schema to stdout
linear completions                           # shell completions
```

## Common Workflows

- **Start work on an issue**: `linear issue start ENG-123` → branch created + marked Started → implement → `linear issue pr`.
- **Triage / find issues**: `linear issue query --search "..." --all-teams -j` or `linear issue query --team ENG -s started -j`.
- **File a bug non-interactively**: `linear issue create -t "..." --description-file bug.md --team ENG -l bug -p 2 --no-interactive`.
- **Add a comment to the current branch's issue**: `linear issue comment add -b "..."` (issue inferred from branch).
- **Spec doc attached to an issue**: `linear document create -t "Spec" -f spec.md --issue ENG-123`.
- **Cross-workspace**: append `--workspace <slug>` to any command, or rely on the project's `.linear.toml`.

## Tips

- Omit the issue ID on `view`/`update`/`comment`/`pr` etc. inside a git worktree — it infers from the branch name (created by `issue start`).
- Prefer `--description-file` / `--body-file` / `-f` (content-file) over inline flags for markdown to avoid shell-quoting pain.
- `--limit 0` on `issue query` fetches all matches (no 50-cap).
- Use `linear api` + `linear schema` when a needed field isn't exposed (or has no JSON), e.g. teams: `linear api 'query { teams { nodes { id key name } } }'`.
