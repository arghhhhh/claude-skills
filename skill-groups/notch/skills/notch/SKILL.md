---
name: notch
version: 0.6.0
description: Build and modify Notch (notch.one) scenes from JavaScript. Use when the user wants to author a Notch scene programmatically, look up a node's properties or CreateNode string, debug a Notch JS script, or extend automation of Notch Builder 2026.1. Trigger on "notch", "notch builder", ".dfx", "skybox", "video loader", "environment image", "javascript node", "nodegraph".
---

# Notch (Builder 2026.1) Authoring Skill

Notch is a real-time visual effects program. Its JavaScript API lets you create and wire nodes from inside a scene — the only programmatic path to building Notch scenes. **There is no general control MCP**, no `.dfx` file format spec, and the command-line tools (`NotchCmdLineRender`, Notch Render Node, APT) are **render-only**. Notch does ship an official **Manual MCP** for docs lookup.

## What you can and cannot do

| Operation | Possible? | How |
|---|---|---|
| Create nodes | ✅ | `layer.CreateNode("Group::Name")` or multi-segment `"Post-FX::Image Processing::X"` |
| Parent nodes so they render | ✅ | `parent.AddChild(child)` — **required**, orphans don't render |
| Connect node inputs | ✅ | `dst.AddInput(src, "Input Connector Name")` |
| Remove input/child (for rewiring) | ✅ | `dst.RemoveInput(src, "Input Name")`, `parent.RemoveChild(child)` |
| Set float/int/string properties | ✅ | `node.SetFloat("Category.PropertyName", value)` — **category prefix is mandatory** |
| Read property values | ✅ | `node.GetFloat/Int/String("Category.PropertyName")` |
| Set colors | ⚠️ | `SetString(node, "Colours.Colour 0", "r,g,b,a")` — see `references/node-catalog.md` |
| Find a Resource by name | ✅ | `Document.FindResourceByName("filename.ext")` |
| Assign a Resource to a node attribute | ❌ / ⚠️ | **No scriptable setter exists for resource-typed attributes.** Manual UI pick is the only verified path. See `references/node-catalog.md` for details and unverified alternatives. |
| Save the `.dfx` file from JS | ❌ | Officially unsupported. |
| Open a project from JS | ❌ | Same. |
| Build a scene without a user running the script | ❌ | JS runs only inside a Javascript Node in a loaded scene. |
| Listen for keypresses | ✅ | Define `function OnKeyPress(key) { ... }` |

## Documentation lookup (do this BEFORE writing any node code)

### Option 1 (preferred) — Notch Manual MCP server

If your harness has it configured (it's in this skill's manifest, so `install.sh --skills notch` registers it), use the `notch-manual` MCP. Algolia-backed search over the live 2026.1 manual. URL: `https://mcp-manual.notch.one/`. Tool: `algolia_search_prod_manual_1_0`.

### Option 2 (fallback) — bundled CLI extractor

```bash
node ~/.claude/skills/notch/notch-node-info.js Skybox
node ~/.claude/skills/notch/notch-node-info.js "Video Loader"
node ~/.claude/skills/notch/notch-node-info.js --grep particle
node ~/.claude/skills/notch/notch-node-info.js --url "https://manual.notch.one/2026.1/en/docs/reference/nodes/3d/skybox/"
```

Output gives the inferred `CreateNode("Group::Name")` string and every property already prefixed with its category, ready to paste into `Set*` calls.

## Workflow

1. **User has a Notch project open** with a layer and a `Javascript Node` placed in it.
2. **One-time setup** — Pick a stable path (e.g. `~/Documents/Notch/claude.js`). In Notch's **Resources panel: right-click → Import Resource → Script → JavaScript** → browse to the file. On the Javascript Node, set its `Javascript File` attribute to that resource.
3. **Enable file-watching** — Right-click the resource → **Reflect Resource Changes**. As of 2026.1 v1.0.0.221 this **does not reliably fire** — leave it on, but plan on manual reload.
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

Without the prefix, `Set*` appears to succeed (no exception) but writes nothing, and `Get*` returns `undefined`. **This is the single most common Notch-JS bug.**

### Categories are ARBITRARY per node — always verify

A common mistake is assuming every property lives under `Attributes`. **It doesn't.** Each node defines its own attribute-panel sections; the JS API uses those section names verbatim:

| Node | Property | Wrong (intuitive) | Right (actual) |
|---|---|---|---|
| Colour Ramp | Colour 0/1/2 | `Attributes.Colour 0` | `Colours.Colour 0` |
| Generators::Gradient | Colour | `Attributes.Colour` | `Rendering.Colour` |
| Materials::Emissive Material | Brightness | `Attributes.Brightness` | `BSDF.Brightness` (or `BRDF.Brightness`) |
| 3D Primitive (lines mode) | Line colour | `Attributes.Colour` | `Lines.Colour` |

**Always run `notch-node-info.js <NodeName>` (or the MCP) before writing any `Set*` calls.** Common sections in the wild: `Transform`, `Parent Transform`, `Attributes`, `Time`, `Distortion`, `Colours`, `Rendering`, `BSDF`, `BRDF`, `Material`, `Lines`, `FX`, `Misc`, `Shader`. There can be others.

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

## Build-script template

Start from `~/.claude/skills/notch/templates/build-script-template.js`. It demonstrates idempotent CreateNode, cleanup-by-prefix on re-run, readback-verified `setF/setI/setS` helpers, and graph-aware node placement.

## Log location

`C:\Users\<USER>\Documents\Notch\Logs\notch_log__v<version>__<date>__<time>.txt`

Most-recently-modified file is the live session. Grep for `Javascript:` to filter only JS output; engine noise (`FileStream::Open`, etc.) is heavy. For graph snapshots, grep for `GRAPH_`.

## References — read these for deeper topics

- **`~/.claude/skills/notch/references/patterns.md`** — read when writing any non-trivial script: idempotent find-or-create, two-state passive/armed safety, graph snapshot, rewire-safe inputs, robust root lookup, try-multiple-candidate setter.
- **`~/.claude/skills/notch/references/gotchas.md`** — read when something "should work" but doesn't: silent no-ops, off-screen nodes, easy-to-confuse lookalike nodes, Post-FX Apply Mode caveat.
- **`~/.claude/skills/notch/references/node-catalog.md`** — read when you need a verified `CreateNode` string, input connector name, color setter pattern, or the Resources panel API.
- **`~/.claude/skills/notch/references/control-surfaces.md`** — read when the user asks about HTTP, OSC, exposed properties, deployment, or this skill's known boundaries.
