---
version: 1.1.0
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
npx mcporter call blender.search_polyhaven_assets asset_type:"hdris" categories:"outdoor" user_prompt:"find outdoor hdris"
npx mcporter call blender.download_polyhaven_asset asset_id:"rural_asphalt_road" asset_type:"textures" resolution:"2k" user_prompt:"download texture"
npx mcporter call blender.set_texture object_name:"Plane" texture_id:"rural_asphalt_road" user_prompt:"apply texture"
```

### Sketchfab Models

```bash
npx mcporter call blender.search_sketchfab_models query:"medieval chair" downloadable:true count:10 user_prompt:"find chairs"
npx mcporter call blender.get_sketchfab_model_preview uid:"abc123" user_prompt:"preview model"
npx mcporter call blender.download_sketchfab_model uid:"abc123" target_size:1.0 user_prompt:"download chair"
```

**Size reference:** Chair ~1.0m, Table ~0.75m, Car ~4.5m, Person ~1.7m

### Hyper3D Rodin (AI 3D Generation)

```bash
npx mcporter call blender.get_hyper3d_status user_prompt:"check hyper3d"
npx mcporter call blender.generate_hyper3d_model_via_text text_prompt:"a wooden treasure chest" user_prompt:"generate chest"
npx mcporter call blender.poll_rodin_job_status subscription_key:"key_here"
npx mcporter call blender.import_generated_asset name:"TreasureChest" task_uuid:"uuid_here"
```

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
- **Generated models have normalized size**: Always rescale after AI generation.
- Use `execute_blender_code` as the escape hatch for anything specialized tools don't cover.
- Always `get_viewport_screenshot` after making visual changes to verify results.
