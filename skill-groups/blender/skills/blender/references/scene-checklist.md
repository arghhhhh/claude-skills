# Building a Scene — Checklist

Run through this when building a Blender scene from scratch via `blender.execute_blender_code`. Each item maps to a trap in `bpy-cookbook.md`.

1. `blender.get_objects_summary` first — know what's already there before you clear or add anything.
2. Write each step's Python to a file and run it with `code=@/path/step.py`; assign a dict to `result` to get data back.
3. `import bpy`; prefer the **data API** (`bpy.data` + `collection.objects.link`) over `bpy.ops` for context-sensitive work.
4. Clear defaults via the data API: `for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)` — not `bpy.ops.object.delete()`.
5. **Link every new object** to a collection (`bpy.context.collection.objects.link(obj)`) — unlinked objects never appear or render.
6. After creating objects, **read back `obj.name`** — Blender auto-suffixes collisions (`Cube.001`); don't assume your requested name stuck.
7. Materials: `mat.use_nodes = True`, then `node_tree.nodes.get("Principled BSDF")`; set `"Base Color"`, `"Metallic"`, `"Roughness"`.
8. Emission: use **`"Emission Color"` + `"Emission Strength"`** (4.x+/5.x) — the legacy `"Emission"` input is gone.
9. Apply scale before export/sim: select+activate the object, `bpy.ops.object.transform_apply(scale=True)`.
10. Add a **camera and set `scene.camera`** — a scene with no active camera renders nothing.
11. Add at least one light (data API), set its `energy`.
12. Pick the render engine with version-aware EEVEE id (`BLENDER_EEVEE` on ≤4.1 and 5.0+, `BLENDER_EEVEE_NEXT` on 4.2–4.5).
13. World/HDRI: prefer `blender-assets.download_polyhaven_asset asset_type:"hdris"` over hand-wiring an environment texture.
14. Props: `blender-assets` Sketchfab / Poly Pizza (`normalize_size:true target_size:<m>`) — AI-generated or imported assets arrive **normalized/odd-scaled**; rescale, then apply scale.
15. Unsure of an API? `blender.search_api_docs query:"…"` before guessing.
16. `blender.get_screenshot_of_area_as_image area_ui_type:VIEW_3D --save-images <dir>` and **Read the PNG** — confirm the scene looks right before declaring done.
