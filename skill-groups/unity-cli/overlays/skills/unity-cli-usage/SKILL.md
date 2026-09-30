---
name: unity-cli-usage
description: Bootstrap the unity-cli toolchain for Unity Editor automation. Use when verifying the unity-cli binary, discovering available tools, invoking a tool by name, switching active Unity instances, or troubleshooting host/port and install-mode issues. Do not use once a more specific Unity workflow skill applies; defer to `unity-scene-create`, `unity-csharp-edit`, `unity-editor-tools`, or another domain skill instead.
allowed-tools: Bash(unity-cli:*), Read, Grep, Glob
user-invocable: false
metadata:
  author: akiojin
  version: 0.8.0
  category: foundation
  triggers:
    - bootstrap
    - install
    - setup
    - connect
    - ping
    - doctor
    - instance
  siblings:
    - unity-scene-create
    - unity-csharp-edit
    - unity-editor-tools
---

# unity-cli Usage

Bootstrap the unity-cli toolchain so other Unity skills can run reliably. This is a foundation skill that loads automatically when no other unity-* skill matches a connection or install question.

## Use When

- The user asks how to verify or install `unity-cli`, or any Unity task finds `unity-cli` missing or the Editor unreachable.
- The user needs help with `system ping`, `instances list`, or `instances set-active`.
- The user is unsure how to invoke a bridge tool (typed subcommand vs. `raw`/`tool call`) or how to discover what tools exist.
- A workflow is blocked on host/port selection, install mode, or connection troubleshooting.

## Do Not Use When

- A more specific skill clearly matches the task. For scene authoring, use `unity-scene-create`. For C# edits, use `unity-csharp-edit`. For Editor state inspection, use `unity-editor-tools`.
- The request only inspects or edits project files without invoking Unity.

## Preferred Flow

1. **Bootstrap once per project** (skip when `unity-cli system ping` already succeeds):
   1. If `command -v unity-cli` fails, install the release binary without asking for a manual step:
      - macOS / Linux: `curl -fsSL https://raw.githubusercontent.com/akiojin/unity-cli/main/scripts/install.sh | sh`, then use `~/.local/bin/unity-cli` if `~/.local/bin` is not on `PATH`.
      - Windows: run `scripts/install.ps1` the same way when it is published; otherwise download the release asset from GitHub Releases.
      - Only inside a unity-cli source checkout, `cargo run -- <args>` is an alternative for development.
   2. Tell the user that setup edits `Packages/manifest.json` (adds the OpenUPM scoped registry and `com.akiojin.unity-cli-bridge` pinned to the CLI version) and, for legacy-input-only projects, sets `activeInputHandler` to Both in `ProjectSettings/ProjectSettings.asset`; then run `unity-cli --output json setup --launch-editor` from the Unity project root (or pass `--project-path`).
   3. Read the JSON: `ok: true` means the Editor answered `ping` for this project. On `ok: false`, act on `editor.hint` (first import can take several minutes; rerun `setup` to keep waiting). Report any `warnings` — a `versionCheck.status` of `mismatch` means run `unity-cli bridge upgrade`.
2. Verify reachability with `unity-cli system ping`; its `versionCheck` reports CLI ↔ bridge version drift. If it fails, run `unity-cli doctor --output json` and follow the `diagnosis` code (`SAFE_MODE`, `BRIDGE_NOT_INSTALLED`, `PORT_IN_USE`, `EDITOR_NOT_RUNNING`, `SANDBOX_BLOCKED`) before retrying; see the Connection Recovery section of the runtime checklist. On `BRIDGE_NOT_INSTALLED`, run `unity-cli setup`.
3. When multiple editors may run, call `unity-cli instances list` (lists every Editor with its project path) and target one with `--project-path <project>` or by running inside that project directory. On `AMBIGUOUS_EDITOR` (exit 6), pick a `projectPath` from `data.candidates` and retry with `--project-path`. `unity-cli instances set-active <host:port>` still works but persists and takes precedence over the current directory.
4. Pick the right entry point for the operation:
   - **Typed subcommand** when one exists. The bootstrap-relevant typed subcommands are `setup`, `bridge install|upgrade|status`, `system ping`, `scene create`, `instances list`, and `instances set-active`. Other typed subcommands exist too — notably the `reference *` family (`fetch`, `status`, `search`, `grep`, `view`, `find-symbol`, `diff`, `resolve-symbol-at`, `embed-build`, `embed-search`, `clean`), which wrap the `reference_*` bridge tools; see the `unity-csharp-reference` skill. But most bridge tools have no typed wrapper. (Note: `setup`, `bridge *`, `instances list`, and `instances set-active` are local operations, not bridge-tool wrappers.)
   - **`raw <tool_name> --json '{...}'`** (equivalent alias: `tool call <tool_name> --json '{...}'`) for every tool without a typed wrapper. This is the primary way to invoke the bridge, not a fallback. Discover tools by keyword with `unity-cli tool list --query <term> --compact` (narrow further with `--category <name>` such as `scenes`, and `--limit N`) instead of listing all tools; inspect a tool's expected payload with `unity-cli tool schema <tool_name> --output json`.
5. Use `--output json` for chained automation.

```bash
if ! command -v unity-cli >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/akiojin/unity-cli/main/scripts/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
unity-cli --version
unity-cli --output json setup --launch-editor   # bridge install + Editor connection check
unity-cli bridge status                        # declared / resolved bridge version
unity-cli system ping
unity-cli tool list --query scene --compact    # discover tools by keyword
unity-cli tool schema analyze_scene_contents   # inspect a tool's payload shape
unity-cli raw analyze_scene_contents --json '{"includeInactive":true}'
```

## Required Environment (this fork)

This install tracks a **fork** (`arghhhhh/unity-cli`, branch `stable`): upstream v0.16.0 plus
two fixes not yet merged upstream:

| PR | Fix |
|---|---|
| #242 | A bad connection no longer kills `unityd`. |
| #360 | The call that auto-starts `unityd` no longer hangs whatever reads its output (Windows). |

(#357, the `127.0.0.1` default host, is upstream since v0.15.3.)

| Variable | Value | Why |
|---|---|---|
| `UNITY_CLI_NO_AUTO_UPDATE` | `1` | **Load-bearing.** The managed binary auto-updates from `akiojin/unity-cli` GitHub releases. Left on, it overwrites the fork build with upstream's and silently drops both fixes. The claude-skills installer sets it at user scope. |
| `UNITY_CLI_HOST` | **leave unset** | ❌ Setting it makes `resolve_endpoint` ignore `instances set-active` entirely — every call goes to port 6400. The default is already `127.0.0.1`. Set it only for a non-local Unity (Docker → `host.docker.internal`). |

```bash
# check — expect NO_AUTO_UPDATE=1 and an empty HOST
echo "NO_AUTO_UPDATE=$UNITY_CLI_NO_AUTO_UPDATE  HOST=$UNITY_CLI_HOST"

# set persistently (Windows) — a shell `export` doesn't reach the daemon
powershell -c "[Environment]::SetEnvironmentVariable('UNITY_CLI_NO_AUTO_UPDATE','1','User')"
```

### Do not run `unity-cli setup` / `bridge install` to install the CLI itself

Upstream's bootstrap (`scripts/install.sh`, `install.ps1`, `unity-cli setup`) downloads the
**upstream** release binary, which lacks both fixes. Install and upgrade the CLI only through the
claude-skills installer (below). `unity-cli setup` / `bridge install|upgrade|status` are still fine
for the **bridge package** in a Unity project: the fork's bridge is identical to upstream's.

### A call that answers but never returns = upstream build (Windows)

Any remote call auto-starts `unityd` when it isn't running (#270). In upstream builds the
spawned daemon inherits the caller's stdout pipe, so **whatever reads the output — the Bash tool,
`| head`, `$(...)` — hangs until the daemon idles out** (up to 600s), even though Unity answered
instantly. This fork build fixes it (#360). If you see it anyway, the binary was replaced by an
upstream release: re-run the installer (see below). Meanwhile, starting the daemon with output
discarded avoids it:

```bash
unity-cli unityd start >/dev/null 2>&1
```

### Installing or upgrading the binary

**There are two binaries and they are not the same file.** `unityd start` spawns the *managed*
one, not the one on `PATH`, so installing to only one location leaves the daemon running old code:

| Path | Role |
|---|---|
| `~/.cargo/bin/unity-cli` | what `PATH` resolves; produced by `cargo install --git ... --rev <sha>` |
| `~/.unity/tools/unity-cli/<rid>/unity-cli` | **managed** — what `unityd` actually runs, and what auto-update overwrites |

Upgrade: `bash ~/.claude/.skill-repos/claude-skills/install.sh --update` (or `--skills unity-cli`).
It sets `UNITY_CLI_NO_AUTO_UPDATE`, rebuilds only when the pinned SHA changed (`cargo install
--list` shows `rev=<sha>`), then runs `skill-groups/unity-cli/install/sync-managed.sh`, which stops
`unityd` (it holds the managed exe open) and copies the build over the managed binary.

Confirm the fork build is live in **both** locations. `--version` can't tell them apart (the fork
and upstream both report 0.16.0), so compare the files against the cargo build:

```bash
cargo install --list | grep -A1 unity-cli          # expect rev=<sha pinned in manifest.json>
sha256sum ~/.cargo/bin/unity-cli* ~/.unity/tools/unity-cli/*/unity-cli*   # hashes must match
```

Differing hashes mean the managed copy was replaced by an upstream release: re-run the installer.

Do not `cargo uninstall unity-cli` on the advice of the "may shadow the managed binary" warning:
that warning assumes the managed binary is canonical, which is false for a fork install.

## Examples

- "Add a Cube to the scene" in a fresh project without unity-cli → install the binary, run `unity-cli --output json setup --launch-editor`, then `unity-cli raw create_gameobject --json '{"name":"Cube","primitiveType":"cube"}'`.
- "Check whether unity-cli can reach my Unity Editor." → run `unity-cli system ping`.
- "unity-cli cannot connect to Unity." → `unity-cli doctor --output json`; on `SAFE_MODE`, fix the files in `editorLog.compileErrors` and retry instead of assuming the Editor is closed.
- "Switch to the Unity instance running on port 6401." → `unity-cli instances list --ports 6400,6401` then `unity-cli instances set-active 127.0.0.1:6401`.
- "Run this against ProjectB while two Editors are open." → `unity-cli --project-path <ProjectB> raw get_hierarchy --json '{}'`.
- "Inspect what's in the open scene." → `unity-cli raw analyze_scene_contents --json '{}'`. There is no typed `scene` subcommand for this — `scene create` is the only typed scene operation.
- "What tools does the bridge expose?" → `unity-cli tool list --query <term> --compact` (or `--category <name>`); plain `unity-cli tool list` prints all names. For a specific tool's JSON payload shape: `unity-cli tool schema <tool_name> --output json`.

## References

- [runtime-checklist.md](references/runtime-checklist.md): binary selection, instance selection, connection recovery with `unity-cli doctor`, command routing, CI environment notes.
