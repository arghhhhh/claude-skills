---
version: 1.4.0
name: capcut-cli
description: Programmatically edit CapCut / JianYing video drafts from the terminal via the `capcut` CLI. Use to inspect projects, build drafts from specs, add video/audio/text, apply transitions/masks/effects, import/export/translate subtitles, transcribe captions, and cut long-form video — all by reading and writing the local draft store directly (JSON in, JSON out, no server).
---

# capcut-cli — CapCut / JianYing draft editing from the CLI

Independent, unofficial CLI ([renezander030/capcut-cli](https://github.com/renezander030/capcut-cli)) that reads and writes CapCut/JianYing project JSON on disk. Every command loads the local draft, validates it against a version-aware schema, applies one edit, and writes it back **atomically with a `.bak`**. No MCP server, no HTTP daemon. Nothing leaves the machine except the opt-in cloud flags and `translate` (see rule 7). Documented against **capcut-cli 0.37.1**.

## Critical rules

1. **Run `capcut doctor` first on a new machine/session** — verifies Node, ffmpeg/ffprobe, whisper, API key, and that CapCut/JianYing draft dirs exist.
2. **`<project>` is a draft folder path** (e.g. `./my-first/` or the CapCut draft dir), not a name — except `init`/`quickstart` which take a `<name>` and create the folder.
3. **JSON is the default output**; pipe to `jq`. Add **`-H`** for a human-readable table. JSON layout is stable for parsing; the `-H` table layout is not.
4. **Pass `--jianying`** to target the JianYing enum namespace instead of CapCut's. Enum slugs differ between the two.
5. **Mutating commands write in place** and leave a `.bak`. Use **`capcut restore <project> --list` / `--step N`** to undo. Confirm destructive ops (`prune`, `replace-media`, `migrate`) with the user first.
6. **CapCut must NOT have the project open** while you mutate it — the editor can overwrite your changes. Close CapCut, edit, then reopen. On CapCut ≥ 8.7 use `sync-timelines` to reconcile mirror files if they drift.
7. **This tool never renders CapCut's final output and never publishes.** `render` is a low-res ffmpeg *proxy* preview only. The human opens CapCut to review and export. **Data-egress exceptions, all opt-in:** `caption --cloud` uploads the audio to ByteDance's CapCut servers; `caption --translate <lang>` and `translate --cloud` send caption/text content there; `translate` without `--cloud` sends text to the Anthropic API. The ByteDance paths are experimental and unofficial. Ask the user before using any of them, and default to local Whisper / `--words`.
8. **Global safety flags:** `--dry-run` previews any mutating command (prints result with `"dryRun":true`, leaves draft and `.bak` untouched); `--force-write` overrides editor-running / changed-on-disk / version-boundary guards (only with user say-so); `--active-timeline` follows the `Timelines/project.json` pointer on an unverified build; `-q` silences success output.
9. **`capcut describe`** emits the full command surface as JSON (an agent tool spec). `describe --compact` gives a short discovery index and `describe --command <name>` gives one command's contract. Use them to discover exact flags programmatically. `capcut <command> --help` gives per-command flags. `capcut enums <category> [--jianying]` lists valid slugs for transitions/masks/effects/etc.

## Command reference

`<id>` = segment or material id (get from `segments` / `materials` / `texts`). Times are seconds unless noted. `yes`/`no` = mutates the draft.

### Inspect (read-only)
| Command | Usage |
|---|---|
| `info` | `capcut info <project>` — overview + material summary |
| `version` | `capcut version <project>` — detect CapCut/JianYing version, schema flags, support status |
| `lint` | `capcut lint <project> [--fix] [--frame-grid] [--max-chars <n>] [--max-cue-secs <n>] [--min-gap-ms <n>] [--max-cps <n>] [--safe-area] [--max-still-secs <n>] [--max-shot-secs <n>] [--min-silent-secs <n>] [--pip] [--no-check-paths] [--no-probe]` — overlaps, line length, main-track gaps, media outside draft, missing files, over-long stills/shots, silent stretches; `--fix` repairs `fixable:true` issues; exit 0/1/2 for CI |
| `tracks` | `capcut tracks <project>` |
| `segments` | `capcut segments <project> [--track <type>]` — timing per segment |
| `texts` | `capcut texts <project>` — all text/subtitle content |
| `segment` | `capcut segment <project> <id>` — full detail for one segment + its material |
| `material` | `capcut material <project> <id>` |
| `materials` | `capcut materials <project> [--type <type>]` |
| `timeline` | `capcut timeline <project> [--cols <n>]` (`-H` for ASCII bars) |
| `projects` | `capcut projects [query] [--drafts <path>] [--names]` — list draft folders on disk |
| `diff` | `capcut diff <project-a> (<project-b> \| --since-write)` — `--since-write` shows what the CapCut app changed since capcut-cli's last write |
| `config` | `capcut config` — resolved `.capcutrc` + effective defaults |
| `describe` | `capcut describe [--compact] [--command <name>]` — full command surface as JSON (agent tool spec) |
| `catalogue` | `capcut catalogue <query> [--kind <category>] [--limit <n>] [--jianying]` — fuzzy-find a resource id/slug by name across every category (filters, bubbles, fonts, harvested entries) |
| `enums` | `capcut enums <category-flag> [--jianying]` — list slugs (transitions, masks, effects, …) |
| `doctor` | `capcut doctor [--drafts <dir>]` — environment preflight (Node, ffmpeg/ffprobe, whisper, TTS, API key, draft stores) |
| `diagnose` | `capcut diagnose <project> [--bundle <report.json>]` — canonical files, divergence, write safety |

### Create / build
| Command | Usage |
|---|---|
| `init` | `capcut init <name> [--template auto\|bundled\|<dir>] [--drafts <dir>]` — new empty draft |
| `quickstart` | `capcut quickstart <name> [--video <f>] [--audio <f>] [--srt <f>] [--drafts <dir>]` — create + add one input + lint |
| `compile` | `capcut compile <spec.json> [--out <draftdir> \| --into <project>] [--data <rows.jsonl\|->] [--check \| --plan]` — build a draft from a declarative JSON spec (inverse of `describe`); `--data` builds one draft per JSONL row, substituting `{{key}}` placeholders |
| `init` / `quickstart` canvas | both accept `--ratio 16:9\|9:16\|1:1\|4:3\|3:4` or exact `--width <px> --height <px>` |

### Add media / elements (mutates)
| Command | Usage |
|---|---|
| `add-video` | `capcut add-video <project> <file-or-url> <start> [duration] [opts]` (Wikimedia URLs, license-checked) |
| `add-audio` | `capcut add-audio <project> <file-or-url> <start> [duration] [opts]` |
| `add-text` | `capcut add-text <project> <start> <duration> <text> [--font-size <n>] [--color <hex>] [--align 0\|1\|2] [--x <-1..1>] [--y <-1..1>] [--track-name <s>] [--preset <file>]` — there is no `--position`/`--font` flag; place with `--x/--y` (`--y -0.8` ≈ bottom) |
| `add-sticker` | `capcut add-sticker <project> <resource-id> <start> <duration> [opts]` |
| `add-filter` | `capcut add-filter <project> <slug-or-name> (<start> <duration> \| --full) [--intensity 0-1] [--resource-id <id> [--effect-id <id>]] [--track-name <s>]` |
| `add-effect` | `capcut add-effect <project> <slug-or-name> (<start> <duration> \| --full) [--intensity 0-1] [--params <json>] [--resource-id <id>] [--bind <segment-id>]` — scene effect on own track; `--bind` (experimental) attaches to one segment |
| `add-sfx` | `capcut add-sfx <project> <slug> <start> <duration> [opts]` |
| `tts` | `capcut tts <project> [start] [duration] (--text <s> \| --text-file <f>) --tts-cmd '<template>'` — local TTS → audio segment. Template runs without a shell: `{out}` required (wav path), `{text}` one arg or piped to stdin. e.g. `--tts-cmd 'piper --model en_US-amy-medium --output_file {out}'`, `'espeak-ng -w {out} {text}'`, macOS `'say -o {out} {text}'`. `--lexicon <file>` applies pronunciation rules |
| `dub` | `capcut dub <project> <subs.srt\|.vtt> --tts-cmd '<template>' [--lexicon <f>] [--trim-overlap] [--volume <n>] [--track-name <s>]` — one TTS clip per cue, placed at the cue start. Speech that runs into the next cue (or an existing segment) is refused unless `--trim-overlap` cuts it there. Same `--tts-cmd` template as `tts` |
| `add-cover` | `capcut add-cover <project> <image> [--time <ms>]` |

### Edit / animate (mutates)
| Command | Usage |
|---|---|
| `set-text` | `capcut set-text <project> <id> <text>` |
| `shift` / `shift-all` | `capcut shift <project> <id> <offset>` · `capcut shift-all <project> <offset> [--track <type>] [--from <time>]` (e.g. `+0.5s`; `--from` shifts only segments at/after that boundary) |
| `remove` | `capcut remove <project> <segment-id> [--keep-track] [--keep-materials] [--ripple]` — delete a segment, drop its emptied track, sweep orphaned materials; `--ripple` closes the gap across all tracks |
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
| `import-srt` | `capcut import-srt <project> <srt-or-> [--track-name <s>] [--time-offset <s>] [--style-ref <seg-id> \| --clone-style] [style flags] [--highlight-words <w,…\|@file>] [--keyword-color <hex>] [--color-cycle <hex,…>]` — one text segment per cue. SRT or WebVTT (detected by the `WEBVTT` header); non-UTF-8 input is refused |
| `import-ass` | `capcut import-ass <project> <ass-or-> [opts]` |
| `export-ass` | `capcut export-ass <project> [--karaoke] [--out <f.ass>]` — styled ASS (per-style lines, inline override tags, `{\k}` word timing with `--karaoke`) |
| `export-srt` | `capcut export-srt <project> [--granularity line\|word] [--format srt\|vtt]` → stdout |
| `caption` | `capcut caption <project> (--audio <path> \| --from-segment <id> \| --words <file.json\|->) [opts]` — Whisper transcription into caption-track segments. `--words` takes word timings from any aligner (no Whisper needed). `--script <file>` keeps Whisper timing but uses your transcript's wording. Also `--karaoke`, `--word-reveal`, `--max-chars`, `--max-words`, `--highlight-words`, `--preset`/`--style-ref`, `--language`, `--whisper-model`. The transcript is cached, so restyling doesn't re-transcribe (`--no-cache` to force). ⚠ `--cloud` / `--translate` send data to ByteDance (rule 7) |
| `translate` | `capcut translate <project> --to <language> --out <path> [--from <lang>] [--model <id>] [--api-key <k>] [--cloud]` — clone draft into another language via the Anthropic API, or ByteDance with `--cloud` (no key, experimental) |

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
| `batch` | `capcut batch <project> [--continue-on-error] [--plan <plan.json>] < operations.jsonl` · `capcut batch <project> --apply-plan <plan.json>` — many edits, one file write; `--plan` saves a reviewable plan to apply later |
| `serve` | `capcut serve [--queue <path>] [--fail-fast] [--workers <n>] [--retries <n>] [--timeout <s>]` — stateless JSONL job runner from stdin (for n8n/Make/Coze) |

### Maintenance / repair (mutates unless noted)
| Command | Usage |
|---|---|
| `prune` | `capcut prune <project>` — remove unreferenced materials |
| `relink` | `capcut relink <project> (--dir <path> [--recursive] \| --from <prefix> --to <prefix>) [--stage]` — repair broken media paths; `--stage` copies relinked video/audio into the draft's `assets/` so it is portable |
| `replace-media` | `capcut replace-media <project> <segment-id> <new-file> [--retime]` — swap source, keep timing/effects/keyframes |
| `migrate` | `capcut migrate <project> (--from <version> --to <version> \| --like <project> \| --from-store)` — schema migrations (mask ↔ common_masks across JianYing 5.9 / CapCut 9.6); `--like <donor>` / `--from-store` copy schema markers from an app-authored draft so a build that refuses a CLI-made draft opens it |
| `sync-timelines` | `capcut sync-timelines <project-dir> [--nested] [--apply]` — reconcile drifted mirrors (CapCut ≥ 8.7); plan by default, `--apply` rewrites |
| `register` | `capcut register <project-dir> [--apply] [--materials] [--drafts <dir>]` — repair registration metadata (`draft_meta_info.json` + store `root_meta_info.json`) so CapCut lists an existing draft again; plan by default |
| `rename` | `capcut rename <project> <new-name> [--drafts <dir>]` — rename folder + metadata in one transaction; prints relink command for stale media refs |
| `harvest-enums` | `capcut harvest-enums (<project> \| --sync) [--apply] [--catalogue <path>]` / `--add <kind> <slug> <resource-id>` — learn store resource ids from app-authored drafts into `~/.config/capcut-cli/user-enums.json` so they stop lint-flagging and become writable slugs |
| `restore` | `capcut restore <project> [--step <n> \| --list]` — undo writes from `.bak`/snapshot history |
| `loudness` | `capcut loudness <project> [--target <lufs>] [--per-clip] [--max-gain-db <db>] [--apply] [--tolerance <lu>] [--max-true-peak <dbtp>]` — EBU R128 measure of the timeline's audio; `--target -14` (long-form) / `-11` (shorts) computes gain, `--apply` writes it as segment volume (mutates only with `--apply`); `--tolerance`/`--max-true-peak` make it a delivery gate (exit 1). Needs ffmpeg |
| `render` (read-only) | `capcut render <project> [--out <preview.mp4>] [--scale <f>] [--fps <n>] [--burn-captions \| --soft-captions] [--all-video-tracks] [--crf <n> \| --video-bitrate <r>] [--encoder <c>] [--audio-track <n>] [--audio-channel left\|right\|mix] [--strict] [--verify]` — low-res ffmpeg proxy, NOT CapCut's final render. `--audio-track` picks the stream of multi-stream audio files (0-based); `--audio-channel` plays one stereo channel as mono |
| `decrypt` (read-only) | `capcut decrypt <project-or-file>` — detect JianYing 6.0+ encryption + explain workaround |
| `fixture` (read-only) | `capcut fixture <project> --out <dir> [--anonymize] [--check]` — redacted compatibility bundle for a bug report; `--anonymize` also scrubs media/folder/project names and texts |
| `export` | `capcut export <drafts-dir> --batch [--app capcut\|jianying]` — ⚠ EXPERIMENTAL UI-automated render queue (macOS only) |
| `completions` (read-only) | `capcut completions <bash\|zsh\|fish>` |

## Typical workflow

```bash
capcut doctor                                   # 1. verify environment + draft dirs
capcut projects --names                         # 2. find a draft folder (or quickstart a new one)
capcut quickstart promo --video clip.mp4        #    -> creates ./promo/, adds clip, lints
capcut info ./promo/ -H                          # 3. inspect (table)
capcut segments ./promo/                         #    get segment ids for edits
capcut add-text ./promo/ 0 3 "Hello" --y -0.8      # x/y in -1..1
capcut transition ./promo/ <seg-id> $(capcut enums --transitions | jq -r '.[0].slug')
capcut loudness ./promo/ --target -14            #    optional: check delivery loudness (add --apply)
capcut lint ./promo/                             # 4. validate before handing back
# human opens CapCut to review + render
```

## Gotchas

- **Draft dir must exist** — CapCut/JianYing create the drafts root on first launch. If `doctor` reports the dir missing, open the editor once or pass a path directly.
- **Editor race** — CapCut open on the same project can clobber your writes; and on ≥ 8.7 it keeps mirror files (`template-2.tmp`, `draft_info.json`) that must be reconciled with `sync-timelines`.
- **`caption` needs Whisper on PATH** (or pass `--words <aligner.json>`, or `import-srt` an existing SRT); **`translate` needs `ANTHROPIC_API_KEY`** (or `--api-key`); **`render`/media metadata need ffmpeg/ffprobe**. `tts` needs a local TTS binary (piper/espeak-ng/say) via `--tts-cmd`. `doctor` flags which are missing and which commands they affect.
- **JianYing 6.0+ drafts are encrypted** — `capcut decrypt` only detects and explains the workaround; it does not decrypt.
- **Slugs are namespace-specific** — always source them from `capcut enums <category> [--jianying]`, don't guess.
- **`render --soft-captions`** muxes cues as a toggleable `mov_text` stream (+ `<preview>.srt`); skipped if the ffmpeg build lacks `mov_text`. `doctor` reports `drawtext=false` on Homebrew ffmpeg → `--burn-captions` unavailable there; use `--soft-captions`.
- **Detect → cut pipeline:** `detect-scenes` / `detect-silence` / `detect-retakes` never touch a draft; they emit µs segment lists to feed `cut` or `compile`.
- **`render` exit codes (0.37+):** audio is padded to the timeline, and a proxy whose probed duration misses the draft's by more than one frame **exits non-zero** (file kept). Main-track gaps and music/captions past the last clip are held to what the proxy plays (a stderr note; an error only with `--verify`). Scripts that run `render` under `set -e` can now stop there.
- **`render --burn-captions` and fonts:** each caption uses its draft font file when it exists (.ttf/.otf/.ttc); a missing one falls back to ffmpeg's default face and is counted in `fidelity.dropped.missing_fonts` (not `faithful`). `--strict` refuses instead.
- **App versions (0.37.1):** CapCut 9.5.0 round-trip verified; **9.8.0 untested** (a compiled draft opens, no round trip yet). JianYing 11.x is write-only (see `capcut version`).
- **Subtitle input:** `import-srt`, `quickstart --srt`, `detect-retakes --srt`, `compile` captions and `dub` all accept WebVTT too.
- **Unofficial tool** — schema support tracks specific CapCut/JianYing versions. Check `capcut version <project>` for support status; use `capcut fixture` to file a version-support issue.
- **Finding slugs by name:** `capcut catalogue "glitch"` searches every category at once, harvested store items included. Use it before guessing an `enums` category.
- **Removing vs pruning:** `remove` deletes one segment and sweeps its orphans. `prune` sweeps orphans only. Both can be undone with `restore`.
