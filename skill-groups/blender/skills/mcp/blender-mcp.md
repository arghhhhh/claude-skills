---
version: 1.2.0
---

# Blender MCP Skill

Use this skill when the user wants to interact with Blender — create/modify 3D scenes, objects, materials, import assets, generate 3D models, or execute Python scripts in Blender.

## Prerequisites

- **Blender must be running** with the BlenderMCP addon enabled and connected
- Addon: Download `addon.py` from https://github.com/ahujasid/blender-mcp, install via Edit > Preferences > Add-ons
- In Blender's 3D View sidebar (N key) > "BlenderMCP" tab > click "Connect to Claude"
- Default connection: `localhost:9876`

## Not Installed?

- **Blender**: https://www.blender.org/download/
- **BlenderMCP addon**: https://github.com/ahujasid/blender-mcp — download `addon.py`, install via Edit > Preferences > Add-ons
- **MCPorter**: runs via `npx mcporter` (auto-fetched, no global install needed)

## Commands

### Scene Inspection

```bash
npx mcporter call blender.get_scene_info user_prompt:"describe the scene"
npx mcporter call blender.get_object_info object_name:"Cube" user_prompt:"inspect cube"
npx mcporter call blender.get_viewport_screenshot user_prompt:"show viewport"
```

### Execute Python Code in Blender

The most powerful tool — can do anything Blender's Python API supports.

```bash
npx mcporter call blender.execute_blender_code code:"import bpy; bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))" user_prompt:"add a cube"
```

**Break complex operations into smaller chunks.** Don't send massive scripts.

### Poly Haven Assets (HDRIs, Textures, Models)

```bash
npx mcporter call blender.get_polyhaven_status user_prompt:"check polyhaven"
npx mcporter call blender.get_polyhaven_categories asset_type:"hdris" user_prompt:"list hdri categories"
npx mcporter call blender.search_polyhaven_assets asset_type:"hdris" categories:"outdoor" user_prompt:"find outdoor hdris"
npx mcporter call blender.download_polyhaven_asset asset_id:"rural_asphalt_road" asset_type:"textures" resolution:"2k" user_prompt:"download texture"
npx mcporter call blender.set_texture object_name:"Plane" texture_id:"rural_asphalt_road" user_prompt:"apply texture"
```

`download_polyhaven_asset` also takes an optional `file_format` param (e.g. `hdr`/`exr` for HDRIs).

### Sketchfab Models

```bash
npx mcporter call blender.get_sketchfab_status user_prompt:"check sketchfab"
npx mcporter call blender.search_sketchfab_models query:"medieval chair" downloadable:true count:10 user_prompt:"find chairs"
npx mcporter call blender.get_sketchfab_model_preview uid:"abc123" user_prompt:"preview model"
npx mcporter call blender.download_sketchfab_model uid:"abc123" target_size:1.0 user_prompt:"download chair"
```

**Size reference:** Chair ~1.0m, Table ~0.75m, Car ~4.5m, Person ~1.7m

### Hyper3D Rodin (AI 3D Generation)

```bash
npx mcporter call blender.get_hyper3d_status user_prompt:"check hyper3d"
npx mcporter call blender.generate_hyper3d_model_via_text text_prompt:"a wooden treasure chest" user_prompt:"generate chest"
npx mcporter call blender.generate_hyper3d_model_via_images input_image_paths:'["/path/to/ref.png"]' user_prompt:"generate from image"
npx mcporter call blender.poll_rodin_job_status subscription_key:"key_here"
npx mcporter call blender.import_generated_asset name:"TreasureChest" task_uuid:"uuid_here"
```

**Mode-dependent params:** Hyper3D runs in MAIN_SITE or FAL.AI mode. In MAIN_SITE mode `poll_rodin_job_status`/`import_generated_asset` use `subscription_key`/`task_uuid`; in FAL.AI mode they use `request_id`. Use whichever `generate_*` returned. `generate_hyper3d_model_via_images` accepts `input_image_paths` (local) or `input_image_urls`.

### Hunyuan3D (AI 3D Generation)

```bash
npx mcporter call blender.get_hunyuan3d_status user_prompt:"check hunyuan3d"
npx mcporter call blender.generate_hunyuan3d_model text_prompt:"a red sports car" user_prompt:"generate car"
npx mcporter call blender.poll_hunyuan_job_status job_id:"job_xxx"
npx mcporter call blender.import_generated_asset_hunyuan name:"SportsCar" zip_file_url:"url_here"
```

## Common Workflows

### Create a Scene from Scratch
1. `get_scene_info` — understand current state
2. `execute_blender_code` — clear default objects, set up lighting/camera
3. Create objects or import from Poly Haven / Sketchfab
4. Apply materials/textures
5. `get_viewport_screenshot` — verify result

### AI-Generate a 3D Model
1. Check integration status (`get_hyper3d_status` or `get_hunyuan3d_status`)
2. Generate model via text or image prompt
3. Poll job status until complete
4. Import the generated asset
5. Rescale as needed via `execute_blender_code`

## Quirks & Gotchas

- **`user_prompt` parameter**: Most tools require it. Include a brief description.
- **Connection errors**: Ensure the Blender addon is running and connected.
- **Only one client at a time**: Don't run both Cursor and Claude Code with blender MCP simultaneously.
- **No background/headless mode**: As of blender-mcp 1.6.x the server fails fast under `blender -b` (commands would never execute). Run Blender with a GUI, or a virtual display (`xvfb-run -a blender`).
- **Keep addon & server in sync**: The Blender addon (`addon.py`, `bl_info` version) and the MCP server (`uvx blender-mcp`, currently 1.6.x) are versioned separately. Note the addon's `bl_info` may not bump even when content changes — re-install `addon.py` from the repo if tools misbehave.
- **Telemetry consent**: Recent versions add a telemetry consent flow (`get_telemetry_consent`); first run may prompt.
- **API keys persist**: Sketchfab/Hyper3D/Hunyuan3D keys are saved in addon preferences and survive Blender restarts. The Hyper3D free-trial key is `vibecoding`.
- **Verify the live tool list**: `npx mcporter list blender --all-parameters` prints the authoritative tool/param list from the running server — use it to reconcile this doc after a server update.
- **Generated models have normalized size**: Always rescale after AI generation.
- Use `execute_blender_code` as the escape hatch for anything specialized tools don't cover.
- Always `get_viewport_screenshot` after making visual changes to verify results.
