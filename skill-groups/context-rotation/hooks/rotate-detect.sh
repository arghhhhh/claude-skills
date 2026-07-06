#!/usr/bin/env bash
# PostToolUse hook. Only in long-horizon mode: when ROTATION-HANDOVER.md is
# written, launch the detached rotator that drives /clear via tmux. A no-op
# unless long-horizon is armed AND we are inside tmux, so the default
# (write-handover-then-manual-/clear) flow is never disturbed.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

cr_long_horizon_active || exit 0
[ -n "${TMUX:-}" ] || exit 0

input="$(cat)"
tool="$(cr_json_get "$input" tool_name)"
case "$tool" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

fp="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path",""))
except Exception:
    pass' 2>/dev/null)"
case "$fp" in *ROTATION-HANDOVER.md) ;; *) exit 0 ;; esac

# Atomic lock (mkdir) with a 300s TTL so a crash can't wedge rotation forever.
lock="$CR_STATE/rotate.lock"
mkdir -p "$CR_STATE"
if ! mkdir "$lock" 2>/dev/null; then
  age="$(cr_file_age "$lock")"
  [ "$age" -gt 300 ] && rm -rf "$lock" && mkdir "$lock" 2>/dev/null || exit 0
fi

nohup bash "$SELF_DIR/rotator.sh" "$TMUX_PANE" >/dev/null 2>&1 &
exit 0
