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

reason="⚠ Context rotation — about ${pct}% of the context window is used (threshold ${threshold}%). Pause the current work and write a file named ROTATION-HANDOVER.md in the current working directory. Write it as MEMORY for a successor with none of your context, not as a status log — capture what a file or the repo could NOT reconstruct. Use exactly these sections:
'## Completed Work' — what is done, with concrete anchors (file paths, IDs, ports, URLs, tab/session ids).
'## Remaining Tasks' — what is left, in order.
'## Open Questions / Pending User Decisions' — every unresolved choice awaiting the user, quoted the way you framed it to them, plus any boundaries you were told to respect (e.g. 'do not submit').
'## Working Context (not in any file)' — the WHY behind key decisions, options you considered and rejected, assumptions/constraints the user stated, and current UI/session state needed to resume.
'## Next Steps for Incoming Context' — the exact next action(s) and command(s).
If the project has few docs, err toward verbosity: this handover is the only memory that survives the rotation. After writing it, tell the user to run /clear. The handover is auto-loaded into the next session."
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
