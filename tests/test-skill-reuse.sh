#!/usr/bin/env bash
# test-skill-reuse.sh
# Validates cross-skill consistency and reuse patterns:
#   - No duplicate skill names across groups
#   - Skill names declared in manifest match actual directory/file names
#   - Shared CLAUDE.md snippets (in shared/claude-md/) don't contradict manifests
#   - No skill file is orphaned (file exists but not declared in any manifest)
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-skill-reuse${NC}"

suite "no duplicate skill names across authored groups"

declare -A skill_owners  # skill_name -> group

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue

  skills=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      (m.skills||[]).forEach(s=>console.log(s));
    } catch(e){}
  " "$mf" 2>/dev/null) || skills=""

  for skill in $skills; do
    existing="${skill_owners[$skill]:-}"
    if [ -n "$existing" ]; then
      fail "Duplicate skill '$skill': declared in both '$existing' and '$group'"
    else
      skill_owners[$skill]="$group"
      ok "skill '$skill' uniquely owned by '$group'"
    fi
  done
done

suite "manifest skills match filesystem names (authored)"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue

  skills=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      (m.skills||[]).forEach(s=>console.log(s));
    } catch(e){}
  " "$mf" 2>/dev/null) || skills=""

  for skill in $skills; do
    base="$group_dir/skills/$skill"
    if [ -d "$base" ]; then
      # Directory skill: name must match directory name exactly
      dirname_match="$(basename "$base")"
      if [ "$dirname_match" = "$skill" ]; then
        ok "$group: skill '$skill' matches directory name"
      else
        fail "$group: skill '$skill' does not match directory '$(basename "$base")'"
      fi
    elif [ -f "${base}.md" ]; then
      # Flat .md skill: name must match filename without .md
      filename="$(basename "${base}.md" .md)"
      if [ "$filename" = "$skill" ]; then
        ok "$group: skill '$skill' matches file '$skill.md'"
      else
        fail "$group: skill '$skill' does not match file '$filename.md'"
      fi
    fi
    # Missing files caught by test-discovery.sh
  done
done

suite "no orphaned skill files (authored)"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue

  skills_dir="$group_dir/skills"
  [ -d "$skills_dir" ] || continue

  # Get declared skills
  declared=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      (m.skills||[]).forEach(s=>console.log(s));
    } catch(e){}
  " "$mf" 2>/dev/null) || declared=""

  # Check every item in skills/ is declared
  for item in "$skills_dir"/*/; do
    [ -e "$item" ] || continue
    name="$(basename "$item")"
    # Strip .md if present
    name="${name%.md}"
    found=false
    for s in $declared; do
      [ "$s" = "$name" ] && found=true && break
    done
    if [ "$found" = "true" ]; then
      ok "$group/$name: skill file is declared in manifest"
    else
      fail "$group/$name: skill file exists in skills/ but is NOT declared in manifest"
    fi
  done

  # Also check flat .md skills
  for item in "$skills_dir"/*.md; do
    [ -f "$item" ] || continue
    name="$(basename "$item" .md)"
    found=false
    for s in $declared; do
      [ "$s" = "$name" ] && found=true && break
    done
    if [ "$found" = "true" ]; then
      ok "$group/$name: skill .md is declared in manifest"
    else
      fail "$group/$name: skill .md exists but is NOT declared in manifest"
    fi
  done
done

suite "no orphaned agent files (authored)"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue

  agents_dir="$group_dir/agents"
  [ -d "$agents_dir" ] || continue

  declared_agents=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      (m.agents||[]).forEach(a=>console.log(a));
    } catch(e){}
  " "$mf" 2>/dev/null) || declared_agents=""

  for item in "$agents_dir"/*.md; do
    [ -f "$item" ] || continue
    name="$(basename "$item" .md)"
    found=false
    for a in $declared_agents; do
      [ "$a" = "$name" ] && found=true && break
    done
    if [ "$found" = "true" ]; then
      ok "$group/agents/$name.md: declared in manifest"
    else
      fail "$group/agents/$name.md: agent file exists but NOT declared in manifest"
    fi
  done
done

suite "shared/claude-md snippets reference known groups"

for snippet in "$SHARED_DIR/claude-md"/*.md; do
  [ -f "$snippet" ] || continue
  name="$(basename "$snippet" .md)"
  if [ -d "$SKILL_GROUPS_DIR/$name" ]; then
    ok "claude-md/$name.md matches group '$name'"
  else
    fail "claude-md/$name.md has no corresponding group in skill-groups/"
  fi
done

summary
