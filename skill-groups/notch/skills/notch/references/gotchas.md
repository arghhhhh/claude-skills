# Notch JS — Gotchas and Easy-to-Confuse Nodes

Read this when something "should work" but doesn't — silent no-ops, nodes that don't render, post-FX that doesn't feed downstream, or wrong-named lookalike nodes.

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

## Post-FX generator caveat: Apply Mode controls where they draw, not whether they output

Post-FX generators (`Gradient 2D`, `Composite Image`, etc.) have an `Apply Mode` enum:
- `0` = **Background** — draws the gradient directly to the scene background (visible)
- `1` = **3D Quad** — renders as a 2D plane in the scene
- `2` = **Object Shading** — per-pixel based on rendered 3D depths
- `3` = **None** — doesn't draw anywhere

Critically: **these nodes don't appear to expose their output as an image port for downstream nodes** like a Skybox or Render To Texture. If you wire them to a Skybox's `Skybox Image` input and Apply Mode is `None`, the Skybox gets nothing. If Apply Mode is `Background`, the gradient draws as the visible sky but the Skybox still gets nothing. To feed an actual rendered image into a Skybox, the proven path is **Video Loader (Filename = absolute path) → Skybox.Skybox Image**, not a Post-FX generator. For animated procedural skies feeding reflections, you likely need a **Custom Shader Post Effect** with a procedural sky shader (`.fx` resource) — that's the approach Notch sample projects use.
