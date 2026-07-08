# context-rotation

Automatic context-window rotation for Claude Code. Tool-only group — ships no
skills/agents; it wires Claude Code hooks + two slash commands via `install/wire.sh`.

## Behavior

| Layer | Always on? | What happens |
|---|---|---|
| **Detect + handover** | ✅ default | `PreToolUse` interrupts **once** when context ≥ threshold and tells the agent to write `ROTATION-HANDOVER.md`, then `/clear`. |
| **Session recovery** | ✅ default | `SessionStart` re-injects a recent `ROTATION-HANDOVER.md` from the cwd into the fresh session. |
| **Auto-rotate** | opt-in via `/long-horizon` or `CONTEXT_ROTATION_LONG_HORIZON=1` | `PostToolUse` spots the handover write and a detached `rotator.sh` drives `/clear` via tmux, then re-injects a continuation prompt. `/long-horizon-off` disarms the global marker. |

Only the handover-writing tools (`Write`/`Edit`/`MultiEdit`/`NotebookEdit`) are
exempt — every other tool, **including `Read`**, can trip the interrupt, so a
read-heavy session still rotates. Blocking a read just makes the agent write the
handover (writes stay allowed) instead. One interruption per session (a
post-`/clear` session has a new id, so it re-arms).

### Unattended operation needs no permission prompts

For hands-off long-horizon rotation, run the session with
`--dangerously-skip-permissions` (or pre-allow `Write`/`Edit`). Otherwise the
handover write and the auto-injected continuation each stall on a permission
prompt. The `PreToolUse` deny hook still fires under `--dsp` (it is *not*
bypassed), so rotation still triggers — you just also skip the prompts that
would block the automation. In plain interactive mode the permission prompt on
the handover write is harmless: you're at the keyboard and `/clear` yourself.

### Debugging

`touch ~/.claude/hooks/context-rotation/state/debug` (or set
`CONTEXT_ROTATION_DEBUG=1`) to append every hook decision to
`state/decisions.log` — session id, tool, env vs config threshold, used tokens,
pct, and the allow/deny outcome. Note: the context % can't be computed on a
session's *first* tool call (the assistant usage isn't in the transcript yet),
so that call logs `used=0` and allows. Remove the marker to stop logging.

### Handover contents

The interrupt prompts the agent for a *memory*, not a status log — five
sections: Completed Work, Remaining Tasks, **Open Questions / Pending User
Decisions**, **Working Context (not in any file)**, Next Steps. It's told to err
toward verbosity in doc-sparse projects, since the handover is the only memory
that survives the rotation. It then runs a **required self-review pass** — re-Read
the file as the context-less successor and fix gaps — before finishing, because
handover quality is the whole point of the rotation.

**Load ≠ auto-continue.** `SessionStart` recovery (always on) injects the handover
as the fresh session's opening *context*; it does **not** make the agent resume on
its own. In the default flow you `/clear`, then send any message (e.g. `continue`)
to kick it off. Only long-horizon mode (tmux) also sends `/clear` and the
continuation prompt for you — that's the sole path where rotation is fully
hands-off. The interrupt prompt now says exactly this, per mode, so the agent
doesn't over-promise auto-continuation on the manual flow.

### Changing settings / getting help — `/rotation`

Run `/rotation` any time to see current settings + the long-horizon/tmux
quickstart, or to change values without remembering commands:

- `/rotation` → show settings + quickstart
- `/rotation set threshold to 75` → global threshold change (applies to the next
  tool call; hooks read the config live)
- `/rotation 75` → same

Under the hood it calls `~/.claude/hooks/context-rotation/rotation-ctl.sh`
(`show` | `set-threshold N` | `set-window N` | `help`), which you can also run
directly. Global changes affect all sessions; for one session only, use the env
overrides below.

### `lh` launcher (avoids env leaks)

The installer adds an `lh` shell function (restart your shell to pick it up):

```bash
lh                    # new tmux session running `claude --dsp`, long-horizon armed
lh 75                 # ...also set this session's threshold to 75%
lh fl-mcp-testing     # ...and label the whole rotated chain (see below)
lh fl-mcp-testing 75  # name + threshold — args may be given in either order
```

It sets `CONTEXT_ROTATION_LONG_HORIZON` (and optional threshold) **only for that
launch's subshell**, so the vars never persist in your interactive shell.

**Auto-numbered sessions (`lh <name>`).** Give a launch a task name and every
session in the rotated chain is titled `name-1`, `name-2`, `name-3` … — the first
launch, then one increment per auto-`/clear`. The number is written as a native
`custom-title` entry, so it shows up both in Claude Code's own `/resume` picker
and in the [`cs`](../claude-code-sessions) session browser, making it obvious the
whole chain is one long task. The tmux session is also named after the task (so
two named runs don't collide on the default `lh` name). A trailing `-N` you type
is ignored (`lh fl-mcp-testing-1` and `lh fl-mcp-testing` both number from `-1`),
and each fresh `lh <name>` launch restarts numbering at `-1`. Un-named `lh` and
plain `claude` are unaffected — no titles are written.

⚠ **Env-leak footgun (why `lh` exists):** if you `export CONTEXT_ROTATION_LONG_HORIZON=1`
in a shell and then launch `claude` from it, that (and any later) session inherits
the arming — including your normal interactive session, where a handover write
would then auto-`/clear` your conversation. Prefer `lh`, or use inline env
(`CONTEXT_ROTATION_LONG_HORIZON=1 claude --dsp`), not a bare `export`.

### Scoping a test

`CR_THRESHOLD` is global (all sessions). To test without disturbing other
sessions, launch ONE session with env overrides — both win over the global
config/marker:

```bash
export CONTEXT_ROTATION_THRESHOLD=8 CONTEXT_ROTATION_LONG_HORIZON=1
claude   # only this session rotates early / auto-rotates (NOTE: the export
         # persists — unset it or use `lh` to avoid leaking into later launches)
```

## Detection

The `PreToolUse` payload does **not** expose context usage (verified against the
Claude Code hook docs). So `detect-context.sh` reads `transcript_path` and sums
`input + cache_creation + cache_read` tokens on the last main-chain assistant
message, divides by the window, and compares to the threshold.

## Config

`~/.claude/hooks/context-rotation/config` (env vars override):

| Key | Env override | Default |
|---|---|---|
| `CR_WINDOW` | `CONTEXT_ROTATION_WINDOW` | `200000`, auto-bumped to `1000000` if a recent transcript exceeded 200k |
| `CR_THRESHOLD` | `CONTEXT_ROTATION_THRESHOLD` | `65` |
| `CR_HANDOFF_MAX_AGE` | — | `3600` (s) |

⚠ **Window caveat:** the transcript logs the base model id (`claude-opus-4-8`)
with no `[1m]` marker, so a 1M-context session is indistinguishable from a 200k
one until it actually exceeds 200k tokens. `wire.sh` auto-detects the 1M tier
from recent transcripts; if you switch plans, edit `CR_WINDOW` by hand.

## Requirements

- `python3` (JSON parsing / token math).
- Auto-rotate layer only: **tmux** + Bash 4+. Without tmux, `/long-horizon`
  degrades gracefully to the default write-handover-then-manual-`/clear` flow.

## Windows / WSL

Core rotation (detect + handover + re-inject) and `/rotation` work in **Windows
Git Bash**. But hands-off auto-`/clear` needs tmux, which Git for Windows omits —
so run **unattended long-horizon sessions in WSL2**, where tmux is native. It's a
one-time setup (native node+claude in the distro, auth copy, and symlinking the
`projects/` + rotation `config` into the Windows store so sessions stay locatable
and `/rotation` changes hit both). Full recipe: [`references/wsl-setup.md`](references/wsl-setup.md).

## Re-wiring

`bash install.sh --skills context-rotation` — idempotent (dedupes its own
`settings.json` entries; never clobbers an existing `config`). Restart Claude
Code after install so the hooks load.
