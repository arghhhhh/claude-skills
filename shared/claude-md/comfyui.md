## ComfyUI - Image/Video Generation

**Three skills, all via CLI/MCPorter (no MCP overhead):**
1. **comfy-cli** — server management, running workflow files, node/model management. Read `~/.claude/skills/comfy-cli.md`.
2. **comfy-pilot** — live workflow editing, node discovery, image viewing, canvas control (via MCPorter `comfyui` server). Read `~/.claude/skills/comfy-pilot.md`.
3. **fl-mcp** — FL-MCP's ~108-tool surface (via MCPorter `flmcp` server): broad REST automation (queue/exec/models/settings/logs), node-library introspection, ComfyUI-Manager ops, custom-node Python authoring, and a browser-bridge canvas editor. Read `~/.claude/skills/fl-mcp.md`.

**When to use which:**
- Launch/stop server, run a workflow file, list/install nodes/models → comfy-cli skill
- Build/edit workflows on canvas, search node types, view output images, check status → comfy-pilot skill
- Broad REST control (queue/models/settings/logs), node-library details, Manager operations, or authoring/patching custom-node code → fl-mcp skill
- Analyze generated images → `comfy run --wait` to get file path, then Read tool to view image

Trigger phrases: "comfyui", "comfy", "workflow", "generate image", "generate video", "install node", "download model", "run workflow", "fl-mcp", "comfyui manager", "custom node dev", "node library", "queue status"
