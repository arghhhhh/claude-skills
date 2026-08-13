#!/usr/bin/env bash
# test-unsupported-targets.sh
# Validates that the installer correctly rejects or flags unsupported targets:
#   - vendored source.ref must not be a bare branch name (main/master/HEAD/develop/trunk/dev)
#   - validate_vendor_ref logic correctness (inline test)
#   - Platform-specific install methods have valid platform values
#   - prereq.required field is boolean (true/false), not string "true"/"false"
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-unsupported-targets${NC}"

# ─── validate_vendor_ref inline tests ────────────────────────────────────────

suite "validate_vendor_ref: branch name rejection"

# Mirror of install.sh's validate_vendor_ref
validate_vendor_ref() {
  local ref="$1"
  case "$ref" in
    main|master|develop|HEAD|trunk|dev) return 1 ;;
  esac
  [ -n "$ref" ]
}

# Rejected cases
for bad_ref in main master develop HEAD trunk dev; do
  if validate_vendor_ref "$bad_ref"; then
    fail "ref '$bad_ref' should be rejected but passed"
  else
    ok "ref '$bad_ref' correctly rejected"
  fi
done

# Accepted cases
for good_ref in "c4489443c6968d3ee6219a8de5572f9de8e0b70c" "v1.2.3" "2024-01-15" "release-1.0" "abc123def456"; do
  if validate_vendor_ref "$good_ref"; then
    ok "ref '$good_ref' correctly accepted"
  else
    fail "ref '$good_ref' should be accepted but was rejected"
  fi
done

# Empty ref rejected
if validate_vendor_ref ""; then
  fail "empty ref should be rejected"
else
  ok "empty ref correctly rejected"
fi

# ─── All vendored groups pass validate_vendor_ref ──────────────────────────────

suite "all vendored groups: source.ref validation"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")
  [ "$gtype" = "vendored" ] || continue

  ref=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write((m.source||{}).ref||'');
    } catch(e){}
  " "$mf" 2>/dev/null) || ref=""

  if validate_vendor_ref "$ref"; then
    ok "$group: source.ref='$ref' is valid"
  else
    fail "$group: source.ref='$ref' is a bare branch name (rejected by installer)"
  fi
done

# ─── Platform values in install methods ──────────────────────────────────────

suite "install method platform values"

VALID_PLATFORMS=("macos" "linux" "windows")

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  # Extract all platform values from install.methods[]
  platforms=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const methods=(m.install||{}).methods||[];
      const seen=new Set();
      for(const method of methods){
        for(const p of (method.platforms||[])) seen.add(p);
      }
      console.log([...seen].join('\n'));
    } catch(e){}
  " "$mf" 2>/dev/null) || platforms=""

  for platform in $platforms; do
    valid=false
    for vp in "${VALID_PLATFORMS[@]}"; do
      [ "$platform" = "$vp" ] && valid=true && break
    done
    if [ "$valid" = "true" ]; then
      ok "$group: platform '$platform' is valid"
    else
      fail "$group: platform '$platform' is not one of: ${VALID_PLATFORMS[*]}"
    fi
  done
done

# ─── Prerequisites required field type ────────────────────────────────────────

suite "prerequisites.required is boolean"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  # Check each prerequisite's 'required' field is a boolean (not a string)
  result=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const prereqs=m.prerequisites||[];
      const problems=[];
      for(const p of prereqs){
        if('required' in p && typeof p.required !== 'boolean'){
          problems.push(p.name+':type='+typeof p.required);
        }
      }
      process.stdout.write(problems.join('\n'));
    } catch(e){}
  " "$mf" 2>/dev/null) || result=""

  if [ -z "$result" ]; then
    # Check if there are any prereqs at all
    prereq_count=$(node -e "
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write(String((m.prerequisites||[]).length));
    " "$mf" 2>/dev/null) || prereq_count="0"
    if [ "$prereq_count" = "0" ]; then
      ok "$group: no prerequisites declared"
    else
      ok "$group: $prereq_count prerequisite(s) — required fields are boolean"
    fi
  else
    while IFS= read -r problem; do
      [ -z "$problem" ] && continue
      fail "$group: prerequisite.$problem (should be boolean)"
    done <<< "$result"
  fi
done

# ─── install methods have command OR url (not neither) ────────────────────────

suite "install methods have command or url"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  result=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const methods=(m.install||{}).methods||[];
      const problems=[];
      for(const [i,method] of methods.entries()){
        if(!method.command && !method.url){
          problems.push('method['+i+'] ('+method.name+') has neither command nor url');
        }
      }
      process.stdout.write(problems.join('\n'));
    } catch(e){}
  " "$mf" 2>/dev/null) || result=""

  if [ -z "$result" ]; then
    method_count=$(node -e "
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write(String(((m.install||{}).methods||[]).length));
    " "$mf" 2>/dev/null) || method_count="0"
    ok "$group: $method_count install method(s) — all have command or url"
  else
    while IFS= read -r problem; do
      [ -z "$problem" ] && continue
      fail "$group: $problem"
    done <<< "$result"
  fi
done

summary
