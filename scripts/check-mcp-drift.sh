#!/usr/bin/env bash
# check-mcp-drift.sh — detect drift between an MCP server's live tool list and
# the tools its skill docs reference.
#
# For every skill-group whose manifest declares `mcp_servers`, this:
#   1. runs `npx mcporter list <server>` to get the authoritative live tool set
#   2. greps the group's skill + agent docs for those tool names
#   3. reports:
#        UNDOCUMENTED — tool exists on the server but is not in the docs
#        STALE        — docs reference `<server>.X` but X is not a live tool
#
# Advisory only: it never edits files. Servers backed by a host app
# (Blender, Houdini, ComfyUI) only introspect while that app is running;
# unreachable servers are SKIPPED, not failed.
#
# Usage:
#   scripts/check-mcp-drift.sh            # all mcp-backed groups
#   scripts/check-mcp-drift.sh blender    # one or more named groups
#   scripts/check-mcp-drift.sh blender mermaid comfyui

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GROUPS_DIR="$REPO_ROOT/skill-groups"
TIMEOUT="${MCP_DRIFT_TIMEOUT:-120}"

PY=python
command -v python >/dev/null 2>&1 || PY=python3

if [ -t 1 ]; then
  RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; DIM=$'\e[2m'; BLD=$'\e[1m'; RST=$'\e[0m'
else
  RED=; GRN=; YEL=; DIM=; BLD=; RST=
fi

DRIFT=0
CHECKED=0
SKIPPED=0

# Print "SERVER <name>", "SKILL <name>", "AGENT <name>" lines for a manifest that
# has mcp_servers. Only bare names are emitted (no paths, no drive letters) so
# bash rebuilds file paths in native form — avoids MSYS path mangling. Bash also
# resolves flat (skills/<n>.md) vs directory (skills/<n>/*.md) skill layouts.
emit_manifest_info() {
  "$PY" - "$1" <<'PYEOF'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
servers = m.get("mcp_servers") or {}
if not servers:
    sys.exit(0)
for s in servers:
    print("SERVER", s)
for sk in (m.get("skills") or []):
    print("SKILL", sk)
for ag in (m.get("agents") or []):
    print("AGENT", ag)
PYEOF
}

process_group() {
  local mpath="$1"
  local gdir; gdir="$(dirname "$mpath")"
  local gname; gname="$(basename "$gdir")"

  local servers=() existing=()
  local f
  while read -r kind val; do
    case "$kind" in
      SERVER) servers+=("$val") ;;
      SKILL)
        if [ -f "$gdir/skills/$val.md" ]; then
          existing+=("$gdir/skills/$val.md")
        elif [ -d "$gdir/skills/$val" ]; then
          while IFS= read -r f; do existing+=("$f"); done \
            < <(find "$gdir/skills/$val" -type f -name '*.md')
        fi ;;
      AGENT)
        [ -f "$gdir/agents/$val.md" ] && existing+=("$gdir/agents/$val.md") ;;
    esac
  done < <(emit_manifest_info "$mpath" | tr -d '\r')

  [ ${#servers[@]} -eq 0 ] && return 0

  echo "${BLD}== $gname ==${RST}"
  if [ ${#existing[@]} -eq 0 ]; then
    echo "  ${YEL}note${RST} — no skill/agent doc files found on disk"
  fi

  local srv
  for srv in "${servers[@]}"; do
    echo "  ${DIM}server: $srv${RST}"

    local out rc live
    out="$(timeout "$TIMEOUT" npx mcporter list "$srv" 2>/dev/null)"; rc=$?
    live="$(printf '%s\n' "$out" \
      | grep -oE '^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
      | sed -E 's/.*function[[:space:]]+//' | sort -u)"

    if [ -z "$live" ]; then
      echo "  ${YEL}SKIP${RST} — '$srv' unreachable or exposed no tools (rc=$rc). Is the host app running?"
      SKIPPED=$((SKIPPED+1))
      continue
    fi

    local ntools; ntools=$(printf '%s\n' "$live" | grep -c .)
    CHECKED=$((CHECKED+1))

    # UNDOCUMENTED: live tool name absent from every doc file.
    local missing=() t
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      if [ ${#existing[@]} -eq 0 ] || ! grep -qwF -- "$t" "${existing[@]}" 2>/dev/null; then
        missing+=("$t")
      fi
    done <<< "$live"

    # STALE: docs call `<srv>.X` but X is not a live tool (renamed/removed).
    # Strip URLs first so a domain like `blender.org` isn't read as a tool ref.
    local stale=() refs r
    if [ ${#existing[@]} -gt 0 ]; then
      refs="$(cat "${existing[@]}" 2>/dev/null | sed -E 's#https?://[^[:space:])"]*##g' \
        | grep -oE -- "${srv}\.[A-Za-z_][A-Za-z0-9_]*" \
        | sed -E "s/^${srv}\.//" | sort -u)"
      while IFS= read -r r; do
        [ -z "$r" ] && continue
        grep -qxF -- "$r" <<< "$live" || stale+=("$r")
      done <<< "$refs"
    fi

    echo "  live tools: $ntools | docs scanned: ${#existing[@]} file(s)"
    if [ ${#missing[@]} -eq 0 ] && [ ${#stale[@]} -eq 0 ]; then
      echo "  ${GRN}OK${RST} — docs in sync"
    else
      if [ ${#missing[@]} -gt 0 ]; then
        echo "  ${RED}UNDOCUMENTED${RST} (on server, not in docs):"
        printf '    - %s\n' "${missing[@]}"
        DRIFT=1
      fi
      if [ ${#stale[@]} -gt 0 ]; then
        echo "  ${YEL}STALE${RST} (docs reference ${srv}.X, not a live tool):"
        printf '    - %s\n' "${stale[@]}"
        DRIFT=1
      fi
    fi
  done
  echo
}

# Resolve targets: named groups, or all mcp-backed groups.
manifests=()
if [ $# -gt 0 ] && [ "$1" != "--all" ]; then
  for g in "$@"; do
    mp="$GROUPS_DIR/$g/manifest.json"
    if [ -f "$mp" ]; then manifests+=("$mp"); else echo "${RED}no such group: $g${RST}" >&2; fi
  done
else
  for mp in "$GROUPS_DIR"/*/manifest.json; do
    grep -q '"mcp_servers"' "$mp" && manifests+=("$mp")
  done
fi

echo "${BLD}MCP tool-drift check${RST}  ${DIM}(${#manifests[@]} group(s), timeout ${TIMEOUT}s)${RST}"
echo
for mp in "${manifests[@]}"; do process_group "$mp"; done

echo "${BLD}Summary:${RST} ${CHECKED} server(s) checked, ${SKIPPED} skipped"
if [ "$DRIFT" -ne 0 ]; then
  echo "${YEL}Drift detected — reconcile the docs above, then bump the skill version.${RST}"
  exit 1
fi
echo "${GRN}No drift on reachable servers.${RST}"
exit 0
