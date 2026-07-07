---
description: Arm automatic context rotation — auto-/clear and resume across a chain of sessions until turned off
---

Enable **long-horizon mode** for context rotation. While armed, crossing the context threshold will not just write a handover — it will automatically rotate to a fresh session (via `/clear`) and resume, with no manual step. This persists across the whole chain of rotated sessions until you run `/long-horizon-off`.

Do this now:

1. Run:

```bash
mkdir -p "$HOME/.claude/hooks/context-rotation/state" && : > "$HOME/.claude/hooks/context-rotation/state/long-horizon.on" && echo "long-horizon: ARMED"
```

2. Confirm to the user that long-horizon auto-rotation is armed, and note the requirements for a truly hands-off `/clear`:
   - the session must be running **inside tmux** (otherwise it degrades to the default flow: handover is written and the user runs `/clear` manually);
   - the session should run with **`--dangerously-skip-permissions` (`--dsp`)** or have `Write`/`Edit` pre-allowed — otherwise the handover write and the post-rotation continuation stall on permission prompts, defeating unattended operation. (The rotation deny hook still fires under `--dsp` — it is not bypassed.)
   - rotation fires when context passes the threshold (default 65%).

3. Tell the user they can disarm anytime with `/long-horizon-off`.
