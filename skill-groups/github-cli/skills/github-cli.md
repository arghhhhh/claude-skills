---
version: 1.1.1
---

# GitHub CLI (gh) Skill

Use this skill when working with GitHub issues, pull requests, repos, CI checks, or any GitHub operations via the `gh` CLI.

## Setup

- **Binary**: `gh` (should be on PATH)
- **Auth**: Run `gh auth login` to authenticate
- **Check auth**: `gh auth status`

## Not Installed?

- **GitHub CLI**: https://cli.github.com/ — install via `winget install --id GitHub.cli`, `brew install gh`, or download from the site

## Tips

- Use `--json` flag with `--jq` for scriptable output: `gh pr list --json number,title --jq '.[].title'`
- Use `gh api` for anything not covered by dedicated commands
- `gh pr create` from the current branch — it auto-detects the base branch
- Always quote PR/issue bodies with `"$(cat <<'EOF' ... EOF)"` for multi-line content
