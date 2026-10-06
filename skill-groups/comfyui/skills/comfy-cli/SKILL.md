---
version: 1.3.0
name: comfy-cli
description: Manage ComfyUI from the command line via comfy-cli — launch/stop the server, run workflow files, install custom nodes and models, and the Projects folder convention. Use comfy-pilot for live canvas editing.
---

# ComfyUI CLI Skill

Use this skill for **server management**, running workflow files, and quick node/model operations via the command line.

For live workflow editing on the canvas, node discovery with slot details, and viewing generated images — use the comfy-pilot skill instead.

## Setup

- **Binary**: `{{COMFY_CLI}}`
- **Workspace**: `{{COMFYUI_WORKSPACE}}`
- **Always prefix**: `PYTHONIOENCODING=utf-8`

## Not Installed?

- **ComfyUI**: https://github.com/Tavris1/ComfyUI-Easy-Install
- **comfy-cli**: `pip install comfy-cli`

## Launching ComfyUI

```bash
# Check if already running first
curl -s http://127.0.0.1:8188/system_stats

# Standard launch
comfy --workspace "{{COMFYUI_WORKSPACE}}" launch

# If using embedded Python (Windows standalone), launch directly:
# "{{COMFYUI_PYTHON}}" -I -W ignore::FutureWarning "{{COMFYUI_WORKSPACE}}/main.py" --windows-standalone-build
```

**Startup takes ~60s** due to custom nodes loading. Poll with `curl -s http://127.0.0.1:8188/system_stats` until you get a JSON response with `vram` info.

### Dtype Mismatch Errors

If you see `expected scalar type Half but found Float` (or vice versa), it means some models are fp16 and others are fp32. This commonly happens with AnimateDiff (motion modules are fp32) + fp16 checkpoints. Fix by launching with `--force-fp32`. This uses more VRAM but avoids all dtype conflicts.

## Running Workflows

```bash
# Run an API-format workflow and wait for completion
PYTHONIOENCODING=utf-8 comfy --workspace "{{COMFYUI_WORKSPACE}}" run --workflow <path_to_api_workflow.json> --wait

# With timeout
PYTHONIOENCODING=utf-8 comfy run --workflow workflow.json --wait --timeout 300
```

**Important:** Workflow must be in **API format** (nodes with `class_type`), not the standard UI save format. `comfy run --wait` returns output image file paths.

## Node Management

```bash
# Show installed nodes
PYTHONIOENCODING=utf-8 comfy --workspace "{{COMFYUI_WORKSPACE}}" node show installed

# Install a node
PYTHONIOENCODING=utf-8 comfy node install <node-name>

# Uninstall / Update
PYTHONIOENCODING=utf-8 comfy node uninstall <node-name>
PYTHONIOENCODING=utf-8 comfy node update all

# Save/restore snapshots
PYTHONIOENCODING=utf-8 comfy node save-snapshot
PYTHONIOENCODING=utf-8 comfy node restore-snapshot <name>
```

## Model Management

```bash
# List models in specific folder
PYTHONIOENCODING=utf-8 comfy model list --relative-path checkpoints

# Download a model
PYTHONIOENCODING=utf-8 comfy model download --url "https://huggingface.co/user/repo/resolve/main/model.safetensors" --relative-path checkpoints

# Remove a model
PYTHONIOENCODING=utf-8 comfy model remove --relative-path checkpoints --model-names "model.safetensors"
```

### UNET-Only vs Full Checkpoints

Some HuggingFace models labeled as "checkpoints" are actually **UNET-only** (no CLIP/VAE). `CheckpointLoaderSimple` will load them without error but output `None` for CLIP and VAE, causing confusing failures in downstream nodes like CLIPTextEncode ("clip input is invalid: None"). If CLIP/VAE are missing, use `UNETLoader` instead of `CheckpointLoaderSimple` and load CLIP/VAE separately.

### Model Filename Patterns

Some nodes auto-detect models by **filename regex**, not just folder location. IPAdapter's `UnifiedLoader` is a key example — CLIP Vision must match `ViT.H.14.*s32B.b79K` in the name. A file named `clip_vision_h.safetensors` with identical contents won't be found. When downloading models, preserve the original filename.

## Environment & Status

```bash
PYTHONIOENCODING=utf-8 comfy env
PYTHONIOENCODING=utf-8 comfy which
```

## Analyzing Output Images

After `comfy run --wait` returns file paths:
1. Use the Read tool to view the image directly (cheapest option)
2. If path isn't accessible, fall back to comfy-pilot's `view_image` via MCPorter

## Projects Convention (organized, no-duplication runs)

All agent-driven ComfyUI work lives in one folder per project. The user starts one with `/comfy-project <name> <task>`; if you are given a project path, follow these rules.

**Layout** — real folder is `{{COMFYUI_WORKSPACE}}/output/Projects/<name>/`; `<easy-install-root>/Projects` is a junction to `output/Projects`, so the user sees the same files at the top level. Create with:

```bash
bash "$HOME/.claude/.skill-repos/claude-skills/skill-groups/comfyui/scripts/comfy-project-init.sh" <name> [files to move into input/...]
```

```
Projects/<name>/
  input/       source files (moved here, never copied into ComfyUI/input)
  work/        intermediates: frames, masks, test renders
  output/      final deliverables
  workflows/   every UI + API JSON you ran
  NOTES.md     task, runs (what/why/params), where deliverables are
```

**Why it works without copies:** the folder is inside ComfyUI's output tree, and every loader accepts an `[output]` suffix that reads from there. ComfyUI resolves junctions in its path checks, so the reverse (a Projects folder outside the tree linked *into* input/output) is rejected — don't try it.

**Rules**
- Load inputs with the annotated path: `"image": "Projects/<name>/input/src.png [output]"`. Works for LoadImage, LoadVideo, LoadAudio, VHS LoadVideo, and any node using `get_annotated_filepath`. Subfolders are fine: these nodes skip the dropdown-list check.
- Save with a subfolder prefix: `"filename_prefix": "Projects/<name>/work/mask"` or `.../output/final`. Works for SaveImage, VHS VideoCombine, SaveAudio, etc. ComfyUI creates the folders.
- Never call upload tools (`comfy_upload_image`, `/upload/image`, canvas drag-drop) — they copy into `ComfyUI/input/`. Move files with the shell instead.
- Never write to the workflow-default `output/` root; everything goes under the project.
- Save each API JSON you run to `workflows/` before running it; name it after the step (`01_extract_frames_api.json`).
- Append to `NOTES.md` after each run: what you ran, key params/seed, output path, and whether it succeeded.
- Shared assets that many projects use (a reference face, a LUT) may stay in `ComfyUI/input/` — say so in NOTES.md rather than moving them.

**Verify** a run landed correctly: `ls "<project>/output"` — the `/history` entry reports `"subfolder": "Projects\<name>\output"`.
