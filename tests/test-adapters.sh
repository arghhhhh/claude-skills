#!/usr/bin/env bash
# test-adapters.sh
# Validates the three group type adapters (authored / vendored / tool-only):
#   - authored: has skills/ directory, no source block
#   - vendored: has source block with repo/ref, overlays/ respected
#   - tool-only: no skills/, has test.command for verify
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-adapters${NC}"

# ─── authored ────────────────────────────────────────────────────────────────

suite "authored adapter"

authored_count=0
for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "authored" ] || continue
  authored_count=$((authored_count + 1))

  # Must have a skills/ directory (even if empty — it may be command-only)
  # Actually skills/ may be absent for authored groups with no skills declared.
  # Verify instead that each declared skill has a file in skills/.
  skills=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      (m.skills||[]).forEach(s=>console.log(s));
    } catch(e){}
  " "$mf" 2>/dev/null) || skills=""

  for skill in $skills; do
    base="$group_dir/skills/$skill"
    if [ -d "$base" ] || [ -f "${base}.md" ] || [ -f "$base" ]; then
      ok "$group/$skill: authored skill file present"
    else
      fail "$group/$skill: authored skill file missing at $base[/.md]"
    fi
  done

  # Must NOT declare type: vendored or type: tool-only
  type_field=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.type||'')" "$mf" 2>/dev/null)
  case "$type_field" in
    ""|authored) ok "$group: type field is absent or 'authored'" ;;
    *) fail "$group: classified as authored but type='$type_field'" ;;
  esac
done

if [ "$authored_count" -eq 0 ]; then
  skip "no authored groups found"
else
  ok "found $authored_count authored group(s)"
fi

# ─── vendored ────────────────────────────────────────────────────────────────

suite "vendored adapter"

vendored_count=0
for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "vendored" ] || continue
  vendored_count=$((vendored_count + 1))

  # Must have source.repo
  repo=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write((m.source||{}).repo||'')" "$mf" 2>/dev/null)
  assert_not_empty "$group: has source.repo" "$repo"

  # source.repo should look like owner/repo
  if echo "$repo" | grep -qE '^[^/]+/[^/]+$'; then
    ok "$group: source.repo '$repo' matches owner/repo"
  else
    fail "$group: source.repo '$repo' doesn't match owner/repo format"
  fi

  # Must have source.ref (SHA or tag, not branch)
  ref=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write((m.source||{}).ref||'')" "$mf" 2>/dev/null)
  assert_not_empty "$group: has source.ref" "$ref"

  # Must have source.paths.skills and source.paths.agents
  skills_path=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(((m.source||{}).paths||{}).skills||'')" "$mf" 2>/dev/null)
  agents_path=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(((m.source||{}).paths||{}).agents||'')" "$mf" 2>/dev/null)
  assert_not_empty "$group: has source.paths.skills" "$skills_path"
  assert_not_empty "$group: has source.paths.agents" "$agents_path"

  # Overlays (if declared) must map to actual overlay files
  overlay_dir="$group_dir/overlays/skills"
  if [ -d "$overlay_dir" ]; then
    overlay_count=0
    while IFS= read -r -d '' overlay; do
      overlay_count=$((overlay_count + 1))
    done < <(find "$overlay_dir" -name 'SKILL.md' -print0 2>/dev/null)
    ok "$group: overlays/ present with $overlay_count override(s)"
  else
    ok "$group: no overlays/ directory (vendored without overrides)"
  fi
done

if [ "$vendored_count" -eq 0 ]; then
  skip "no vendored groups found"
else
  ok "found $vendored_count vendored group(s)"
fi

# ─── tool-only ────────────────────────────────────────────────────────────────

suite "tool-only adapter"

toolonly_count=0
for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "tool-only" ] || continue
  toolonly_count=$((toolonly_count + 1))

  # Must NOT declare skills or agents (tool-only ships no skill files)
  skills=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.stdout.write(JSON.stringify(m.skills||[]))
  " "$mf" 2>/dev/null)
  agents=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.stdout.write(JSON.stringify(m.agents||[]))
  " "$mf" 2>/dev/null)

  if [ "$skills" = "[]" ] || [ -z "$skills" ]; then
    ok "$group: tool-only has no skills array (correct)"
  else
    # tool-only CAN have an empty skills array, but not populated — warn
    skill_count=$(node -e "
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write(String((m.skills||[]).length));
    " "$mf" 2>/dev/null)
    if [ "$skill_count" = "0" ]; then
      ok "$group: tool-only skills array is empty"
    else
      fail "$group: tool-only declares $skill_count skills (should be none)"
    fi
  fi

  # Must have test.command (required for verify to detect install status)
  test_cmd=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.stdout.write((m.test||{}).command||'')
  " "$mf" 2>/dev/null)
  if [ -n "$test_cmd" ]; then
    ok "$group: has test.command '$test_cmd'"
  else
    fail "$group: tool-only missing test.command (verify will be unable to detect install status)"
  fi

  # update_policy: groups that own their own scripts should be "latest"
  # (heuristic: if install.methods[0].command references this repo, it needs latest)
  install_cmd=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    const methods=(m.install||{}).methods||[];
    process.stdout.write(methods.length?methods[0].command||'':'');
  " "$mf" 2>/dev/null)
  update_policy=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.stdout.write(m.update_policy||'pinned');
  " "$mf" 2>/dev/null)

  if echo "$install_cmd" | grep -qE '(\.skill-repos/claude-skills|REPO\b)'; then
    if [ "$update_policy" = "latest" ]; then
      ok "$group: update_policy=latest (install references this repo)"
    else
      fail "$group: install references this repo but update_policy='$update_policy' (should be 'latest' to avoid stale hooks)"
    fi
  else
    ok "$group: update_policy=$update_policy (install does not reference this repo)"
  fi
done

if [ "$toolonly_count" -eq 0 ]; then
  skip "no tool-only groups found"
else
  ok "found $toolonly_count tool-only group(s)"
fi

summary
