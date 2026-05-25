---
name: notch
version: 0.3.0
description: Build and modify Notch (notch.one) scenes from JavaScript. Use when the user wants to author a Notch scene programmatically, look up a node's properties or CreateNode string, debug a Notch JS script, or extend automation of Notch Builder 2026.1. Trigger on "notch", "notch builder", ".dfx", "skybox", "video loader", "environment image", "javascript node", "nodegraph".
---

# Notch (Builder 2026.1) Authoring Skill

Notch is a real-time visual effects program. Its JavaScript API lets you create and wire nodes from inside a scene — the only programmatic path to building Notch scenes. There is **no general control MCP**, no `.dfx` file format spec, and the command-line tools (`NotchCmdLineRender`, Notch Render Node, APT) are **render-only**. Notch does, however, ship an official **Manual MCP** for docs lookup (see below).

## What you can and cannot do

| Operation | Possible? | How |
|---|---|---|
| Create nodes | ✅ | `layer.CreateNode("Group::Name")` or multi-segment `"Post-FX::Image Processing::X"` |
| Parent nodes so they render | ✅ | `parent.AddChild(child)` — **required**, orphans don't render |
| Connect node inputs | ✅ | `dst.AddInput(src, "Input Connector Name")` |
| Remove input/child (for rewiring) | ✅ | `dst.RemoveInput(src, "Input Name")`, `parent.RemoveChild(child)` |
| Set float/int/string properties | ✅ | `node.SetFloat("Category.PropertyName", value)` — **category prefix is mandatory** |
| Read property values | ✅ | `node.GetFloat/Int/String("Category.PropertyName")` |
| Set colors | ⚠️ | `SetString(node, "Attributes.Colour", "r,g,b,a")` (comma-separated) seems to work for some color attrs. Unverified for all. |
| Find a Resource by name | ✅ | `Document.FindResourceByName("filename.ext")` |
| Assign a Resource to a node attribute | ⚠️ | Empirically: `SetString(node, "Attributes.Shader", "filename.fx")` after the file is imported. Tested for shaders; unverified for Video Loader's `Video` attribute. The proven escape hatch is `Attributes.Load External File=1` + `Attributes.Filename=<abs path>`. |
| Save the `.dfx` file from JS | ❌ | Officially unsupported. |
| Open a project from JS | ❌ | Same. |
| Build a scene without a user running the script | ❌ | JS runs only inside a Javascript Node in a loaded scene. |
| Listen for keypresses | ✅ | Define `function OnKeyPress(key) { ... }` |

## Documentation lookup (use this BEFORE writing any node code)

Two ways to look up node properties — prefer the MCP, fall back to the CLI.

### Option 1 (preferred) — Notch Manual MCP server

If your harness has it configured (it's in this skill's manifest, so `install.sh --skills notch` registers it), use the `notch-manual` MCP. It's Algolia-backed search over the live 2026.1 manual. Server URL: `https://mcp-manual.notch.one/`. Tools include `algolia_search_prod_manual_1_0` for full-text search.

### Option 2 (fallback) — bundled CLI extractor

```bash
# By name (substring match against the 651-node index)
node ~/.claude/skills/notch/notch-node-info.js Skybox
node ~/.claude/skills/notch/notch-node-info.js "Video Loader"

# Find candidate nodes by pattern
node ~/.claude/skills/notch/notch-node-info.js --grep particle

# By full URL
node ~/.claude/skills/notch/notch-node-info.js --url "https://manual.notch.one/2026.1/en/docs/reference/nodes/3d/skybox/"
```

Output gives the inferred `CreateNode("Group::Name")` string and every property already prefixed with its category, ready to paste into `Set*` calls.

## Workflow

1. **User has a Notch project open** with a layer and a `Javascript Node` placed in it.
2. **One-time setup** — Pick a stable path for your script, e.g. `~/Documents/Notch/claude.js`. Create the file. In Notch's **Resources panel: right-click → Import Resource → Script → JavaScript** → browse to `claude.js`. On the Javascript Node, set its `Javascript File` attribute to that resource.
3. **Enable file-watching** — Right-click the resource → **Reflect Resource Changes**. The docs claim this auto-reloads on disk changes, but as of 2026.1 v1.0.0.221 **it does not reliably fire**. Leave it on, but plan on manual reload.
4. **Reload workflow:** after overwriting the .js file, the user must **right-click the resource → Reload Resource** in the Resources panel, then hit play. Tell them this every time.
5. **Read the log directly** from `C:\Users\<USER>\Documents\Notch\Logs\` (Windows). Pick the most recently modified `notch_log__*.txt`, grep for `Javascript:`.

⚠️ **Do NOT tell the user to click "Create Javascript File" on the Javascript Node repeatedly.** That creates a NEW resource each time, accumulating duplicates. Use Import Resource (step 2) once.

## The mandatory `Category.Property` naming convention

Every property in a Notch node sits under a category visible in the attribute panel. JS Set/Get **must** use the prefix:

```js
node.SetFloat("Brightness", 1.0);              // WRONG — silent no-op
node.SetFloat("Attributes.Brightness", 1.0);   // RIGHT
node.SetFloat("Transform.Position X", 10.0);
node.SetString("Attributes.Filename", path);
```

Without the prefix, `Set*` appears to succeed (no exception) but writes nothing, and `Get*` returns `undefined`. This is the single most common Notch-JS bug to look for.

### Categories are ARBITRARY per node — always verify

A common mistake is assuming every property lives under `Attributes`. **It doesn't.** Each node defines its own attribute-panel sections, and the JS API uses those section names verbatim. Examples we've hit the hard way:

| Node | Property | Wrong (intuitive) | Right (actual) |
|---|---|---|---|
| Colour Ramp | Colour 0/1/2 | `Attributes.Colour 0` | `Colours.Colour 0` |
| Generators::Gradient | Colour | `Attributes.Colour` | `Rendering.Colour` |
| Materials::Emissive Material | Brightness | `Attributes.Brightness` | `BSDF.Brightness` (or `BRDF.Brightness`) |
| 3D Primitive (lines mode) | Line colour | `Attributes.Colour` | `Lines.Colour` |

**Always run `notch-node-info.js <NodeName>`** before writing any `Set*` calls. The extractor now detects arbitrary section names dynamically. Common sections in the wild: `Transform`, `Parent Transform`, `Attributes`, `Time`, `Distortion`, `Colours`, `Rendering`, `BSDF`, `BRDF`, `Material`, `Lines`, `FX`, `Misc`, `Shader`. There can be others.

### Color setter pattern

Colors are written as a comma-separated string via `SetString`:

```js
node.SetString("Colours.Colour 0", "0.1,0.2,0.55,1.0"); // r,g,b,a
```

`GetString` reads back the same property as **comma-separated, 6-decimal precision**, e.g. `"0.100000,0.200000,0.550000,1.000000"`. So strict-equality on readback will fail — verify by substring or just trust the write if no exception. Per-channel float setters (`"Colour 0 R"`, `".R"`, `"[0]"`) do NOT work — we've probed them.

### When unsure, try multiple candidate names per call

```js
function trySetFloatAny(node, names, value) {
    for (var i = 0; i < names.length; i++) {
        node.SetFloat(names[i], value);
        if (node.GetFloat(names[i]) === value) return names[i];
    }
    return null;
}
trySetFloatAny(material, ["BSDF.Brightness", "BRDF.Brightness", "Attributes.Brightness"], 1.6);
```

## JS entry points and globals

```js
function Init()         { ... }   // alias: Initialize - once when script loads
function Update()       { ... }   // every frame while project is playing
function OnKeyPress(key){ ... }   // keyboard event, key as string e.g. "B"
```

**Globals available in any function:**
- `Document` — top-level document. Methods: `GetLayer(i)`, `GetNumLayers()`, `FindLayer(name)`, `FindResourceByName(name)`, `SetExposedPropertyValue(uid, value)`, `GetExposedPropertyValue(uid)`.
- `UpdateContext` — current frame context. Fields: `.Layer` (current layer scope), `.GlobalTime`, `.LocalTime`, `.TimeDelta`, `.Node` (the JS node itself).
- `Log(msg)` — appends a line to the Notch log. Prefix your messages for grep-ability.

`UpdateContext.Layer` is preferred over `Document.GetLayer(0)` — it's the JS node's owning layer, which is correct for multi-layer projects.

## Confirmed working patterns

### Idempotent CreateNode (find-or-create)

The most important pattern. Always check before creating, so re-runs don't pile up duplicates:

```js
function findOrCreate(layer, group, name, x, y) {
    var existing = layer.FindNode(name);
    if (existing) return existing;
    var n = layer.CreateNode(group);
    if (!n) { Log("FAIL CreateNode: " + group); return null; }
    n.SetName(name);
    n.SetNodeGraphPosition(x, y);
    return n;
}
```

### Two-state safety (load passive, arm via key)

Import-time mutation can wreck a project. The proven pattern: load script in a passive "log only" mode, arm it via a keypress.

```js
var ENABLE_MUTATION = false;       // flip to true OR press B to arm
var HAS_RUN = false;

function runTask() {
    if (!ENABLE_MUTATION || HAS_RUN) return;
    HAS_RUN = true;
    // ... actual mutations
}

function Init()   { Log("[BRIDGE] Loaded passive. Press B to arm."); }
function Update() { runTask(); }
function OnKeyPress(key) {
    if (key == "B") { ENABLE_MUTATION = true; HAS_RUN = false; runTask(); }
}
```

### Graph snapshot for self-awareness

Before mutating, dump the current graph so the agent (you, reading the log) knows what already exists:

```js
function snapshotGraph(layer) {
    var n = layer.GetNumNodes();
    Log("GRAPH_BEGIN|nodes=" + n);
    for (var i = 0; i < n; i++) {
        var nd = layer.GetNode(i);
        var name = nd.GetName();
        var type = nd.GetCategoryAndType ? nd.GetCategoryAndType() : "?";
        var pos  = nd.GetNodeGraphPosition();
        Log("GRAPH_NODE|i=" + i + "|name=" + name + "|type=" + type + "|pos=" + pos[0] + "," + pos[1]);
    }
    Log("GRAPH_END|nodes=" + n);
}
```

Then grep the log for `GRAPH_` to reconstruct state in the agent context.

### Rewire-idempotent inputs

`AddInput` doesn't reject duplicates. Always `RemoveInput` first when rewiring:

```js
function wire(dst, src, inputName) {
    try { dst.RemoveInput(src, inputName); } catch(e) {}
    dst.AddInput(src, inputName);
}
```

### Find root robustly

Don't assume `layer.GetNode(0)` is the root. Search by name or type:

```js
function findRoot(layer) {
    var r = layer.FindNode("Root");
    if (r) return r;
    var n = layer.GetNumNodes();
    for (var i = 0; i < n; i++) {
        var nd = layer.GetNode(i);
        var type = nd.GetCategoryAndType ? nd.GetCategoryAndType() : "";
        if (type.indexOf("Root") >= 0) return nd;
    }
    return layer.GetNode(0); // last-resort fallback
}
```

## Easy-to-confuse nodes (don't pick the wrong one)

Notch has multiple nodes with similar names that do very different things. The doc page title is the source of truth — always look up properties before assuming.

| Name | Group | What it actually does |
|---|---|---|
| `Generators::Gradient` | Generators | **Single-color sampler** — takes a Colour Ramp input and outputs ONE color (sampled at one position). NOT a 2D gradient image. |
| `Post-FX::Generators::Gradient 2D` | Post-FX | **Spatial 2D gradient renderer** with `Mode` (Linear/Radial) and `Apply Mode` (Background/3D Quad/Object Shading/None). |
| `Particles::Rendering::Gradient 2D Renderer` | Particles | Particle-specific renderer; not a general gradient image source. |
| `Lighting::Sky Light` | Lighting | Two words. `Lighting::Skylight` (one word) does NOT exist. |
| `3D::Skybox` | 3D | Visual sky background. Takes an image; produces no IBL by itself. |
| `Lighting::Environment Image` | Lighting | Preps an HDR image for IBL. Feeds Sky Light. |

### Post-FX generator caveat: Apply Mode controls where they draw, not whether they output

Post-FX generators (`Gradient 2D`, `Composite Image`, etc.) have an `Apply Mode` enum:
- `0` = **Background** — draws the gradient directly to the scene background (visible)
- `1` = **3D Quad** — renders as a 2D plane in the scene
- `2` = **Object Shading** — per-pixel based on rendered 3D depths
- `3` = **None** — doesn't draw anywhere

Critically: **these nodes don't appear to expose their output as an image port for downstream nodes** like a Skybox or Render To Texture. If you wire them to a Skybox's `Skybox Image` input and Apply Mode is `None`, the Skybox gets nothing. If Apply Mode is `Background`, the gradient draws as the visible sky but the Skybox still gets nothing. To feed an actual rendered image into a Skybox, the proven path is **Video Loader (Filename = absolute path) → Skybox.Skybox Image**, not a Post-FX generator. For animated procedural skies feeding reflections, you likely need a **Custom Shader Post Effect** with a procedural sky shader (`.fx` resource) — that's the approach Notch sample projects use.

## Confirmed CreateNode strings

| Node | String |
|---|---|
| Video Loader | `Video::Video Loader` |
| Skybox | `3D::Skybox` |
| Environment Image | `Lighting::Environment Image` |
| Sky Light | `Lighting::Sky Light` |
| Custom Shader Post Effect | `Post-FX::Image Processing::Custom Shader Post Effect` (multi-segment works) |
| Region (graph annotation) | `Nodes::Region` |
| Comment | `Nodes::Comment` |
| Flat Colour generator | `Generators::Flat Colour` |
| Sound Capture | `Sound::Sound Capture` |
| Sound Modifier | `Modifiers::Sound Modifier` |
| Sound FFT Modifier | `Modifiers::Sound FFT Modifier` |
| Sound FFT Region Modifier | `Modifiers::Sound FFT Region Modifier` |
| Value modifier | `Modifiers::Value` |
| Directional Light | `Lighting::Directional Light` |
| Camera | `Cameras::Camera` |
| 3D Primitive | `3D::3D Primitive` |
| Emissive Material | `Materials::Emissive Material` |

**Inferring an unknown one:** `<TopGroupTitleCased>::<NodeNameAsDocPageTitle>`. Special casing: `3d`→`3D`, `2d`→`2D`, `post-fx`→`Post-FX`. Multi-segment paths (3+ levels) also work, e.g. `"Post-FX::Image Processing::Custom Shader Post Effect"`. When in doubt, query the extractor or MCP — every node page in the manual yields the right string.

## Confirmed inputs (use with AddInput)

| Source → Destination | Input name | Purpose |
|---|---|---|
| Video Loader → Skybox | `Skybox Image` | Background texture |
| Video Loader → Environment Image | `Envmap Image` | IBL source |
| Environment Image → Sky Light | `Envmap Image` | IBL drives light |
| Material → 3D Primitive | `Material` (or `Default Material`) | Material assignment |
| Sound Capture → Sound Modifier | `Sound` | Audio routing |
| Sound Capture → Sound FFT Modifier | `Sound` | FFT input |

Notch lighting architecture: **Skybox is visual-only; reflections/IBL need Environment Image + Sky Light** fed from the same image. Don't expect the Skybox alone to tint models.

## Build-script template

Start from `~/.claude/skills/notch/templates/build-script-template.js`. It demonstrates:
- Finding layer root and placing nodes adjacent to the user's Javascript Node so they appear on-screen (the UI auto-refreshes, but new nodes go where you put them — `(0,0)` is usually far from where the user is looking)
- Cleanup-by-prefix on re-run so orphan nodes don't pile up
- Readback-verified `setF/setI/setS` helpers that log every Set with verification

## Resources panel API

```js
var r = Document.FindResourceByName("env_day_night_sky_simple.fx");
if (r) Log("Resource found");
```

To assign a Resource to a node attribute, the empirically-working pattern is to set the attribute's string to the resource's **filename** (after the resource is imported):

```js
node.SetString("Attributes.Shader", "env_day_night_sky_simple.fx");
```

For Video Loader's `Video` attribute specifically, this is unverified — the proven escape hatch is `Attributes.Load External File=1` + `Attributes.Filename=<abs path>`.

## Common gotchas

1. **UI looks like it didn't refresh.** It did — your new nodes are off-screen, or stacked on top of the root node. Place them away from BOTH the JS node and the root:
    ```js
    var jsn  = layer.FindNode("Javascript Node");
    var root = layer.FindNode("Root") || layer.GetNode(0);
    var jp = jsn  ? jsn.GetNodeGraphPosition()  : [0, 0];
    var rp = root ? root.GetNodeGraphPosition() : [0, 0];
    // Place below the root and to the left of the JS node so nothing overlaps.
    var ox = Math.min(jp[0], rp[0]) - 900;
    var oy = Math.max(jp[1], rp[1]) + 250;
    ```
2. **Property won't take.** You forgot the `Category.` prefix. Use the MCP or extractor to get the exact name. Or try multiple candidate names per call.
3. **Node created but doesn't render or affect lighting.** You forgot `AddChild(root, node)`. CreateNode adds to the layer but doesn't parent to the composition root.
4. **Video Loader shows nothing.** `Filename` is dormant until `Load External File = 1` is set first.
5. **`Set*` returns undefined from Get*.** Almost always a wrong property name — `Set*` silently no-ops on unknown names. Verify with the extractor.
6. **Sky Light doesn't exist as `Skylight`.** It's `Sky Light` (two words) — `Lighting::Sky Light`.
7. **JS scripts cannot save the project.** All session work is lost if the user closes without saving manually. Remind them to save.
8. **Duplicate JS resources in the Resources panel.** Sign that the user clicked "Create Javascript File" multiple times. Use the right-click → Import Resource workflow instead.
9. **Edits to the .js file don't take effect.** "Reflect Resource Changes" auto-reload is unreliable. The user must right-click the resource → **Reload Resource** manually after each edit.
10. **Script runs as soon as imported and breaks the project.** Use the two-state safety pattern — start in passive mode, arm via key.
11. **Rerun creates duplicates of every node.** Make CreateNode idempotent (`findOrCreate` pattern) or cleanup-by-prefix first.

## Log location

`C:\Users\<USER>\Documents\Notch\Logs\notch_log__v<version>__<date>__<time>.txt`

The most recently modified file is the live session. Grep for `Javascript:` to filter to only JS output. Engine noise (`FileStream::Open`, etc.) is heavy — always grep before reading.

For structured graph snapshots, grep for `GRAPH_` (if your script emits them per the pattern above).

## HTTP API (orthogonal control surface)

For runtime tweaks of **already-exposed** properties on a Block/Standalone export (NOT Builder), Notch exposes a tiny HTTP API on a project-settings-configurable port (e.g. 8910):
- `GET /control` → manifest of exposed properties by UID
- `GET /control?uid=<urlencoded>&value=<urlencoded>` → set a value

Cannot create nodes. Useful only when the scene is pre-built and properties are right-click → Exposed.

## OSC

For live numeric/text values while the scene is playing (not for scene authoring), Notch supports OSC. The OSC Modifier node receives values into the nodegraph. Use OSC for real-time parameter modulation; use JS for structural scene work.

## When to use JS vs OSC vs HTTP vs file-load

- **JS** — scene setup, node creation, property editing, graph wiring (this skill's focus).
- **OSC** — live numeric/text values while the scene is playing (modulation, performance).
- **HTTP** — exposed-property control on Blocks/Standalone exports (production deployment).
- **External files via Reflect Resource Changes** — agentic iteration loop (this skill's workflow).
- **Native Notch Assets** — portable, reusable handoff once a setup is proven.

## Refreshing the node index

If Notch ships a new version and the index goes stale:

```bash
curl -sL "https://manual.notch.one/<version>/en/" -o /tmp/notch_home.html
# Re-run the URL extraction (see notch-node-info.js bottom + git history of this skill).
```

The version in the URL needs to be the actual Notch version (e.g. `2026.1`). Inferred `CreateNode` strings stay correct as long as the doc URL → CreateNode-string convention holds.

## What's not in this skill (yet)

- **Color property API canonical form.** Comma-separated string via `SetString` works for some color attrs, but the full convention (per-channel floats? packed RGBA?) is not fully verified.
- **Document save / project open.** Officially unsupported by Notch.
- **Exposed-property workflow end-to-end.** `Document.SetExposedPropertyValue(uid, value)` works in principle but requires pre-exposing in the .dfx; not yet exercised here.
- **`EmbedConnectedNodes()` for converting a working subgraph into an Asset.** Documented but not tested.
- **Reflect Resource Changes auto-reload root cause.** Why it doesn't fire reliably — bug or config — is unknown.

Add to this list as you discover new patterns. The skill should grow with the user's Notch work.

## Sources

- [Notch JavaScript reference](https://manual.notch.one/2026.1/en/docs/reference/javascript/)
- [Manual MCP Server](https://manual.notch.one/2026.1/en/docs/misc/manual-mcp-server/)
- [Add JS Script workflow](https://manual.notch.one/2026.1/en/docs/reference/javascript/add-a-js-script/)
- [CreateNode signature](https://manual.notch.one/2026.1/en/docs/reference/javascript/reference/layer/createnode/)
- [Web/HTTP API](https://manual.notch.one/2026.1/en/docs/reference/devices-protocols/web-http-api/)
- [OSC](https://manual.notch.one/2026.1/en/docs/reference/devices-protocols/osc/)
