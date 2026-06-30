# bpy Cookbook & Gotchas

Non-obvious truths about Blender's Python API that silently break `execute_blender_code` scripts. **Read before writing bpy.** Facts marked ✅ were verified live against Blender 5.1.2 via the MCP; version-sensitive items note the range.

## Data API vs `bpy.ops`

Prefer the **data API** (`bpy.data`, `bpy.context.collection`) over `bpy.ops` wherever both exist. `bpy.ops` operators depend on the current context (active object, mode, the area/region they're invoked from) and fail or misfire when that context isn't what they expect. The data API has no such dependency and is deterministic.

```python
import bpy
mesh = bpy.data.meshes.new("MyMesh")
obj  = bpy.data.objects.new("MyObj", mesh)
bpy.context.collection.objects.link(obj)   # ✅ without link(), the object exists but never appears in the scene
```

✅ `bpy.ops.mesh.primitive_cube_add(...)` **does** work in the MCP context, and it leaves the new object **active and selected** — so chaining `bpy.context.view_layer.objects.active` / `obj.select_get()` right after is reliable. Use ops for primitives when convenient; drop to the data API for anything context-sensitive.

## Collection linking — the #1 "nothing appeared" trap

A freshly `new()`'d object is **not** in any collection. It won't render, won't show in the viewport, and won't be in `bpy.context.scene.objects` until you link it:

```python
bpy.context.collection.objects.link(obj)        # link to active collection  ✅
# or a specific collection:
bpy.data.collections["Props"].objects.link(obj)
```

To remove cleanly: `bpy.data.objects.remove(obj, do_unlink=True)`.

## Naming collisions — verify names after create

Blender auto-suffixes duplicate names (`Cube` → `Cube.001`). The name you *requested* may not be the name you *got*. After bulk creation, read back actual names instead of assuming:

```python
obj = bpy.data.objects.new("Wheel", mesh)
real_name = obj.name          # may be "Wheel.001" — use this, not the literal "Wheel"
```

## Active object & selection (when you must use ops)

Many `bpy.ops.object.*` operators act on the **active** object and/or the **selection**, not on a variable you hold:

```python
bpy.context.view_layer.objects.active = obj     # set active
obj.select_set(True)                            # add to selection
# now mode/transform ops will target it
```

## Object mode vs edit mode

Mesh-geometry edits need edit mode; most object-level ops need object mode. ✅ `bpy.ops.object.mode_set(mode='EDIT')` / `mode_set(mode='OBJECT')` works in the MCP context (requires an active object). For robust geometry work prefer **bmesh** over `bpy.ops.mesh.*`:

```python
import bmesh
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=2.0)
bm.to_mesh(mesh); bm.free()
```

## Apply transforms

✅ `bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)` bakes the object's scale into the mesh and resets `obj.scale` to `(1,1,1)`. Needs the target selected + active and object mode. Apply scale before modifiers/exports that are scale-sensitive.

## Materials — `node_tree` setup (verified input names)

```python
mat = bpy.data.materials.new("MyMat")
mat.use_nodes = True                                   # ✅ enables the node tree
bsdf = mat.node_tree.nodes.get("Principled BSDF")      # ✅ present by default after use_nodes
bsdf.inputs["Base Color"].default_value = (0.8, 0.1, 0.1, 1.0)
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.5
obj.data.materials.append(mat)                          # assign to the object's mesh
```

⚠ **Emission input renamed.** In Blender 4.x+ (✅ confirmed 5.1.2) the Principled BSDF emission inputs are **`"Emission Color"`** and **`"Emission Strength"`**. The legacy single `"Emission"` input **no longer exists** — `bsdf.inputs["Emission"]` raises `KeyError`. Set both:

```python
bsdf.inputs["Emission Color"].default_value = (1.0, 0.6, 0.2, 1.0)
bsdf.inputs["Emission Strength"].default_value = 5.0
```

## Render engine ids — version-sensitive

✅ Settable in 5.1.2: `CYCLES`, `BLENDER_EEVEE`, `BLENDER_WORKBENCH`.

⚠ The EEVEE identifier **changed across versions** — guard for it:

| Blender | EEVEE id |
|---|---|
| ≤ 4.1 | `BLENDER_EEVEE` |
| 4.2 – 4.5 | `BLENDER_EEVEE_NEXT` |
| 5.0+ | `BLENDER_EEVEE` (✅ 5.1.2) |

```python
import bpy
v = bpy.app.version                                    # e.g. (5, 1, 2)
eevee = "BLENDER_EEVEE_NEXT" if (4,2) <= v[:2] < (5,0) else "BLENDER_EEVEE"
bpy.context.scene.render.engine = eevee
```

Render to file: set `scene.render.filepath`, then `bpy.ops.render.render(write_still=True)`.

## World / HDRI via nodes

```python
world = bpy.context.scene.world or bpy.data.worlds.new("World")
bpy.context.scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs["Color"].default_value = (0.05, 0.05, 0.05, 1.0)
bg.inputs["Strength"].default_value = 1.0
```

For an HDRI, prefer the skill's `download_polyhaven_asset asset_type:"hdris"` — it wires the environment texture for you. Hand-rolling means adding an `ShaderNodeTexEnvironment` and linking it to the Background `Color`.

## Camera & lights

```python
cam_data = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
bpy.context.scene.camera = cam                         # ← scene needs an active camera to render

light_data = bpy.data.lights.new("Sun", type='SUN'); light_data.energy = 5.0
light = bpy.data.objects.new("Sun", light_data)
bpy.context.collection.objects.link(light)
```

## Clearing the default scene

```python
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
```

(Removing via the data API avoids the context requirements of `bpy.ops.object.delete()`.)

## Units & scale

Default scene unit is **metres**; `unit_settings.scale_length = 1.0`. Imported assets (Sketchfab/FBX) often arrive at wildly different scales — rescale after import, and apply scale (above) before exporting or simulating.

## Returning data to the caller

`execute_blender_code` captures stdout, so `print(...)` is your return channel. Emit a parseable marker and join fields:

```python
print("RESULT::" + "|".join([f"objs={len(bpy.data.objects)}", f"engine={bpy.context.scene.render.engine}"]))
```

When driving from the shell, multi-line scripts are painful to quote through mcporter — hex-encode and decode in one line: `exec(__import__('binascii').unhexlify('<hex>').decode())` (avoid base64: its `+/=` chars break mcporter's `key:value` parsing).
