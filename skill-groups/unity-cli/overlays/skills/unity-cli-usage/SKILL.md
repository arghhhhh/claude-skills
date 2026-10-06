---
name: unity-cli-usage
description: Bootstrap the unity-cli toolchain for Unity Editor automation. Use when verifying the unity-cli binary, discovering available tools, invoking a tool by name, switching active Unity instances, configuring an MCP client, or troubleshooting host/port and install-mode issues. Do not use once a more specific Unity workflow skill applies; defer to `unity-scene-create`, `unity-csharp-edit`, `unity-editor-tools`, or another domain skill instead.
allowed-tools: Bash(unity-cli:*), Read, Grep, Glob
user-invocable: false
metadata:
  author: akiojin
  version: 0.9.0
  category: foundation
  triggers:
    - bootstrap
    - install
    - setup
    - connect
    - ping
    - doctor
    - instance
    - mcp
  siblings:
    - unity-package-management
    - unity-project-bootstrap
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

- The user wants to create a new Unity project and bootstrap its bridge and first scene; use `unity-project-bootstrap`.
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
5. Use `--output json` for chained automation. Both success and failure write one stdout envelope: `{success, command, data, errors:[{code,message}], warnings}`. Tool fields below are relative to `data`; check the exit status and `success` before reading them. Bridge error codes remain unchanged in `errors[0].code`.

| Exit | Meaning / next action |
| --- | --- |
| 0 | Success: consume `data` |
| 1 | General failure: inspect diagnostics |
| 2 | `INVALID_ARGUMENT`: correct arguments/JSON |
| 3 | `UNAUTHORIZED`: correct authentication |
| 4 | Unmet precondition: correct settings/capabilities |
| 6 | Operation failure: inspect Bridge code; retry only if safe |
| 7 | Editor unreachable: run `doctor`, recover the target, reconnect |
| 8 | `TEST_FAILED`: inspect `data.failures` |
| 130 / 143 | SIGINT / SIGTERM shell status: interrupted/terminated |

For example, a failed ping returns `{"success":false,"command":"system ping","data":null,"errors":[{"code":"EDITOR_UNREACHABLE","message":"Could not connect to the Editor"}],"warnings":[]}` and exit 7. Read successful results with `jq '.data'`. `--help`/`--version` retain informational text; a signal may terminate the process before an envelope is written.

`run_tests` normally returns a running job with exit 0. Poll `get_test_status` until `data.status` is `completed`; that final call returns exit 8 for failures and 0 for all passed. Response timeout (`TIMEOUT`, exit 6) may follow an executed mutation: inspect its job/request ID before resending.

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
unity-cli tool list --names-only --output json # name array in data
unity-cli tool schema analyze_scene_contents   # inspect a tool's payload shape
unity-cli raw analyze_scene_contents --json '{"includeInactive":true}'
```

## Pinned Install (claude-skills)

This install is built from `arghhhhh/unity-cli`, branch `stable`, pinned by SHA in the claude-skills
manifest. At the current pin `stable` is identical to upstream v0.18.1.

| Variable | Value | Why |
|---|---|---|
| `UNITY_CLI_NO_AUTO_UPDATE` | `1` | Keeps the managed binary on the pinned build. Unset, it auto-updates from `akiojin/unity-cli` GitHub releases and drifts from the cargo build and from the bridge version pinned in Unity projects; upgrades go through the pin. The claude-skills installer sets it at user scope. |
| `UNITY_CLI_HOST` | **leave unset** | ❌ Setting it makes `resolve_endpoint` ignore `instances set-active` entirely — every call goes to port 6400. The default is already `127.0.0.1`. Set it only for a non-local Unity (Docker → `host.docker.internal`). |

```bash
# check — expect NO_AUTO_UPDATE=1 and an empty HOST
echo "NO_AUTO_UPDATE=$UNITY_CLI_NO_AUTO_UPDATE  HOST=$UNITY_CLI_HOST"

# set persistently (Windows) — a shell `export` doesn't reach the daemon
powershell -c "[Environment]::SetEnvironmentVariable('UNITY_CLI_NO_AUTO_UPDATE','1','User')"
```

### Install the CLI through claude-skills, not upstream's bootstrap

Upstream's bootstrap (`scripts/install.sh`, `install.ps1`, `unity-cli setup`) downloads the latest
upstream release binary. That is functionally fine from v0.18.0 on, but it bypasses the pin and
leaves the two binaries below out of sync. Install and upgrade the CLI only through the
claude-skills installer (below). `unity-cli setup` / `bridge install|upgrade|status` are fine for
the **bridge package** in a Unity project.

### A call that answers but never returns = build older than v0.18.0 (Windows)

Any remote call auto-starts `unityd` when it isn't running (#270). In builds before v0.18.0 the
spawned daemon inherits the caller's stdout pipe, so **whatever reads the output — the Bash tool,
`| head`, `$(...)` — hangs until the daemon idles out** (up to 600s), even though Unity answered
instantly. Fixed by #360. If you see it, one of the two binaries is stale: re-run the installer
(see below). Meanwhile, starting the daemon with output discarded avoids it:

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

Confirm the pinned build is live in **both** locations. `--version` only names the release, not the
commit, so compare the files against the cargo build:

```bash
cargo install --list | grep -A1 unity-cli          # expect rev=<sha pinned in manifest.json>
sha256sum ~/.cargo/bin/unity-cli* ~/.unity/tools/unity-cli/*/unity-cli*   # hashes must match
```

Differing hashes mean the managed copy was replaced by a downloaded release: re-run the installer.

Do not `cargo uninstall unity-cli` on the advice of the "may shadow the managed binary" warning:
that warning assumes the managed binary is canonical, but here the cargo build is the source and
the managed copy is synced from it.

## MCP client setup

The CLI is the primary implementation; `unity-cli mcp` is a thin stdio adapter
over the same catalog, execution path and Editor authentication. Use it when a
client needs MCP instead of shell/skill execution. It starts without an Editor
and emits `notifications/tools/list_changed` when the selected Editor connects.

1. Preview the requested client settings with `unity-cli mcp configure cursor --local --dry-run`.
2. Apply them with `unity-cli mcp configure cursor --local`. Supported clients:
   `claude-code`, `cursor`, `vscode`, `windsurf`, `codex`; Claude Desktop is not
   distributed. `--local` writes project settings in the current directory and
   pins that project path; omit it for user settings. Windsurf has no local scope.
3. Ensure `unity-cli` is on the client's PATH, reload its MCP settings, and follow
   the client's trust prompt. Existing keys/other servers are preserved; invalid
   files and symlinks are rejected. Never put an Editor token in client settings.
4. Verify with `npx @modelcontextprotocol/inspector --cli unity-cli mcp --method tools/list`.
   MCP tool failures have `isError: true` and the normal CLI envelope in text
   content. Inspect `errors[0].code` and use the same recovery steps as CLI calls.

## Examples

JSON discovery returns descriptors in `data`, including `params_schema` and
`source` (`builtin` or `custom`). Read `.data[].name` for names, or add
`--names-only` to retain `.data[]`. `--compact` still returns name/description
pairs. Connected Editors add project-local tools to `tool list` / `tool schema`;
`--category custom` selects them. Offline discovery lists builtins. For creating
`[UnityCliBridge.Tools.UnityCliTool]` methods, use `unity-editor-tools`.

- "Add a Cube to the scene" in a fresh project without unity-cli → install the binary, run `unity-cli --output json setup --launch-editor`, then `unity-cli raw create_gameobject --json '{"name":"Cube","primitiveType":"cube"}'`.
- "Check whether unity-cli can reach my Unity Editor." → run `unity-cli system ping`.
- "unity-cli cannot connect to Unity." → `unity-cli doctor --output json`; on `SAFE_MODE`, fix the files in `editorLog.compileErrors` and retry instead of assuming the Editor is closed.
- "Switch to the Unity instance running on port 6401." → `unity-cli instances list --ports 6400,6401` then `unity-cli instances set-active 127.0.0.1:6401`.
- "Run this against ProjectB while two Editors are open." → `unity-cli --project-path <ProjectB> raw get_hierarchy --json '{}'`.
- "Inspect what's in the open scene." → `unity-cli raw analyze_scene_contents --json '{}'`. There is no typed `scene` subcommand for this — `scene create` is the only typed scene operation.
- "What tools does the bridge expose?" → `unity-cli tool list --query <term> --compact` (or `--category <name>`); plain `unity-cli tool list` prints all names. For a specific tool's JSON payload shape: `unity-cli tool schema <tool_name> --output json`.

## References

- [runtime-checklist.md](references/runtime-checklist.md): binary selection, instance selection, connection recovery with `unity-cli doctor`, command routing, CI environment notes.
