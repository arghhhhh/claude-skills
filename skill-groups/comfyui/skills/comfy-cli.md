---
version: 1.0.0
---

# ComfyUI CLI Skill

Use this skill for **server management**, running workflow files, and quick node/model operations via the command line.

For live workflow editing on the canvas, node discovery with slot details, and viewing generated images — use the comfy-pilot skill instead.

## Setup

- **Binary**: `{{COMFY_CLI}}`
- **Workspace**: `{{COMFYUI_WORKSPACE}}`
- **Always prefix**: `PYTHONIOENCODING=utf-8`

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
