#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Shared test framework for claude-skills test suite.
# Each test file sources this, then calls suite/assert functions.
# ─────────────────────────────────────────────────────────────────────────────

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$FRAMEWORK_DIR")"
SKILL_GROUPS_DIR="$REPO_DIR/skill-groups"
SHARED_DIR="$REPO_DIR/shared"

# Colors
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

_PASS=0; _FAIL=0; _SKIP=0

suite() {
  echo -e "\n${BOLD}▸ $*${NC}"
}

ok() {
  echo -e "  ${GREEN}✓${NC} $*"
  _PASS=$((_PASS + 1))
}

fail() {
  echo -e "  ${RED}✗${NC} $*"
  _FAIL=$((_FAIL + 1))
}

skip() {
  echo -e "  ${YELLOW}~${NC} $* (skipped)"
  _SKIP=$((_SKIP + 1))
}

# assert <label> <command...>
assert() {
  local label="$1"; shift
  if "$@" 2>/dev/null; then
    ok "$label"
  else
    fail "$label"
  fi
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    ok "$label"
  else
    fail "$label — expected='$expected' got='$actual'"
  fi
}

# assert_match <label> <pattern> <string>
assert_match() {
  local label="$1" pattern="$2" string="$3"
  if echo "$string" | grep -qE "$pattern"; then
    ok "$label"
  else
    fail "$label — pattern='$pattern' not matched in: $string"
  fi
}

# assert_contains <label> <needle> <haystack>
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    ok "$label"
  else
    fail "$label — '$needle' not found in output"
  fi
}

# assert_not_empty <label> <value>
assert_not_empty() {
  local label="$1" val="$2"
  if [ -n "$val" ]; then
    ok "$label"
  else
    fail "$label — expected non-empty value"
  fi
}

# assert_file <label> <path>
assert_file() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    ok "$label"
  else
    fail "$label — not found: $path"
  fi
}

# assert_dir <label> <path>
assert_dir() {
  local label="$1" path="$2"
  if [ -d "$path" ]; then
    ok "$label"
  else
    fail "$label — directory not found: $path"
  fi
}

# assert_json_field <label> <manifest_path> <dotted.key> <expected>
assert_json_field() {
  local label="$1" manifest="$2" key="$3" expected="$4"
  local actual
  actual=$(node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      let v = m;
      for (const k of process.argv[2].split('.')) v = (v || {})[k];
      process.stdout.write(String(v == null ? '' : v));
    } catch(e) { process.stdout.write(''); }
  " "$manifest" "$key" 2>/dev/null) || actual=""
  assert_eq "$label" "$expected" "$actual"
}

# List all groups (directories under skill-groups/ with manifest.json)
list_groups() {
  local groups=()
  for dir in "$SKILL_GROUPS_DIR"/*/; do
    [ -f "$dir/manifest.json" ] || continue
    groups+=("$(basename "$dir")")
  done
  echo "${groups[@]}"
}

# Get manifest type for a group
group_type() {
  local group="$1"
  local mf="$SKILL_GROUPS_DIR/$group/manifest.json"
  [ -f "$mf" ] || { echo "authored"; return; }
  node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      process.stdout.write(m.type || 'authored');
    } catch(e) { process.stdout.write('authored'); }
  " "$mf" 2>/dev/null || echo "authored"
}

# summary — print pass/fail/skip counts and emit machine-readable RESULT line
# The runner captures RESULT: to aggregate totals.
summary() {
  echo ""
  if [ "$_FAIL" -eq 0 ]; then
    echo -e "${GREEN}${_PASS} passed${NC}, ${_SKIP} skipped"
  else
    echo -e "${GREEN}${_PASS} passed${NC}, ${RED}${_FAIL} failed${NC}, ${_SKIP} skipped"
  fi
  # Machine-readable: runner greps this
  echo "RESULT:$_PASS:$_FAIL:$_SKIP"
}
