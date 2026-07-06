# context-rotation shared helpers — sourced by the hook scripts.
# No shebang: always sourced, never executed directly.

CR_HOME="$HOME/.claude/hooks/context-rotation"
CR_STATE="$CR_HOME/state"
CR_CONFIG="$CR_HOME/config"

# Load persisted config (CR_WINDOW, CR_THRESHOLD, CR_HANDOFF_MAX_AGE) if present.
[ -f "$CR_CONFIG" ] && . "$CR_CONFIG"

# Pull a top-level string field out of a hook's stdin JSON.
cr_json_get() {
  # $1 = raw json, $2 = key
  printf '%s' "$1" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    v=d.get(sys.argv[1],"")
    sys.stdout.write("" if v is None else str(v))
except Exception:
    pass' "$2" 2>/dev/null
}

# Effective context window (tokens). Env wins, then config, then 200k default.
cr_window() { echo "${CONTEXT_ROTATION_WINDOW:-${CR_WINDOW:-200000}}"; }

# Rotation threshold as an integer percent. Env wins, then config, then 65.
cr_threshold() { echo "${CONTEXT_ROTATION_THRESHOLD:-${CR_THRESHOLD:-65}}"; }

# True when long-horizon auto-rotate is armed.
cr_long_horizon_active() { [ -f "$CR_STATE/long-horizon.on" ]; }

# Current context occupancy in tokens = input + cache_creation + cache_read on
# the most recent MAIN-CHAIN assistant message (sidechain/subagent lines skipped).
cr_used_tokens() {
  # $1 = transcript_path
  python3 - "$1" <<'PY' 2>/dev/null
import json,sys
path=sys.argv[1]
used=0
try:
    with open(path,encoding="utf-8") as f:
        for line in f:
            line=line.strip()
            if not line:
                continue
            try:
                o=json.loads(line)
            except Exception:
                continue
            if o.get("isSidechain"):
                continue
            m=o.get("message") or {}
            if m.get("role")!="assistant":
                continue
            u=m.get("usage") or {}
            if not u:
                continue
            used=(u.get("input_tokens",0) or 0)+ \
                 (u.get("cache_creation_input_tokens",0) or 0)+ \
                 (u.get("cache_read_input_tokens",0) or 0)
except Exception:
    pass
sys.stdout.write(str(used))
PY
}

# Age of a file in whole seconds (portable across macOS/Linux stat).
cr_file_age() {
  # $1 = path
  local now mt
  now=$(date +%s)
  mt=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null)
  [ -n "$mt" ] || { echo 999999; return; }
  echo $(( now - mt ))
}
