---
version: 1.0.0
name: blender-assets
description: Bring content into a running Blender session via the ahujasid "MCP for Blender" server (mcporter `blender-assets`) — Poly Haven HDRIs/textures/models, Sketchfab and Poly Pizza model import, Hyper3D Rodin and Hunyuan3D AI generation. Scene inspection, Python, screenshots, renders and docs live in the sibling `blender` skill.
---

# Blender Assets Skill (ahujasid MCP, via MCPorter)

Use this skill to **import assets and AI-generate models** into a live Blender session through the ahujasid "MCP for Blender" server, called as `npx mcporter call blender-assets.<tool> [params]`.

For **inspecting the scene, running Python, screenshots, renders, or bpy docs** — use the **blender** skill instead (`blender.<tool>`): its versions of those tools are structured, uncapped and telemetry-free. This server duplicates a few of them (`get_scene_info`, `get_object_info`, `get_viewport_screenshot`, `execute_blender_code`) — only reach for those if `blender.*` is down.

## Setup

- **Transport**: `npx mcporter call blender-assets.<tool>` → `uvx blender-mcp` (PyPI, v1.9.x) with env `BLENDER_PORT=9878` → legacy add-on socket on **localhost:9878**.
- **Requires**: Blender with the **Interface: MCP for Blender** add-on (`blender_mcp.py`) enabled, port set to **9878**, integrations ticked, and **Start MCP Server** clicked — all in the 3D View sidebar (`N` → "MCP for Blender" tab). The port is a scene property: save the startup file or re-set it after reopening Blender.
- **Port map on this machine**: 9876 official Blender (`blender` skill) · 9877 Houdini-MCP · 9878 this add-on. Both Blender add-ons default to 9876 — left there, this one collides with the official add-on and every call **hangs** (server connects, handshake never answers).
- **`user_prompt`** — required on `get_scene_info`, accepted by most tools (telemetry). Pass a short description.
- **API keys** persist in add-on preferences or env: `BLENDERMCP_SKETCHFAB_API_KEY`, `BLENDERMCP_POLYPIZZA_API_KEY`, `BLENDERMCP_HYPER3D_API_KEY`, `BLENDERMCP_HUNYUAN3D_SECRET_ID` / `_SECRET_KEY`.

## Not Installed?

- **Add-on**: `uvx blender-mcp install-addon` (copies `blender_mcp.py` into the addons folder, keeps a `.bak`; `uvx blender-mcp addon-paths` lists targets). Then Preferences → Add-ons → enable **Interface: MCP for Blender**. Source: https://github.com/ahujasid/blender-mcp
- **MCPorter**: `npx mcporter` (auto-fetched) · **uv**: https://docs.astral.sh/uv/

## Always Start Here

```bash
npx mcporter call blender-assets.get_addon_status user_prompt:"check"     # reachable on 9878? protocol match? telemetry on?
npx mcporter call blender-assets.get_polyhaven_status user_prompt:"check"  # or get_sketchfab_status / get_polypizza_status / get_hyper3d_status / get_hunyuan3d_status
```

If `get_addon_status` hangs, the add-on server isn't started or is on the wrong port — see **Gotchas**.

## mcporter mechanics

- **Images** (`get_sketchfab_model_preview`, `get_viewport_screenshot`) return image blocks; add `--save-images <dir>` and Read the saved PNG.
- **Lists** — `bbox_condition:[1,1,2]`, `input_image_paths:["C:/a.png"]`. Use `--args '{...}'` when quoting gets ugly.
- **Scale** — imported and generated models arrive normalized or at arbitrary scale. Give a real-world `target_size` (largest dimension, metres) and apply scale afterwards via `blender.execute_blender_code`.

**Size reference (`target_size`, metres):** chair 1.0 · table 0.75 · car 4.5 · person 1.7 · cup/phone 0.1–0.3.

## Tools (28)

### Server & add-on

| Tool | Purpose |
|---|---|
| `get_addon_status user_prompt:<p>` | Add-on reachability, `up_to_date`, protocol version, `telemetry_consent`, update command. |
| `disable_telemetry user_prompt:<p>` | Turns the add-on's collection of prompts/code/screenshots/scene data **off** (on by default; only re-enabled in Blender prefs). |
| `record_trajectory_feedback feedback:<accept\|reject\|undo\|correction> [correction_text] [step_index] [user_prompt]` | Telemetry feedback row — not needed for normal work. |

### Duplicates of `blender.*` (fallback only)

| Tool | Prefer instead |
|---|---|
| `get_scene_info user_prompt:<p>` — flat, row-capped object list | `blender.get_objects_summary` |
| `get_object_info object_name:<n> user_prompt:<p>` | `blender.get_object_detail_summary` |
| `get_viewport_screenshot [max_size:800] user_prompt:<p>` | `blender.get_screenshot_of_area_as_image area_ui_type:VIEW_3D` |
| `execute_blender_code code:<py> user_prompt:<p>` — returns **stdout only** as a string | `blender.execute_blender_code` (structured `result` + tracebacks) |

### Poly Haven (HDRIs, textures, models — no key)

| Tool | Purpose |
|---|---|
| `get_polyhaven_status user_prompt:<p>` | Integration enabled? |
| `get_polyhaven_categories asset_type:<hdris\|textures\|models\|all> user_prompt:<p>` | Categories |
| `search_polyhaven_assets asset_type:<t> [categories:<a,b>] user_prompt:<p>` | Search |
| `download_polyhaven_asset asset_id:<id> asset_type:<t> [resolution:1k\|2k\|4k] [file_format:<fmt>] user_prompt:<p>` | Download + import. HDRIs are wired into the World for you. `file_format`: `hdr`/`exr` HDRIs, `jpg`/`png` textures, `gltf`/`fbx` models. |
| `set_texture object_name:<n> texture_id:<id> user_prompt:<p>` | Apply a previously downloaded texture |

### Sketchfab (free API key)

| Tool | Purpose |
|---|---|
| `get_sketchfab_status user_prompt:<p>` | Enabled + key present? |
| `search_sketchfab_models query:<q> [categories:<c>] [count:20] [downloadable:true] user_prompt:<p>` | Search |
| `get_sketchfab_model_preview uid:<uid> user_prompt:<p>` | Thumbnail (image → `--save-images`) |
| `download_sketchfab_model uid:<uid> target_size:<m> user_prompt:<p>` | Import scaled so the largest dimension = `target_size` metres. Returns object names, dimensions, bbox. |

### Poly Pizza (free API key — ~10.6k low-poly CC models)

| Tool | Purpose |
|---|---|
| `get_polypizza_status user_prompt:<p>` | Enabled + key present? |
| `search_polypizza_models [query:<q>] [category:<name>] [licence:CC0\|CC-BY] [animated:true] [limit:20] user_prompt:<p>` | Search; rows include licence + triangle count. Categories: Animals, Furniture & Decor, Transport, Nature, Buildings, People & Characters, Food & Drink, Weapons, Clutter, Objects, Scenes & Levels, Other. API caps `limit` at 32. |
| `download_polypizza_model model_id:<id> normalize_size:true target_size:<m> user_prompt:<p>` | Import; writes `polypizza_attribution` / `polypizza_id` / `polypizza_licence` custom props on the root object. **Always pass `normalize_size:true`** — archive scales are arbitrary. |

Filter `licence:CC0` to skip attribution (~69% of models are CC-BY). The CDN sits behind Cloudflare bot protection and blocks datacenter/VPN IPs — retry from a residential connection or import the `.glb` by hand.

### Hyper3D Rodin (AI generation)

| Tool | Purpose |
|---|---|
| `get_hyper3d_status user_prompt:<p>` | Enabled + mode (MAIN_SITE / FAL.AI) |
| `generate_hyper3d_model_via_text text_prompt:<t> [bbox_condition:[x,y,z]] user_prompt:<p>` | From text (English). `bbox_condition` = length:width:height ratio. |
| `generate_hyper3d_model_via_images input_image_paths:[..] \| input_image_urls:[..] [bbox_condition] user_prompt:<p>` | From images — absolute `paths` for MAIN_SITE, `urls` for FAL.AI |
| `poll_rodin_job_status subscription_key:<k> \| request_id:<id>` | Poll until all `Done` (MAIN_SITE) / `COMPLETED` (FAL.AI) |
| `import_generated_asset name:<n> task_uuid:<u> \| request_id:<id>` | Import |

MAIN_SITE uses `subscription_key` + `task_uuid`; FAL.AI uses `request_id` — use whatever `generate_*` returned. Free-trial key: `vibecoding`. Generated models have built-in materials and normalized size.

### Hunyuan3D (AI generation — Tencent Cloud SecretId/Key, AI3D API 3.0)

| Tool | Purpose |
|---|---|
| `get_hunyuan3d_status user_prompt:<p>` | Enabled |
| `generate_hunyuan3d_model [text_prompt:<t>] [input_image_url:<u>] user_prompt:<p>` | Text (EN/ZH) and/or image. Returns `job_id`. |
| `poll_hunyuan_job_status job_id:<id>` | `RUN` → `DONE`; DONE includes `ResultFile3Ds` URLs |
| `import_generated_asset_hunyuan name:<n> zip_file_url:<url>` | Prefer a `.glb` URL; `.zip`/`.obj` also work |

## Common Workflows

**HDRI + textures for a scene** — `get_polyhaven_status` → `search_polyhaven_assets asset_type:hdris categories:"outdoor"` → `download_polyhaven_asset asset_id:<id> asset_type:hdris resolution:2k` → `search_polyhaven_assets asset_type:textures` → `download_polyhaven_asset … asset_type:textures` → `set_texture object_name:Floor texture_id:<id>` → `blender.get_screenshot_of_area_as_image area_ui_type:VIEW_3D --save-images <dir>`.

**Prop from a library** — Poly Pizza for stylised/low-poly (`search_polypizza_models query:"chair" licence:CC0` → `download_polypizza_model … normalize_size:true target_size:1.0`); Sketchfab for realistic (`search_sketchfab_models` → `get_sketchfab_model_preview` → Read → `download_sketchfab_model uid target_size`). Then `blender.get_objects_summary` to read back the real object names and `blender.execute_blender_code` to place / apply scale.

**AI-generate a model** — `get_hyper3d_status` or `get_hunyuan3d_status` → `generate_*` → `poll_*` until done → `import_*` → rescale + apply scale via `blender.execute_blender_code` → screenshot.

## Gotchas (MCP / connection level)

- **Every call hangs, but `blender.*` works** → this add-on is on 9876 (colliding with the official add-on) or its server isn't started. Sidebar → port **9878** → **Start MCP Server**. `netstat -ano | findstr :987` should show 9876 and 9878 owned by `blender.exe`.
- **First call after a Blender restart stalls** occasionally — retry once (acknowledged upstream).
- **Package-name collision** — `uvx blender-mcp` is this (PyPI) server; the official one shares the name but installs only from git. Don't mix them up in configs.
- **Add-on ≠ server version** — `get_addon_status` reports `up_to_date`; if false run `uvx blender-mcp install-addon`, disable/enable the add-on in Blender, Start MCP Server again.
- **Telemetry is on by default** and includes prompts, code and screenshots — call `disable_telemetry` (or untick consent in add-on prefs) if that matters.
- **Safe mode** — env `BLENDER_MCP_SAFE_MODE=1` on the server validates scripts and blocks file I/O / subprocess / network / persistent code. Off in this setup.
- **`get_scene_info` truncates** the object list (row cap) — use `blender.get_objects_summary`.
- **No background/headless mode** — the server fails fast under `blender -b`.
- **One client at a time** — don't point Cursor and Claude Code at this add-on simultaneously.
- **Reconcile this doc after a server update** — `npx mcporter list blender-assets --all-parameters` is the authoritative tool/param list; `install.sh --check-drift --skills blender` flags doc drift.
