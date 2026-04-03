---
version: 1.0.0
---

# ComfyUI Pilot Skill (via MCPorter)

Use this skill for **live workflow editing**, node discovery, image viewing, and canvas control in ComfyUI. Requires ComfyUI to be running.

For server management (launch/stop), node installation, model downloads via CLI, and running workflow files — use the comfy-cli skill instead.

## Prerequisites

- ComfyUI must be running at http://127.0.0.1:8188
- comfy-pilot custom node installed in ComfyUI/custom_nodes/comfy-pilot
- MCPorter available via npx

## Commands

All commands use: `npx mcporter call comfyui.<tool> [params]`

### Workflow Inspection

```bash
# Get lightweight summary: node IDs, types, titles, positions, connections
npx mcporter call comfyui.summarize_workflow

# Get full workflow (heavy — use summarize_workflow first)
npx mcporter call comfyui.get_workflow
```

**Always use `summarize_workflow` first.** Only use `get_workflow` if you need full widget values.

### Node Type Discovery

```bash
# Search for node types (minimal info — start here)
npx mcporter call comfyui.get_node_types search:"sampler"

# Multiple search terms
npx mcporter call comfyui.get_node_types search:'["camera", "sampler"]'

# Filter by category
npx mcporter call comfyui.get_node_types search:"preview" category:"image"

# Get detailed info (inputs/outputs) — only after narrowing down
npx mcporter call comfyui.get_node_types search:"KSampler" fields:'["inputs", "outputs", "input_types"]'
```

**Token optimization:** Search without `fields` first, then request `fields` only for the 1-3 nodes you'll actually use.

### Node Inspection

```bash
# Get detailed info about a specific node in the current workflow
npx mcporter call comfyui.get_node_info node_id:"5"
```

### Workflow Editing (edit_graph)

All graph modifications use `edit_graph` with batched operations:

```bash
# Create nodes with refs for chaining
npx mcporter call comfyui.edit_graph operations:'[
  {"action": "create", "node_type": "CheckpointLoaderSimple", "title": "Load Model", "pos_x": 100, "pos_y": 200, "ref": "loader"},
  {"action": "create", "node_type": "KSampler", "title": "Main Sampler", "pos_x": 400, "pos_y": 200, "ref": "sampler"},
  {"action": "connect", "from_node": "loader", "from_slot": 0, "to_node": "sampler", "to_slot": 0}
]'

# Set node properties
npx mcporter call comfyui.edit_graph operations:'[
  {"action": "set", "node_id": "5", "property": "steps", "value": 30},
  {"action": "set", "node_id": "5", "properties": {"cfg": 7.5, "seed": 12345}}
]'

# Move, resize, delete
npx mcporter call comfyui.edit_graph operations:'[
  {"action": "move", "node_id": "5", "x": 400, "y": 100},
  {"action": "move", "node_id": "6", "relative_to": "5", "direction": "below", "gap": 30},
  {"action": "delete", "node_id": "3"}
]'

# Place new nodes in user's current viewport
npx mcporter call comfyui.edit_graph operations:'[
  {"action": "create", "node_type": "PreviewImage", "title": "Preview", "place_in_view": true}
]'
```

**Actions:** create, delete, move, resize, set, connect, disconnect
**Refs:** Use `"ref": "myname"` in create, then reference as `"node_id": "myname"` in later ops within the same batch.

### Running & Interrupting

```bash
npx mcporter call comfyui.run action:"queue"
npx mcporter call comfyui.run action:"interrupt"
```

### Status & History

```bash
npx mcporter call comfyui.get_status
npx mcporter call comfyui.get_status include:'["queue", "system", "history"]'
```

### Viewing Generated Images

```bash
npx mcporter call comfyui.view_image
npx mcporter call comfyui.view_image node_id:"15"
```

### Custom Node Management

```bash
npx mcporter call comfyui.search_custom_nodes query:"controlnet"
npx mcporter call comfyui.install_custom_node node_id:"ComfyUI-Advanced-ControlNet"
```

## Converting UI Workflows to API Format

ComfyUI saves workflows in two formats: **UI format** (browser) and **API format** (flat dict with `class_type` and `inputs`). `comfy run` and `/prompt` endpoint require API format.

**Key pitfall: `widgets_values` indexing.** UI format stores widget values as an ordered array, but hidden widgets shift the indices. To convert correctly, fetch node definitions from `http://127.0.0.1:8188/object_info` and map inputs in order, skipping connections and slot-type inputs.

## Quirks & Gotchas

- `view_image` returns base64 — MCPorter may truncate very large images. Prefer Read tool on saved file path.
- `edit_graph` operations execute in order — put creates before connects/sets that reference them.
- Node management (install/uninstall/update) requires ComfyUI restart to take effect.
- Some custom nodes output `None` when given empty/disabled inputs instead of passing through. Check for passthrough nodes if CLIP or MODEL is unexpectedly None.
