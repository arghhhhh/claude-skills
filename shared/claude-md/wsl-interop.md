## WSL — Reuse Windows tooling, don't rebuild on Linux

You are running inside **WSL2 on a Windows host**. The Windows side already has a full toolchain installed — the claude-skills CLIs (ghidra, unity-cli, ilspy, comfy, td-cli, magick, gh…), dev tools, and GUI apps. Windows executables are callable straight from WSL, but **only with the `.exe` suffix** (`ghidra.exe`, `magick.exe`, `gh.exe`), because their install dirs are on the appended Windows PATH.

Before installing ANY tool on the Linux side, check whether the Windows one already exists: `command -v <tool>.exe` or `where.exe <tool>`. If it does, call the `.exe` (with Windows paths via `wslpath -w`) instead of reinstalling. The claude-skills SKILL.md files invoke bare names (`ghidra`, `magick`, `comfy`) that MISS on WSL — that's the trap; append `.exe`, don't conclude "not installed."

Read `~/.claude/skills/wsl-interop/SKILL.md` before installing a package, running a claude-skills tool, or passing file paths between Linux and Windows tools.

Trigger phrases: "wsl", "windows tool", ".exe", "interop", "wslpath", "/mnt/c", "not installed", "install" (a tool, inside WSL), "reinstall", "command not found" (inside WSL)
