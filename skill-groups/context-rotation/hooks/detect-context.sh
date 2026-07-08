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

# Only exempt the tools needed to WRITE the handover — everything else (incl.
# Read) can trip the interrupt, so a read-heavy session still rotates. Blocking
# a read just makes the agent write the handover (writes stay allowed) instead.
case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit) exit 0 ;;
esac

# Diagnostic (only when state/debug or CONTEXT_ROTATION_DEBUG=1): record what the
# hook actually sees — including whether env overrides reached it — on EVERY
# non-exempt call, before any early-exit guard.
cr_log "sid=${sid:0:8} tool=$tool envTHR=${CONTEXT_ROTATION_THRESHOLD:-unset} envLH=${CONTEXT_ROTATION_LONG_HORIZON:-unset} cfgTHR=${CR_THRESHOLD:-unset}"

[ -n "$tp" ] && [ -f "$tp" ] || { cr_log "  → exit: no transcript ($tp)"; exit 0; }
used="$(cr_used_tokens "$tp")"
[ -n "$used" ] && [ "$used" -gt 0 ] 2>/dev/null || { cr_log "  → exit: used=$used (no usage yet, e.g. first tool call)"; exit 0; }

window="$(cr_window)"
threshold="$(cr_threshold)"
pct=$(( used * 100 / window ))

notified="$CR_STATE/${sid}.notified"
if [ "$pct" -lt "$threshold" ]; then
  cr_log "sid=${sid:0:8} tool=$tool used=$used win=$window thr=$threshold pct=$pct → allow(under)"
  exit 0
fi
# One interruption per session (a fresh post-/clear session gets a new id).
if [ -f "$notified" ]; then
  cr_log "sid=${sid:0:8} tool=$tool used=$used win=$window thr=$threshold pct=$pct → allow(already-notified)"
  exit 0
fi
cr_log "sid=${sid:0:8} tool=$tool used=$used win=$window thr=$threshold pct=$pct → DENY(rotate)"
mkdir -p "$CR_STATE"
: > "$notified"

reason="⚠ Context rotation — about ${pct}% of the context window is used (threshold ${threshold}%). Pause the current work and write a file named ROTATION-HANDOVER.md in the current working directory. Write it as MEMORY for a successor with none of your context, not as a status log — capture what a file or the repo could NOT reconstruct. Use exactly these sections:
'## Completed Work' — what is done, with concrete anchors (file paths, IDs, ports, URLs, tab/session ids).
'## Remaining Tasks' — what is left, in order.
'## Open Questions / Pending User Decisions' — every unresolved choice awaiting the user, quoted the way you framed it to them, plus any boundaries you were told to respect (e.g. 'do not submit').
'## Working Context (not in any file)' — the WHY behind key decisions, options you considered and rejected, assumptions/constraints the user stated, and current UI/session state needed to resume.
'## Next Steps for Incoming Context' — the exact next action(s) and command(s).
If the project has few docs, err toward verbosity: this handover is the only memory that survives the rotation.
THEN, before you finish, do a REQUIRED review pass: re-open ROTATION-HANDOVER.md with the Read tool and read it top-to-bottom as if you were the successor who has NONE of your current context. Fix anything a stranger could not act on — unstated assumptions, in-flight state, the exact next command, why rejected paths were rejected. Handover quality is the single most important output of this rotation, so this review is not optional."
if cr_long_horizon_active; then
  reason="$reason  Long-horizon mode is ON: do NOT ask the user to do anything — once the reviewed ROTATION-HANDOVER.md is saved, the session rotates on its own (/clear is sent for you and the fresh session is automatically prompted to continue)."
else
  reason="$reason  When the reviewed handover is saved, tell the user to run /clear. The next session AUTO-LOADS this handover as its opening context (a SessionStart hook injects it), but it does NOT resume the work on its own — after /clear the user sends any message (e.g. 'continue') and the fresh agent picks up the Remaining Tasks. Fully hands-off rotation (auto-/clear plus auto-continue, no user step) happens only in long-horizon mode in a tmux-capable shell — see /long-horizon."
fi

python3 - "$reason" <<'PY'
import json,sys
print(json.dumps({"hookSpecificOutput":{
    "hookEventName":"PreToolUse",
    "permissionDecision":"deny",
    "permissionDecisionReason":sys.argv[1]}}))
PY
exit 0
