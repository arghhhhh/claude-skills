---
version: 1.1.0
---

# HuggingFace Downloader Skill

Use this skill whenever the user wants to download a model, checkpoint, LoRA,
VAE, text encoder, dataset, or any file from HuggingFace — especially to install
models into ComfyUI. The user will usually just paste a `huggingface.co` link
and say something like "grab this model".

`hfdownloader` is a fast, resumable, multi-connection downloader for HuggingFace
repos. Prefer it over `git clone` or `huggingface-cli` — it is faster and
resumes cleanly after interruptions.

## Critical thing to know about output layout

`hfdownloader download` **always writes files into a `<owner>/<repo>/` subtree**,
never straight into your target folder. With `--local-dir DIR`, a repo file at
internal path `P` lands at:

```
DIR/<owner>/<repo>/P
```

So you **always** download into a staging location and then **move** the file(s)
to their final name. There is no flag that places a file flat — `--legacy -o`
behaves the same as `--local-dir`. (hfdownloader *can* also build a flat
"friendly view", but on Windows that view is a full second copy of every file,
doubling disk use — so this skill disables it with `--no-friendly` and moves
files manually instead.)

## Quick example (the common case)

User: *"grab this model:
`https://huggingface.co/Kijai/LTX2.3_comfy/blob/main/diffusion_models/ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors`"*

1. Parse → repo `Kijai/LTX2.3_comfy`, revision `main`, file
   `diffusion_models/ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors`.
2. Model type = standalone diffusion model → ComfyUI folder `diffusion_models`.
3. Dry-run, then download (staging into the destination folder itself):

```
hfdownloader download Kijai/LTX2.3_comfy -F ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors -E .md,LICENSE,.gitattributes --local-dir <COMFYUI_MODELS_DIR>/diffusion_models --no-friendly --no-manifest -c 16 --dry-run
```

4. The file lands at
   `<COMFYUI_MODELS_DIR>/diffusion_models/Kijai/LTX2.3_comfy/diffusion_models/ltx-2.3-22b-...v3.safetensors`.
5. Move it to `<COMFYUI_MODELS_DIR>/diffusion_models/ltx-2.3-22b-...v3.safetensors`
   and delete the leftover `<COMFYUI_MODELS_DIR>/diffusion_models/Kijai/` folder.

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

- **Revision** defaults to `main` if the URL has no `/blob/`, `/resolve/`, or `/tree/` segment. Pass it with `-b <rev>` only when it is not `main`.
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

Append `--dry-run` to the download command before running it for real. Confirm
the plan lists exactly the file(s) you expect and the sizes look right. Repos
can be huge — the dry-run is how you catch an accidental whole-repo pull, and it
shows each file's repo-internal path (which tells you where it will land).

## Step 5 — Download

Stage the download **into the destination folder itself** so the later move is
on the same drive (instant). The command is the same for one file or several:

```
hfdownloader download <repo-id> -b <revision> -F <filename> -E .md,LICENSE,.gitattributes --local-dir <destination-folder> --no-friendly --no-manifest -c 16
```

- `-F <filename>` — include filter. **Matches the file's basename only, not its
  path.** Use the exact filename. If several wanted files share a basename, one
  `-F` grabs them all (that is fine — see Step 6).
- `-E .md,LICENSE,.gitattributes` — drops repo boilerplate. Add more patterns
  (`.json,.pth,.txt`, …) to exclude auxiliary files you do not want.
- `--local-dir <destination-folder>` — staging root. Files arrive under
  `<destination-folder>/<owner>/<repo>/...`.
- `--no-friendly` — skip the friendly-view copy (it would double disk usage on Windows).
- `--no-manifest` — skip the stray `hfd.yaml` file.
- `-c 16` — 16 parallel connections (faster for large files).
- For a **whole repo**, omit `-F`. For a **dataset**, add `--dataset`.

For large downloads, run this in the background and continue once it completes.

## Step 6 — Place the file(s) and clean up

After the download, each file sits at
`<destination-folder>/<owner>/<repo>/<repo-internal-path>`. Move every wanted
file to its final name directly in `<destination-folder>`, then delete the
leftover `<destination-folder>/<owner>/` tree.

Naming:
- If the file's basename is already descriptive, keep it.
- If it is generic (`diffusion_pytorch_model.safetensors`, `model.safetensors`,
  `pytorch_model.bin`), rename it to something descriptive built from the repo
  name, e.g. `wan2.2_vace_fun_a14b_high_noise.safetensors`.
- If you downloaded **multiple files that share a basename** (common when a repo
  has `high_noise_model/` and `low_noise_model/` subfolders), they MUST get
  distinct names or they will overwrite each other.

Example (PowerShell, moving two same-named files to distinct names):

```powershell
$d = "<destination-folder>"
Move-Item "$d\alibaba-pai\Wan2.2-VACE-Fun-A14B\high_noise_model\diffusion_pytorch_model.safetensors" "$d\wan2.2_vace_fun_a14b_high_noise.safetensors"
Move-Item "$d\alibaba-pai\Wan2.2-VACE-Fun-A14B\low_noise_model\diffusion_pytorch_model.safetensors"  "$d\wan2.2_vace_fun_a14b_low_noise.safetensors"
Remove-Item "$d\alibaba-pai" -Recurse -Force
```

## Step 7 — Verify

Confirm each final file exists and its size matches the dry-run plan (compare
exact byte counts). Report the final paths to the user. If a download is
interrupted, just re-run the **same Step 5 command** — hfdownloader resumes from
where it stopped.

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
| `hfdownloader download <repo> ... --dry-run` | List planned files and sizes |
| `hfdownloader download <repo> ...` | Download |

Key flags: `-F` include filter (matches **basename** of LFS artifacts) · `-E`
exclude patterns · `-b` revision/branch · `-c` connections per file ·
`--max-active` concurrent files · `--local-dir DIR` stage into
`DIR/<owner>/<repo>/...` · `--no-friendly` skip the duplicate friendly-view copy
(always use) · `--no-manifest` skip the `hfd.yaml` file · `--dataset` treat as
dataset · `-t` token · `--dry-run` plan only.

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

### After installing — always tell the user about the token

Whenever you install or first set up `hfdownloader` for the user (or run the
skill-repo installer), **proactively inform the user** that gated or private
HuggingFace models need an access token, and how to set it:

> Gated/private models (Llama, Gemma, etc.) need a HuggingFace token. Create one
> with **read** access at https://huggingface.co/settings/tokens, then set it
> once:
> - **Windows:** `[Environment]::SetEnvironmentVariable("HF_TOKEN", "hf_xxx", "User")` (open a new terminal afterward)
> - **macOS/Linux:** add `export HF_TOKEN="hf_xxx"` to `~/.bashrc` or `~/.zshrc`
>
> Public models download fine without a token.

Do this even if the current download target is public — the user should know
before they hit their first gated model.

## Web UI (optional)

`hfdownloader serve --addr 127.0.0.1 --port 8080` starts a browser UI at
http://localhost:8080 — handy for browsing and analyzing repos. Bind to
`127.0.0.1` (not the default `0.0.0.0`) so it is not exposed to the network.

**Caveat:** the web UI downloads into the HuggingFace cache (a blob + symlink
structure), **not** directly into ComfyUI folders. For placing models into
ComfyUI, always use the CLI workflow above.
