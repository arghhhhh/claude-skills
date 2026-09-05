---
version: 3.1.0
name: blender
description: Drive a running Blender session via the official Blender Lab MCP server (mcporter `blender`) — scene/file introspection, bpy + manual docs search, area/window screenshots, renders, headless .blend analysis, and structured Python execution. Asset import and AI generation live in the sibling `blender-assets` skill.
---

# Blender Skill (official MCP, via MCPorter)

Use this skill to **inspect, script, document, screenshot and render** a live Blender session through the official Blender Lab MCP server, called as `npx mcporter call blender.<tool> [params]`.

For **importing assets** (Poly Haven, Sketchfab, Poly Pizza) or **AI-generating models** (Hyper3D Rodin, Hunyuan3D) — use the **blender-assets** skill instead (`blender-assets.<tool>`). Everything else, including running Python, belongs here.

## Setup

- **Transport**: `npx mcporter call blender.<tool>` → `uvx --with "mcp<2" --from "git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp" blender-mcp` → official add-on socket on **localhost:9876**. The `mcp<2` pin is required (the package imports the v1 FastMCP API).
- **Requires**: Blender **5.1+** with the **MCP** extension enabled (Preferences → Get Extensions → repo `https://lab.blender.org/` → install **MCP**). Its prefs panel has Host/Port, **Auto Start** (on by default) and Start/Stop. Nothing to click in the viewport.
- **Port map on this machine**: 9876 official Blender · 9877 Houdini-MCP · 9878 legacy Blender (`blender-assets`).
- **No `user_prompt` param** on any tool (unlike `blender-assets`).

## Not Installed?

- **Blender 5.1+**: https://www.blender.org/download/
- **MCP extension**: repo `https://lab.blender.org/` · docs https://www.blender.org/lab/mcp-server/ · source https://projects.blender.org/lab/blender_mcp
- **MCPorter**: `npx mcporter` (auto-fetched) · **uv**: https://docs.astral.sh/uv/

## Always Start Here

```bash
npx mcporter call blender.get_objects_summary                                                     # collection tree, objects, active object, mode, camera
npx mcporter call blender.get_screenshot_of_area_as_image area_ui_type:VIEW_3D --save-images <dir>   # then Read the saved PNG
```

If a call hangs or is refused: Blender isn't running, or the MCP extension isn't enabled / Auto Start is off. See **Gotchas**.

## mcporter mechanics

- **Code from a file** — `code=@/path/script.py` passes the file verbatim. Use it for anything beyond one line; inline `code:"..."` breaks on `:`, `=`, spaces and `+/`. Fallback without a file: `exec(__import__('binascii').unhexlify('<hex>').decode())`.
- **Images** — screenshot tools return image blocks; add `--save-images <dir>` and mcporter writes `mcp-image-<ts>-1.png` there. Read that file. Without the flag you only see `{type:'image'}`.
- **JSON payloads** — `--args '{"k":"v"}'` when quoting gets ugly.
- **Renders** — `render_*_to_path` keeps only the *basename* of `output_path` and saves under `<bpy.app.tempdir>/blender_mcp/`. Read `result.filepath` from the response.

## Tools (26)

`RO` = read-only annotated. `_for_cli` tools open a `.blend` in `blender --background` — Blender need not be running; needs `blender` on PATH or `BLENDER_PATH`.

### Python

| Tool | Purpose |
|---|---|
| `execute_blender_code code:<py>` | Run Python with `bpy`. Assign a JSON-serialisable dict to **`result`** to return data; prints come back as `stdout`; exceptions return `status:"error"` + full traceback. Keep chunks small. |
| `execute_blender_code_for_cli blend_file:<path> code:<py>` | Same, headless against a file on disk. Synchronous code only. |

### Scene & file introspection

| Tool | Purpose |
|---|---|
| `get_objects_summary` RO | Collection hierarchy with objects (type, parent, data name, selected, visibility), active object, mode, camera. **Start here.** |
| `get_object_detail_summary name:<obj>` RO | Transforms, parent/children, modifiers, constraints, materials, visibility, collections. |
| `get_blendfile_summary_datablocks` RO | Data-block counts, active workspace, render engine. |
| `get_blendfile_summary_missing_files` RO | Missing external refs (images, libraries, fonts, sounds, clips, caches). |
| `get_blendfile_summary_of_linked_libraries` RO | Tree of direct + indirect linked libraries. |
| `get_blendfile_summary_path_info` RO | File path, saved/dirty, age, backups. Fast. |
| `get_blendfile_summary_usage_guess` RO | Scores 0–100 per use-case (modeling, animation, geometry nodes, VSE, …). |
| `get_blendfile_summary_datablocks_for_cli` · `get_blendfile_summary_missing_files_for_cli` · `get_blendfile_summary_of_linked_libraries_for_cli` · `get_blendfile_summary_path_info_for_cli` · `get_blendfile_summary_usage_guess_for_cli` — all `blend_file:<path>` RO | Headless twins of the five summaries above; work on a closed file. |

### Screenshots & navigation

| Tool | Purpose |
|---|---|
| `get_screenshot_of_area_as_image area_ui_type:<T> [size_limit_in_bytes]` RO | PNG of one editor. `T` ∈ `VIEW_3D IMAGE_EDITOR UV ShaderNodeTree CompositorNodeTree GeometryNodeTree TextureNodeTree SEQUENCE_EDITOR CLIP_EDITOR DOPESHEET_EDITOR GRAPH_EDITOR NLA_EDITOR TEXT_EDITOR CONSOLE INFO TOPBAR STATUSBAR OUTLINER PROPERTIES FILE_BROWSER SPREADSHEET PREFERENCES`. |
| `get_screenshot_of_window_as_image [size_limit_in_bytes]` RO | PNG of the whole Blender window. |
| `get_screenshot_of_window_as_json` RO | Window/area/region layout with pixel rects, active object, selection — find an editor before screenshotting it. |
| `jump_to_tab_by_name name:<ws>` | Switch workspace tab. |
| `jump_to_tab_by_space_type space_type:<T> [allow_edits:true]` | Switch to a workspace whose main area is `T`; `allow_edits` duplicates the current one if none exists. |
| `jump_to_view3d_object_by_name name:<obj> [allow_edits:true]` | Frame an object in the 3D view; `allow_edits` may unhide it / enable its collections. |
| `jump_to_view3d_object_data_by_name name:<data> [allow_edits:true]` | Same, by data-block name. |

### Rendering

| Tool | Purpose |
|---|---|
| `render_thumbnail_to_path output_path:<name.png>` | Quick low-quality render (temporarily overrides settings). |
| `render_viewport_to_path output_path:<name.png>` RO | Full render with current settings; runs deferred so the call blocks until done. |

### Documentation (bundled, matches the running Blender version)

| Tool | Purpose |
|---|---|
| `get_python_api_docs identifier:<bpy.x.y>` RO | bpy reference for one identifier. `*` lists top-level modules; `bpy.types.*` lists children. Response `kind` ∈ exact/namespace/definition/partial/suggestions/missing. |
| `search_api_docs query:<words> [max_results:20] [context:0] [index]` RO | Full-text search over the bpy API RST. All tokens must match; stop-words dropped; no regex. `index:<n>` re-fetches one hit widened to its section. |
| `search_manual_docs query:<words> [max_results] [context] [index]` RO | Same over the Blender user manual. |

**Look up before guessing** — `search_api_docs query:"shade_smooth"` returns the real operator signature; no web needed.

## Common Workflows

**Understand an unfamiliar file** — `get_blendfile_summary_path_info` → `get_blendfile_summary_usage_guess` → `get_objects_summary` → `get_object_detail_summary` on the interesting ones → `get_blendfile_summary_missing_files` if textures look pink. Or run the `_for_cli` twins on a path without opening Blender.

**Build a scene from scratch** — `get_objects_summary` → write bpy to a file, `execute_blender_code code=@file` in small chunks (data API; see cookbook) → HDRI/textures/props via **blender-assets** → materials → `get_screenshot_of_area_as_image area_ui_type:VIEW_3D --save-images <dir>` → Read. Follow `references/scene-checklist.md`.

**Look up an API** — `search_api_docs` / `get_python_api_docs` before writing code; `search_manual_docs` for how a feature is meant to be used.

**Always screenshot after a visual change** and Read the image — it's the only way to know it actually looks right.

## Gotchas (MCP / connection level)

Scripting/`bpy` traps live in `references/bpy-cookbook.md`.

- **Hang / connection refused** → MCP extension not enabled or Auto Start off. Preferences → Add-ons → MCP → Start. `netstat -ano | findstr :9876` should show `blender.exe`.
- **`ModuleNotFoundError: mcp.server.fastmcp`** on launch → the `--with "mcp<2"` pin is missing from the mcporter/Claude config.
- **Package-name collision** — this server and the `blender-assets` one are both called `blender-mcp` with the same entry point. `uvx blender-mcp` is always the PyPI (ahujasid) one; the official one only installs from git.
- **Houdini-MCP is on 9877** — never put a Blender add-on there; Blender would silently answer `houdini.*` calls.
- **Background mode** — `execute_blender_code` can't return deferred results (renders with `INVOKE_DEFAULT`) when Blender runs `-b`; `_for_cli` variants run synchronous code only.
- **No telemetry** — this server collects nothing (the `blender-assets` one does by default).
- **Reconcile this doc after a server update** — `npx mcporter list blender --all-parameters` is the authoritative tool/param list; `install.sh --check-drift --skills blender` flags doc drift.

## References — read these for deeper topics

- **`references/bpy-cookbook.md`** — read **before writing any `execute_blender_code` Python**. Data-API vs `bpy.ops`, collection linking, material `node_tree` setup (Blender 5.x input names), render-engine ids per version, transform-apply, naming collisions, world/HDRI setup, returning data.
- **`references/scene-checklist.md`** — end-to-end checklist for building a scene from scratch, each item mapping to a trap in the cookbook.
