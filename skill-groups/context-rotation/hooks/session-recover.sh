#!/usr/bin/env bash
# SessionStart hook. If a recent ROTATION-HANDOVER.md sits in the session cwd,
# inject it so the fresh context resumes where the last one paused.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

input="$(cat)"
cwd="$(cr_json_get "$input" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
hand="$cwd/ROTATION-HANDOVER.md"
[ -f "$hand" ] || exit 0

age="$(cr_file_age "$hand")"
max="${CR_HANDOFF_MAX_AGE:-3600}"
[ "$age" -le "$max" ] || exit 0

python3 - "$hand" <<'PY'
import json,sys
try:
    body=open(sys.argv[1],encoding="utf-8").read()
except Exception:
    sys.exit(0)
ctx=("A context rotation handover from the previous session was found. "
     "Resume from it. Once you have absorbed it, delete ROTATION-HANDOVER.md.\n\n"+body)
print(json.dumps({"hookSpecificOutput":{
    "hookEventName":"SessionStart",
    "additionalContext":ctx}}))
PY
exit 0
