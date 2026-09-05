## Blender - 3D Scene Inspection, Scripting, Assets & AI Generation

**Two skill files, both via MCPorter (two MCP servers talking to the same Blender):**
1. **blender** — official Blender Lab MCP: scene/file introspection, `bpy` Python execution, bpy + manual docs search, editor/window screenshots, renders, headless `.blend` analysis. Read `~/.claude/skills/blender/SKILL.md`.
2. **blender-assets** — ahujasid "MCP for Blender": Poly Haven HDRIs/textures/models, Sketchfab and Poly Pizza import, Hyper3D Rodin and Hunyuan3D AI generation. Read `~/.claude/skills/blender-assets/SKILL.md`.

**When to use which:**
- Inspect a scene or file, run Python, screenshot, render, look up a `bpy` API → blender skill
- Download an HDRI/texture/model, or AI-generate a model → blender-assets skill, then back to blender to place/rescale/verify
- Building a scene end-to-end → both; the `blender` agent routes between them

Ports: 9876 official add-on, 9878 legacy add-on (9877 is Houdini).

Trigger phrases: "blender", "3D scene", "3D model", "render", "material", "texture", "bpy", ".blend", "poly haven", "sketchfab", "poly pizza", "hyper3d", "rodin", "hunyuan3d"
