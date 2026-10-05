---
version: 1.1.1
name: capcut-cli
description: Programmatically edit CapCut / JianYing video drafts from the terminal via the `capcut` CLI. Use to inspect projects, build drafts from specs, add video/audio/text, apply transitions/masks/effects, import/export/translate subtitles, transcribe captions, and cut long-form video — all by reading and writing the local draft store directly (JSON in, JSON out, no server).
---

# capcut-cli — CapCut / JianYing draft editing from the CLI

Independent, unofficial CLI ([renezander030/capcut-cli](https://github.com/renezander030/capcut-cli)) that reads and writes CapCut/JianYing project JSON on disk. Every command loads the local draft, validates it against a version-aware schema, applies one edit, and writes it back **atomically with a `.bak`**. No MCP server, no HTTP daemon, no uploads.

## Critical rules

1. **Run `capcut doctor` first on a new machine/session** — verifies Node, ffmpeg/ffprobe, whisper, API key, and that CapCut/JianYing draft dirs exist.
2. **`<project>` is a draft folder path** (e.g. `./my-first/` or the CapCut draft dir), not a name — except `init`/`quickstart` which take a `<name>` and create the folder.
3. **JSON is the default output**; pipe to `jq`. Add **`-H`** for a human-readable table. JSON layout is stable for parsing; the `-H` table layout is not.
4. **Pass `--jianying`** to target the JianYing enum namespace instead of CapCut's. Enum slugs differ between the two.
5. **Mutating commands write in place** and leave a `.bak`. Use **`capcut restore <project> --list` / `--step N`** to undo. Confirm destructive ops (`prune`, `replace-media`, `migrate`) with the user first.
6. **CapCut must NOT have the project open** while you mutate it — the editor can overwrite your changes. Close CapCut, edit, then reopen. On CapCut ≥ 8.7 use `sync-timelines` to reconcile mirror files if they drift.
7. **This tool never renders CapCut's final output and never uploads.** `render` is a low-res ffmpeg *proxy* preview only. The human opens CapCut to review and export.
8. **Global safety flags:** `--dry-run` previews any mutating command (prints result with `"dryRun":true`, leaves draft and `.bak` untouched); `--force-write` overrides editor-running / changed-on-disk / version-boundary guards (only with user say-so); `--active-timeline` follows the `Timelines/project.json` pointer on an unverified build; `-q` silences success output.
9. **`capcut describe`** emits the full command surface as JSON (an agent tool spec) — use it to discover exact flags programmatically. `capcut <command> --help` gives per-command flags. `capcut enums <category> [--jianying]` lists valid slugs for transitions/masks/effects/etc.

## Command reference

`<id>` = segment or material id (get from `segments` / `materials` / `texts`). Times are seconds unless noted. `yes`/`no` = mutates the draft.

### Inspect (read-only)
| Command | Usage |
|---|---|
| `info` | `capcut info <project>` — overview + material summary |
| `version` | `capcut version <project>` — detect CapCut/JianYing version, schema flags, support status |
| `lint` | `capcut lint <project> [--fix] [--frame-grid] [--max-chars <n>] [--max-cue-secs <n>] [--min-gap-ms <n>] [--no-check-paths]` — overlaps, line length, main-track gaps, media outside draft, missing files; `--fix` repairs `fixable:true` issues; exit 0/1/2 for CI |
| `tracks` | `capcut tracks <project>` |
| `segments` | `capcut segments <project> [--track <type>]` — timing per segment |
| `texts` | `capcut texts <project>` — all text/subtitle content |
| `segment` | `capcut segment <project> <id>` — full detail for one segment + its material |
| `material` | `capcut material <project> <id>` |
| `materials` | `capcut materials <project> [--type <type>]` |
| `timeline` | `capcut timeline <project> [--cols <n>]` (`-H` for ASCII bars) |
| `projects` | `capcut projects [query] [--drafts <path>] [--names]` — list draft folders on disk |
| `diff` | `capcut diff <project-a> <project-b>` |
| `config` | `capcut config` — resolved `.capcutrc` + effective defaults |
| `describe` | `capcut describe` — full command surface as JSON (agent tool spec) |
| `enums` | `capcut enums <category-flag> [--jianying]` — list slugs (transitions, masks, effects, …) |
| `doctor` | `capcut doctor` — environment preflight |
| `diagnose` | `capcut diagnose <project> [--bundle <report.json>]` — canonical files, divergence, write safety |

### Create / build
| Command | Usage |
|---|---|
| `init` | `capcut init <name> [--template <dir>] [--drafts <dir>]` — new empty draft |
| `quickstart` | `capcut quickstart <name> [--video <f>] [--audio <f>] [--srt <f>] [--drafts <dir>]` — create + add one input + lint |
| `compile` | `capcut compile <spec.json> [--out <draftdir> \| --into <project>] [--data <rows.jsonl\|->] [--check \| --plan]` — build a draft from a declarative JSON spec (inverse of `describe`); `--data` builds one draft per JSONL row, substituting `{{key}}` placeholders |
| `init` / `quickstart` canvas | both accept `--ratio 16:9\|9:16\|1:1\|4:3\|3:4` or exact `--width <px> --height <px>` |

### Add media / elements (mutates)
| Command | Usage |
|---|---|
| `add-video` | `capcut add-video <project> <file-or-url> <start> [duration] [opts]` (Wikimedia URLs, license-checked) |
| `add-audio` | `capcut add-audio <project> <file-or-url> <start> [duration] [opts]` |
| `add-text` | `capcut add-text <project> <start> <duration> <text> [--font/--color/--position …]` |
| `add-sticker` | `capcut add-sticker <project> <resource-id> <start> <duration> [opts]` |
| `add-filter` | `capcut add-filter <project> <slug> <start> <duration> [opts]` |
| `add-effect` | `capcut add-effect <project> <slug> <start> <duration> [opts]` — scene effect on own track |
| `add-sfx` | `capcut add-sfx <project> <slug> <start> <duration> [opts]` |
| `tts` | `capcut tts <project> [start] [duration] (--text <s> \| --text-file <f>) --tts-cmd '<template>'` — local TTS → audio segment. Template runs without a shell: `{out}` required (wav path), `{text}` one arg or piped to stdin. macOS: `--tts-cmd 'say -o {out} {text}'` |
| `add-cover` | `capcut add-cover <project> <image> [--time <ms>]` |

### Edit / animate (mutates)
| Command | Usage |
|---|---|
| `set-text` | `capcut set-text <project> <id> <text>` |
| `shift` / `shift-all` | `capcut shift <project> <id> <offset>` · `capcut shift-all <project> <offset> [--track <type>]` (e.g. `+0.5s`) |
| `trim` | `capcut trim <project> <id> <start> <duration>` |
| `speed` | `capcut speed <project> <id> <multiplier>` |
| `volume` | `capcut volume <project> <id> <0.0-1.0>` |
| `opacity` | `capcut opacity <project> <id> <0.0-1.0>` |
| `audio-fade` | `capcut audio-fade <project> <id> [--in <s>] [--fade-out <s>]` |
| `keyframe` | `capcut keyframe <project> <id> <property> <time> <value> [--easing <name>] \| --batch` (position/scale/rotation/alpha/volume) |
| `transition` | `capcut transition <project> <id> <slug> [--duration <t>]` |
| `mask` | `capcut mask <project> <id> <slug> [geometry opts] \| --off` |
| `bg-blur` | `capcut bg-blur <project> <id> <1-4> \| --off` |
| `mix-mode` | `capcut mix-mode <project> <id> <mode>` — blend mode |
| `chroma` | `capcut chroma <project> <id> (--color <hex> \| --off) [opts]` — green-screen key |
| `text-style` | `capcut text-style <project> <id> [--alpha/--shadow/--border/--background …]` |
| `text-anim` / `image-anim` | `capcut text-anim <project> <id> [--intro/--outro/--combo …]` (same for `image-anim`) |
| `text-ranges` | `capcut text-ranges <project> <id> --styles <json-or-@file>` — byte-accurate multi-style ranges |
| `crop` | `capcut crop <project> <id> [--ratio free\|1:1\|16:9\|9:16\|4:3\|3:4 \| --rect x,y,w,h \| --reset]` — no flags = read-only print of crop struct |
| `duplicate` | `capcut duplicate <project> <id> [--track <name> \| --new-track]` — copy segment onto a track above itself (PIP retouch flow; mask the copy); material cloned with fresh ids |
| `matting` | `capcut matting <project> <id> [--off]` — smart "Remove background"; flag lives on the *material*, so segments sharing it change too |
| `restyle` | `capcut restyle <project> --preset <file> [--track-name <name>] [style flags]` — apply a preset atomically to all text segments or one caption track |
| `bubble-text` | `capcut bubble-text <project> <id> --bubble <slug>` |

### Templates & presets
| Command | Usage |
|---|---|
| `templates` | `capcut templates <project>` — list bundled reusable templates |
| `save-template` | `capcut save-template <project> <id> <name> --out <path>` |
| `apply-template` | `capcut apply-template <project> <template> <start> <duration> [text] [opts]` |
| `make-preset` | `capcut make-preset <project> <text-segment-id> --out <preset.json>` (apply via `--preset`) |

### Subtitles & i18n
| Command | Usage |
|---|---|
| `import-srt` | `capcut import-srt <project> <srt-or-> [opts]` — one text segment per cue |
| `import-ass` | `capcut import-ass <project> <ass-or-> [opts]` |
| `export-ass` | `capcut export-ass <project> [--karaoke] [--out <f.ass>]` — styled ASS (per-style lines, inline override tags, `{\k}` word timing with `--karaoke`) |
| `export-srt` | `capcut export-srt <project> [--granularity line\|word] [--format srt\|vtt]` → stdout |
| `caption` | `capcut caption <project> (--audio <path> \| --from-segment <id>) [opts]` — Whisper transcription into caption-track segments |
| `translate` | `capcut translate <project> --to <language> --out <path> [opts]` — clone draft into another language (Anthropic API) |

### Long-form → short, and batch
| Command | Usage |
|---|---|
| `cut` | `capcut cut <project> <start> <end> --out <path>` — extract a range into a new standalone draft |
| `detect-scenes` | `capcut detect-scenes <video> [opts]` — ffmpeg scene-cut detection; prints cuts to seed `compile`/`cut` |
| `detect-silence` | `capcut detect-silence <media> [--threshold-db <dB>] [--min-silence <s>] [--pad <s>] [--limit <n>]` — silence spans + complementary keep segments (s and µs); feed keeps to `compile`/`cut` to drop dead air. Detection only |
| `detect-retakes` | `capcut detect-retakes (<project> [--track-name <s>] \| --srt <file>) [--window <s>] [--similarity <0..1>] [--min-words <n>]` — repeated takes from caption cues; later take is the keeper, earlier spans are cuts. Detection only |
| `export-timeline` | `capcut export-timeline <project> [--out <f.otio>] [--captions markers]` — OpenTimelineIO export (DaVinci Resolve imports natively); exit ramp when the app rejects a draft |
| `import-timeline` | `capcut import-timeline <f.otio> (--out <dir> \| --into <project>)` — inverse; missing media becomes a placeholder to `replace-media` |
| `concat` | `capcut concat <project-a> <project-b> [--out <path>]` — append timeline (id-safe) |
| `batch` | `capcut batch <project> [--continue-on-error] < operations.jsonl` — many edits, one file write |
| `serve` | `capcut serve [--queue <path>] [opts]` — stateless JSONL job runner from stdin (for n8n/Make/Coze) |

### Maintenance / repair (mutates unless noted)
| Command | Usage |
|---|---|
| `prune` | `capcut prune <project>` — remove unreferenced materials |
| `relink` | `capcut relink <project> (--dir <path> \| --from <prefix> --to <prefix>)` — repair broken media paths |
| `replace-media` | `capcut replace-media <project> <segment-id> <new-file> [--retime]` — swap source, keep timing/effects/keyframes |
| `migrate` | `capcut migrate <project> --from <version> --to <version>` — schema migrations |
| `sync-timelines` | `capcut sync-timelines <project-dir> [--apply]` — reconcile drifted mirrors (CapCut ≥ 8.7); plan by default, `--apply` rewrites |
| `register` | `capcut register <project-dir> [--apply] [--materials] [--drafts <dir>]` — repair registration metadata (`draft_meta_info.json` + store `root_meta_info.json`) so CapCut lists an existing draft again; plan by default |
| `rename` | `capcut rename <project> <new-name> [--drafts <dir>]` — rename folder + metadata in one transaction; prints relink command for stale media refs |
| `harvest-enums` | `capcut harvest-enums (<project> \| --sync) [--apply] [--catalogue <path>]` / `--add <kind> <slug> <resource-id>` — learn store resource ids from app-authored drafts into `~/.config/capcut-cli/user-enums.json` so they stop lint-flagging and become writable slugs |
| `restore` | `capcut restore <project> [--step <n> \| --list]` — undo writes from `.bak`/snapshot history |
| `render` (read-only) | `capcut render <project> [--out <preview.mp4>] [--burn-captions …]` — low-res ffmpeg proxy, NOT CapCut's final render |
| `decrypt` (read-only) | `capcut decrypt <project-or-file>` — detect JianYing 6.0+ encryption + explain workaround |
| `fixture` (read-only) | `capcut fixture <project> --out <dir>` — redacted compatibility bundle for a bug report |
| `export` | `capcut export <drafts-dir> --batch [opts]` — ⚠ EXPERIMENTAL UI-automated render queue (macOS only) |
| `completions` (read-only) | `capcut completions <bash\|zsh\|fish>` |

## Typical workflow

```bash
capcut doctor                                   # 1. verify environment + draft dirs
capcut projects --names                         # 2. find a draft folder (or quickstart a new one)
capcut quickstart promo --video clip.mp4        #    -> creates ./promo/, adds clip, lints
capcut info ./promo/ -H                          # 3. inspect (table)
capcut segments ./promo/                         #    get segment ids for edits
capcut add-text ./promo/ 0 3 "Hello" --position bottom
capcut transition ./promo/ <seg-id> $(capcut enums --transitions | jq -r '.[0].slug')
capcut lint ./promo/                             # 4. validate before handing back
# human opens CapCut to review + render
```

## Gotchas

- **Draft dir must exist** — CapCut/JianYing create the drafts root on first launch. If `doctor` reports the dir missing, open the editor once or pass a path directly.
- **Editor race** — CapCut open on the same project can clobber your writes; and on ≥ 8.7 it keeps mirror files (`template-2.tmp`, `draft_info.json`) that must be reconciled with `sync-timelines`.
- **`caption` needs Whisper on PATH**; **`translate` needs `ANTHROPIC_API_KEY`** (or `--api-key`); **`render`/media metadata need ffmpeg/ffprobe**. `doctor` flags which are missing and which commands they affect.
- **JianYing 6.0+ drafts are encrypted** — `capcut decrypt` only detects and explains the workaround; it does not decrypt.
- **Slugs are namespace-specific** — always source them from `capcut enums <category> [--jianying]`, don't guess.
- **`render --soft-captions`** muxes cues as a toggleable `mov_text` stream (+ `<preview>.srt`); skipped if the ffmpeg build lacks `mov_text`. `doctor` reports `drawtext=false` on Homebrew ffmpeg → `--burn-captions` unavailable there; use `--soft-captions`.
- **Detect → cut pipeline:** `detect-scenes` / `detect-silence` / `detect-retakes` never touch a draft; they emit µs segment lists to feed `cut` or `compile`.
- **Unofficial tool** — schema support tracks specific CapCut/JianYing versions. Check `capcut version <project>` for support status; use `capcut fixture` to file a version-support issue.
