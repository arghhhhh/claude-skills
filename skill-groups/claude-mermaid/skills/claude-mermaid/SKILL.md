---
version: 1.0.0
name: claude-mermaid
description: Render Mermaid diagrams with a live-reload browser preview and export them to SVG/PNG/PDF. Use whenever the user wants to create, edit, preview, or save a diagram — flowcharts, node graphs, sequence/state/class/ER diagrams, mind maps, Gantt charts, or architecture and data-flow diagrams.
---

# Claude Mermaid

Render [Mermaid](https://mermaid.js.org/) diagrams through the `claude-mermaid` MCP server. It opens a live-reload browser preview that auto-refreshes every time you re-run the preview tool, then lets you export the result to a file.

## Tools

The MCP server exposes two tools (call them as native MCP tools — they appear as `mermaid_preview` and `mermaid_save`).

### `mermaid_preview`

Renders a diagram and opens/updates a live preview in the browser.

| Parameter | Required | Default | Notes |
|-----------|----------|---------|-------|
| `diagram` | yes | — | The Mermaid source code |
| `preview_id` | yes | — | Unique name for this preview, e.g. `"vfx-flow"`. Reuse the same id to update; use different ids for concurrent diagrams |
| `format` | no | `svg` | `svg`, `png`, or `pdf`. Only `svg` supports live reload — keep `svg` while iterating |
| `theme` | no | `default` | `default`, `forest`, `dark`, `neutral` |
| `background` | no | `white` | Color name or hex, e.g. `transparent`, `#1e1e1e` |
| `width` | no | `800` | Pixels |
| `height` | no | `600` | Pixels |
| `scale` | no | `2` | Quality multiplier for raster output |

### `mermaid_save`

Saves the current live diagram for a `preview_id` to a file.

| Parameter | Required | Default | Notes |
|-----------|----------|---------|-------|
| `save_path` | yes | — | Destination path, e.g. `./docs/architecture.svg` |
| `preview_id` | yes | — | Must match the id used in `mermaid_preview` |
| `format` | no | `svg` | `svg`, `png`, or `pdf` |

## Workflow

1. **Preview** — call `mermaid_preview` with the diagram and a descriptive `preview_id`. A browser tab opens at `http://localhost:3737/<preview_id>` showing the render.
2. **Iterate** — edit the `diagram` and call `mermaid_preview` again with the *same* `preview_id`. The open tab live-reloads; no need to reopen anything.
3. **Save** — once the user is happy, call `mermaid_save` with the same `preview_id` and a `save_path`. Ask the user where to save if they have not said.

Always preview before saving. Show the diagram, confirm it is correct, then export.

## Diagram types

Mermaid covers far more than flowcharts:

- `flowchart` / `graph` — node graphs, pipelines, architecture (best fit for node-based 3D tooling like Notch or Unity VFX Graph)
- `sequenceDiagram` — message/call flow over time
- `stateDiagram-v2` — state machines
- `classDiagram` — class/type relationships
- `erDiagram` — entity-relationship / data models
- `mindmap`, `gitGraph`, `gantt`, `timeline`, `quadrantChart`, `journey`

## Flowchart quick reference

```
flowchart LR
    A[Rectangle] --> B(Rounded)
    B --> C{Decision}
    C -->|yes| D[/Parallelogram/]
    C -->|no| E((Circle))
    D --> F[[Subroutine]]

    subgraph Group
        G[Node] --> H[Node]
    end

    A:::accent
    classDef accent fill:#5b8def,stroke:#fff,color:#fff
```

- Directions: `TD`/`TB` (top-down), `LR` (left-right), `RL`, `BT`.
- Edges: `-->` arrow, `---` line, `-.->` dotted, `==>` thick, `-->|label|` labelled.
- Group nodes with `subgraph <name> ... end` — useful for mirroring node-graph containers/contexts.
- Style with `classDef` + `:::class`, or inline `style <id> fill:#...`.

## Tips

- Quote node text that contains special characters: `A["text (with parens)"]`.
- For diagrams meant to sit on a dark page, use `theme:"dark"` with `background:"transparent"`.
- Export `svg` for docs/web (crisp, small), `png` for slides/chat, `pdf` for print.
- Bump `width`/`height` for large graphs so labels do not crowd; raise `scale` for sharper PNGs.
- Working files live in `~/.config/claude-mermaid/live`; logs in `~/.config/claude-mermaid/logs/`.

## Troubleshooting

- **`mermaid_preview` / `mermaid_save` tools are not available** — the MCP server is not registered, or Claude Code has not been restarted since it was added. Register it (user scope) and restart Claude Code:
  ```bash
  claude mcp add --scope user mermaid -- claude-mermaid
  # Windows fallback if the .cmd shim fails to start:
  claude mcp add --scope user mermaid -- node "$(npm root -g)/claude-mermaid/build/index.js"
  ```
  Confirm with `claude mcp list` — the `mermaid` entry should show **Connected**.
- **`claude-mermaid` command not found** — install it: `npm install -g claude-mermaid`.
- **First render is slow or fails to render** — the renderer downloads a headless Chromium (Puppeteer) on first use. Retry once; allow time/network.
- **Preview tab shows a red status dot** — the web server lost connection. Re-run `mermaid_preview`; the server reselects a free port in the range 3737–3747.
- **Syntax errors** — Mermaid is whitespace- and keyword-sensitive. Verify the first line names a valid diagram type and that node ids are alphanumeric.

## CLI fallback (mcporter)

If the native MCP tools are unavailable and you cannot restart, the server can be driven via mcporter once it is in `~/.mcporter/mcporter.json` (the installer adds it):

```bash
npx mcporter call mermaid.mermaid_preview preview_id:"flow" diagram:"flowchart LR
A --> B"
npx mcporter call mermaid.mermaid_save preview_id:"flow" save_path:"./diagram.svg"
```

Native MCP tool calls are strongly preferred — they handle multi-line diagram source cleanly.
