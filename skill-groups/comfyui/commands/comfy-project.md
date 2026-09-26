---
description: Run a ComfyUI task inside an organized project folder (Projects/<name>/{input,work,output,workflows}) with no file duplication
---

The user wants ComfyUI work done inside a self-contained project folder. Their request: $ARGUMENTS

Parse `$ARGUMENTS` as: `<project-name> <task description>`. The first token is the project name (kebab-case it if needed). Everything after is the task. If the task names files (paths, or files sitting in the current directory), those are the project's input files.

## 1. Set up the project folder

```bash
bash "$HOME/.claude/.skill-repos/claude-skills/skill-groups/comfyui/scripts/comfy-project-init.sh" <project-name> [input files...]
```

The last line printed is the project path, e.g. `C:/Comfy/ComfyUI-Easy-Install/Projects/<name>`. Input files listed are **moved** (not copied) into `input/`. If a named input already lives in the ComfyUI `input/` folder (Workspace path in the comfy-cli skill), move it too, unless the user says it's a shared asset.

## 2. Hand off to the comfyui agent

Launch the `comfyui` agent with the task plus this preamble (fill in the path):

> Project folder: `<project path>`. Follow the **Projects convention** in the comfy-cli skill: read inputs as `Projects/<name>/input/<file> [output]`, write intermediates with prefix `Projects/<name>/work/<label>`, finals with prefix `Projects/<name>/output/<label>`, save every workflow JSON you run to `workflows/`, never upload files into ComfyUI/input, and append what you ran and where the deliverables are to `NOTES.md`.

## 3. Report

When the agent finishes, tell the user the project path and list the deliverables in `output/`. If anything was left in `work/` that they may want, say so.
