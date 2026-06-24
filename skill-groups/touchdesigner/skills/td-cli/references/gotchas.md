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

## GLSL TOP — `premultrgbbyalpha` Silently Zeroes RGB (CRITICAL)

Every GLSL TOP defaults `par.premultrgbbyalpha = True`. The output stage multiplies RGB by alpha — so anywhere the shader writes `alpha < 1.0`, the stored RGB gets scaled down (and at `alpha = 0`, RGB collapses to zero). The on-screen node thumbnail may still look fine, but the saved PNG or anything downstream that reads RGB will be black/dim wherever alpha was low.

```python
glsl.par.premultrgbbyalpha = False   # required whenever the shader writes RGB and alpha independently
                                     # (e.g. RGB + density pairs, sky shaders that ignore alpha, etc.)
```

`td-cli screenshot --opaque` does **not** rescue this — it only forces output alpha to 255 in the PNG file. If TD already zeroed RGB during premultiplication, the file is genuinely black; `--opaque` will just hide the alpha=0 symptom and make the loss look like a "broken shader" instead of "premultiplication ate the RGB." Disable `premultrgbbyalpha` at the source.

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

## Parameter Expressions — `math.sin`, not `sin`

Parameter expressions are Python, but the bare-name shortcuts you might expect from a shader/REPL aren't in scope. Use the `math` module explicitly:

```python
par.expr = "math.sin(absTime.seconds * 0.5) * 0.5 + 0.5"   # ✅
par.expr = "sin(absTime.seconds)"                          # ❌ NameError
```

Same for `math.cos`, `math.pi`, `math.tau`, etc. `absTime`, `me`, `op(...)` are in scope.

## Custom Parameter Names — One Leading Uppercase Only

Custom parameter names (created via `appendFloat`, `appendInt`, etc.) must be **one leading uppercase letter, the rest lowercase**. TD rejects anything else silently or with a vague error.

| Name | Valid? |
|---|---|
| `Tintred` | ✅ |
| `Tint_red` | ✅ |
| `TintRed` | ❌ second uppercase letter |
| `tintred` | ❌ no leading uppercase |

If you need a multi-word display label, set `.label` on the parameter — the name itself stays single-capitalized.

## Sequence-Based Parameters — Use `.numBlocks`, Not Repeated `.par.X`

Several operators expose their multi-slot parameters as **sequences**, not as `par.X` / `par.X1` / `par.X2`. Setting `par.X = N` on these doesn't expand slots — you have to grow the sequence:

```python
# constantCHOP — number of named channels
chop.seq.const.numBlocks = 8       # ✅ creates 8 const slots
chop.par.const = 8                 # ❌ doesn't do what you think

# GLSL TOP — number of vector uniforms (when you need vec4+ or >3 slots)
glsl.seq.vec.numBlocks = 6         # adds vec0..vec5
# then: glsl.par.vec3name = 'iColor'; glsl.par.vec3valuex = 1.0; ...
```

Same pattern for any "Vectors" / "Channels" / similar repeating page in TD.

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
- **The Constants page silently does NOT bind to `uniform float` declarations.** Even when the const name matches the uniform name, no value reaches the GPU — the uniform reads whatever garbage was at that memory location, often differing frame to frame (flicker). Put all scalar float uniforms on **vec slots** instead and read from `.x` in the shader; TD wires those correctly. The only signal TD gives you is a small `Uniform 'X' is not assigned` line in the GLSL TOP's `_info` DAT — easily missed because the shader still compiles without error.
- **Always read the `_info` DAT after wiring uniforms.** `td-cli dat read /path/to/glsl_info` lists every "Uniform 'X' is not assigned" warning. If any uniform is unbound, the rest of your debugging is wasted. Check info DAT first, before sampling, before screenshotting.
- **Don't use GLSL `out` parameters for sampling helpers.** A function like `void sampleCloud(vec3 d, out vec3 col, out float density)` called twice with different inputs can return identical results — the compiler optimizes one of the calls away, especially when both invocations look structurally similar. Inline the samples or return a struct.
- **`g.seq.const.numBlocks = N` to expand slots can silently wipe existing names.** After every sequence resize, re-set every `constNname` (and re-bind expressions). Same caveat applies to `g.seq.vec.numBlocks`.
- **The val/eval discrepancy is a red herring.** Expression-mode params often have `par.val == 0.0` (cached default) while `par.eval() == correct_value`. The GPU uses `eval()` at cook time, not `val`. Don't waste time forcing `par.val := par.eval()` — it does nothing for GPU behavior.

## Node Layout — Layout at End of Task

**Don't position-as-you-go.** Mid-task iteration deletes and recreates nodes constantly; any positions you set get thrown away. Newly-created nodes pile on top of each other and on top of the user's existing network — illegible.

**Do this instead:** track every op you create, then at the end of the task call TD's built-in layout on **only your new ops**:

```python
new_ops = []
new_ops.append(p.create(td.noiseTOP, 'noise1'))
new_ops.append(p.create(td.levelTOP, 'level1'))
# ... iterate, wire, set params ...

p.layout(ops=new_ops)   # one call, TD's algorithm, leaves user's existing nodes untouched
```

`comp.layout()` with no args rearranges **every** child in the COMP — including the user's hand-laid-out work. Always pass `ops=[...]` with just your additions.

### Fallback: manual positioning

If you need a specific topology (e.g. audio CHOPs forced to the left), set positions yourself:

```python
op_ref.nodeCenterX = x
op_ref.nodeCenterY = y
```

Convention: left→right = data flow, top→bottom = parallel branches. Column spacing ~300px, row spacing ~150px. Audio CHOPs at x:-1800 to -900, processing -400 to 500, render 800 to 1400, post 1700+.

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
