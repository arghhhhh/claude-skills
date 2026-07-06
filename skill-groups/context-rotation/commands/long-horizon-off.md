---
description: Disarm automatic context rotation — revert to write-handover-then-manual-/clear
---

Disable **long-horizon mode**. Automatic `/clear` rotation stops; the default behavior remains (at the threshold a handover is written and the user clears manually).

Run:

```bash
rm -f "$HOME/.claude/hooks/context-rotation/state/long-horizon.on" && echo "long-horizon: DISARMED"
```

Then confirm to the user that long-horizon auto-rotation is off and the default handover-on-pause behavior is still active.
