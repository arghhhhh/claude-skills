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

To assign a Resource to a node attribute, the empirically-working pattern is to set the attribute's string to the resource's **filename** (after the resource is imported):

```js
node.SetString("Attributes.Shader", "env_day_night_sky_simple.fx");
```

For Video Loader's `Video` attribute specifically, this is unverified — the proven escape hatch is `Attributes.Load External File=1` + `Attributes.Filename=<abs path>`.

## Refreshing the node index

If Notch ships a new version and the index goes stale:

```bash
curl -sL "https://manual.notch.one/<version>/en/" -o /tmp/notch_home.html
# Re-run the URL extraction (see notch-node-info.js bottom + git history of this skill).
```

The version in the URL needs to be the actual Notch version (e.g. `2026.1`). Inferred `CreateNode` strings stay correct as long as the doc URL → CreateNode-string convention holds.
