---
version: 1.2.0
name: gen-image
description: Generate and edit images from the command line via Google's Gemini image models (nano banana) or OpenAI's GPT Image models. Single-shot text-to-image, image editing, and style-referenced generation with aspect-ratio and resolution control. Use for quick AI image generation/editing without a ComfyUI workflow.
---

# gen-image — image generation CLI (Gemini + OpenAI)

Zero-dependency Node script. Sends a prompt (plus optional input images) to the Gemini or
OpenAI image API (provider inferred from model name), saves a PNG, prints the output path to stdout.

```bash
node ~/.claude/skills/gen-image/gen-image.mjs "PROMPT" -o out.png [--ar 16:9] [--size 2K] [-i ref.png]
node ~/.claude/skills/gen-image/gen-image.mjs -m gpt-image-2 -i photo.png -o out.png "edit prompt"
```

## Options

| Flag | Meaning | Default |
|---|---|---|
| `-o, --out <path>` | Output PNG path | `./gen-image-<timestamp>.png` |
| `-m, --model <id>` | Model (see table below); provider inferred from name | `gemini-3-pro-image` |
| `--ar <w:h>` | Aspect ratio: `1:1` `16:9` `9:16` `4:3` `3:4` `21:9` … OpenAI: mapped to nearest of square/landscape/portrait | `1:1` |
| `--size <1K\|2K\|4K>` | Resolution — **Gemini pro models only**, ignored elsewhere | `2K` |
| `--quality <q>` | **OpenAI only**: `low` `medium` `high` `auto` | `high` |
| `-i, --input <path>` | Input image (png/jpg/webp), repeatable | none |
| `--mask <path>` | **OpenAI only**: PNG mask, transparent areas = editable region | none |
| `--prompt-file <path>` | Read prompt from file (long prompts) | — |

## Models

| Model | Provider | Use for |
|---|---|---|
| `gemini-3-pro-image` | Gemini | Default. Highest Gemini quality, supports `--size`, ~10-30s |
| `gemini-3.1-flash-image` | Gemini | Faster/cheaper drafts and iterations |
| `gemini-2.5-flash-image` | Gemini | Legacy fallback |
| `gpt-image-2` | OpenAI | Top-ranked edit fidelity (Aug 2026). ⚠ If the account lacks access, API errors — fall back to `gpt-image-1` |
| `gpt-image-1` | OpenAI | Older GPT Image model, broad account access |
| `codex` | Codex CLI | Same gpt-image quality, billed to the logged-in **ChatGPT subscription** (no API key/credits). Needs `npm i -g @openai/codex` + `codex login` (ChatGPT auth). Slower (agent round-trip); driver model `gpt-5.5` (override: `CODEX_MODEL` env). ✅ Verified: edits with input images work |

## API keys

Resolution order per provider (first hit wins):

1. `GOOGLE_API_KEY` / `OPENAI_API_KEY` env var (machine-level — the normal setup)
2. Same-named line in a `.env`, searched cwd → upward (per-project override)
3. `~/.claude/.google-api-key` / `~/.claude/.openai-api-key` (file containing only the key)

Missing key → the script exits with an error listing these options. Never commit keys;
if a project carries a `.env`, verify it is gitignored before writing to it.

## Recipes

```bash
S=~/.claude/skills/gen-image/gen-image.mjs

# text-to-image
node $S "a lighthouse in fog, cinematic, no text" -o light.png --ar 16:9

# edit an existing image (keep everything, change one thing)
node $S -i photo.png -o photo2.png "Edit this image: remove the car on the left. Keep everything else exactly as it is. No text, no watermarks."

# style/product reference (design consistency across generations)
node $S -i product-ref.png -o scene.png "Using the attached photo as the exact product design reference, show the product in a busy cafe."

# multiple refs (style + content)
node $S -i style.webp -i subject.png -o out.png "Render the subject in the style of the first image."

# OpenAI edit with the same interface
node $S -m gpt-image-2 -i photo.png -o out.png --ar 4:3 "Replace the storefront window contents with artwork. Keep everything else identical."

# OpenAI masked edit (transparent mask areas get regenerated, rest is preserved)
node $S -m gpt-image-2 -i photo.png --mask mask.png -o out.png "Fill the masked windows with vibrant murals."

# Subscription-billed via Codex CLI (no API key; slower — allow ~1-3 min)
node $S -m codex -i photo.png -o out.png --ar 4:3 "Replace the green-masked windows with artwork. Keep everything else identical."
```

## Behavior notes (verified in practice)

- **Editing preserves untouched regions well** (Gemini) — chains of "remove X, keep everything else"
  edits (each output as the next input) work; people/objects survive edit passes intact.
- Gemini edits regenerate the WHOLE image — for strict preservation, mask the editable
  region in solid chroma green in the input and prompt "replace only the green regions".
- Prompts ending with "no text, no watermarks" reliably suppress stray lettering.
- Gemini sometimes returns text alongside the image — printed to stderr as `model says:`.
- Output is always PNG regardless of extension. Convert/compress afterwards
  (e.g. `magick out.png -resize 2000x -quality 82 out.webp`).
- `--size` on a non-pro model is silently dropped (harmless).
- OpenAI output caps at 1536px on the long edge (1024x1024 / 1536x1024 / 1024x1536);
  upscale afterwards if larger output is needed.
- Stderr shows the resolved provider/model/params before the request; stdout is only the
  output path, so `OUT=$(node $S ...)` scripts cleanly.
