---
version: 1.0.0
---

# HuggingFace Downloader Skill

Use this skill whenever the user wants to download a model, checkpoint, LoRA,
VAE, text encoder, dataset, or any file from HuggingFace — especially to install
models into ComfyUI. The user will usually just paste a `huggingface.co` link
and say something like "grab this model".

`hfdownloader` is a fast, resumable, multi-connection downloader for HuggingFace
repos. Prefer it over `git clone` or `huggingface-cli` — it is faster and
resumes cleanly after interruptions.

## Quick example (the common case)

User: *"Use the HuggingFace downloader to grab this model:
`https://huggingface.co/Kijai/LTX2.3_comfy/blob/main/diffusion_models/ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors`"*

1. Parse → repo `Kijai/LTX2.3_comfy`, revision `main`, file
   `diffusion_models/ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors`.
2. The repo path starts with `diffusion_models/` → ComfyUI folder is `diffusion_models`.
3. Dry-run, then download:

```
hfdownloader download Kijai/LTX2.3_comfy -b main -F ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors -E .md,LICENSE,.gitattributes --legacy -o <COMFYUI_MODELS_DIR>/diffusion_models --no-friendly --no-manifest -c 16 --dry-run
```

Confirm the plan shows exactly that one file, then re-run without `--dry-run`.

---

## Step 1 — Check it is installed

Run `hfdownloader version`. If that fails, install it (see **Installation** at
the bottom), then continue.

## Step 2 — Parse the HuggingFace URL

Strip any `?query` and `#fragment` first, then read the path after
`https://huggingface.co/`:

| URL form | Meaning |
|----------|---------|
| `.../{owner}/{name}` | Whole model repo. Repo id = `{owner}/{name}`. |
| `.../{owner}/{name}/blob/{rev}/{path}` | Single file. Repo `{owner}/{name}`, revision `{rev}`, file path `{path}`. |
| `.../{owner}/{name}/resolve/{rev}/{path}` | Same as `blob` (a direct-download link). |
| `.../{owner}/{name}/tree/{rev}/{subdir}` | A subfolder `{subdir}` of the repo. |
| `.../datasets/{owner}/{name}/...` | A **dataset** — add `--dataset` to commands. Repo id = `{owner}/{name}`. |
| `.../{name}` (single segment) | A canonical model (e.g. `bert-base-uncased`). Repo id = `{name}`. |

- **Revision** defaults to `main` if the URL has no `/blob/`, `/resolve/`, or `/tree/` segment.
- The **filename** is the last segment of the file path.

## Step 3 — Decide the destination

**For ComfyUI** (the default — this is usually what the user wants):

Determine the ComfyUI models directory, in this order:
1. `COMFYUI_MODELS_DIR` in `~/.claude/skills-config.sh`, if set and non-empty.
2. `COMFYUI_WORKSPACE` in the same file → use `<COMFYUI_WORKSPACE>/models`.
3. A `models/` folder beside a known ComfyUI install.
4. If none can be found, ask the user.

Then pick the correct **subfolder** for the model type (table below). The final
destination is `<models-dir>/<subfolder>`.

**Not for ComfyUI:** just use whatever folder the user specifies.

### Model type → ComfyUI subfolder

| Model type | Subfolder |
|------------|-----------|
| Full checkpoint — SD1.5 / SDXL / Flux / etc. all-in-one | `checkpoints` |
| Standalone diffusion model / transformer / unet — Flux dev, LTX, Wan, Hunyuan, Qwen-Image, GGUF unet | `diffusion_models` |
| LoRA | `loras` |
| VAE | `vae` |
| Text encoder — T5 / UMT5 / CLIP-L or CLIP-G used as encoder / llava | `text_encoders` |
| CLIP | `clip` |
| CLIP vision | `clip_vision` |
| ControlNet | `controlnet` |
| IP-Adapter | `ipadapter` |
| Upscale model — ESRGAN, RealESRGAN, etc. | `upscale_models` |
| Style model | `style_models` |
| Textual inversion / embedding | `embeddings` |

If the model type is unclear, run `hfdownloader analyze <repo-id>`, read the
model card, or inspect the filename — and ask the user when still ambiguous.

## Step 4 — Dry-run first (always)

Append `--dry-run` to any download command before running it for real. Confirm
the plan lists exactly the file(s) you expect and the size looks right. Repos
can be huge — the dry-run is how you catch an accidental whole-repo pull.

## Step 5 — Download

### Single file (most common)

```
hfdownloader download <repo-id> -b <revision> -F <filename> -E .md,LICENSE,.gitattributes --legacy -o <destination-folder> --no-friendly --no-manifest -c 16
```

- `-F <filename>` — selects only LFS artifacts matching the name. Use the exact filename.
- `-E .md,LICENSE,.gitattributes` — drops repo boilerplate text files.
- `--legacy -o <dir>` — flat layout: the file lands exactly at `<dir>/<filename>`, regardless of its path inside the repo.
- `--no-friendly` — **important.** Without it, hfdownloader writes a *second full copy* of every file in a `<owner>/<repo>/` "friendly view" tree. On Windows that copy is real data, not a symlink — it doubles disk usage.
- `--no-manifest` — skips the stray `hfd.yaml` manifest file in the output folder.
- `-c 16` — 16 parallel connections (faster for large files).
- `-b <revision>` — branch/revision; omit if it is `main`.

### Whole repo

```
hfdownloader download <repo-id> --local-dir <ComfyUI-models-dir> -E .md,LICENSE,.gitattributes --no-friendly --no-manifest -c 16
```

`--local-dir` preserves the repo's internal folder layout. When a repo is
already organised with ComfyUI folder names (`diffusion_models/`, `loras/`,
`vae/`, `text_encoders/`, …) every file routes to the right place
automatically. Keep `--no-friendly` here too — otherwise every file is written
twice (see the single-file notes above). Dry-run first; if the repo is large,
narrow it with `-F`.

### Dataset

Add `--dataset` to any of the above.

## Step 6 — Verify

Confirm the file exists at the destination and its size matches the dry-run
plan. If a download is interrupted, just re-run the **same command** —
hfdownloader resumes from where it stopped.

## Authentication — gated / private models

`hfdownloader` automatically reads the `HF_TOKEN` environment variable; or pass
`-t <token>` explicitly. If a download fails with HTTP 401/403:

- The token is missing or lacks read access — get one at
  https://huggingface.co/settings/tokens (read scope is enough), **or**
- The user has not accepted the model's license — tell them to open the model's
  HuggingFace page and click **"Agree and access repository"** once. The token
  alone does not bypass an un-accepted license.

## Command cheat-sheet

| Command | Purpose |
|---------|---------|
| `hfdownloader version` | Check it is installed |
| `hfdownloader analyze <repo>` | Inspect repo type/structure — no download |
| `hfdownloader download <repo> --dry-run` | List planned files and sizes |
| `hfdownloader download <repo> ...` | Download |

Key flags: `-F` include (LFS name filter) · `-E` exclude patterns · `-b`
revision/branch · `-c` connections per file · `--max-active` concurrent files ·
`--local-dir` keep repo layout · `--legacy -o` flat into one dir · `--no-friendly`
skip the duplicate friendly-view copy (always use this) · `--no-manifest` skip
the `hfd.yaml` file · `--dataset` treat as dataset · `-t` token · `--dry-run`
plan only.

## Installation

Check first with `hfdownloader version`. If missing:

### Windows (PowerShell)

```powershell
$dir = "$env:USERPROFILE\bin"
New-Item -ItemType Directory -Force $dir | Out-Null
$url = (Invoke-RestMethod https://api.github.com/repos/bodaay/HuggingFaceModelDownloader/releases/latest).assets |
       Where-Object { $_.name -like "*windows_amd64*" } | ForEach-Object browser_download_url
Invoke-WebRequest $url -OutFile "$dir\hfdownloader.exe"
$p = [Environment]::GetEnvironmentVariable("Path","User")
if ($p -notlike "*$dir*") { [Environment]::SetEnvironmentVariable("Path", ($p.TrimEnd(';') + ";$dir"), "User") }
```

Open a **new** terminal, then verify with `hfdownloader version`.

### macOS / Linux

```bash
mkdir -p ~/.local/bin
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
URL=$(curl -s https://api.github.com/repos/bodaay/HuggingFaceModelDownloader/releases/latest | grep browser_download_url | grep "${OS}_${ARCH}" | head -1 | cut -d'"' -f4)
curl -sSL -o ~/.local/bin/hfdownloader "$URL" && chmod +x ~/.local/bin/hfdownloader
```

Ensure the install directory is on `PATH`, then verify with `hfdownloader version`.

## Web UI (optional)

`hfdownloader serve --addr 127.0.0.1 --port 8080` starts a browser UI at
http://localhost:8080 — handy for browsing and analyzing repos. Bind to
`127.0.0.1` (not the default `0.0.0.0`) so it is not exposed to the network.

**Caveat:** the web UI downloads into the HuggingFace cache (a blob + symlink
structure), **not** directly into ComfyUI folders. For placing models into
ComfyUI, always use the CLI workflow above.
