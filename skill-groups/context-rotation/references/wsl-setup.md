# Hands-off long-horizon on Windows via WSL

Core rotation (detect → handover → SessionStart re-inject) works fine in Windows
Git Bash. **Hands-off auto-`/clear` does not** — `rotator.sh` drives `/clear`
with `tmux send-keys`, and Git for Windows deliberately ships no tmux (it needs a
real pty). MSYS2-tmux-in-Git-Bash is fragile and was rejected. The supported path
is: run unattended long-horizon sessions inside **WSL2**, where tmux is native.

This is a one-time setup. Interactive day-to-day work can stay on Windows (core
rotation covers it); only the unattended runs move to WSL.

## Sharing model (why it's built this way)

WSL Claude Code uses the Linux home `~/.claude` = `/home/<user>/.claude`, a
DIFFERENT store from Windows `C:\Users\<user>\.claude`. Keep them **separate** —
a shared `settings.json` can't hold both `bash C:/Users/...` (valid in Windows
Claude/Git Bash) and `bash /home/<user>/...` (valid in WSL) hook commands, and
re-running `wire.sh` in one clobbers the other. Instead share only the two
platform-neutral things:

| Symlink WSL → Windows | Effect |
|---|---|
| `~/.claude/projects` → `/mnt/c/Users/<user>/.claude/projects` | WSL session `.jsonl`s land in the Windows store, so a Windows session-browser TUI lists them (grouped under a `-home-<user>-...` folder). |
| `~/.claude/hooks/context-rotation/config` → the Windows config | `CR_WINDOW`/`CR_THRESHOLD` (no paths in it) stay in sync — `/rotation` on either side changes both. |

Everything else (settings.json, hooks, commands) stays per-environment.

## Steps (inside the WSL distro)

```bash
# 0. Confirm WSL2 (from PowerShell): wsl -l -v   → VERSION must be 2

# 1. tmux + python3 + git  (usually already present on Ubuntu)
sudo apt update && sudo apt install -y tmux python3 git

# 2. NATIVE Linux node + Claude Code. The Windows binaries leak into the WSL
#    PATH via /mnt/c interop but must NOT be used (a Windows process in a Linux
#    tmux pane won't drive /clear reliably). Install real Linux ones:
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
. "$HOME/.nvm/nvm.sh" && nvm install --lts && nvm alias default 'lts/*'
npm i -g @anthropic-ai/claude-code
#   Verify in an INTERACTIVE shell (nvm loads from .bashrc, which a
#   non-interactive `bash -l` skips — there `claude` falls back to the Windows
#   binary):  bash -ic 'command -v claude'  → must be ~/.nvm/.../bin/claude

# 3. Auth. A fresh ~/.claude isn't logged in. The OAuth token is account-bound,
#    not machine-bound, so copy it from Windows:
cp /mnt/c/Users/<user>/.claude/.credentials.json ~/.claude/.credentials.json
chmod 600 ~/.claude/.credentials.json
#   Creds alone still show the theme/login/trust onboarding — also seed the
#   account+onboarding keys into ~/.claude.json (copy hasCompletedOnboarding,
#   oauthAccount, userID from the Windows C:\Users\<user>\.claude.json). First
#   real launch still needs a one-time "trust this folder" Enter.

# 4. Wire context-rotation into the Linux ~/.claude (hook paths resolve to
#    /home/<user>/... form; installs the `lh` launcher into ~/.bashrc).
#    Run wire.sh straight from the Windows repo via /mnt/c — do NOT re-clone
#    claude-skills into WSL. wire.sh COPIES the hooks into ~/.claude/hooks, so
#    afterwards WSL needs /mnt/c only for future re-wires. (If you also want the
#    skills symlinked in WSL, symlink the whole repo rather than cloning it —
#    see the wsl-interop skill, "The claude-skills repo: reuse Windows, don't
#    re-clone".)
bash /mnt/c/Users/<user>/.claude/.skill-repos/claude-skills/skill-groups/context-rotation/install/wire.sh

# 4b. Set the context window. cr_window auto-detects from the `model` in
#     ~/.claude/settings.json. A fresh WSL ~/.claude has NO model set, so a
#     1M-context model is measured against the 200k default and rotates early
#     (e.g. real 3% shows as ~14%). Set "model" to the SAME id + marker Claude
#     Code uses — the [1m]/[Nk] suffix is what opts a model into its long window
#     and is required for cr_window to pick 1M (a bare id stays 200k):
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
s = json.load(open(p))
s["model"] = "claude-opus-4-8[1m]"   # ← your actual model id, with its context marker
json.dump(s, open(p, "w"), indent=2)
print("model set to", s["model"])
PY
#     Verify:  . ~/.claude/hooks/context-rotation/lib.sh; cr_window   # → 1000000
#     (Alternative: pin CR_WINDOW=1000000 in ~/.claude/hooks/context-rotation/config.)

# 5. Hands-off needs no permission prompts — set in WSL ~/.claude/settings.json:
#      "skipDangerousModePermissionPrompt": true
#      "permissions": { "allow": ["Write","Edit","MultiEdit"] }

# 6. Share sessions + config with the Windows store:
ln -sfn /mnt/c/Users/<user>/.claude/projects ~/.claude/projects
ln -sfn /mnt/c/Users/<user>/.claude/hooks/context-rotation/config \
        ~/.claude/hooks/context-rotation/config   # back up the WSL one first if non-empty
```

## Run it

```bash
lh        # tmux session, claude --dsp, long-horizon armed for that launch only
lh 75     # ...also set this session's threshold to 75%
```

`lh` is the same function on macOS/Linux/WSL (installed by `wire.sh` step 4). It
arms via **inline env on the claude command** (not `export`), so nothing leaks
into your interactive shell. Rotation fires at the threshold; `rotator.sh` sends
`/clear` and pastes a continuation prompt — no keyboard needed.

## Verifying the loop (and NOT looping forever)

Enable debug and drive one rotation:

```bash
touch ~/.claude/hooks/context-rotation/state/debug   # logs to state/decisions.log
```

⚠ **Infinite-rotation footgun:** a fresh post-`/clear` session inherits the same
low threshold + armed marker, so a persistently-low `CR_THRESHOLD` rotates every
session forever. For a bounded test, arm via the marker/config (not env) so you
can disarm mid-run: right after the first `→ DENY(rotate)` in `decisions.log`,
`rm ~/.claude/hooks/context-rotation/state/long-horizon.on` and restore the real
threshold. Note the FIRST tool call of any session logs `used=0` (assistant usage
isn't in the transcript yet) and always allows — trip it on the SECOND call.

Proof it worked: `decisions.log` shows `... pct=N → DENY(rotate)`, the pane shows
an auto-typed `/clear` + continuation prompt, and two session `.jsonl`s (pre/post
clear) appear under the Windows `projects/-home-<user>-<cwd>/` folder.
