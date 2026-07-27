#!/usr/bin/env bash
# SessionStart hook. If a recent ROTATION-HANDOVER.md sits in the session cwd,
# inject it so the fresh context resumes where the last one paused.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

input="$(cat)"

# Auto-number long-horizon sessions launched via `lh <name>` (no-op otherwise).
# Runs before the handover check so the very first session is numbered too.
cr_apply_lh_title "$(cr_json_get "$input" session_id)" "$(cr_json_get "$input" transcript_path)"

cwd="$(cr_json_get "$input" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
max="${CR_HANDOFF_MAX_AGE:-3600}"

# Emit the injection for one specific handover file.
inject() {
  # $1 = handover path
  python3 - "$1" <<'PY'
import json,os,sys
path=sys.argv[1]
try:
    body=open(path,encoding="utf-8").read()
except Exception:
    sys.exit(0)
name=os.path.basename(path)
ctx=("A context rotation handover from this session's predecessor was found ("
     +name+"). Resume from it. Once you have absorbed it, delete "+name+
     " (and ONLY that file — other ROTATION-HANDOVER*.md files in this "
     "directory belong to other concurrent sessions; never read, modify, or "
     "delete those).\n\n"+body)
print(json.dumps({"hookSpecificOutput":{
    "hookEventName":"SessionStart",
    "additionalContext":ctx}}))
PY
}

# 1) tmux long-horizon path: rotate-detect.sh left a pane-keyed pointer naming
#    exactly which handover this pane's fresh session should load. Authoritative
#    when present — no guessing in a shared directory.
pending="$(cr_pending_file)"
if [ -n "$pending" ] && [ -f "$pending" ]; then
  hand="$(cat "$pending" 2>/dev/null)"
  rm -f "$pending" 2>/dev/null || true
  case "$hand" in
    /*|[A-Za-z]:*) ;;              # absolute (POSIX or Windows drive) → as-is
    ?*) hand="$cwd/$hand" ;;       # relative → resolve against session cwd
  esac
  if [ -n "$hand" ] && [ -f "$hand" ] && [ "$(cr_file_age "$hand")" -le "$max" ]; then
    inject "$hand"
    exit 0
  fi
fi

# 2) No pointer (manual flow, or pointer went stale): look at what's in cwd.
#    Session-unique names mean several sessions' handovers can coexist here, so
#    only auto-inject when exactly one fresh candidate exists.
cands=()
for f in "$cwd"/ROTATION-HANDOVER*.md; do
  [ -f "$f" ] || continue
  [ "$(cr_file_age "$f")" -le "$max" ] || continue
  cands+=("$f")
done
[ "${#cands[@]}" -gt 0 ] || exit 0

if [ "${#cands[@]}" -eq 1 ]; then
  inject "${cands[0]}"
  exit 0
fi

# 3) Ambiguous: multiple fresh handovers (concurrent sessions rotated in the
#    same directory). Don't inject any body — the wrong one belongs to another
#    live session. List them and let the user's opening message pick.
listing=""
for f in "${cands[@]}"; do
  listing="$listing- $(basename "$f") (written $(cr_file_age "$f")s ago)"$'\n'
done
python3 - "$listing" <<'PY'
import json,sys
ctx=("Multiple context-rotation handover files were found in the working "
     "directory — they were written by DIFFERENT concurrent sessions, and only "
     "one belongs to this session's predecessor:\n"+sys.argv[1]+
     "If the user's first message names one of these files, resume from that "
     "one (read it, then delete only it). Otherwise ASK the user which handover "
     "belongs to this session before reading any of them — the others are "
     "another live session's memory and must not be read, modified, or deleted.")
print(json.dumps({"hookSpecificOutput":{
    "hookEventName":"SessionStart",
    "additionalContext":ctx}}))
PY
exit 0
