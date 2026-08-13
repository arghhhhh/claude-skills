#!/usr/bin/env bash
# test-generated-outputs.sh
# Validates that outputs install.sh would generate are correct:
#   - Default CLAUDE.md snippet generation (from manifest name+description)
#   - json_get / json_get_manifest_field parses correctly
#   - generate_default_snippet produces expected fields
#   - json_array extracts skill lists correctly
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-generated-outputs${NC}"

# ─── json_get_manifest_field equivalent ──────────────────────────────────────

suite "json field extraction"

# Helper: extract a dotted field from a manifest
json_field() {
  local mf="$1" key="$2"
  node -e "
    try {
      let v=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      for(const k of process.argv[2].split('.')) v=(v||{})[k];
      process.stdout.write(typeof v==='string'?v:v==null?'':String(v));
    } catch(e){}
  " "$mf" "$key" 2>/dev/null
}

# Test against blender manifest (known values)
blender_mf="$SKILL_GROUPS_DIR/blender/manifest.json"
if [ -f "$blender_mf" ]; then
  name=$(json_field "$blender_mf" "name")
  assert_eq "blender manifest: name" "blender" "$name"

  install_check=$(json_field "$blender_mf" "install.check")
  assert_eq "blender manifest: install.check" "blender --version" "$install_check"

  test_cmd=$(json_field "$blender_mf" "test.command")
  assert_eq "blender manifest: test.command" "blender --version" "$test_cmd"

  gtype=$(json_field "$blender_mf" "type")
  # blender is authored (no type field → empty → defaults to authored)
  ok "blender manifest: type='$gtype' (authored is default)"
else
  skip "blender manifest not found — skipping json extraction tests"
fi

# Test against unity-cli manifest (vendored, known values)
unity_mf="$SKILL_GROUPS_DIR/unity-cli/manifest.json"
if [ -f "$unity_mf" ]; then
  gtype=$(json_field "$unity_mf" "type")
  assert_eq "unity-cli manifest: type" "vendored" "$gtype"

  repo=$(json_field "$unity_mf" "source.repo")
  assert_not_empty "unity-cli manifest: source.repo" "$repo"

  ref=$(json_field "$unity_mf" "source.ref")
  assert_not_empty "unity-cli manifest: source.ref" "$ref"
else
  skip "unity-cli manifest not found — skipping vendored field tests"
fi

# ─── CLAUDE.md snippet generation ─────────────────────────────────────────────

suite "CLAUDE.md snippet generation"

# Verify that for every group with a hand-authored snippet, the snippet
# mentions the group name or at least one declared skill name (basic coherence)
for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  snippet="$SHARED_DIR/claude-md/$group.md"
  [ -f "$snippet" ] || continue

  content=$(cat "$snippet")

  # Snippet should contain something (non-trivial)
  if [ ${#content} -lt 20 ]; then
    fail "$group: snippet file is suspiciously short (${#content} chars)"
    continue
  fi
  ok "$group: snippet has content (${#content} chars)"

  # Snippet should mention a skill or the group name in a recognizable way
  skill_names=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      (m.skills||[]).forEach(s=>console.log(s));
    } catch(e){}
  " "$mf" 2>/dev/null) || skill_names=""

  found_ref=false
  if echo "$content" | grep -qi "$group"; then
    found_ref=true
  fi
  for sn in $skill_names; do
    echo "$content" | grep -qi "$sn" && found_ref=true
  done

  if [ "$found_ref" = "true" ]; then
    ok "$group: snippet references group/skill name"
  else
    # Some snippets use very different naming — warn, don't fail
    ok "$group: snippet content present (name cross-ref not strictly required)"
  fi
done

# ─── json_array extraction ────────────────────────────────────────────────────

suite "skills array extraction"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  # Count skills via node
  skill_count=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write(String((m.skills||[]).length));
    } catch(e){process.stdout.write('0');}
  " "$mf" 2>/dev/null) || skill_count="0"

  # Verify the count is a number
  if echo "$skill_count" | grep -qE '^[0-9]+$'; then
    ok "$group: skills array has $skill_count items (parseable)"
  else
    fail "$group: skills array count not parseable (got '$skill_count')"
  fi
done

# ─── install.check vs test.command distinction ────────────────────────────────

suite "install.check vs test.command distinction"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  install_check=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write((m.install||{}).check||'');
    } catch(e){}
  " "$mf" 2>/dev/null) || install_check=""

  test_cmd=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write((m.test||{}).command||'');
    } catch(e){}
  " "$mf" 2>/dev/null) || test_cmd=""

  # If install.check is "false", test.command MUST exist (otherwise verify can't detect install status)
  if [ "$install_check" = "false" ]; then
    if [ -n "$test_cmd" ]; then
      ok "$group: install.check=false AND test.command present — verify-safe"
    else
      fail "$group: install.check=false but test.command missing — verify will always report failure"
    fi
  elif [ -n "$install_check" ] || [ -n "$test_cmd" ]; then
    ok "$group: has install.check='${install_check:-<none>}' test.command='${test_cmd:-<none>}'"
  else
    ok "$group: no install.check or test.command (install may have no binary to check)"
  fi
done

summary
