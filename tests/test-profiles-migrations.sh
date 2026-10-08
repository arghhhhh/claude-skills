#!/usr/bin/env bash
# test-profiles-migrations.sh
# profiles/*.json: valid JSON, name matches filename, non-empty groups that all exist.
# migrations/*.md: NNNN-<slug>.md names, unique ids, a title, and real groups in `groups:`.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-profiles-migrations${NC}"

for pf in "$REPO_DIR"/profiles/*.json; do
  [ -f "$pf" ] || continue
  pname="$(basename "$pf" .json)"
  suite "profile: $pname"

  if ! out=$(node -e '
    const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    console.log("NAME " + (p.name || ""));
    console.log("DESC " + (p.description || ""));
    for (const g of (p.groups || [])) console.log("GROUP " + g);
  ' "$pf" 2>/dev/null); then
    fail "valid JSON"
    continue
  fi
  ok "valid JSON"
  out=$(echo "$out" | tr -d '\r')
  assert_eq "name matches filename" "$pname" "$(echo "$out" | sed -n 's/^NAME //p')"
  assert_not_empty "has description" "$(echo "$out" | sed -n 's/^DESC //p')"
  groups=$(echo "$out" | sed -n 's/^GROUP //p')
  assert_not_empty "has groups" "$groups"
  for g in $groups; do
    assert_file "group '$g' exists" "$SKILL_GROUPS_DIR/$g/manifest.json"
  done
done

suite "migrations"
seen_ids=""
for mf in "$REPO_DIR"/migrations/*.md; do
  [ -f "$mf" ] || continue
  base="$(basename "$mf")"
  [ "$base" = "README.md" ] && continue
  if ! echo "$base" | grep -qE '^[0-9]{4}-[a-z0-9-]+\.md$'; then
    fail "$base: name must be NNNN-<slug>.md"
    continue
  fi
  id="${base%%-*}"
  if echo "$seen_ids" | grep -qx "$id"; then fail "$base: duplicate id $id"; else ok "$base: unique id"; fi
  seen_ids="$seen_ids"$'\n'"$id"
  fm_get() { awk -v k="$1" '{sub(/\r$/,"")} NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&index($0,k":")==1{v=substr($0,length(k)+2);sub(/^[ \t]+/,"",v);print v;exit}' "$mf"; }
  assert_not_empty "$base: has title" "$(fm_get title)"
  groups="$(fm_get groups)"
  if [ -n "$groups" ] && [ "$groups" != all ]; then
    for g in $(echo "$groups" | tr ',' ' '); do
      assert_file "$base: group '$g' exists" "$SKILL_GROUPS_DIR/$g/manifest.json"
    done
  fi
done
[ -n "$seen_ids" ] || ok "no migrations yet"

summary
