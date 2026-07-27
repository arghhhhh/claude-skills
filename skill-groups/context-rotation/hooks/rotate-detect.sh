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
# Session-unique names (ROTATION-HANDOVER-<sid8>.md) and the legacy fixed name.
case "$fp" in *ROTATION-HANDOVER*.md) ;; *) exit 0 ;; esac

# Record which handover THIS pane's successor session must load. The pane id is
# the identity that survives /clear, so session-recover.sh reads this pointer
# instead of guessing among possibly-many handover files in a shared cwd.
mkdir -p "$CR_STATE"
pending="$(cr_pending_file)"
if [ -n "$pending" ]; then
  mkdir -p "$(dirname "$pending")"
  printf '%s\n' "$fp" > "$pending" 2>/dev/null || true
fi

# Atomic lock (mkdir) with a 300s TTL so a crash can't wedge rotation forever.
# Keyed per pane so two long-horizon sessions rotating at the same time in
# different panes don't block each other's /clear.
lock="$CR_STATE/rotate.$(cr_pane_key).lock"
if ! mkdir "$lock" 2>/dev/null; then
  age="$(cr_file_age "$lock")"
  [ "$age" -gt 300 ] && rm -rf "$lock" && mkdir "$lock" 2>/dev/null || exit 0
fi

nohup bash "$SELF_DIR/rotator.sh" "$TMUX_PANE" "$(basename "$fp")" >/dev/null 2>&1 &
exit 0
