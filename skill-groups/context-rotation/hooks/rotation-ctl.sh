#!/usr/bin/env bash
# Control + help utility for context-rotation. Not a hook — a CLI you (or an
# agent via /rotation) run to view/change settings and recall the long-horizon
# quickstart. Lives next to the hooks so it shares lib.sh + the config path.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"
cfg="$CR_CONFIG"

# Update KEY=VALUE in the config, preserving any trailing comment. Adds the line
# if missing. Env vars still override at runtime; this edits the on-disk default.
set_kv() {
  mkdir -p "$(dirname "$cfg")"
  [ -f "$cfg" ] || printf '# context-rotation config\n' > "$cfg"
  python3 - "$cfg" "$1" "$2" <<'PY'
import os,re,sys
path,key,val=sys.argv[1],sys.argv[2],sys.argv[3]
lines=open(path).read().splitlines() if os.path.exists(path) else []
out=[]; found=False
for l in lines:
    m=re.match(r'^(\s*'+re.escape(key)+r')=(\S+)(.*)$', l)
    if m and not found:
        out.append(f"{m.group(1)}={val}{m.group(3)}"); found=True
    else:
        out.append(l)
if not found: out.append(f"{key}={val}")
open(path,'w').write("\n".join(out)+"\n")
PY
}

is_int() { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

show() {
  echo "context-rotation settings  ($cfg)"
  echo "  threshold : ${CR_THRESHOLD:-65}%   (rotate when context usage >= this)"
  echo "  window    : ${CR_WINDOW:-200000} tokens"
  echo "  handoff max age : ${CR_HANDOFF_MAX_AGE:-3600}s"
  echo "  long-horizon (global marker) : $(cr_long_horizon_active && echo ARMED || echo off)"
  [ -n "${CONTEXT_ROTATION_THRESHOLD:-}" ] && echo "  NOTE: this shell overrides threshold via env = ${CONTEXT_ROTATION_THRESHOLD}%"
  [ -n "${CONTEXT_ROTATION_LONG_HORIZON:-}" ] && echo "  NOTE: this shell has CONTEXT_ROTATION_LONG_HORIZON=${CONTEXT_ROTATION_LONG_HORIZON}"
}

quickstart() {
  local thr="${CR_THRESHOLD:-65}"
  cat <<EOF

── Run a long-horizon (unattended) session ──────────────────────────
  1. open a tmux window:
       tmux new-session
  2. arm auto-rotate for THIS session only (leaves other sessions alone):
       export CONTEXT_ROTATION_LONG_HORIZON=1
       # optional per-session threshold override:
       # export CONTEXT_ROTATION_THRESHOLD=75
  3. launch so rotation is hands-off (skips permission prompts):
       claude --dsp

  Current global threshold is ${thr}%. Auto-/clear needs tmux + --dsp
  (or pre-allowed Write), else the handover write stalls on a prompt.

  tmux basics:
    detach (leave it running) : Ctrl-b then d
    reattach                  : tmux attach
    scroll back               : Ctrl-b then [   (arrows/PageUp, q to quit)
    close for good            : type 'exit' inside it
─────────────────────────────────────────────────────────────────────
EOF
}

case "${1:-help}" in
  show|status) show ;;
  set-threshold)
    v="${2:-}"
    is_int "$v" && [ "$v" -ge 1 ] && [ "$v" -le 99 ] || { echo "usage: set-threshold <1-99>"; exit 1; }
    set_kv CR_THRESHOLD "$v"
    echo "✓ global threshold → ${v}%  (applies to your NEXT tool call — hooks read the config live)"
    if [ "$v" -lt 10 ]; then
      echo "⚠ below ~10% risks rotating on every fresh session (baseline is a few %)."
    fi
    ;;
  set-window)
    v="${2:-}"
    is_int "$v" && [ "$v" -ge 50000 ] || { echo "usage: set-window <tokens, e.g. 200000 or 1000000>"; exit 1; }
    set_kv CR_WINDOW "$v"
    echo "✓ window → ${v} tokens"
    ;;
  help|*)
    show
    quickstart
    echo "change settings:"
    echo "  bash $SELF_DIR/rotation-ctl.sh set-threshold 75"
    echo "  bash $SELF_DIR/rotation-ctl.sh set-window 1000000"
    ;;
esac
