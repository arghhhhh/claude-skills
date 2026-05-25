# Notch — Confirmed CreateNode Strings, Inputs, and Resources

Read this when you need a verified `CreateNode` string, the right input-connector name for `AddInput`, the color setter pattern, or how the Resources panel is addressed from JS.

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

## Color setter pattern

Colors are written as a comma-separated string via `SetString`:

```js
node.SetString("Colours.Colour 0", "0.1,0.2,0.55,1.0"); // r,g,b,a
```

`GetString` reads back the same property as **comma-separated, 6-decimal precision**, e.g. `"0.100000,0.200000,0.550000,1.000000"`. So strict-equality on readback will fail — verify by substring or just trust the write if no exception. Per-channel float setters (`"Colour 0 R"`, `".R"`, `"[0]"`) do NOT work — we've probed them.

## Resources panel API

```js
var r = Document.FindResourceByName("env_day_night_sky_simple.fx");
if (r) Log("Resource found");
```

`FindResourceByName` is **case-insensitive on the basename** (e.g. `"FOO.FX"` and `"foo.fx"` both match) but does NOT match on absolute paths — pass just the filename. The returned Resource object does NOT expose `GetName()` / `GetUID()` / `GetFilename()` in build 1.0.0.221 — those return `undefined`/`null`. Don't try to introspect it.

`Document.GetNumResources()` / `GetResource(i)` and similar enumeration methods don't exist either — there is no way to list all imported resources from JS.

### Assigning a Resource to a node attribute

The empirically-working pattern is `SetString` with the **filename** (after import):

```js
node.SetString("Attributes.Shader", "env_day_night_sky_simple.fx");
```

⚠ **The `GetString` readback after this is misleading.** For `Custom Shader Post Effect` specifically, `GetString("Attributes.Shader")` returns `"0"` (an internal index, not the filename) even when the bind succeeded — verified by the UI dropdown showing the shader. **Do not treat `"0"` as a binding failure and do not loop retrying.** Confirm binding by checking `Document.FindResourceByName(name)` returns non-null, or just trust the write.

For Video Loader's `Video` attribute specifically, this is unverified — the proven escape hatch is `Attributes.Load External File=1` + `Attributes.Filename=<abs path>`.

### Resource-binding crash: never AddInput a Resource as a node

```js
// CRASHES Notch 1.0.0.221 — no error, hard process crash:
var res = Document.FindResourceByName("foo.fx");
node.AddInput(res, "Shader");
```

`AddInput`'s first argument must be a **Node**. Passing a Resource crashes the editor. To assign a Resource to an attribute use `SetString` (above). To wire a Node use `AddInput`. Never mix them.

## Verified pipeline: Custom Shader Post Effect → Skybox + IBL

The working topology for a procedural-image-driven Skybox + IBL chain (verified in G45/sunset-test.dfx, 2026-05-25):

```
Root
  ├─ RTT (2D::Render To Texture, equirect dimensions e.g. 2048×1024,
  │        Use Main Output Aspect Ratio=0, Rendering Enabled=1)
  │    ├─ Generators::Flat Colour    (Active=1, Width/Height matching RTT —
  │    │                              seeds the framebuffer so the post-fx
  │    │                              chain has something to dispatch over.
  │    │                              Setting it to magenta during dev is a
  │    │                              useful "shader didn't paint" signal.)
  │    └─ Post-FX::Image Processing::Custom Shader Post Effect
  │           Attributes.Active = 1
  │           SetString("Attributes.Shader", "your-shader.fx")
  ├─ Skybox             ← AddInput(RTT, "Skybox Image")
  │                       + Attributes.Image Source Mapping = 2 (equirect)
  ├─ Environment Image  ← AddInput(RTT, "Envmap Image")
  └─ Sky Light          ← AddInput(EnvImg, "Envmap Image")
```

Same RTT feeds both the visible sky AND the PBR-reflection IBL. The `Generators::Flat Colour` child is structural — without an upstream image source inside the RTT the post-fx pass doesn't appear to fire.

⚠ Do **not** put a `Cameras::Camera` inside the RTT — it conflicts with the post-fx render path. The Custom Shader Post Effect runs as a fullscreen pixel pass; it doesn't need a camera. See gotchas.md for the dead-end history.

`Custom Shader Post Effect` exposes only `Attributes.Active` and `Attributes.Shader` — no `Apply Mode`, `Visible`, `Blend Mode`, or `Blend Amount` candidates exist at any prefix (`Attributes.*`, `Rendering.*`, `FX.*`, `Shader.*`).

## Refreshing the node index

If Notch ships a new version and the index goes stale:

```bash
curl -sL "https://manual.notch.one/<version>/en/" -o /tmp/notch_home.html
# Re-run the URL extraction (see notch-node-info.js bottom + git history of this skill).
```

The version in the URL needs to be the actual Notch version (e.g. `2026.1`). Inferred `CreateNode` strings stay correct as long as the doc URL → CreateNode-string convention holds.
