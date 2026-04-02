## ComfyUI - Image/Video Generation

**Two skill files, both via CLI (no MCP overhead):**
1. **comfy-cli** — server management, running workflow files, node/model management. Read `~/.claude/skills/comfy-cli.md`.
2. **comfy-pilot** — live workflow editing, node discovery, image viewing, canvas control (via MCPorter). Read `~/.claude/skills/comfy-pilot.md`.

**When to use which:**
- Launch/stop server, run a workflow file, list/install nodes/models → comfy-cli skill
- Build/edit workflows on canvas, search node types, view output images, check status → comfy-pilot skill
- Analyze generated images → `comfy run --wait` to get file path, then Read tool to view image

Trigger phrases: "comfyui", "comfy", "workflow", "generate image", "generate video", "install node", "download model", "run workflow"
