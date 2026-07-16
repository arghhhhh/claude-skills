---
version: 1.0.0
name: wireviz
description: Author and render wiring / cable harness diagrams from plain-text YAML using the WireViz CLI. Use when documenting connector pinouts, cable colors, and point-to-point wiring for electronics and test benches.
---

# WireViz CLI Skill

Use this skill to author and render **wiring / cable harness diagrams** from plain-text YAML using the `wireviz` CLI (WireViz 0.4.x). Great for documenting connector pinouts, cable colors, and point-to-point wiring for electronics and test benches.

## Setup

- **Binary**: `wireviz` (Python package). Verify: `wireviz --version`
- **Install**: `pip install wireviz`
- **HARD DEPENDENCY — Graphviz `dot`**: WireViz shells out to the Graphviz `dot` binary to lay out diagrams. It MUST be on `PATH`. Verify: `dot -V`
  - Windows: `winget install Graphviz.Graphviz` (or `choco install graphviz`). The installer often does NOT add `dot` to PATH — add `C:\Program Files\Graphviz\bin` to PATH, then open a fresh shell.
  - macOS: `brew install graphviz`
  - Linux: `sudo apt install graphviz`
- If rendering fails with "dot not found" / "ExecutableNotFound", the `dot` binary is missing from PATH — this is the #1 failure.

## Rendering

```bash
wireviz harness.yml               # renders ALL default outputs next to the .yml
```

Default outputs (same basename as the input): `.svg`, `.png`, `.html`, `.bom.tsv`, plus an intermediate `.gv`.

Pick specific formats with `-f` / `--format` (concatenate single-letter codes):

```bash
wireviz harness.yml -f sp         # only SVG + PNG
wireviz harness.yml -f s          # only SVG
wireviz harness.yml -f hpst       # html, png, svg, tsv
wireviz harness.yml -o out/name   # custom output basename/dir
```

Format letters: `h`=HTML, `p`=PNG, `s`=SVG, `t`=TSV (BOM), `g`=GV (Graphviz source).

## YAML structure

Three top-level sections: `connectors`, `cables`, `connections`.

```yaml
connectors:
  X1:                       # connector designator
    pinlabels: [GND, +5V, SIG]   # pin 1, pin 2, pin 3 (1-indexed)
  X2:
    pinlabels: [GND, VCC, DATA]

cables:
  W1:
    colors: [BK, RD, GN]    # wire 1, wire 2, wire 3 (1-indexed)

connections:
  -                         # each list item is one "harness segment"
    - X1: [1-3]             # connector X1 pins 1,2,3
    - W1: [1-3]             # through cable W1 wires 1,2,3
    - X2: [1-3]             # to connector X2 pins 1,2,3
```

### Connections rules (important)
- A connection block is a list of alternating **connector** and **cable** references.
- Each ref is `Designator: [pin/wire list]`. The three lists in a block must be the **same length** — they are zipped together (X1 pin 1 → W1 wire 1 → X2 pin 1, etc.).
- Pins/wires are **1-indexed**. `[1-3]` expands to `[1,2,3]`. You can also write explicit lists like `[1,4,2]`.
- To wire non-contiguous pins, use explicit lists and matching-length lists on both sides, e.g. `- X1: [1,5,9]` / `- W1: [1,2,3]` / `- X2: [2,2,2]`.
- Reference a pin **by its label** instead of index by quoting it, but index lists are simplest and least error-prone.

### Wire colors — WireViz 2-letter codes
Use these codes in `colors:` (NOT hex or full names):

| Code | Color | Code | Color |
|------|-------|------|-------|
| BK | Black | GN | Green |
| WH | White | BU | Blue |
| RD | Red | VT | Violet/Purple |
| BN | Brown | GY | Grey |
| YE | Yellow | PK | Pink |
| OG | Orange | TQ | Turquoise |
| GD | Gold | SL | Silver |

Multi-color wires: concatenate codes, e.g. `BKWH` (black/white), `RDBU`.

## Common gotchas
- **`dot` binary required** on PATH — see Setup. Missing `dot` is the most common failure.
- **Pin/wire indices are 1-based**, not 0-based.
- **List lengths must match** across the connector/cable/connector in a connection block (they zip).
- Colors are **2-letter codes** (`RD`, `BK`, `BU`, `GN`, `YE`, `OG`, `VT`, `WH`, `GY`, `BN`…), not `red`/`#FF0000`.
- Every pin referenced in `connections` must exist in the connector's `pinlabels` (index within range).
- Use `# comments` freely in the YAML to document firmware notes, tie-offs, etc.

## Minimal working example

`example.yml`:
```yaml
connectors:
  MCU:
    pinlabels: [3V3, GND, TX, RX]
  Sensor:
    pinlabels: [VCC, GND, RXD, TXD]

cables:
  W1:
    colors: [RD, BK, GN, YE]

connections:
  -
    - MCU: [1, 2, 3, 4]
    - W1: [1, 2, 3, 4]
    - Sensor: [1, 2, 4, 3]   # note TX->RXD, RX->TXD crossover
```

Render:
```bash
wireviz example.yml -f sp     # produces example.svg + example.png
```
