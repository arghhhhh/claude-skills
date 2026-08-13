# claude-skills Test Suite

Regression tests for the claude-skills installer system.

## Running Tests

### Quick smoke check (Node.js, no bash required)

```bash
node tests/smoke-check.js
```

Covers all major suites in one pass. Requires only Node.js (already a prerequisite for install.sh).

### Full bash test suite (Git Bash / Linux / macOS)

```bash
bash tests/run-tests.sh              # all suites
bash tests/run-tests.sh test-manifest-contracts  # one suite
```

## Test Suites

| File | What it covers |
|---|---|
| `test-manifest-contracts.sh` | Every `manifest.json` schema: required fields, semver version, valid type, install/test blocks, vendored source.ref, tool-only test.command |
| `test-discovery.sh` | Group/skill discovery: skill files exist, agent files exist, CLAUDE.md snippet coverage, SKILL.md version frontmatter |
| `test-adapters.sh` | Authored / vendored / tool-only adapter contracts: file layout, source block, overlay presence, update_policy |
| `test-generated-outputs.sh` | JSON field extraction correctness, snippet content quality, install.check vs test.command distinction |
| `test-idempotency.sh` | semver_compare logic, update_policy=latest idempotency, install.check=false safety, overlay mapping consistency |
| `test-mcp-parity.sh` | mcp_servers structure: command+args, CLAUDE.md snippet presence, {{PLACEHOLDER}} in config.example.sh |
| `test-skill-reuse.sh` | No duplicate skill names across groups, manifest↔filesystem name match, no orphaned skill/agent files |
| `test-unsupported-targets.sh` | validate_vendor_ref branch rejection, platform values, prerequisite.required boolean, method command/url |
| `test-windows-paths.sh` | repo_slug(), sed_escape_repl() Windows path safety, detect_platform(), {{PLACEHOLDER}} substitution, wsl_propagate structure |

## smoke-check.js

The `smoke-check.js` file consolidates the most critical checks from all bash suites into a single Node.js script. Run it from any machine with Node.js installed — no bash or Git Bash required.

It validates:
- All manifests: name, version (semver), type, install, test, description
- Vendored groups: source.repo/ref, no bare branch names
- Tool-only groups: test.command present
- Skill file existence (authored groups)
- Agent file existence (authored groups)  
- No duplicate skill names across groups
- Platform value validity
- Overlay mapping consistency (vendored)
- mcp_servers structure

## Framework

`framework.sh` provides shared assertion helpers sourced by all bash test files:
- `ok <msg>` / `fail <msg>` / `skip <msg>` — record results
- `assert <label> <cmd...>` — run command, pass/fail by exit code
- `assert_eq <label> <expected> <actual>` — string equality
- `assert_contains <label> <needle> <haystack>` — substring check
- `assert_match <label> <regex> <string>` — regex match
- `assert_not_empty <label> <value>` — non-empty check
- `assert_file <label> <path>` / `assert_dir <label> <path>` — path existence
- `list_groups` — enumerate all groups with manifest.json
- `group_type <group>` — read type field (defaults to "authored")
- `summary` — print counts and emit `RESULT:pass:fail:skip` for runner

## Adding Tests

1. Create `tests/test-<name>.sh` sourcing `framework.sh`
2. Call `suite "description"`, then assertions, then `summary`
3. The runner picks it up automatically

To add to `smoke-check.js`: append a new `console.log('=== test-<name> ===')` block following the existing patterns.
