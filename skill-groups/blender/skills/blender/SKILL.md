---
version: 2.0.0
name: blender
description: Drive a running Blender session via the BlenderMCP server (mcporter) — scene inspection, bpy Python execution, Poly Haven / Sketchfab asset import, Hyper3D & Hunyuan3D AI generation, and viewport screenshots.
---

# Blender Skill (via MCP)

Use this skill to inspect and modify a live Blender session through the BlenderMCP server, called over `npx mcporter call blender.<tool>`.

## Setup

- **Transport**: `npx mcporter call blender.<tool> [params]` (MCPorter → BlenderMCP server `uvx blender-mcp` → Blender addon on `localhost:9876`)
- **Requires**: Blender running with the BlenderMCP addon enabled and connected — in the 3D View sidebar (`N`) → "BlenderMCP" tab → **Connect to Claude**
- **Most tools require a `user_prompt` param** — a short description of why you're calling it (used for telemetry). Always include it.

## Not Installed?

- **Blender**: https://www.blender.org/download/
- **BlenderMCP addon**: https://github.com/ahujasid/blender-mcp — download `addon.py`, install via Edit → Preferences → Add-ons, then Connect to Claude
- **MCPorter**: runs via `npx mcporter` (auto-fetched, no global install)
- **Server**: `uvx blender-mcp` (auto-fetched by mcporter; no pin)

## Always Start Here

```bash
npx mcporter call blender.get_scene_info user_prompt:"survey scene"        # objects, materials, current state
npx mcporter call blender.get_viewport_screenshot user_prompt:"see viewport"
```

If calls fail: Blender isn't running, the addon isn't connected ("Connect to Claude"), or another client already holds the connection (only one at a time). See **Connection** in the agent or the gotchas below.

## Scene Inspection & Python

All commands: `npx mcporter call blender.<tool> [params]` (omit the prefix below for brevity).

| Command | Purpose |
|---|---|
| `get_scene_info user_prompt:<p>` | Objects, materials, scene summary |
| `get_object_info object_name:<n> user_prompt:<p>` | Detail on one object |
| `get_viewport_screenshot max_size:<px> user_prompt:<p>` | Capture viewport (default max 800px) |
| `execute_blender_code code:<py> user_prompt:<p>` | Run arbitrary `bpy` Python — the escape hatch for anything below |

`execute_blender_code` returns captured stdout, so `print(...)` results come back to you. **Break complex work into small chunks** rather than one massive script. For non-obvious `bpy` patterns and silent-failure traps, read `references/bpy-cookbook.md` **before** writing scripts.

## Poly Haven (HDRIs, Textures, Models)

| Command | Purpose |
|---|---|
| `get_polyhaven_status user_prompt:<p>` | Check the integration is enabled |
| `get_polyhaven_categories asset_type:<hdris\|textures\|models> user_prompt:<p>` | List categories |
| `search_polyhaven_assets asset_type:<t> categories:<c> user_prompt:<p>` | Search assets |
| `download_polyhaven_asset asset_id:<id> asset_type:<t> resolution:<1k\|2k\|4k> [file_format:<fmt>] user_prompt:<p>` | Download + import |
| `set_texture object_name:<n> texture_id:<id> user_prompt:<p>` | Apply a downloaded texture |

`file_format` is optional (e.g. `hdr`/`exr` for HDRIs; `jpg`/`png` for textures; `gltf`/`fbx` for models).

## Sketchfab Models

| Command | Purpose |
|---|---|
| `get_sketchfab_status user_prompt:<p>` | Check the integration is enabled (needs API key) |
| `search_sketchfab_models query:<q> [categories:<c>] [count:<n>] [downloadable:true] user_prompt:<p>` | Search |
| `get_sketchfab_model_preview uid:<uid> user_prompt:<p>` | Preview thumbnails |
| `download_sketchfab_model uid:<uid> target_size:<m> user_prompt:<p>` | Download + import at a target size |

**Size reference (target_size, metres):** Chair ~1.0, Table ~0.75, Car ~4.5, Person ~1.7.

## Hyper3D Rodin (AI 3D generation)

| Command | Purpose |
|---|---|
| `get_hyper3d_status user_prompt:<p>` | Check enabled + which mode (MAIN_SITE / FAL.AI) |
| `generate_hyper3d_model_via_text text_prompt:<t> [bbox_condition:<[x,y,z]>] user_prompt:<p>` | Generate from text |
| `generate_hyper3d_model_via_images input_image_paths:<[paths]> \| input_image_urls:<[urls]> user_prompt:<p>` | Generate from images |
| `poll_rodin_job_status subscription_key:<k> \| request_id:<id>` | Poll until complete |
| `import_generated_asset name:<n> task_uuid:<u> \| request_id:<id>` | Import the finished model |

**Mode-dependent params:** MAIN_SITE uses `subscription_key`/`task_uuid`; FAL.AI uses `request_id`. Use whichever the `generate_*` call returned. Free-trial key is `vibecoding`.

## Hunyuan3D (AI 3D generation)

| Command | Purpose |
|---|---|
| `get_hunyuan3d_status user_prompt:<p>` | Check enabled |
| `generate_hunyuan3d_model text_prompt:<t> \| input_image_url:<u> user_prompt:<p>` | Generate |
| `poll_hunyuan_job_status job_id:<id>` | Poll until complete |
| `import_generated_asset_hunyuan name:<n> zip_file_url:<url>` | Import the finished model |

## Common Workflows

**Build a scene from scratch** — `get_scene_info` → `execute_blender_code` (clear defaults, add objects/lights/camera via the data API) → import assets (Poly Haven / Sketchfab) → materials → `get_viewport_screenshot`. Follow `references/scene-checklist.md` step by step.

**AI-generate a model** — status check → `generate_*` (text or image) → `poll_*` until done → `import_*` → rescale (generated models arrive normalized; always rescale via `execute_blender_code`).

**Always `get_viewport_screenshot` after a visual change** and Read the image — it's the only way to know a change actually looks right.

## Quirks & Gotchas (MCP / connection level)

Scripting/`bpy` traps live in `references/bpy-cookbook.md`. These are about the MCP layer itself:

- **`user_prompt` is required** on most tools — include a short description.
- **One client at a time** — don't run Cursor and Claude Code against the BlenderMCP server simultaneously; the second connection fails.
- **No background/headless mode** — as of blender-mcp 1.6.x the server fails fast under `blender -b`. Run with a GUI, or a virtual display (`xvfb-run -a blender`).
- **Addon ≠ server version** — the addon (`addon.py`, `bl_info`) and server (`uvx blender-mcp`) version independently; `bl_info` may not bump even when `addon.py` changes. Re-install `addon.py` from the repo if tools misbehave after a server bump.
- **Telemetry consent** — first run may prompt (`get_telemetry_consent`).
- **API keys persist** — Sketchfab/Hyper3D/Hunyuan3D keys are saved in addon preferences across restarts.
- **`execute_blender_code` captures stdout** — return data with `print(...)`. Multi-line scripts via mcporter on the CLI are awkward to quote; hex-encode and decode in one line when needed (`exec(__import__('binascii').unhexlify('<hex>').decode())`).
- **Reconcile this doc after a server update** — `npx mcporter list blender --all-parameters` is the authoritative tool/param list; `install.sh --check-drift --skills blender` flags doc drift.

## References — read these for deeper topics

- **`references/bpy-cookbook.md`** — read **before writing any `execute_blender_code` Python**. Data-API vs `bpy.ops`, collection linking, material `node_tree` setup (with verified Blender 5.x input names), render-engine ids per version, transform-apply, naming collisions, world/HDRI setup.
- **`references/scene-checklist.md`** — an end-to-end checklist for building a scene from scratch, each item mapping to a trap in the cookbook.
