#!/usr/bin/env bash
# Detached rotator (long-horizon only). Sends /clear to the originating tmux
# pane, then re-injects a short continuation prompt so the fresh session picks
# up immediately. Hooks cannot call /clear directly — hence the tmux dance.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

pane="${1:-}"
lock="$CR_STATE/rotate.lock"
cleanup() { rm -rf "$lock"; }
trap cleanup EXIT

command -v tmux >/dev/null 2>&1 || exit 0
[ -n "$pane" ] || exit 0

# Let the agent finish flushing the handover to disk.
sleep 3

# Clear the context.
tmux send-keys -t "$pane" '/clear' Enter 2>/dev/null || exit 0
sleep 2

# Nudge the fresh session. SessionStart already injected the handover body;
# this just tells it to act. Sent via buffer to survive special characters.
prompt='Continue from the ROTATION-HANDOVER.md that was just injected. Pick up the Remaining Tasks and proceed with the Next Steps.'
tmux set-buffer -b cr_cont "$prompt" 2>/dev/null
tmux paste-buffer -b cr_cont -t "$pane" 2>/dev/null
tmux send-keys -t "$pane" Enter 2>/dev/null
tmux delete-buffer -b cr_cont 2>/dev/null || true
exit 0
