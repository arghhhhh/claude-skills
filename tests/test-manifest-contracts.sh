#!/usr/bin/env bash
# test-manifest-contracts.sh
# Validates that every manifest.json conforms to the expected schema.
# Checks: required fields, valid type values, valid semver version,
# skills array non-empty for authored/vendored, vendored source block.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-manifest-contracts${NC}"

VALID_TYPES=("authored" "vendored" "tool-only")

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"

  suite "manifest: $group"

  assert_file "manifest.json exists" "$mf"

  # Valid JSON
  if ! node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$mf" 2>/dev/null; then
    fail "manifest.json is valid JSON"
    continue
  fi
  ok "manifest.json is valid JSON"

  # name field
  name=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.name||'')" "$mf" 2>/dev/null)
  assert_not_empty "has 'name' field" "$name"

  # version field — semver (major.minor.patch)
  version=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.version||'')" "$mf" 2>/dev/null)
  assert_not_empty "has 'version' field" "$version"
  if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    ok "version '$version' is valid semver"
  else
    fail "version '$version' is not valid semver (major.minor.patch)"
  fi

  # type field
  gtype=$(group_type "$group")
  valid_type=false
  for t in "${VALID_TYPES[@]}"; do [ "$t" = "$gtype" ] && valid_type=true; done
  if [ "$valid_type" = "true" ]; then
    ok "type '$gtype' is valid"
  else
    fail "type '$gtype' is not one of: ${VALID_TYPES[*]}"
  fi

  # install block
  has_install=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.install?'yes':'no')" "$mf" 2>/dev/null)
  assert_eq "has 'install' block" "yes" "$has_install"

  # test block
  has_test=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.test?'yes':'no')" "$mf" 2>/dev/null)
  assert_eq "has 'test' block" "yes" "$has_test"

  # description
  desc=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.description||'')" "$mf" 2>/dev/null)
  assert_not_empty "has 'description' field" "$desc"

  # authored/vendored must have 'skills' array
  if [ "$gtype" = "authored" ] || [ "$gtype" = "vendored" ]; then
    has_skills=$(node -e "
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write(Array.isArray(m.skills)?'yes':'no')
    " "$mf" 2>/dev/null)
    assert_eq "has 'skills' array" "yes" "$has_skills"
  fi

  # vendored groups must have source.repo and source.ref
  if [ "$gtype" = "vendored" ]; then
    repo=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write((m.source||{}).repo||'')" "$mf" 2>/dev/null)
    ref=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write((m.source||{}).ref||'')" "$mf" 2>/dev/null)
    assert_not_empty "vendored: has source.repo" "$repo"
    assert_not_empty "vendored: has source.ref" "$ref"

    # Ref must NOT be a branch name (main/master/develop/HEAD/trunk/dev)
    case "$ref" in
      main|master|develop|HEAD|trunk|dev)
        fail "vendored: source.ref '$ref' is a branch name (must be SHA or tag)" ;;
      *)
        ok "vendored: source.ref '$ref' is not a bare branch name" ;;
    esac

    # source.ref should look like a full SHA (40 hex chars) or a tag
    if echo "$ref" | grep -qE '^[0-9a-f]{40}$'; then
      ok "vendored: source.ref is a full SHA"
    elif echo "$ref" | grep -qE '^v?[0-9]+\.[0-9]+'; then
      ok "vendored: source.ref looks like a version tag"
    else
      # Could be a short SHA or unusual tag — warn but don't fail
      ok "vendored: source.ref format accepted (not a bare branch name)"
    fi
  fi

  # tool-only should have test.command (not just install.check) per SKILL.md rules
  if [ "$gtype" = "tool-only" ]; then
    test_cmd=$(node -e "
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write((m.test||{}).command||'')
    " "$mf" 2>/dev/null)
    if [ -n "$test_cmd" ]; then
      ok "tool-only: has test.command"
    else
      fail "tool-only: missing test.command (verify relies on it, not install.check)"
    fi
  fi

done

summary
