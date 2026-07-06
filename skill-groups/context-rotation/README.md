# context-rotation

Automatic context-window rotation for Claude Code. Tool-only group — ships no
skills/agents; it wires Claude Code hooks + two slash commands via `install/wire.sh`.

## Behavior

| Layer | Always on? | What happens |
|---|---|---|
| **Detect + handover** | ✅ default | `PreToolUse` interrupts **once** when context ≥ threshold and tells the agent to write `ROTATION-HANDOVER.md`, then `/clear`. |
| **Session recovery** | ✅ default | `SessionStart` re-injects a recent `ROTATION-HANDOVER.md` from the cwd into the fresh session. |
| **Auto-rotate** | opt-in via `/long-horizon` | `PostToolUse` spots the handover write and a detached `rotator.sh` drives `/clear` via tmux, then re-injects a continuation prompt. `/long-horizon-off` disarms. |

File-write/read tools are never blocked, so the handover can always be written
and there's no block loop. One interruption per session (a post-`/clear` session
has a new id, so it re-arms).

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

## Re-wiring

`bash install.sh --skills context-rotation` — idempotent (dedupes its own
`settings.json` entries; never clobbers an existing `config`). Restart Claude
Code after install so the hooks load.
