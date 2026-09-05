---
version: 3.0.0
name: blender
description: Drive a running Blender session via two MCP servers over mcporter — `blender` (official Blender Lab server: scene/file introspection, bpy + manual docs search, area/window screenshots, renders, headless .blend analysis) and `blender-assets` (ahujasid "MCP for Blender": Poly Haven / Sketchfab / Poly Pizza import, Hyper3D & Hunyuan3D AI generation).
---

# Blender Skill (via MCP)

Two MCP servers talk to the same running Blender, each through its own add-on and TCP port. Call either over `npx mcporter call <server>.<tool> [params]`.

| mcporter server | Upstream | Add-on in Blender | Port | Use it for |
|---|---|---|---|---|
| **`blender`** | Official — Blender Lab `lab/blender_mcp` (v1.0.0, GPL, Blender **5.1+**) | Extension **"MCP"** from the `lab.blender.org` extensions repo | **9876** | Understanding a scene/file, bpy + manual docs, screenshots of any editor, renders, headless `.blend` analysis, running Python |
| **`blender-assets`** | ahujasid `blender-mcp` (PyPI, v1.9.x, "MCP for Blender") | Legacy add-on `blender_mcp.py` ("Interface: MCP for Blender") | **9878** | Getting content in: Poly Haven, Sketchfab, Poly Pizza, Hyper3D Rodin, Hunyuan3D |

Both expose `execute_blender_code`. Prefer **`blender`** for it — structured `result` dict + captured stdout + full traceback on error. Use `blender-assets` only for its asset/AI tools.

## Setup

- **Transport**: `npx mcporter call <server>.<tool>` → MCP server process (`uvx`) → add-on socket in Blender.
  - `blender` = `uvx --with "mcp<2" --from "git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp" blender-mcp` (the `mcp<2` pin is required — the package still imports the v1 FastMCP API).
  - `blender-assets` = `uvx blender-mcp` with env `BLENDER_PORT=9878`.
- **Blender side**: both add-ons must be enabled and their servers running.
  - Official: Preferences → Get Extensions → add repo `https://lab.blender.org/` → install **MCP** → enable. Its prefs panel has Host/Port (**9876**), Auto Start (on by default), and Start/Stop buttons. Nothing to click in the viewport.
  - Legacy: `uvx blender-mcp install-addon` (copies `blender_mcp.py` into the addons folder, keeps a `.bak`), enable **Interface: MCP for Blender**, set port to **9878** in the sidebar (`N` → "MCP for Blender" tab), tick the integrations you want, click **Start MCP Server**.
- **Port map on this machine**: 9876 official Blender · 9877 Houdini-MCP · 9878 legacy Blender. Both Blender add-ons default to 9876 — if the legacy one is left on 9876 the two collide and `blender-assets` calls **hang** (server connects, handshake never answers).
- **`user_prompt`** — required on `blender-assets.get_scene_info`, accepted by most other `blender-assets` tools (telemetry). Official tools have no such param.

## Not Installed?

- **Blender 5.1+**: https://www.blender.org/download/
- **Official add-on**: extensions repo `https://lab.blender.org/` (docs: https://www.blender.org/lab/mcp-server/ · source: https://projects.blender.org/lab/blender_mcp)
- **Legacy add-on**: `uvx blender-mcp install-addon` (https://github.com/ahujasid/blender-mcp)
- **MCPorter**: `npx mcporter` (auto-fetched) · **uv**: https://docs.astral.sh/uv/

## Always Start Here

```bash
npx mcporter call blender.get_objects_summary                                   # collection tree + objects, active object, mode, camera
npx mcporter call blender.get_screenshot_of_area_as_image area_ui_type:VIEW_3D --save-images <dir>   # then Read the saved PNG
```

Before an asset job: `npx mcporter call blender-assets.get_addon_status user_prompt:"check"` — confirms the legacy add-on is reachable on 9878 and its protocol matches the server.

If a call fails see **Gotchas** — it's almost always Blender not running, an add-on server not started, or the port map above.

## Passing Python and getting images back (mcporter mechanics)

- **Code from a file** — `code=@/path/script.py` reads the argument verbatim. Use this for anything longer than one line; inline `code:"..."` breaks on `:`, `=`, spaces and `+/`. (Hex-encoding still works as a fallback: `exec(__import__('binascii').unhexlify('<hex>').decode())`.)
- **Images** — screenshot/preview tools return image blocks; add `--save-images <dir>` and mcporter writes `mcp-image-<ts>-1.png` there. Read that file. Without the flag you only see `{type:'image'}`.
- **JSON payloads** — `--args '{"k":"v"}'` when quoting gets ugly.
- **Renders** write into Blender's temp dir, not your path: `render_*_to_path` uses only the *basename* of `output_path` and saves under `<bpy.app.tempdir>/blender_mcp/`. Read `result.filepath` from the response.

## `blender` — official server (26 tools)

`RO` = read-only annotated. Tools ending `_for_cli` open a `.blend` in `blender --background` (Blender need not be running; needs `blender` on PATH or `BLENDER_PATH`).

| Tool | Purpose |
|---|---|
| `execute_blender_code code:<py>` | Run Python with `bpy`. Assign a JSON-serialisable dict to **`result`** to return data; stdout is captured as `stdout`; exceptions come back as `status:"error"` + traceback. |
| `execute_blender_code_for_cli blend_file:<path> code:<py>` | Same, headless against a file on disk. |
| `get_objects_summary` RO | Collection hierarchy with objects (type, parent, data name, selected, visibility), active object, mode, camera. **Start here.** |
| `get_object_detail_summary name:<obj>` RO | Transforms, parent/children, modifiers, constraints, materials, visibility, collections. |
| `get_blendfile_summary_datablocks` RO | Data-block counts, active workspace, render engine. |
| `get_blendfile_summary_missing_files` RO | Missing external refs (images, libraries, fonts, sounds, clips, caches). |
| `get_blendfile_summary_of_linked_libraries` RO | Tree of direct + indirect linked libraries. |
| `get_blendfile_summary_path_info` RO | File path, saved/dirty, age, backups. Fast. |
| `get_blendfile_summary_usage_guess` RO | Scores 0–100 per use-case (modeling, animation, geometry nodes, VSE, …). |
| `get_blendfile_summary_datablocks_for_cli` · `get_blendfile_summary_missing_files_for_cli` · `get_blendfile_summary_of_linked_libraries_for_cli` · `get_blendfile_summary_path_info_for_cli` · `get_blendfile_summary_usage_guess_for_cli` — all `blend_file:<path>` RO | Headless twins of the five summaries above; work on a closed file. |
| `get_screenshot_of_area_as_image area_ui_type:<T> [size_limit_in_bytes]` RO | PNG of one editor. `T` ∈ `VIEW_3D IMAGE_EDITOR UV ShaderNodeTree CompositorNodeTree GeometryNodeTree TextureNodeTree SEQUENCE_EDITOR CLIP_EDITOR DOPESHEET_EDITOR GRAPH_EDITOR NLA_EDITOR TEXT_EDITOR CONSOLE INFO TOPBAR STATUSBAR OUTLINER PROPERTIES FILE_BROWSER SPREADSHEET PREFERENCES`. |
| `get_screenshot_of_window_as_image [size_limit_in_bytes]` RO | PNG of the whole Blender window. |
| `get_screenshot_of_window_as_json` RO | Window/area/region layout with pixel rects, active object, selection — use to find an editor before screenshotting it. |
| `jump_to_tab_by_name name:<ws>` | Switch workspace tab. |
| `jump_to_tab_by_space_type space_type:<T> [allow_edits:true]` | Switch to a workspace whose main area is `T`; `allow_edits` duplicates the current one if none exists. |
| `jump_to_view3d_object_by_name name:<obj> [allow_edits:true]` | Frame an object in the 3D view; `allow_edits` may unhide it / enable its collections. |
| `jump_to_view3d_object_data_by_name name:<data> [allow_edits:true]` | Same, by data-block name. |
| `render_thumbnail_to_path output_path:<name.png>` | Quick low-quality render (temporarily overrides settings). |
| `render_viewport_to_path output_path:<name.png>` RO | Full render with current settings; runs deferred (`INVOKE_DEFAULT`) so the call blocks until done. |
| `get_python_api_docs identifier:<bpy.x.y>` RO | Bundled bpy reference for one identifier. `*` lists top-level modules; `bpy.types.*` lists children. Response `kind` ∈ exact/namespace/definition/partial/suggestions/missing. |
| `search_api_docs query:<words> [max_results:20] [context:0] [index]` RO | Full-text search over the bundled bpy API RST. All tokens must match; stop-words dropped; no regex. `index:<n>` re-fetches one hit widened to its section. |
| `search_manual_docs query:<words> [max_results] [context] [index]` RO | Same over the bundled Blender user manual. |

**Use the docs tools before guessing an API** — `search_api_docs query:"shade_smooth"` returns the operator signature for the running Blender version, no web needed.

## `blender-assets` — ahujasid server (28 tools)

| Tool | Purpose |
|---|---|
| `get_addon_status user_prompt:<p>` | Add-on reachability, protocol match, `telemetry_consent`, update command. |
| `get_scene_info user_prompt:<p>` | Flat object list (name/type/location, capped) + material count. Prefer `blender.get_objects_summary`. |
| `get_object_info object_name:<n> user_prompt:<p>` | One object. Prefer `blender.get_object_detail_summary`. |
| `get_viewport_screenshot [max_size:800] user_prompt:<p>` | 3D viewport PNG (rendered offscreen). Prefer `blender.get_screenshot_of_area_as_image`. |
| `execute_blender_code code:<py> user_prompt:<p>` | Returns **stdout only** as a string (no `result` dict). Prefer `blender.execute_blender_code`. |
| `disable_telemetry user_prompt:<p>` | Turns the add-on's data collection off (on by default; only re-enabled in Blender prefs). |
| `record_trajectory_feedback feedback:<accept\|reject\|undo\|correction> [correction_text] [step_index]` | Telemetry feedback row — not needed for normal work. |

### Poly Haven (HDRIs, textures, models — no key)

| Tool | Purpose |
|---|---|
| `get_polyhaven_status user_prompt:<p>` | Integration enabled? |
| `get_polyhaven_categories asset_type:<hdris\|textures\|models\|all> user_prompt:<p>` | Categories |
| `search_polyhaven_assets asset_type:<t> [categories:<a,b>] user_prompt:<p>` | Search |
| `download_polyhaven_asset asset_id:<id> asset_type:<t> [resolution:1k\|2k\|4k] [file_format:<fmt>] user_prompt:<p>` | Download + import (HDRIs are wired into the World) |
| `set_texture object_name:<n> texture_id:<id> user_prompt:<p>` | Apply a downloaded texture |

### Sketchfab (free API key)

| Tool | Purpose |
|---|---|
| `get_sketchfab_status user_prompt:<p>` | Enabled + key present? |
| `search_sketchfab_models query:<q> [categories:<c>] [count:20] [downloadable:true] user_prompt:<p>` | Search |
| `get_sketchfab_model_preview uid:<uid> user_prompt:<p>` | Thumbnail (image → use `--save-images`) |
| `download_sketchfab_model uid:<uid> target_size:<m> user_prompt:<p>` | Import scaled so the largest dimension = `target_size` metres |

### Poly Pizza (free API key — ~10.6k low-poly CC models)

| Tool | Purpose |
|---|---|
| `get_polypizza_status user_prompt:<p>` | Enabled + key present? |
| `search_polypizza_models [query:<q>] [category:<name>] [licence:CC0\|CC-BY] [animated:true] [limit:20] user_prompt:<p>` | Search; rows include licence + triangle count. Categories: Animals, Furniture & Decor, Transport, Nature, Buildings, People & Characters, Food & Drink, Weapons, Clutter, Objects, Scenes & Levels, Other |
| `download_polypizza_model model_id:<id> normalize_size:true target_size:<m> user_prompt:<p>` | Import; writes `polypizza_attribution`/`_id`/`_licence` custom props on the root object. **Always pass `normalize_size:true`** — archive scales are arbitrary. |

Filter `licence:CC0` to skip attribution. The CDN blocks datacenter/VPN IPs (Cloudflare challenge) — retry from a residential connection or import the `.glb` by hand.

**Size reference (`target_size`, metres):** chair 1.0 · table 0.75 · car 4.5 · person 1.7 · cup/phone 0.1–0.3.

### Hyper3D Rodin (AI generation)

| Tool | Purpose |
|---|---|
| `get_hyper3d_status user_prompt:<p>` | Enabled + mode (MAIN_SITE / FAL.AI) |
| `generate_hyper3d_model_via_text text_prompt:<t> [bbox_condition:[x,y,z]] user_prompt:<p>` | From text (English) |
| `generate_hyper3d_model_via_images input_image_paths:[..] \| input_image_urls:[..] [bbox_condition] user_prompt:<p>` | From images — `paths` for MAIN_SITE, `urls` for FAL.AI |
| `poll_rodin_job_status subscription_key:<k> \| request_id:<id>` | Poll until Done / COMPLETED |
| `import_generated_asset name:<n> task_uuid:<u> \| request_id:<id>` | Import |

MAIN_SITE uses `subscription_key`/`task_uuid`; FAL.AI uses `request_id` — use whatever `generate_*` returned. Free-trial key: `vibecoding`.

### Hunyuan3D (AI generation — Tencent Cloud SecretId/Key)

| Tool | Purpose |
|---|---|
| `get_hunyuan3d_status user_prompt:<p>` | Enabled |
| `generate_hunyuan3d_model [text_prompt:<t>] [input_image_url:<u>] user_prompt:<p>` | Returns `job_id` |
| `poll_hunyuan_job_status job_id:<id>` | `RUN` → `DONE`; DONE includes `ResultFile3Ds` URLs |
| `import_generated_asset_hunyuan name:<n> zip_file_url:<url>` | Prefer a `.glb` URL; `.zip/.obj` also work |

## Common Workflows

**Understand an unfamiliar file** — `blender.get_blendfile_summary_path_info` → `get_blendfile_summary_usage_guess` → `get_objects_summary` → `get_object_detail_summary` on the interesting ones → `get_blendfile_summary_missing_files` if textures look pink. Or do it all headless with the `_for_cli` twins on a path.

**Build a scene from scratch** — `blender.get_objects_summary` → write bpy to a file, `blender.execute_blender_code code=@file` in small chunks (data API; see cookbook) → `blender-assets.download_polyhaven_asset` for HDRI/textures, Sketchfab/Poly Pizza for props → materials → `blender.get_screenshot_of_area_as_image area_ui_type:VIEW_3D --save-images <dir>` → Read. Follow `references/scene-checklist.md`.

**AI-generate a model** — `blender-assets.get_*_status` → `generate_*` → `poll_*` until done → `import_*` → rescale + apply scale via `blender.execute_blender_code` (generated models arrive normalized).

**Look up an API you're unsure of** — `blender.search_api_docs query:"…"` or `get_python_api_docs identifier:bpy.types.X` before writing code; `search_manual_docs` for how a feature is meant to be used.

**Always screenshot after a visual change** and Read the image — it's the only way to know it actually looks right.

## Gotchas (MCP / connection level)

Scripting/`bpy` traps live in `references/bpy-cookbook.md`. These are about the servers themselves:

- **Hang on `blender-assets`, official works** → legacy add-on is on 9876 (colliding with the official add-on) or its server isn't started. Fix the port to 9878 in the sidebar panel and click Start MCP Server. `netstat -ano | findstr :987` should show 9876 and 9878 owned by `blender.exe`.
- **Hang on `blender`, assets works** → official add-on not enabled or Auto Start off. Preferences → Add-ons → MCP → Start.
- **`ModuleNotFoundError: mcp.server.fastmcp`** launching the official server → the `--with "mcp<2"` pin is missing from the mcporter/Claude config.
- **Both packages are called `blender-mcp`** and both entry points are `blender-mcp`. `uvx blender-mcp` is always the PyPI (ahujasid) one; the official one only installs from git. Don't mix them up in configs.
- **Houdini-MCP is on 9877** (`HOUDINIMCP_PORT`). Never put a Blender add-on there — Blender would silently answer `houdini.*` calls.
- **Legacy server hangs on first call after Blender restart** occasionally — retry once; the README acknowledges "sometimes the first command won't go through".
- **Legacy `get_scene_info` truncates** the object list (row cap). Use `blender.get_objects_summary` for the full tree.
- **Official `execute_blender_code` in background mode** can't return deferred results (renders with `INVOKE_DEFAULT`); `_for_cli` variants run synchronous code only.
- **Safe mode** — `BLENDER_MCP_SAFE_MODE=1` on the `blender-assets` server validates scripts and blocks file I/O / subprocess / network / persistent code. Off by default here.
- **Legacy add-on ≠ server version** — `get_addon_status` reports `up_to_date`; if false run `uvx blender-mcp install-addon`, then disable/enable the add-on in Blender and Start MCP Server again.
- **Telemetry** — the legacy add-on collects prompts/code/screenshots by default; `disable_telemetry` turns it off. The official server collects nothing.
- **Reconcile this doc after a server update** — `npx mcporter list blender --all-parameters` and `npx mcporter list blender-assets --all-parameters` are the authoritative tool/param lists; `install.sh --check-drift --skills blender` flags doc drift.

## References — read these for deeper topics

- **`references/bpy-cookbook.md`** — read **before writing any `execute_blender_code` Python**. Data-API vs `bpy.ops`, collection linking, material `node_tree` setup (Blender 5.x input names), render-engine ids per version, transform-apply, naming collisions, world/HDRI setup, returning data.
- **`references/scene-checklist.md`** — end-to-end checklist for building a scene from scratch, each item mapping to a trap in the cookbook.
