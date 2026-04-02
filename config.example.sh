# claude-skills configuration
# Copy this to ~/.claude/skills-config.sh and customize for your machine.
# The installer will auto-detect what it can and prompt for the rest.

# ─── ComfyUI ─────────────────────────────────────────────────────────────────
# Path to comfy-cli binary (pip install comfy-cli)
COMFY_CLI=""  # e.g. /usr/local/bin/comfy or C:/Users/you/miniconda3/Scripts/comfy.exe

# ComfyUI workspace (the directory containing main.py)
COMFYUI_WORKSPACE=""  # e.g. ~/ComfyUI or C:/Users/you/ComfyUI

# Embedded Python (only for Windows standalone builds, leave empty otherwise)
COMFYUI_PYTHON=""  # e.g. C:/Users/you/ComfyUI-Easy-Install/python_embeded/python.exe

# GPU description (for agent context)
GPU_INFO=""  # e.g. "NVIDIA RTX 4080 (12GB VRAM)"

# ─── OBS Studio ──────────────────────────────────────────────────────────────
# Path to gobs-cli binary
GOBS_CLI=""  # e.g. /usr/local/bin/gobs-cli or C:/Users/you/tools/obs-cli/gobs-cli.exe

# OBS config directory
OBS_CONFIG_DIR=""  # e.g. ~/.config/obs-studio or C:/Users/you/AppData/Roaming/obs-studio

# gobs-cli config (contains OBS_PASSWORD)
GOBS_CONFIG=""  # e.g. ~/.config/gobs-cli/config.env or C:/Users/you/AppData/Local/gobs-cli/config.env

# ─── Blender ─────────────────────────────────────────────────────────────────
# No machine-specific config needed — blender-mcp uses mcporter + localhost:9876

# ─── Unity CLI ───────────────────────────────────────────────────────────────
# No machine-specific config needed — skills are pulled from the unity-cli repo
