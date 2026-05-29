---
version: 1.1.1
name: td-cli
description: Drive a live TouchDesigner session from the terminal via td-cli — operator/parameter editing, Python exec, screenshots, shader templates, harness loop with backup/rollback.
---

# TouchDesigner CLI Skill

Use this skill to inspect and modify a running TouchDesigner project via `td-cli` (HTTP to `TDCliServer.tox` on port 9500).

## Setup

- **Binary**: `{{TD_CLI}}`
- **Requires**: TouchDesigner running with `TDCliServer.tox` loaded in the root network, `webserver1` on port 9500
- **Auto-discovery**: TD writes heartbeat files to `~/.td-cli/instances/`; `td-cli` reads them
- **Auth (optional)**: set `TD_CLI_TOKEN` in both shell and TD process env for HMAC-verified requests

For brevity, `td-cli` below refers to the full path to the binary.

## Not Installed?

- **TouchDesigner**: https://derivative.ca/download
- **td-cli**: https://github.com/0dot77/td-cli — `git clone` + `go install ./cmd/td-cli/` (no prebuilt releases yet)
- **TDCliServer.tox**: drag from the cloned repo's `tox/` folder into your TD project root

## Always Start Here

```bash
td-cli status                              # confirm connection (project name, TD version)
td-cli context --depth 2                   # full project summary: tree, families, harness history
td-cli describe /project1                  # AI-friendly network description
```

If `status` fails: TD isn't running, or `TDCliServer.tox` isn't loaded, or port 9500 is wrong.

## Connection & Discovery

| Command | Purpose |
|---|---|
| `td-cli status` | Check TD connection |
| `td-cli context [--depth N]` | Project summary (tree, families, activity, harness) |
| `td-cli instances` | List running TD instances |
| `td-cli describe [path]` | AI-friendly network description |
| `td-cli doctor` | Full diagnostics |

## Operators

| Command | Purpose |
|---|---|
| `td-cli ops list [path] [--depth N] [--family TYPE]` | List operators |
| `td-cli ops create <type> <parent> [--name N] [--x X] [--y Y]` | Create operator |
| `td-cli ops delete <path>` | Delete |
| `td-cli ops info <path>` | Operator details |
| `td-cli ops rename <path> <new-name>` | Rename |
| `td-cli ops copy/move/clone <src> <parent>` | Duplicate/move |
| `td-cli ops search <parent> <pattern> [--family TYPE]` | Search by name |

## Parameters

| Command | Purpose |
|---|---|
| `td-cli par get <op> [names...]` | Read parameters |
| `td-cli par set <op> <name> <val> [...]` | Set (key-value pairs) |
| `td-cli par pulse <op> <name>` | Pulse a button parameter |
| `td-cli par reset <op> [names...]` | Reset to default |
| `td-cli par expr <op> <name> [expression]` | Get/set an expression |
| `td-cli par export <op>` | Export all params as JSON |
| `td-cli par import <op> <json>` | Import from JSON |

## Connections

| Command | Purpose |
|---|---|
| `td-cli connect <src> <dst> [--src-index N] [--dst-index N]` | Wire operators |
| `td-cli disconnect <src> <dst>` | Unwire |

## Python Execution

| Command | Purpose |
|---|---|
| `td-cli exec "<code>"` | Inline Python in TD |
| `td-cli exec -f <file>` | Execute Python file |
| `td-cli exec ... --verify <path>` | Verify node graph after |
| `td-cli exec ... --screenshot <path>` | Capture TOP to `.tmp/preview.png` |

Inside exec: `td` is pre-imported; `_T('nullTOP')` is a shortcut for `getattr(td, 'nullTOP')`.

## Data Access

| Command | Purpose |
|---|---|
| `td-cli dat read <path>` | Read DAT content |
| `td-cli dat write <path> <content> [-f file]` | Write DAT |
| `td-cli chop info/channels/sample <path>` | Channel data |
| `td-cli sop info/points <path>` | Geometry data |
| `td-cli pop info/points/bounds <path>` | POP data |
| `td-cli table rows/cell <path>` | Table read/write |

## Visual & Media

| Command | Purpose |
|---|---|
| `td-cli screenshot [path] [-o file] [--opaque]` | Capture TOP as PNG (default `.tmp/preview.png`) |
| `td-cli media info <path>` | TOP metadata |
| `td-cli media export <path> <file>` | Export media |
| `td-cli watch [path] [--interval ms]` | Real-time monitor |

**Always screenshot + Read the file after a visual change** — the only way to know whether a render actually looks right.

**⚠ Always pass `--opaque` when capturing for your own visual inspection.** Many TD shaders write `fragColor` with `alpha = 0` (sky/atmospheric shaders, GLSL templates that omit alpha, anything using alpha as a compositing flag). The PNG is technically correct but image viewers composite RGBA over white when alpha=0 — you'll see a blank-white image and reach wrong conclusions, while TD's node thumbnail shows the actual sky because its viewer ignores alpha. `--opaque` forces alpha=255 in the saved PNG so what you Read matches what the artist sees. Omit `--opaque` only when you genuinely need the alpha channel preserved for downstream compositing.

## Harness — Safe Mutation Loop

| Command | Purpose |
|---|---|
| `td-cli harness capabilities` | List supported features |
| `td-cli harness observe [path] [--depth N]` | Snapshot state |
| `td-cli harness verify [path] [--assert JSON]` | Run assertions |
| `td-cli harness apply <path> [--goal TEXT] [--op JSON]` | Apply ops with auto-backup |
| `td-cli harness rollback <id>` | Restore prior state |
| `td-cli harness history [--limit N]` | List iterations |

Use this loop for any restructuring — backups are automatic, rollback is one command.

## Project, Timeline, Cook

| Command | Purpose |
|---|---|
| `td-cli project info` / `td-cli project save [path]` | Metadata / save |
| `td-cli timeline [info\|play\|pause]` | Timeline control |
| `td-cli timeline seek <time>` | Jump to frame |
| `td-cli cook node <path>` | Force-cook an operator |

## Templates & Docs

| Command | Purpose |
|---|---|
| `td-cli pop av [--root path] [--name NAME]` | Build audio-reactive POP scene |
| `td-cli shaders list [--cat CAT]` | List GLSL shader templates |
| `td-cli shaders apply <name> <top>` | Apply shader to GLSL TOP |
| `td-cli docs <operator>` | Offline operator docs |
| `td-cli docs search <keyword>` | Search operators |
| `td-cli docs api [class]` | Python API reference |

## Batch & Network Snapshots

| Command | Purpose |
|---|---|
| `td-cli batch exec <file.json>` | Batch-execute commands |
| `td-cli batch parset <file.json>` | Batch-set parameters |
| `td-cli network export [path] [-o file]` | Export network snapshot |
| `td-cli network import <file> [target]` | Import snapshot |
| `td-cli tox export <comp> -o <file>` | Export component as .tox |
| `td-cli tox import <file> [parent]` | Import .tox |

## Global Flags

- `--port N` — connect to a non-default port
- `--project <path>` — target a specific TD project
- `--json` — raw JSON (pipe-friendly)
- `--timeout <ms>` — request timeout (default 30000)

---

# TD-099 Critical Gotchas

These are non-obvious truths about TouchDesigner 099 that will silently break your code. **Read before writing exec scripts.**

## Operator Type Access

- Types live in the `td` module: `td.noiseTOP`, `td.gridPOP`, `td.audiodeviceinCHOP` (lowercase prefix — **not** `audioDeviceInCHOP`)
- Shortcut in exec: `_T('nullTOP')` ≡ `getattr(td, 'nullTOP')`
- There is **no `popnet`** in 099 — POPs are standalone operators

## POP Network (TD 099)

- POPs wire like normal ops: `noisePOP.inputConnectors[0].connect(gridPOP.outputConnectors[0])`
- Generators: `gridPOP`, `pointgeneratorPOP`, `circlePOP`, `spherePOP`
- Modifiers: `noisePOP`, `transformPOP`, `particlePOP`, `mathPOP`, `randomPOP`
- Converters: `soptoPOP`, `poptoSOP`, `choptoPOP`, `toptoPOP`
- `poptoSOP` uses `par.pop = <pop_op>` (parameter reference — **not** a wire; the SOP has no POP connectors)

## POP → Render Pipeline (Verified)

```python
p2s = container.create(_T('poptoSOP'), 'pop2sop')
p2s.par.pop = noise_pop          # par reference, NOT wire
geo = container.create(_T('geometryCOMP'), 'geo')
geo.par.pathsop = p2s            # pathsop, NOT sop  ⚠ see geometryCOMP gotcha below
geo.par.material = mat
geo.par['ry'].expr = 'absTime.seconds * 5'  # rotate at GEO level, not POP level
cam = container.create(_T('cameraCOMP'), 'cam')
cam.par.lookat = geo             # keeps mesh centered
render = container.create(_T('renderTOP'), 'render')
render.par.camera = cam
render.par.geometry = geo
render.par.lights = light.path   # string path
```

## geometryCOMP — `pathsop` Cook Loop (CRITICAL)

`geo.par.pathsop` can self-loop. Safer pattern: set display/render flags on the output SOP **inside** the geo:

```python
geo = p.create(td.geometryCOMP, 'geo')
for child in list(geo.findChildren(depth=1)): child.destroy()
grid = geo.create(td.gridSOP, 'grid')
noise = geo.create(td.noiseSOP, 'noise')
noise.inputConnectors[0].connect(grid.outputConnectors[0])
null_out = geo.create(td.nullSOP, 'out')
null_out.inputConnectors[0].connect(noise.outputConnectors[0])
null_out.display = True   # ← CRITICAL — defaults are False on programmatic SOPs
null_out.render = True
# DO NOT: geo.par.pathsop = 'out'  ← cook loop
```

## feedbackTOP — Wiring Pattern (CRITICAL)

Needs **both** `par.top` AND a wire input from the **same independent upstream node**:

```python
fb = container.create(_T('feedbackTOP'), 'fb')
fb.inputConnectors[0].connect(glsl.outputConnectors[0])  # wire first
fb.par.top = glsl                                          # then par.top
```

Wrong patterns: `par.top` only ("Not enough sources" error), or `par.top` pointing at a node that depends on `fb` (cook loop).

## renderTOP — Parameter References, Not Wires

```python
render.par.camera = cam_op         # not inputConnectors[0].connect(...)
render.par.geometry = geo_op
render.par.lights = '/project1/light1 /project1/light2'  # space-separated paths
```

## noisePOP — Animation & Calibration

- `par.tx/ty/tz` translates the noise field **spatially** — pushes points out of view. **Do not use for animation.**
- `par.t4d` translates the 4th dimension of 4D noise — **use this** for smooth temporal animation.
- `par.gain` keep small (0.1–1.5). `par.spread` keep 0.1–0.8.

```python
noise.par.type = 'simplex4d'
noise.par['t4d'].expr = 'absTime.seconds * 0.5'
noise.par['gain'].expr = "op('math_bass')['chan1'] * 0.8 + 0.15"
```

## Audio Signal Calibration (CRITICAL)

Raw `audiodeviceinCHOP` is typically -60 to -20 dB (peak ~0.01–0.05). After `audiofilterCHOP` + `analyzeCHOP(rmspower)`, values are ~0.001–0.01. The chain needs amplification:

```
audiodevicein → select(chan1) → audiofilter → analyze(rmspower) → lag → math(gain)
typical gains: bass=5, mid=10, high=20
```

- Too low → no visible reaction. Too high → shader saturates white.
- Always clamp in shader: `float bass = clamp(uAudio.x, 0.0, 2.0);`
- `audiodeviceinCHOP` usually outputs only `chan1` — do not select `chan1-chan8`. Split into bands with `analyzeCHOP` / `audiofilterCHOP`.

## Audio-Reactive Parameters — Use `par.expr`

```python
par.expr = "op('math_bass')['chan1'] * 2.0"   # ✅ live binding
par.val = X                                    # ❌ static set
```

## Expression Paths — Absolute Inside COMPs (CRITICAL)

Expressions resolve **relative to the operator that owns the parameter**. Inside a SOP that lives in `geo_main`, `op('math_bass')` resolves to `/project1/geo_main/math_bass` (wrong).

```python
noise.par.amp.expr = "op('/project1/math_bass')['chan1'] * 2.0"  # ✅ absolute
```

Top-level cross-references can use relative paths; anything inside a COMP referencing outside ops **must** be absolute.

## Parameter Name Gotchas (TD 099)

| Op | Correct param names |
|---|---|
| `selectCHOP` | `channames` (not `chans`) |
| `mathCHOP` | `gain`, `fromrange1/2`, `torange1/2` (no `clamp`/`clampmax`) |
| `analyzeCHOP` | `function` — use `'rmspower'` for audio (NOT `'average'` — cancels +/- to ~0) |
| `noiseCHOP` | `rough` (not `roughness`) |
| `levelTOP` | `brightness1` (not `brightness`), `contrast` |
| `compositeTOP` | `operand` STRING values: `'add'`, `'multiply'`, `'over'`, `'screen'` (not int indices, not `blend`) |
| `constantMAT` | `wireframe` `'on'`/`'off'`, `wirewidth` — default OFF |
| `lightCOMP` | `dimmer` (not `intensity`), `cr/cg/cb` (not `colorr/g/b`) |
| `blurTOP` | `size` |
| `pointgeneratorPOP` | `numpoints` (not `rate`) |
| `spherePOP` | `radx/rady/radz` (not `radius`) |
| `noisePOP` | `spread`, `gain`, `t4d` (NOT `tx/ty/tz` for time) |
| `gridPOP` | `sizex/sizey`, `cols/rows`, `randomx/randomy` |
| `poptoSOP` | `pop` (reference, not wire) |
| `geometryCOMP` | `pathsop` ⚠ cook loop risk; prefer display/render flags |
| `glslmultiTOP` | `pixeldat`, `vec0name`, `vec0valuex/y/z/w` for uniforms |

## GLSL TOP Gotchas (TD 099 / macOS)

- `uTDOutputInfo.res` does **not** contain resolution — hardcode aspect: `vec2(1.78, 1.0)`
- macOS does **not** support geometry shaders — use raymarching in GLSL TOP instead
- Use `vUV.st` for texture coords. Apply `TDOutputSwizzle()` to final `fragColor`.
- `root` is a `baseCOMP` object, not a function — `root.time`, not `root().time`

## Node Layout — Always Position

When creating multiple ops, set `nodeCenterX`/`nodeCenterY`. Convention: left→right = data flow, top→bottom = parallel branches.

```python
def pos(op_ref, x, y):
    op_ref.nodeCenterX = x
    op_ref.nodeCenterY = y
```

Column spacing ~300px, row spacing ~150px. Audio CHOPs at x:-1800 to -900, processing -400 to 500, render 800 to 1400, post 1700+.

## Node Naming — Suffix Collisions

If a name exists (even from a just-destroyed op), TD appends a numeric suffix (`sl_bass` → `sl_bass1`). After bulk `destroy()` + `create()`, **verify actual names** via `op.name` or use `op.path` directly.

## UI Panels — `parameterCOMP` is Simplest

```python
ui = p.create(td.parameterCOMP, 'ui')
ui.par.op = ctrl.path
ui.par.builtin = False
ui.par.custom = True
ui.par.pagenames = True
win = p.create(td.windowCOMP, 'ui_window')
win.par.winop = ui.path
win.par.winw, win.par.winh = 350, 550
win.par.winopen = True
```

Edits `ctrl` parameters directly — no expression wiring needed. Use `windowCOMP` for guaranteed interaction (container viewer requires `A` key).

## Handler Recovery

If the `td_cli_handler` DAT has a compile error, **all POST routes fail** (including `dat write` — you can't recover via the CLI). Recovery: in TD UI, open `/project1/TDCliServer/handler` and paste fresh content from upstream `td/td_cli_handler.py`. Verify syntax locally first: `python -c "import py_compile; py_compile.compile('handler.py', doraise=True)"`.

---

# Creating Networks — Checklist

1. `import td`; use `td.lowercaseTypeCHOP` (not uppercase globals)
2. Set node positions immediately after `create()`
3. Wire inputs: `child.inputConnectors[0].connect(parent.outputConnectors[0])`
4. `renderTOP`: `par.camera`, `par.geometry`, `par.lights` (not wires)
5. `feedbackTOP`: wire + `par.top` to **same** independent upstream node
6. `poptoSOP`: `par.pop = pop_op` (not a wire — SOP has no POP connectors)
7. Audio-reactive params: `par.expr = "..."` (not `par.val`)
8. 3D rotation: at `geometryCOMP` level, not POP/SOP level
9. `noisePOP` time animation: `par.t4d` (not `tx/ty/tz`)
10. Verify parameter names against the gotchas table before setting
11. `display=True, render=True` on output SOP inside `geometryCOMP`
12. Skip `geo.par.pathsop` — cook loop risk; use display/render flags
13. Absolute paths in expressions inside COMPs referencing outside ops
14. After bulk `create()`, verify actual node names (suffix collisions)
