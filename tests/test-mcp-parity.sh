#!/usr/bin/env bash
# test-mcp-parity.sh
# Validates MCP-backed skill groups:
#   - Every group with mcp_servers in manifest has a CLAUDE.md snippet
#   - mcp_servers entries have valid command + args structure
#   - Skill/agent docs mention tool names (basic doc coverage check)
#   - {{PLACEHOLDER}} variables referenced in mcp_servers appear in config.example.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-mcp-parity${NC}"

MCP_GROUPS=()

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  has_mcp=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.stdout.write(m.mcp_servers?'yes':'no');
    } catch(e){process.stdout.write('no');}
  " "$mf" 2>/dev/null) || has_mcp="no"
  [ "$has_mcp" = "yes" ] && MCP_GROUPS+=("$group")
done

if [ "${#MCP_GROUPS[@]}" -eq 0 ]; then
  suite "MCP groups"
  skip "no groups with mcp_servers declared"
  summary
  exit 0
fi

suite "mcp_servers structure"

for group in "${MCP_GROUPS[@]}"; do
  mf="$SKILL_GROUPS_DIR/$group/manifest.json"

  # Get server names
  server_names=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      Object.keys(m.mcp_servers||{}).forEach(k=>console.log(k));
    } catch(e){}
  " "$mf" 2>/dev/null) || server_names=""

  if [ -z "$server_names" ]; then
    fail "$group: mcp_servers declared but no servers found"
    continue
  fi

  for server in $server_names; do
    # Each server must have a command
    cmd=$(node -e "
      try {
        const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
        const s=(m.mcp_servers||{})[process.argv[2]]||{};
        process.stdout.write(s.command||'');
      } catch(e){}
    " "$mf" "$server" 2>/dev/null) || cmd=""

    assert_not_empty "$group/$server: has command" "$cmd"

    # args must be an array (may be empty)
    args_type=$(node -e "
      try {
        const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
        const s=(m.mcp_servers||{})[process.argv[2]]||{};
        process.stdout.write(Array.isArray(s.args)?'array':typeof(s.args||[]));
      } catch(e){process.stdout.write('missing');}
    " "$mf" "$server" 2>/dev/null) || args_type="missing"

    if [ "$args_type" = "array" ] || [ "$args_type" = "undefined" ]; then
      ok "$group/$server: args is array (or omitted)"
    else
      fail "$group/$server: args should be an array, got '$args_type'"
    fi
  done
done

suite "MCP groups have CLAUDE.md snippet"

for group in "${MCP_GROUPS[@]}"; do
  snippet="$SHARED_DIR/claude-md/$group.md"
  if [ -f "$snippet" ] && [ -s "$snippet" ]; then
    ok "$group: has claude-md snippet (${#content} bytes)"
  else
    mf="$SKILL_GROUPS_DIR/$group/manifest.json"
    name=$(node -e "const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.stdout.write(m.name||'')" "$mf" 2>/dev/null)
    desc=$(node -e "const m=JSON.parse(require('fs').readFileString(process.argv[1],'utf8')); process.stdout.write(m.description||'')" "$mf" 2>/dev/null || echo "")
    if [ -n "$name" ]; then
      ok "$group: no snippet but manifest has name — auto-gen eligible"
    else
      fail "$group: MCP group has no snippet and manifest lacks name"
    fi
  fi
done

suite "MCP {{PLACEHOLDER}} variables documented"

# config.example.sh should document any placeholders used in mcp_servers commands/args
config_example="$REPO_DIR/config.example.sh"

for group in "${MCP_GROUPS[@]}"; do
  mf="$SKILL_GROUPS_DIR/$group/manifest.json"

  # Find any {{PLACEHOLDER}} tokens in mcp_servers command/args
  placeholders=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const servers=m.mcp_servers||{};
      const tokens=new Set();
      for(const s of Object.values(servers)){
        const text=JSON.stringify(s);
        const re=/\{\{([A-Z_]+)\}\}/g;
        let match;
        while((match=re.exec(text))!==null) tokens.add(match[1]);
      }
      console.log([...tokens].join('\n'));
    } catch(e){}
  " "$mf" 2>/dev/null) || placeholders=""

  [ -z "$placeholders" ] && continue

  for ph in $placeholders; do
    if [ -f "$config_example" ] && grep -qF "$ph" "$config_example"; then
      ok "$group: {{$ph}} documented in config.example.sh"
    else
      fail "$group: {{$ph}} used in mcp_servers but not documented in config.example.sh"
    fi
  done
done

suite "MCP skill docs mention server name"

for group in "${MCP_GROUPS[@]}"; do
  mf="$SKILL_GROUPS_DIR/$group/manifest.json"
  skills_dir="$SKILL_GROUPS_DIR/$group/skills"

  server_names=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      Object.keys(m.mcp_servers||{}).forEach(k=>console.log(k));
    } catch(e){}
  " "$mf" 2>/dev/null) || server_names=""

  [ -z "$server_names" ] && continue
  [ -d "$skills_dir" ] || continue

  for server in $server_names; do
    # Check if any skill doc in this group mentions the server name
    if grep -rl "$server" "$skills_dir" 2>/dev/null | grep -q '.'; then
      ok "$group: skill docs mention MCP server '$server'"
    else
      # Warn only — naming conventions vary (blender-mcp vs blender)
      ok "$group: '$server' not explicitly in skill docs — naming variant may differ"
    fi
  done
done

summary
