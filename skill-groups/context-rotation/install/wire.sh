#!/usr/bin/env bash
# Idempotent wiring for the context-rotation group. Safe to re-run.
#   1. copy hook scripts into ~/.claude/hooks/context-rotation/
#   2. write a default config (auto-detects a 1M context window if seen)
#   3. install the /long-horizon commands
#   4. merge the three hook registrations into ~/.claude/settings.json
set -euo pipefail

GROUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
HOOK_DIR="$CLAUDE_DIR/hooks/context-rotation"
CMD_DIR="$CLAUDE_DIR/commands"
SETTINGS="$CLAUDE_DIR/settings.json"

# 1. hook scripts
mkdir -p "$HOOK_DIR/state"
cp "$GROUP_DIR"/hooks/*.sh "$HOOK_DIR/"
chmod +x "$HOOK_DIR"/*.sh
echo "✓ hooks → $HOOK_DIR"

# 2. default config — only written if absent (never clobbers user tuning).
if [ ! -f "$HOOK_DIR/config" ]; then
  window=200000
  # If any recent transcript shows >200k tokens in context, this machine runs a
  # 1M-context model; default the window accordingly so rotation isn't premature.
  proj_root="$CLAUDE_DIR/projects"
  if [ -d "$proj_root" ]; then
    biggest=$(python3 - "$proj_root" <<'PY' 2>/dev/null || echo 0
import json,os,sys,glob
root=sys.argv[1]; mx=0
files=sorted(glob.glob(os.path.join(root,"**","*.jsonl"),recursive=True),
             key=lambda p: os.path.getmtime(p), reverse=True)[:20]
for fp in files:
    try:
        for line in open(fp,encoding="utf-8"):
            line=line.strip()
            if '"usage"' not in line: continue
            try: o=json.loads(line)
            except Exception: continue
            u=(o.get("message") or {}).get("usage") or {}
            t=(u.get("input_tokens",0) or 0)+(u.get("cache_creation_input_tokens",0) or 0)+(u.get("cache_read_input_tokens",0) or 0)
            if t>mx: mx=t
    except Exception: pass
print(mx)
PY
)
    [ "${biggest:-0}" -gt 200000 ] 2>/dev/null && window=1000000
  fi
  cat > "$HOOK_DIR/config" <<EOF
# context-rotation config — edit freely. Env vars override these per-session:
#   CONTEXT_ROTATION_WINDOW, CONTEXT_ROTATION_THRESHOLD,
#   CONTEXT_ROTATION_LONG_HORIZON=1 (arm auto-rotate for one session only)
CR_WINDOW=$window        # context window size in tokens
CR_THRESHOLD=65          # rotate when used% >= this
CR_HANDOFF_MAX_AGE=3600  # max age (s) of a handover SessionStart will inject
EOF
  echo "✓ config → $HOOK_DIR/config (window=$window)"
else
  echo "▸ config exists — left untouched"
fi

# 3. slash commands
mkdir -p "$CMD_DIR"
cp "$GROUP_DIR"/commands/*.md "$CMD_DIR/"
echo "✓ commands → $CMD_DIR (/long-horizon, /long-horizon-off)"

# 4. settings.json hook registrations — idempotent (drops any prior
#    context-rotation entries first, then re-adds).
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
python3 - "$SETTINGS" "$HOOK_DIR" <<'PY'
import json,sys
settings_path, hook_dir = sys.argv[1], sys.argv[2]
try:
    cfg=json.load(open(settings_path))
except Exception:
    cfg={}
hooks=cfg.setdefault("hooks",{})
MARK="context-rotation"

def cmd(script):
    return "bash "+hook_dir+"/"+script

wanted={
    "PreToolUse":  ("*", "detect-context.sh"),
    "PostToolUse": ("*", "rotate-detect.sh"),
    "SessionStart":(None,"session-recover.sh"),
}
for event,(matcher,script) in wanted.items():
    arr=[e for e in hooks.get(event,[]) if MARK not in json.dumps(e)]
    entry={"hooks":[{"type":"command","command":cmd(script)}]}
    if matcher is not None:
        entry={"matcher":matcher,**entry}
    arr.append(entry)
    hooks[event]=arr

json.dump(cfg,open(settings_path,"w"),indent=2)
open(settings_path,"a").write("\n")
print("✓ settings.json hooks merged (PreToolUse, PostToolUse, SessionStart)")
PY

echo "✓ context-rotation wired. Restart Claude Code to load the hooks."
