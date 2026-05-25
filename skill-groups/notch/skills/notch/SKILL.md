---
name: notch
version: 0.1.1
description: Build and modify Notch (notch.one) scenes from JavaScript. Use when the user wants to author a Notch scene programmatically, look up a node's properties or CreateNode string, debug a Notch JS script, or extend automation of Notch Builder 2026.1. Trigger on "notch", "notch builder", ".dfx", "skybox", "video loader", "environment image", "javascript node", "nodegraph".
---

# Notch (Builder 2026.1) Authoring Skill

Notch is a real-time visual effects program. Its JavaScript API lets you create and wire nodes from inside a scene — the only programmatic path to building Notch scenes. There is **no public Notch MCP server**, no `.dfx` file format spec, and the command-line tools (`NotchCmdLineRender`, Notch Render Node, APT) are **render-only**.

## What you can and cannot do

| Operation | Possible? | How |
|---|---|---|
| Create nodes | ✅ | `layer.CreateNode("Group::Name")` |
| Parent nodes to render | ✅ | `parent.AddChild(child)` — **required**, orphan nodes don't render |
| Connect node inputs | ✅ | `dst.AddInput(src, "Input Connector Name")` |
| Set float/int/string properties | ✅ | `node.SetFloat("Category.PropertyName", value)` — **category prefix is mandatory** |
| Read back property values | ✅ | `node.GetFloat("Category.PropertyName")` returns the value |
| Set color properties | ⚠️ | Unverified. Try `setF(node, "Attributes.Colour 0 R", r)` etc., then verify in the attribute panel. |
| Assign a Resource (Video attribute) to a Video Loader | ⚠️ | Unverified. Use the `Attributes.Load External File = 1` + `Attributes.Filename = <abs path>` workaround instead — that path is proven. |
| Save the `.dfx` file from JS | ❌ | The Notch team has explicitly stated JS cannot save documents. |
| Open a project from JS | ❌ | Same. |
| Build a scene without a user running the script | ❌ | JS runs only inside a Javascript Node in a loaded scene. |

## Workflow

1. **Make sure the user has a Notch project open** with a layer and a `Javascript Node` placed in it.
2. **One-time setup** — choose a stable path for your script, e.g. `~/Documents/Notch/claude.js`. Touch the file (`touch claude.js`). In Notch's **Resources panel: right-click → Import Resource → Script → JavaScript** → browse to `claude.js`. Then on the Javascript Node, set its `Javascript File` attribute to point at that resource.
3. **Enable file-watching** — In the Resources panel, **right-click the `claude.js` resource → Reflect Resource Changes**. The docs claim this triggers auto-reload on disk changes, but as of 2026.1 v1.0.0.221 it **does not reliably fire**. Keep it enabled, but plan on manual reload as the actual workflow.
4. **The actual reload workflow:** after overwriting the file, the user must **right-click the resource → Reload Resource** in Notch's Resources panel. Then hit play. Tell them this each time you push a script update — don't claim "auto-reload" will pick it up.
5. **You read the log directly** from `C:\Users\<USER>\Documents\Notch\Logs\` — pick the most recently modified `notch_log__*.txt`, grep for `Javascript:`.

⚠️ **Do NOT tell the user to click "Create Javascript File" on the Javascript Node repeatedly.** That button creates a NEW file resource each time, accumulating duplicates in the Resources panel that all point at the same disk path. Use it exactly once (or skip it entirely in favor of the Import Resource workflow above) and then update by overwriting the file.

## The mandatory `Category.Property` naming convention

Every property in a Notch node sits under a category visible in the attribute panel: `Transform`, `Parent Transform`, `Attributes`, `Time`, sometimes `Distortion`. JS Set/Get **must** use the prefix:

```js
// WRONG - silently no-ops
node.SetFloat("Brightness", 1.0);

// RIGHT
node.SetFloat("Attributes.Brightness", 1.0);
node.SetFloat("Transform.Position X", 10.0);
```

Without the prefix, `Set*` appears to succeed (no exception) but writes nothing, and `Get*` returns `undefined`. This is the single most common Notch-JS bug to look for.

## Looking up a node

Use the bundled CLI extractor — it pulls every property from the live manual and outputs them already prefixed for `Set*`.

```bash
# By name (substring match against the 651-node index)
node ~/.claude/skills/notch/notch-node-info.js Skybox
node ~/.claude/skills/notch/notch-node-info.js "Video Loader"

# Find candidate nodes by pattern
node ~/.claude/skills/notch/notch-node-info.js --grep particle

# List every node
node ~/.claude/skills/notch/notch-node-info.js --list | less

# By full URL
node ~/.claude/skills/notch/notch-node-info.js --url "https://manual.notch.one/2026.1/en/docs/reference/nodes/3d/skybox/"
```

Output includes the inferred `CreateNode("Group::Name")` string, every property with category prefix, and every input connector. The `[VERIFIED]` tag means the CreateNode string has been confirmed by running it; `[unverified]` means probe with CreateNode first — if it returns null, try other group prefixes.

The static index is `notch-node-index.json` (651 entries as of 2026.1). Refresh it if Notch ships a new version (see "Refreshing the index" below).

## Confirmed CreateNode strings

| Node | String |
|---|---|
| Video Loader | `Video::Video Loader` |
| Skybox | `3D::Skybox` |
| Environment Image | `Lighting::Environment Image` |
| Sky Light | `Lighting::Sky Light` |

The convention is `<TopGroupTitleCased>::<NodeNameAsDocPageTitle>`. Special title-casing: `3d` → `3D`, `2d` → `2D`, `post-fx` → `Post-FX`. Multi-segment URLs (e.g. `/video/input-output/dynamic-image-loader/`) use just the **top** segment — the inferred guess in the index uses this rule but mark them unverified.

## Confirmed inputs (use with AddInput)

| Source | Destination input | Use |
|---|---|---|
| Video Loader → Skybox | `Skybox Image` | Background texture |
| Video Loader → Environment Image | `Envmap Image` | IBL source |
| Environment Image → Sky Light | `Envmap Image` | IBL drives light |

Notch lighting architecture: **Skybox is visual-only; reflections/IBL need Environment Image + Sky Light** fed from the same image. Don't expect the Skybox alone to tint models.

## Build-script template

Start from `~/.claude/skills/notch/templates/build-script-template.js`. It demonstrates:
- Finding layer root via `layer.GetNode(0)` (the "Untitled Composition" / scene root node)
- Placing new nodes adjacent to the user's existing Javascript Node so they appear on-screen (the UI auto-refreshes, but new nodes go where you put them — `(0,0)` is usually far from where the user is looking)
- Cleanup-by-prefix on re-run so orphan nodes don't pile up
- Loud helpers (`setF`/`setI`/`setS`) that log every Set with readback verification

## Common gotchas

1. **UI looks like it didn't refresh.** It did — your new nodes are off-screen. Place them relative to the existing Javascript Node: `var p = layer.FindNode("Javascript Node").GetNodeGraphPosition(); var ox = p[0] - 700;`
2. **Property won't take.** You forgot the `Category.` prefix. Use the extractor to get the exact name.
3. **Node created but doesn't render or affect lighting.** You forgot `AddChild(root, node)`. CreateNode adds to the layer but doesn't parent to the composition root.
4. **Video Loader shows nothing.** `Filename` is dormant until `Load External File = 1` is set first.
5. **`SetString(name, value)` returns "undefined" from GetString.** Almost always wrong property name — the silent failure mode for unknown names is to read back `undefined`. Verify with the extractor.
6. **Sky Light doesn't exist as `Skylight`.** It's `Sky Light` (two words) — `Lighting::Sky Light`.
7. **JS scripts cannot save the project.** All session work is lost if the user closes without saving manually. Remind them to save.
8. **Duplicate JS resources in the Resources panel.** Sign that the user clicked "Create Javascript File" multiple times. Tell them to delete duplicates and use the right-click → Reflect Resource Changes workflow instead (see Workflow §3).
9. **Edits to the .js file don't take effect.** The likely cause: the user thinks "Reflect Resource Changes" auto-reloads — it doesn't, reliably. They have to right-click the resource → **Reload Resource** manually after each edit. Other possibilities: the resource points at a different file than the one you're editing (check its attribute panel for the effective path), or the user is editing a duplicate resource (delete extras).

## Log location

`C:\Users\<USER>\Documents\Notch\Logs\notch_log__v<version>__<date>__<time>.txt`

The most recently modified file is the live session. Grep for `Javascript:` to filter to only JS output. Engine noise (`FileStream::Open`, etc.) is heavy — always grep before reading.

## HTTP API (orthogonal control surface)

For runtime tweaks of **already-exposed** properties on a Block/Standalone export (NOT Builder), Notch exposes a tiny HTTP API on a project-settings-configurable port (e.g. 8910):
- `GET /control` → manifest of exposed properties by UID
- `GET /control?uid=<urlencoded>&value=<urlencoded>` → set a value

Cannot create nodes. Useful only when the scene is pre-built and properties are right-click → Exposed.

## Refreshing the node index

If Notch ships a new version and the index goes stale:

```bash
# Fetch the manual home page (it contains the full nav with every node link)
curl -sL "https://manual.notch.one/<version>/en/" -o /tmp/notch_home.html
# Then re-run the extraction logic at the bottom of notch-node-info.js (or
# re-run the original one-liner from the conversation that built notch-node-index.json).
```

The version in the URL needs to be the actual Notch version (e.g. `2026.1`). Inferred `CreateNode` strings stay correct as long as the doc URL → CreateNode-string convention holds.

## What's not in this skill (yet)

- Color property API (4-float? packed string? per-channel?). Untested.
- Resource-attachment API (assigning a Resource entry to e.g. a Video Loader's `Video` attribute). The `FindResourceByName()` function exists but the assignment side is undocumented.
- Document save / project open. Officially unsupported by Notch.
- Exposed-property workflow via `Document.SetExposedPropertyValue(uid, value)`. The pattern works but requires pre-exposing in the .dfx; not yet exercised end-to-end.

Add to this list as you discover new patterns. The skill should grow as the user does more in Notch.
