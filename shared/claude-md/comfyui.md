## ComfyUI - Image/Video Generation

**Delegate hands-on ComfyUI work to the `comfyui` agent (runs on Sonnet).** That means running or polling workflows, building/editing graphs, installing nodes or models, batch renders, file shuffling, and debugging node errors. Keep the main session for talking with the user, choosing the approach, and reviewing results (Read the output images the agent reports). A one-off check (is the server up, what's in a folder) is fine to do directly; anything that needs a run or more than ~3 tool calls goes to the agent. Give the agent the goal, input paths, constraints, and the project folder if there is one.

**Project-scoped work:** `/comfy-project <name> <task>` sets up `Projects/<name>/` and runs the task in the comfyui agent directly.

**Skills the agent uses** (read them yourself only if you are doing the work directly):
1. **comfy-cli** — server management, running workflow files, node/model management, Projects convention. `~/.claude/skills/comfy-cli/SKILL.md`
2. **comfy-pilot** — live canvas editing, node discovery, image viewing (MCPorter `comfyui` server). `~/.claude/skills/comfy-pilot/SKILL.md`
3. **fl-mcp** — FL-MCP's ~108-tool surface (MCPorter `flmcp` server): broad REST automation, node-library introspection, ComfyUI-Manager ops, custom-node Python authoring. `~/.claude/skills/fl-mcp/SKILL.md`

Trigger phrases: "comfyui", "comfy", "workflow", "generate image", "generate video", "install node", "download model", "run workflow", "fl-mcp", "comfyui manager", "custom node dev", "node library", "queue status"
