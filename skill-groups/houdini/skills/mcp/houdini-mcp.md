---
version: 1.0.1
---

# Houdini MCP Skill

Use this skill when the user wants to interact with SideFX Houdini — create/modify scenes, build node networks, write VEX, set up simulations, render, work with USD/Solaris, PDG/TOPs, COPs, CHOPs, HDAs, or query Houdini docs.

Bridge: `arghhhhh/houdini-mcp` (fork of `kleer001/houdini-mcp`, branch `patched` — Windows path fixes + parm/vex crash fixes). 166 tools total.

## Prerequisites

- **Houdini-side plugin must be installed** (run once: `cd $HOUDINI_MCP_DIR && uv run python scripts/install.py`). After that, the plugin auto-loads when Houdini starts.
- **Houdini does NOT need to be open** for most tools — the bridge auto-launches a headless `hython` session if no GUI is detected. For viewport/render/UI-dependent tools, open Houdini first.
- TCP port (default 9876) must not be blocked.

## Critical Rules

1. **Never rapid-fire commands.** Wait ≥1 s between consecutive tool calls — the Houdini plugin uses a single-threaded listener.
2. **Separate scene work from rendering.** Do all scene setup first, then call render tools as a separate step.
3. **Render commands are slow.** Don't time them out aggressively.
4. **`execute_houdini_code` is the escape hatch** for anything not covered by a dedicated tool.

## Health Check

```bash
npx mcporter call houdini.ping
npx mcporter call houdini.get_connection_status
```

## Tool Catalogue (166 tools across 19 domains)

### Scene & Network (15)
`get_scene_info` `get_scene_summary` `get_network_overview` `get_cook_chain` `find_error_nodes` `explain_node` `save_scene` `load_scene` `set_current_network` `list_panes` `get_selection` `set_selection` `find_nodes` `list_node_types` `get_env_variable`

### Nodes (12)
`create_node` `modify_node` `delete_node` `get_node_info` `connect_nodes` `connect_nodes_batch` `disconnect_node_input` `set_node_flags` `copy_node` `move_node` `rename_node` `list_children` `layout_children` `set_node_color` `reorder_inputs`

### Parameters & Expressions (16)
`get_parameter` `set_parameter` `set_parameters` `get_parameter_schema` `get_expression` `set_expression` `revert_parameter` `link_parameters` `lock_parameter` `create_spare_parameter` `create_spare_parameters` `evaluate_expression` `execute_hscript`

### Animation / Playbar (8)
`set_keyframe` `set_keyframes` `delete_keyframe` `get_keyframes` `set_frame` `get_frame` `set_frame_range` `set_playback_range` `playbar_control`

### Geometry (8)
`get_geo_summary` `get_points` `get_prims` `get_attrib_values` `set_detail_attrib` `get_groups` `get_group_members` `get_bounding_box` `get_prim_intrinsics` `find_nearest_point`

### VEX / Wrangles (5)
`create_wrangle` `set_wrangle_code` `get_wrangle_code` `create_vex_expression` `validate_vex`

### Materials (7)
`set_material` `list_materials` `get_material_info` `create_material_network` `assign_material` `list_material_types` `create_material_workflow` `assign_material_workflow`

### Rendering (10)
`render_single_view` `render_quad_views` `render_specific_camera` `list_render_nodes` `get_render_settings` `set_render_settings` `create_render_node` `start_render` `get_render_progress` `monitor_render` `render_flipbook` `setup_render`

### Viewport (8)
`get_viewport_info` `set_viewport_camera` `set_viewport_display` `set_viewport_renderer` `frame_selection` `frame_all` `set_viewport_direction` `capture_screenshot`

### PDG / TOPs (5)
`pdg_cook` `pdg_status` `pdg_workitems` `pdg_dirty` `pdg_cancel`

### LOPs / USD / Solaris (12)
`lop_stage_info` `lop_prim_get` `lop_prim_search` `lop_layer_info` `lop_import` `create_lop_node` `list_usd_prims` `get_usd_attribute` `set_usd_attribute` `get_usd_prim_stats` `get_last_modified_prims` `get_usd_composition` `get_usd_variants` `inspect_usd_layer` `list_lights`

### HDAs (8)
`hda_list` `hda_get` `hda_install` `hda_create` `uninstall_hda` `reload_hda` `update_hda` `get_hda_sections` `get_hda_section_content` `set_hda_section_content`

### DOPs / Simulation (10)
`get_simulation_info` `list_dop_objects` `get_dop_object` `get_dop_field` `get_dop_relationships` `step_simulation` `reset_simulation` `get_sim_memory_usage` `setup_pyro_sim` `setup_rbd_sim` `setup_flip_sim` `setup_vellum_sim`

### COPs (7)
`get_cop_info` `get_cop_geometry` `get_cop_layer` `create_cop_node` `set_cop_flags` `list_cop_node_types` `get_cop_vdb`

### CHOPs (4)
`get_chop_data` `create_chop_node` `list_chop_channels` `export_chop_to_parm`

### Takes (4)
`list_takes` `get_current_take` `set_current_take` `create_take`

### Cache (4)
`list_caches` `get_cache_status` `clear_cache` `write_cache`

### Workflows (3)
`build_sop_chain` `batch` `geo_export`

### Events (2)
`get_houdini_events` `subscribe_houdini_events`

### Documentation (30,000+ indexed Houdini docs + example HIPs)
`search_docs` `get_doc`

### Code Execution (2)
`execute_houdini_code` `execute_hscript`

## Common Workflows

### Build a Procedural Scene

```bash
npx mcporter call houdini.get_scene_info
npx mcporter call houdini.create_node node_type:"geo" parent_path:"/obj" name:"my_geo"
npx mcporter call houdini.create_node node_type:"box" parent_path:"/obj/my_geo"
npx mcporter call houdini.set_parameter path:"/obj/my_geo/box1" parm_name:"sizex" value:2.0
npx mcporter call houdini.capture_screenshot
```

### Write a VEX Wrangle

```bash
npx mcporter call houdini.create_wrangle parent_path:"/obj/my_geo" wrangle_type:"point"
npx mcporter call houdini.set_wrangle_code path:"/obj/my_geo/attribwrangle1" code:"@P.y += sin(@P.x) * 0.5;"
npx mcporter call houdini.validate_vex code:"@P.y += sin(@P.x) * 0.5;" wrangle_type:"point"
```

### Render

```bash
npx mcporter call houdini.render_single_view render_engine:"karma"
npx mcporter call houdini.render_quad_views render_path:"$HIP/render/quad_$F4.exr"
```

### Search Houdini Docs

```bash
npx mcporter call houdini.search_docs query:"vex noise functions" limit:5
npx mcporter call houdini.get_doc doc_id:"vex/functions/noise"
```

### USD / Solaris

```bash
npx mcporter call houdini.lop_stage_info
npx mcporter call houdini.lop_prim_search pattern:"/World/geo/*"
npx mcporter call houdini.set_usd_attribute prim_path:"/World/geo/sphere" attribute:"radius" value:2.5
```

## Quirks & Gotchas

- **Single-threaded listener** — pace your calls; don't fan out parallel tool calls to Houdini.
- **`execute_houdini_code`** blocks dangerous patterns (`hou.exit`, `os.remove`, `subprocess`, …). Pass `allow_dangerous:true` only when you genuinely need it.
- **Patched fork** — local clone has Windows path/encoding fixes (ysysimon PR #2) and parm/vex crash fixes (ysk424 PR #3) merged on the `patched` branch. If you `git pull` upstream, re-apply.
- **Headless mode** — viewport/screenshot/UI tools require an actual Houdini GUI; the auto-launched hython session is headless.
- **Offline docs** — to enable `search_docs`, run `uv run python scripts/fetch_houdini_docs.py` from the clone (~100 MB download). Skipped by default.
