#!/usr/bin/env bash
# Idempotent wiring for the context-rotation group. Safe to re-run.
#   1. copy hook scripts into ~/.claude/hooks/context-rotation/
#   2. write a default config (auto-detects a 1M context window if seen)
#   3. install the /long-horizon commands
#   4. merge the three hook registrations into ~/.claude/settings.json
set -euo pipefail

# Windows Git Bash defaults Python's stdout to cp1252, which raises
# UnicodeEncodeError on the ✓ status lines below and (under set -e) aborts the
# wire mid-run. Force UTF-8 so the same script runs clean on macOS/Linux/Windows.
export PYTHONIOENCODING=utf-8

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

# 5. lh launcher — a shell function that opens a tmux session running
#    `claude --dsp` with long-horizon armed for THAT launch only (inline env, no
#    leak into the interactive shell). Installed into ~/.bashrc and ~/.zshrc
#    (whichever exist) between markers so re-runs update in place. Same function
#    on every platform, so `lh` behaves identically on macOS/Linux/WSL.
LH_BEGIN="# >>> context-rotation lh >>>"
LH_END="# <<< context-rotation lh <<<"
lh_block() {
cat <<'LHEOF'
# >>> context-rotation lh >>>
# lh [N] : launch Claude Code in tmux with hands-off long-horizon auto-rotation
# armed for THIS launch only (no shell env leak). N = optional threshold percent.
# Needs tmux + --dsp so the handover write / post-/clear continuation never stall
# on a permission prompt. Disarms when you exit the session. See /rotation.
lh() {
  command -v tmux >/dev/null 2>&1 || { echo "lh: tmux required for hands-off auto-/clear" >&2; return 1; }
  local sess="lh" pre="CONTEXT_ROTATION_LONG_HORIZON=1 "
  if [ -n "${1:-}" ]; then
    case "$1" in ''|*[!0-9]*) echo "lh: threshold must be an integer 1-99" >&2; return 1;; esac
    pre="CONTEXT_ROTATION_THRESHOLD=$1 $pre"
  fi
  if tmux has-session -t "$sess" 2>/dev/null; then tmux attach -t "$sess"; return; fi
  tmux new-session -d -s "$sess"
  tmux send-keys -t "$sess" "${pre}claude --dangerously-skip-permissions" Enter
  tmux attach -t "$sess"
}
# <<< context-rotation lh <<<
LHEOF
}
rcs=()
[ -f "$HOME/.bashrc" ] && rcs+=("$HOME/.bashrc")
[ -f "$HOME/.zshrc" ]  && rcs+=("$HOME/.zshrc")
[ ${#rcs[@]} -eq 0 ] && { : > "$HOME/.bashrc"; rcs+=("$HOME/.bashrc"); }
for rc in "${rcs[@]}"; do
  if grep -qF "$LH_BEGIN" "$rc" 2>/dev/null; then
    python3 - "$rc" "$LH_BEGIN" "$LH_END" <<'PY'
import sys
p,b,e=sys.argv[1],sys.argv[2],sys.argv[3]
lines=open(p,encoding="utf-8").read().splitlines()
out=[]; skip=False
for l in lines:
    s=l.strip()
    if s==b: skip=True; continue
    if s==e: skip=False; continue
    if not skip: out.append(l)
open(p,"w",encoding="utf-8").write("\n".join(out).rstrip("\n")+"\n")
PY
  fi
  printf '\n%s\n' "$(lh_block)" >> "$rc"
  echo "✓ lh → $rc (restart your shell to pick it up)"
done

echo "✓ context-rotation wired. Restart Claude Code to load the hooks."
