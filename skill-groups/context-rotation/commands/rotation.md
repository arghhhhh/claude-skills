---
description: View or change context-rotation settings (threshold/window) and get the long-horizon + tmux quickstart
---

The user wants to inspect or change context-rotation, or needs a reminder how to run a long-horizon (unattended) session. Their request: $ARGUMENTS

The control utility is at `~/.claude/hooks/context-rotation/rotation-ctl.sh`. Interpret $ARGUMENTS and act:

- **Change the rotation threshold to N%** (e.g. "set to 75", "make it 75%", "75") →
  run `bash ~/.claude/hooks/context-rotation/rotation-ctl.sh set-threshold N`
  (N = integer 1–99; typical 60–80). Then confirm the new value and note it applies to the next tool call (hooks read the config live — no restart needed). This is a GLOBAL change affecting all sessions; if the user wants it for one session only, tell them to `export CONTEXT_ROTATION_THRESHOLD=N` in that shell instead.
- **Change the context window** → `bash ~/.claude/hooks/context-rotation/rotation-ctl.sh set-window N`.
- **Show current settings** → `bash ~/.claude/hooks/context-rotation/rotation-ctl.sh show`.
- **"How do I start a long-horizon / unattended run?" / tmux help / anything else / empty $ARGUMENTS** →
  run `bash ~/.claude/hooks/context-rotation/rotation-ctl.sh help` and relay its output (current settings + the tmux/long-horizon quickstart + how to change settings).

Always run the script rather than reciting values from memory — it reads the live config. Keep the reply short: run the command, then confirm what changed or surface the quickstart.
