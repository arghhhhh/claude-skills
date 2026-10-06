---
version: 2.2.1
name: houdini
description: Drive a running (or headless) SideFX Houdini session via the houdini-mcp bridge (mcporter) — node networks, VEX wrangles, parameters, geometry, simulations (pyro/RBD/FLIP/Vellum), USD/Solaris, PDG, rendering, HDAs, and 30k+ indexed docs.
---

# Houdini Skill (via MCP)

Use this skill to inspect and modify a Houdini session through the houdini-mcp bridge, called over `npx mcporter call houdini.<tool>`. Covers scene/network editing, VEX, simulation, USD/Solaris, PDG/TOPs, COPs, CHOPs, HDAs, rendering, and doc search.

Bridge: upstream `kleer001/houdini-mcp` (`main`).

## Setup

- **Transport**: `npx mcporter call houdini.<tool> [params]` (MCPorter → houdini-mcp bridge → Houdini/hython over TCP `localhost:9877`)
- **Port**: pinned to **9877** via `HOUDINIMCP_PORT` to avoid colliding with the Blender MCP add-ons (official on 9876, legacy `blender-assets` on 9878). The bridge gets it from the mcporter `env`; the Houdini GUI plugin gets it from `houdini.env` (`HOUDINIMCP_PORT = 9877`). Both must agree — if you change one, change the other, and restart Houdini.
- **Houdini-side plugin** must be installed once: `cd $HOUDINI_MCP_DIR && uv run python scripts/install.py`. After that it auto-loads when Houdini starts.
- **Houdini does NOT need to be open** for most tools — the bridge auto-launches a headless `hython` session if no GUI is detected. Viewport/render/UI tools need a GUI.

## Not Installed?

- **Houdini**: https://www.sidefx.com/download/
- **houdini-mcp bridge**: https://github.com/kleer001/houdini-mcp (upstream `main`; the fork that carried PRs #4/#5/#6 is retired — they merged 2026-09-23)
- **MCPorter**: runs via `npx mcporter` (auto-fetched)

## Critical Rules

1. **Never rapid-fire commands.** Wait ≥1 s between consecutive tool calls — the plugin uses a single-threaded listener. Never fan out parallel calls to Houdini.
2. **Separate scene work from rendering.** Do all scene setup first, then render as a distinct step.
3. **Render commands are slow.** Don't time them out aggressively.
4. **`execute_houdini_code` is the escape hatch** for anything not covered by a dedicated tool. It runs Python in the Houdini session — `import hou` at the top. Dangerous patterns (`hou.exit`, `os.remove`, `subprocess`, and `__import__`/`exec`) are blocked unless `allow_dangerous:true` — so the hex-decode trick for multi-line scripts needs that flag. See `references/hou-cookbook.md` before writing scripts.

## Always Start Here

```bash
npx mcporter call houdini.get_connection_status     # bridge-side state
npx mcporter call houdini.get_scene_info            # read path — confirms hou is live
```

**Confirm you're talking to Houdini, not Blender** (both share port lineage — see Setup): `get_scene_info` should show `/obj`-style node paths, not mesh `Component#…`. A Blender-looking scene, `No module named 'hou'`, or `ping` → `Unknown command type` means the port didn't take — see the agent's Connection Diagnostics.

## Tool Catalogue (by domain — `npx mcporter list houdini --all-parameters` is authoritative)

### Scene & Network
`get_scene_info` `get_scene_summary` `get_network_overview` `get_cook_chain` `find_error_nodes` `explain_node` `save_scene` `load_scene` `set_current_network` `list_panes` `get_selection` `set_selection` `find_nodes` `list_node_types` `get_env_variable`

### Nodes
`create_node` `modify_node` `delete_node` `get_node_info` `connect_nodes` `connect_nodes_batch` `disconnect_node_input` `set_node_flags` `copy_node` `move_node` `rename_node` `list_children` `layout_children` `set_node_color` `reorder_inputs`

### Parameters & Expressions
`get_parameter` `set_parameter` `set_parameters` `get_parameter_schema` `get_expression` `set_expression` `revert_parameter` `link_parameters` `lock_parameter` `create_spare_parameter` `create_spare_parameters` `evaluate_expression` `execute_hscript`

### Animation / Playbar
`set_keyframe` `set_keyframes` `delete_keyframe` `get_keyframes` `set_frame` `get_frame` `set_frame_range` `set_playback_range` `playbar_control`

### Geometry
`get_geo_summary` `get_points` `get_prims` `get_attrib_values` `set_detail_attrib` `get_groups` `get_group_members` `get_bounding_box` `get_prim_intrinsics` `find_nearest_point`

### VEX / Wrangles
`create_wrangle` `set_wrangle_code` `get_wrangle_code` `create_vex_expression` `validate_vex`

### Materials
`set_material` `list_materials` `get_material_info` `create_material_network` `assign_material` `list_material_types` `create_material_workflow` `assign_material_workflow`

### Rendering
`render_single_view` `render_quad_views` `render_specific_camera` `list_render_nodes` `get_render_settings` `set_render_settings` `create_render_node` `start_render` `get_render_progress` `monitor_render` `render_flipbook` `setup_render`

### Viewport
`get_viewport_info` `set_viewport_camera` `set_viewport_display` `set_viewport_renderer` `frame_selection` `frame_all` `set_viewport_direction` `capture_screenshot`

### PDG / TOPs
`pdg_cook` `pdg_status` `pdg_workitems` `pdg_dirty` `pdg_cancel`

### LOPs / USD / Solaris
`lop_stage_info` `lop_prim_get` `lop_prim_search` `lop_layer_info` `lop_import` `create_lop_node` `list_usd_prims` `get_usd_attribute` `set_usd_attribute` `get_usd_prim_stats` `get_last_modified_prims` `get_usd_composition` `get_usd_variants` `inspect_usd_layer` `list_lights`

### HDAs
`hda_list` `hda_get` `hda_install` `hda_create` `uninstall_hda` `reload_hda` `update_hda` `get_hda_sections` `get_hda_section_content` `set_hda_section_content`

### DOPs / Simulation
`get_simulation_info` `list_dop_objects` `get_dop_object` `get_dop_field` `get_dop_relationships` `step_simulation` `reset_simulation` `get_sim_memory_usage` `setup_pyro_sim` `setup_rbd_sim` `setup_flip_sim` `setup_vellum_sim`

### COPs
`get_cop_info` `get_cop_geometry` `get_cop_layer` `create_cop_node` `set_cop_flags` `list_cop_node_types` `get_cop_vdb`

### CHOPs
`get_chop_data` `create_chop_node` `list_chop_channels` `export_chop_to_parm`

### Takes
`list_takes` `get_current_take` `set_current_take` `create_take`

### Cache
`list_caches` `get_cache_status` `clear_cache` `write_cache`

### Workflows
`build_sop_chain` `batch` `geo_export`

### Events
`get_houdini_events` `subscribe_houdini_events`

### Documentation (30,000+ indexed Houdini docs + example HIPs)
`search_docs` `get_doc`

### Code Execution
`execute_houdini_code` `execute_hscript`

## Common Workflows

**Build a procedural scene** — `get_scene_info` → `create_node` (geo) → `create_node` (SOP) → `set_parameter` → `connect_nodes` → `capture_screenshot`. Follow `references/network-checklist.md`.

**VEX wrangle** — `create_wrangle` → `set_wrangle_code` → `validate_vex` before cook-dependent tools.

**Render** — `render_single_view render_engine:"karma"` for a still; `render_flipbook` for animation; `monitor_render` for long jobs.

**USD / Solaris** — `lop_stage_info` → `lop_prim_search pattern:"/World/geo/*"` → `set_usd_attribute`.

**Search docs** — `search_docs query:"vex noise functions" limit:5` → `get_doc doc_id:"..."`. Prefer this over web search for VEX/HOM/parm references.

## Quirks & Gotchas (MCP / bridge level)

`hou` Python and VEX traps live in `references/hou-cookbook.md`. These are about the bridge/transport:

- **Single-threaded listener** — pace calls; never parallelize against Houdini.
- **`execute_houdini_code` blocks dangerous patterns** (`hou.exit`, `os.remove`, `subprocess`, `__import__`, `exec`, …) — pass `allow_dangerous:true` only when genuinely needed (e.g. the hex-decode trick for multi-line scripts).
- **Headless mode** — viewport/screenshot/UI tools require an actual Houdini GUI; the auto-launched hython session is headless.
- **Cold start** — headless hython takes ~30 s; mcporter's default 60 s call timeout is tight. Prelaunch the server for reliability (see agent diagnostics).
- **Offline docs** — `search_docs` needs `uv run python scripts/fetch_houdini_docs.py` from the clone (~100 MB, skipped by default).
- **Reconcile this doc after a bridge update** — `npx mcporter list houdini --all-parameters` is authoritative; `install.sh --check-drift --skills houdini` flags doc drift.

## References — read these for deeper topics

- **`references/hou-cookbook.md`** — read **before writing `execute_houdini_code` Python**. HOM (`hou`) node/parm/geometry patterns, SOP vs OBJ contexts, cook dependencies, USD/LOP stage access, and VEX wrangle gotchas (type prefixes, binding, groups).
- **`references/network-checklist.md`** — end-to-end checklist for building a procedural network from scratch.
