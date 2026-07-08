---
version: 1.0.0
---

# ComfyUI FL-MCP Skill (via MCPorter)

FL-MCP (`filliptm/ComfyUI_FL-MCP`) is a second, much larger MCP surface for ComfyUI — **~108 tools** spanning REST control, a live browser-bridge canvas editor, the node library, ComfyUI-Manager, and a custom-node development toolkit.

**When to use which ComfyUI skill:**
- Server launch/stop, running workflow files, CLI node/model installs → **comfy-cli**
- Focused live canvas editing with a small, batched `edit_graph` API → **comfy-pilot** (`comfyui` mcporter server)
- Broad REST automation (queue/exec/models/settings/logs), node-library introspection, Manager operations, or **authoring/patching custom-node Python** → **this skill** (`flmcp` server)

comfy-pilot and FL-MCP are independent servers — comfy-pilot always drives the live canvas; FL-MCP's canvas tools need a browser bridge (see below), but its REST tools work headless.

## Prerequisites

- ComfyUI running at http://127.0.0.1:8188
- FL-MCP backend running at http://127.0.0.1:8000 (auto-started by the node; check `curl -s http://127.0.0.1:8000/health`)
- `ComfyUI_FL-MCP` custom node installed in `ComfyUI/custom_nodes/`
- MCPorter via npx

**Not installed?** Fork with embedded-Python fixes: `arghhhhh/ComfyUI_FL-MCP` (upstream `filliptm/ComfyUI_FL-MCP`). Clone into `ComfyUI/custom_nodes/`, `pip install -r requirements.txt` into ComfyUI's Python. On the Windows standalone/portable build the fork's fixes are required (see Gotchas).

## Call Convention

Every tool takes a single `request` object argument, even when empty:

```bash
npx mcporter call flmcp.<tool> request:'{"key":"value"}'
npx mcporter call flmcp.mcp_capability_audit request:'{}'
```

**Always start with `mcp_capability_audit`** — it reports which subsystems are live (`comfy_rest`, `bridge`, `manager_v4`, `assets`) and the current safety-gate states. Don't guess; probe.

## Two execution modes — REST vs Browser Bridge

| Mode | Needs | Tools |
|---|---|---|
| **REST** (headless) | ComfyUI + backend running | status/queue/exec, models, settings, logs, node library, Manager, custom-node dev, userdata workflow files |
| **Browser bridge** | ComfyUI open in a browser tab **with the FL-MCP sidebar connected** | live-canvas graph editing, current-tab JSON, screenshots, frontend commands |

Bridge tools fail with `requires_browser_bridge` when no frontend is connected:

```
"error": "requires_browser_bridge: ... Run the MCP server with FL_MCP_MODE=subprocess,
 FL_MCP_SESSION_ID, and FL_MCP_WS_URL, and keep ComfyUI open in a browser."
```

If you only need canvas edits and no browser is bridged, prefer **comfy-pilot** instead.

## Safety Gates

Five write/mutation classes are **disabled by default** (all `false`). Gated tools no-op with a safety error until enabled. Set in the node's `.env` and restart ComfyUI:

| Env var | Unlocks |
|---|---|
| `FL_MCP_ENABLE_WORKFLOW_WRITES` | `workflow_save_current`, `workflow_rename_file`, `workflow_delete_file` |
| `FL_MCP_ENABLE_CUSTOM_NODE_WRITES` | `custom_nodes_write_file`, `custom_nodes_apply_patch`, `custom_nodes_create_pack` |
| `FL_MCP_ENABLE_GIT_WRITES` | `custom_nodes_git_commit`, `custom_nodes_git_push` |
| `FL_MCP_ENABLE_MANAGER_MUTATIONS` | `manager_queue_action` / installs / `manager_v4_queue_action` |
| `FL_MCP_ENABLE_COMFY_PROCESS_CONTROL` | `comfy_restart`, `comfy_free_memory` |

Check current states with the `safety` block of `mcp_capability_audit`.

## Tool Groups

### Utility (headless, no ComfyUI needed)
`calculate_expressions` (batch math AST — bounding boxes/layout), `generate_int`, `generate_float`, `generate_seed`, `random_choice`, `wait`.

### Diagnostics
`mcp_capability_audit`, `get_system_info`, `comfy_get_logs`, `clear_error_buffer`.

### REST — queue & execution
`comfy_status`, `queue_workflow`, `cancel_workflow`, `get_queue_status`, `get_queue_status_details`, `delete_queue_items`, `get_execution_history`, `get_execution_details`, `comfy_jobs_list`, `comfy_job_get`, `comfy_history_delete`, `set_batch_count`, `enable_auto_queue`, `disable_auto_queue`, `comfy_free_memory`⚿, `comfy_restart`⚿.

### REST — models, assets, files, settings
`comfy_models_list`, `comfy_list_folders`, `comfy_search_resources`, `comfy_tags_list`, `comfy_settings_get`, `comfy_settings_set`, `comfy_read_file`, `comfy_upload_image`, `comfy_upload_mask`, `comfy_assets_list`, `comfy_asset_get`, `comfy_asset_upload`, `comfy_assets_upload`, `comfy_workflow_templates_list`, `comfy_global_subgraphs_list`, `comfy_node_replacements_get`, `extract_workflow_from_image`.

### Node library (object_info introspection)
`node_library_search` (start here), `node_library_get_details`, `node_library_find_compatible`.

```bash
npx mcporter call flmcp.node_library_search request:'{"query":"KSampler","limit":2}'
```

### ComfyUI-Manager (mutations gated)
`manager_check_updates`, `manager_search_nodes`, `manager_search_external_models`, `manager_get_node_mappings`, `manager_queue_status`, `manager_queue_start`, `manager_queue_reset`, `manager_queue_action`⚿. V4 API: `manager_v4_status`, `manager_v4_installed_packs`, `manager_v4_node_mappings`, `manager_v4_external_models`, `manager_v4_snapshots`, `manager_v4_queue_status`, `manager_v4_queue_action`⚿.

### Custom-node development (filesystem; writes gated)
`custom_nodes_list_packs`, `custom_nodes_search`, `custom_nodes_read_file`, `custom_nodes_read_file_excerpt`, `custom_nodes_validate_pack`, `custom_nodes_git_status`, `custom_nodes_git_diff`, `custom_nodes_write_file`⚿, `custom_nodes_apply_patch`⚿, `custom_nodes_create_pack`⚿, `custom_nodes_git_commit`⚿, `custom_nodes_git_push`⚿.

### Live canvas — graph editing (browser bridge)
`create_nodes`, `remove_nodes`, `connect_nodes`, `connect_nodes_batch`, `auto_connect_workflow`, `set_node_values`, `get_node_values`, `get_node_slots`, `find_node`, `query_workflow`, `workflow_overview`, `workflow_diagram`, `get_layout`, `modify_layout`, `focus_on_nodes`, `select_nodes`, `get_current_node_selection`, `pin_nodes`, `unpin_nodes`, `bypass_nodes`, `unbypass_nodes`, `take_screenshot`.

Before `create_nodes`, verify the type exists with `node_library_search`.

### Live canvas — workflow tabs & files
Bridge: `workflow_get_current_json`, `workflow_load_json`, `workflow_get_tabs`, `workflow_close_current`, `workflow_duplicate_current`.
REST userdata (write ops gated): `workflow_list_files`, `workflow_read_file`, `workflow_save_current`⚿, `workflow_rename_file`⚿, `workflow_delete_file`⚿.

### Frontend commands (browser bridge)
`frontend_list_commands`, `frontend_execute_command`, `frontend_list_keybindings`.

*⚿ = requires a safety gate to be enabled.*

## Quirks & Gotchas

- **Embedded Python (Windows standalone/portable):** the ComfyUI portable build's Python uses a `._pth` (site disabled, no script-dir on `sys.path`, `PYTHONPATH` ignored). Stock upstream FL-MCP fails silently — auto-start backend crashes on `ModuleNotFoundError: comfy_supervisor`, and the stdio server fails on `pywintypes`. The `arghhhhh/ComfyUI_FL-MCP` fork fixes all three in-process (PR to upstream pending). Use the fork on portable installs.
- **Backend must be up** — REST tools proxy through the :8000 backend, not just :8188. If tools error, check `curl http://127.0.0.1:8000/health`.
- **Two MCP servers, don't confuse them** — `flmcp` here vs `comfyui` (comfy-pilot). Different tool names and APIs.
- **`requires_browser_bridge`** is expected headless — it's not a failure of setup, just that no frontend tab is connected. Use REST tools or comfy-pilot.
- **Gated writes no-op** with a safety error, not an exception — if a write "does nothing," check the gate in `mcp_capability_audit`.
- **`assets` may be `degraded`** ("ComfyUI assets feature is disabled") — the `comfy_asset*` tools need ComfyUI's assets feature on.
