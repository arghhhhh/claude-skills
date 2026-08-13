---
version: 1.0.0
name: gen-image
description: Generate and edit images from the command line via Google's Gemini image models (nano banana). Single-shot text-to-image, image editing, and style-referenced generation with aspect-ratio and resolution control. Use for quick AI image generation/editing without a ComfyUI workflow.
---

# gen-image — Gemini (nano banana) image generation CLI

Zero-dependency Node script. Sends a prompt (plus optional input images) to the Gemini image
API, saves a PNG, prints the output path to stdout.

```bash
node ~/.claude/skills/gen-image/gen-image.mjs "PROMPT" -o out.png [--ar 16:9] [--size 2K] [-i ref.png]
```

## Options

| Flag | Meaning | Default |
|---|---|---|
| `-o, --out <path>` | Output PNG path | `./gen-image-<timestamp>.png` |
| `-m, --model <id>` | Model (see table below) | `gemini-3-pro-image` |
| `--ar <w:h>` | Aspect ratio: `1:1` `16:9` `9:16` `4:3` `3:4` `21:9` … | `1:1` |
| `--size <1K\|2K\|4K>` | Resolution — **pro models only**, ignored by flash | `2K` |
| `-i, --input <path>` | Input image (png/jpg/webp), repeatable | none |
| `--prompt-file <path>` | Read prompt from file (long prompts) | — |

## Models

| Model | Use for |
|---|---|
| `gemini-3-pro-image` | Default. Highest quality, supports `--size`, ~10-30s |
| `gemini-3.1-flash-image` | Faster/cheaper drafts and iterations |
| `gemini-2.5-flash-image` | Legacy fallback |

## API key

Resolution order (first hit wins):

1. `GOOGLE_API_KEY` env var (machine-level — the normal setup)
2. `GOOGLE_API_KEY=` line in a `.env`, searched cwd → upward (per-project override)
3. `~/.claude/.google-api-key` (file containing only the key)

Missing key → the script exits with an error listing these options. Never commit the key;
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
```

## Behavior notes (verified in practice)

- **Editing preserves untouched regions well** — chains of "remove X, keep everything else"
  edits (each output as the next input) work; people/objects survive edit passes intact.
- Prompts ending with "no text, no watermarks" reliably suppress stray lettering.
- The model sometimes returns text alongside the image — printed to stderr as `model says:`.
- Output is always PNG regardless of extension. Convert/compress afterwards
  (e.g. `magick out.png -resize 2000x -quality 82 out.webp`).
- `--size` on a flash model is silently dropped (harmless).
- Stderr shows the resolved model/ar/size before the request; stdout is only the output path,
  so `OUT=$(node $S ...)` scripts cleanly.
