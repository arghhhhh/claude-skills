# Building a Procedural Network — Checklist

Run through this when building a Houdini network from scratch via MCP tools / `execute_houdini_code`. Each item maps to a trap in `hou-cookbook.md`.

1. `get_scene_info` (or `get_scene_summary`) first — and confirm you're actually talking to Houdini, not Blender on the shared port 9876 (paths should look like `/obj/...`, not mesh `Component#…`).
2. Create the OBJ container before SOPs: `create_node node_type:"geo" parent_path:"/obj"`. SOPs (`box`, `sphere`, wrangles) go **inside** the geo, never at `/obj`.
3. After creating, **read back the real node name/path** — Houdini auto-suffixes collisions (`box1`, `box2`).
4. Wire inputs explicitly (`connect_nodes` / `setInput(0, src)`); order matters for merges and booleans.
5. Parameters: single channels are `tx`/`ty`/`tz` (`parm`), the vector is `t` (`parmTuple`). `set_parameter` per channel or `set_parameters` in a batch — pace calls ≥1 s apart.
6. VEX wrangle: `create_wrangle` → set `class` (Run Over) correctly → `set_wrangle_code` → **`validate_vex` before** any cook-dependent step. Use the right attribute type prefix (`f@`/`i@`/`v@`/`s@`).
7. Set **display and render flags** on the terminal SOP — programmatic nodes don't always inherit the display flag.
8. Check `find_error_nodes` / `node.errors()` after building before you trust the result.
9. Keep scene construction and rendering as **separate phases** — finish the network, then render.
10. Render: `render_single_view` (Karma/Mantra) for a still, `render_flipbook` for animation; use `monitor_render` for long jobs and don't time out aggressively.
11. Viewport/screenshot/render need a **GUI** Houdini — the headless hython session can't do them.
12. Save before risky ops: `save_scene path:"..."`.
