#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# claude-skills test runner
# Usage:
#   bash tests/run-tests.sh              # run all suites
#   bash tests/run-tests.sh test-manifest-contracts  # run one suite
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors (for the summary header only; each suite manages its own)
if [ -t 1 ]; then RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
else RED=''; GREEN=''; BOLD=''; NC=''; fi

TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0

# Collect suites
if [ "$#" -gt 0 ]; then
  SUITES=()
  for arg in "$@"; do
    f="$TESTS_DIR/$arg.sh"
    [ -f "$f" ] || f="$TESTS_DIR/$arg"
    [ -f "$f" ] || { echo "Suite not found: $arg" >&2; exit 1; }
    SUITES+=("$f")
  done
else
  mapfile -t SUITES < <(find "$TESTS_DIR" -name 'test-*.sh' | sort)
fi

echo -e "${BOLD}claude-skills test suite${NC} — ${#SUITES[@]} suite(s)"

for s in "${SUITES[@]}"; do
  # Capture output + final count line from each suite
  output=$(bash "$s" 2>&1) || true
  # Each suite ends with a "RESULT:pass:fail:skip" line
  result=$(echo "$output" | grep '^RESULT:' | tail -1) || result="RESULT:0:0:0"
  echo "$output" | grep -v '^RESULT:' || true
  IFS=: read -r _ p f sk <<< "$result"
  TOTAL_PASS=$((TOTAL_PASS + p))
  TOTAL_FAIL=$((TOTAL_FAIL + f))
  TOTAL_SKIP=$((TOTAL_SKIP + sk))
done

echo ""
echo -e "${BOLD}═══ Overall ═══${NC}"
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}${TOTAL_PASS} passed${NC}, ${TOTAL_SKIP} skipped — ${GREEN}all tests passed${NC}"
else
  echo -e "${GREEN}${TOTAL_PASS} passed${NC}, ${RED}${TOTAL_FAIL} failed${NC}, ${TOTAL_SKIP} skipped"
  exit 1
fi
