#!/usr/bin/env bash
# PreToolUse hook. When context crosses the threshold, interrupt ONCE and tell
# the agent to write a handover doc. File/read tools always pass (no loop, and
# so the handover can actually be written).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

input="$(cat)"
tool="$(cr_json_get "$input" tool_name)"
sid="$(cr_json_get "$input" session_id)"
tp="$(cr_json_get "$input" transcript_path)"

# Never block the tools needed to write the handover or inspect state.
case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit|Read|Glob|Grep|TodoWrite) exit 0 ;;
esac

[ -n "$tp" ] && [ -f "$tp" ] || exit 0
used="$(cr_used_tokens "$tp")"
[ -n "$used" ] && [ "$used" -gt 0 ] 2>/dev/null || exit 0

window="$(cr_window)"
threshold="$(cr_threshold)"
pct=$(( used * 100 / window ))
[ "$pct" -ge "$threshold" ] || exit 0

# One interruption per session (a fresh post-/clear session gets a new id).
notified="$CR_STATE/${sid}.notified"
[ -f "$notified" ] && exit 0
mkdir -p "$CR_STATE"
: > "$notified"

reason="⚠ Context rotation — about ${pct}% of the context window is used (threshold ${threshold}%). Pause the current work and write a file named ROTATION-HANDOVER.md in the current working directory with exactly these sections: '## Completed Work', '## Remaining Tasks', '## Next Steps for Incoming Context' (be concrete — include file paths, IDs, ports, and the exact next command). After writing it, tell the user to run /clear. The handover is auto-loaded into the next session."
if cr_long_horizon_active; then
  reason="$reason  Long-horizon mode is ON: once you write ROTATION-HANDOVER.md the session will rotate to a fresh context automatically."
fi

python3 - "$reason" <<'PY'
import json,sys
print(json.dumps({"hookSpecificOutput":{
    "hookEventName":"PreToolUse",
    "permissionDecision":"deny",
    "permissionDecisionReason":sys.argv[1]}}))
PY
exit 0
