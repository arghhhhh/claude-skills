---
version: 1.0.0
---

# GitHub CLI (gh) Skill

Use this skill when working with GitHub issues, pull requests, repos, CI checks, or any GitHub operations via the `gh` CLI.

## Setup

- **Binary**: `gh` (should be on PATH)
- **Auth**: Run `gh auth login` to authenticate
- **Check auth**: `gh auth status`

## Commands

### Issues
```bash
gh issue list [--label "bug"] [--state open]
gh issue view <number>
gh issue create --title "title" --body "description" [--label "label"]
gh issue close <number>
gh issue comment <number> --body "comment text"
```

### Pull Requests
```bash
gh pr list
gh pr view <number>
gh pr create --title "title" --body "## Summary ..."
gh pr checkout <number>
gh pr merge <number>
gh pr checks <number>
gh pr review <number> --approve
gh pr diff <number>
gh pr comment <number> --body "comment text"
```

### Repos
```bash
gh repo view [owner/repo]
gh repo clone owner/repo
gh repo create <name> [--public|--private]
gh repo fork owner/repo
```

### Releases
```bash
gh release list
gh release view <tag>
gh release create <tag> [--title "title"] [--notes "notes"] [files...]
```

### Workflow Runs (CI)
```bash
gh run list
gh run view <run-id>
gh run watch <run-id>
gh workflow list
gh workflow run <workflow> [--ref branch]
```

### API (escape hatch for anything else)
```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments
gh api user
gh api graphql -f query='{ viewer { login } }'
```

### Gists
```bash
gh gist list
gh gist create <file> [--public] [--desc "description"]
gh gist view <id>
```

## Common Workflows

- **Issue-driven dev**: `gh issue list` → branch → implement → `gh pr create`
- **PR review**: `gh pr view` → check comments → fix → push
- **CI checks**: `gh pr checks` or `gh run list` → `gh run view`
- **Release**: tag → `gh release create` with artifacts

## Tips

- Use `--json` flag with `--jq` for scriptable output: `gh pr list --json number,title --jq '.[].title'`
- Use `gh api` for anything not covered by dedicated commands
- `gh pr create` from the current branch — it auto-detects the base branch
- Always quote PR/issue bodies with `"$(cat <<'EOF' ... EOF)"` for multi-line content
