# Building a Scene — Checklist

Run through this when building a Blender scene from scratch via `execute_blender_code`. Each item maps to a trap in `bpy-cookbook.md`.

1. `get_scene_info` first — know what's already there before you clear or add anything.
2. `import bpy`; prefer the **data API** (`bpy.data` + `collection.objects.link`) over `bpy.ops` for context-sensitive work.
3. Clear defaults via the data API: `for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)` — not `bpy.ops.object.delete()`.
4. **Link every new object** to a collection (`bpy.context.collection.objects.link(obj)`) — unlinked objects never appear or render.
5. After creating objects, **read back `obj.name`** — Blender auto-suffixes collisions (`Cube.001`); don't assume your requested name stuck.
6. Materials: `mat.use_nodes = True`, then `node_tree.nodes.get("Principled BSDF")`; set `"Base Color"`, `"Metallic"`, `"Roughness"`.
7. Emission: use **`"Emission Color"` + `"Emission Strength"`** (4.x+/5.x) — the legacy `"Emission"` input is gone.
8. Apply scale before export/sim: select+activate the object, `bpy.ops.object.transform_apply(scale=True)`.
9. Add a **camera and set `scene.camera`** — a scene with no active camera renders nothing.
10. Add at least one light (data API), set its `energy`.
11. Pick the render engine with version-aware EEVEE id (`BLENDER_EEVEE` on ≤4.1 and 5.0+, `BLENDER_EEVEE_NEXT` on 4.2–4.5).
12. World/HDRI: prefer `download_polyhaven_asset asset_type:"hdris"` over hand-wiring an environment texture.
13. AI-generated or imported assets arrive **normalized/odd-scaled** — rescale, then apply scale.
14. `get_viewport_screenshot` and **Read the image** — confirm the scene looks right before declaring done.
