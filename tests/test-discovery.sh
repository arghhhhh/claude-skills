#!/usr/bin/env bash
# test-discovery.sh
# Validates skill and group discovery logic:
#   - Every group dir with manifest.json appears in list_groups()
#   - Every skill listed in manifest.json has a corresponding source file in the repo
#   - Every agent listed in manifest.json has a corresponding source file
#   - CLAUDE.md snippet exists (in shared/claude-md/ or auto-generated from manifest)
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-discovery${NC}"

suite "list_groups: all groups found"

groups_found=0
for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  [ -f "$group_dir/manifest.json" ] || continue
  group="$(basename "$group_dir")"
  groups_found=$((groups_found + 1))
  ok "group '$group' discovered"
done
if [ "$groups_found" -eq 0 ]; then
  fail "No groups found in skill-groups/"
fi

suite "skill file existence (authored groups)"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue

  skills=$(node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      (m.skills || []).forEach(s => console.log(s));
    } catch(e) {}
  " "$mf" 2>/dev/null) || skills=""

  for skill in $skills; do
    skill_base="$group_dir/skills/$skill"
    if [ -d "$skill_base" ] && [ -f "$skill_base/SKILL.md" ]; then
      ok "$group/$skill: SKILL.md found (directory)"
    elif [ -f "$skill_base.md" ]; then
      ok "$group/$skill: skill file found (.md)"
    elif [ -f "$skill_base" ]; then
      ok "$group/$skill: skill file found"
    else
      fail "$group/$skill: skill file missing (expected $skill_base or $skill_base.md)"
    fi
  done
done

suite "agent file existence (authored groups)"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue

  agents=$(node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      (m.agents || []).forEach(a => console.log(a));
    } catch(e) {}
  " "$mf" 2>/dev/null) || agents=""

  [ -z "$agents" ] && continue

  for agent in $agents; do
    agent_path="$group_dir/agents/$agent.md"
    if [ -f "$agent_path" ]; then
      ok "$group/agents/$agent.md exists"
    else
      fail "$group/agents/$agent.md missing"
    fi
  done
done

suite "CLAUDE.md snippets"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  snippet="$SHARED_DIR/claude-md/$group.md"
  if [ -f "$snippet" ]; then
    # Check snippet is non-empty
    if [ -s "$snippet" ]; then
      ok "$group: has shared/claude-md/$group.md"
    else
      fail "$group: shared/claude-md/$group.md is empty"
    fi
  else
    # No hand-authored snippet — that's OK only if the manifest has name+description
    # so the installer can auto-generate one
    name=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.name||'')" "$mf" 2>/dev/null)
    desc=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.description||'')" "$mf" 2>/dev/null)
    if [ -n "$name" ] && [ -n "$desc" ]; then
      ok "$group: no snippet file but manifest has name+description (auto-gen eligible)"
    else
      fail "$group: no snippet and manifest lacks name or description — Claude.md generation will fail"
    fi
  fi
done

suite "skill SKILL.md version frontmatter"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue

  skills=$(node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      (m.skills || []).forEach(s => console.log(s));
    } catch(e) {}
  " "$mf" 2>/dev/null) || continue

  for skill in $skills; do
    skill_base="$group_dir/skills/$skill"
    if [ -d "$skill_base" ]; then
      skill_file="$skill_base/SKILL.md"
    elif [ -f "$skill_base.md" ]; then
      skill_file="$skill_base.md"
    else
      continue  # already caught above
    fi

    version=$(sed -n '/^---$/,/^---$/{s/^version:[[:space:]]*\(.*\)/\1/p}' "$skill_file" | head -1 | tr -d '\r "'"'")
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      ok "$group/$skill: frontmatter version=$version"
    else
      fail "$group/$skill: missing or invalid version in SKILL.md frontmatter (got '$version')"
    fi
  done
done

summary
