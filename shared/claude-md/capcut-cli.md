## CapCut CLI - Video Draft Editing & Automation

When the user wants to programmatically edit a CapCut or JianYing (剪映) video project — inspect a draft, build one from a spec, add video/audio/text, apply transitions/masks/effects/filters, import/export/translate subtitles, transcribe captions with Whisper, cut long-form video into shorts, or repair/relink/prune a draft — read `~/.claude/skills/capcut-cli.md`, or use the `capcut` agent.

Driver is the `capcut` CLI ([renezander030/capcut-cli](https://github.com/renezander030/capcut-cli), `npm install -g capcut-cli`), a zero-dependency Node tool that reads and writes the local CapCut/JianYing draft JSON directly — JSON in, JSON out, no server, no uploads. It never renders CapCut's final output (only a low-res ffmpeg proxy) and never uploads — the human opens CapCut to review and export.

Trigger phrases: "capcut", "capcut-cli", "jianying", "剪映", "draft_content.json", "video draft", "add subtitle to video", "import srt", "export srt", "transcribe captions", "cut long-form video", "video transitions", "chroma key", "green screen"
