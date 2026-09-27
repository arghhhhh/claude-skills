---
description: Run a ComfyUI task inside an organized project folder (Projects/<name>/{input,work,output,workflows}) with no file duplication
argument-hint: <project-name> <task description>
context: fork
agent: comfyui
---

Do ComfyUI work inside a self-contained project folder. Request: $ARGUMENTS

Parse the request as `<project-name> <task description>`. The first token is the project name (kebab-case it if needed). Everything after is the task. Files the task names are the project's input files. Resolve relative file names against the current working directory.

## 1. Set up the project folder

```bash
bash "$HOME/.claude/.skill-repos/claude-skills/skill-groups/comfyui/scripts/comfy-project-init.sh" <project-name> [input files...]
```

The script takes only the project name and the files; it finds the ComfyUI workspace itself. The last line printed is the project path. Input files are **moved** (not copied) into `input/`. If a named input already lives in ComfyUI's own `input/` folder, move it too unless the task says it's a shared asset. Re-running it on an existing project is safe: it only creates missing folders, never overwrites `NOTES.md`, and never replaces files in `input/`.

## 2. Resume an existing project

If `NOTES.md` already has runs logged or `workflows/` is not empty, this is a resume. Before building anything:

1. Read `NOTES.md` in full: the original task, every run, params/seeds, and what was delivered.
2. List `workflows/`, `output/` and `work/` newest first (`ls -t`).
3. Start from the most recent workflow JSON that fits the new task. Edit it rather than rebuilding the graph; keep the step-numbered naming (`05_...` follows `04_...`).
4. Append a `## Session <YYYY-MM-DD>` heading to `NOTES.md` before logging new runs.

If no task was given (just the project name), report the project's state from `NOTES.md` and the folder listing, then stop.

## 3. Do the task

Read the **Projects Convention** section of `~/.claude/skills/comfy-cli.md`. The rules that matter most:

- **Loaders need the ` [output]` suffix** — the project lives inside ComfyUI's *output* tree, so without it the loader looks in ComfyUI's input folder and fails validation.
- Intermediates use prefix `Projects/<name>/work/<label>`; finals use `Projects/<name>/output/<label>`.
- Save every workflow JSON you run to `workflows/`, never upload files into ComfyUI's input folder, and append what you ran to `NOTES.md`.

```json
"1": {"class_type": "LoadImage", "inputs": {"image": "Projects/<name>/input/src.png [output]"}},
"9": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": "Projects/<name>/output/final"}}
```

## 4. Report

End with the project path, the deliverables in `output/` (absolute paths), and anything left in `work/` worth keeping.
