# Notch — Control Surfaces Beyond JS (HTTP, OSC, Files)

Read this when the user asks about real-time parameter control, external exposed-property tweaking on a deployed scene, or "what else can drive a Notch project besides the JS API." Also lists the boundaries of this skill.

## HTTP API (orthogonal control surface)

For runtime tweaks of **already-exposed** properties on a Block/Standalone export (NOT Builder), Notch exposes a tiny HTTP API on a project-settings-configurable port (e.g. 8910):
- `GET /control` → manifest of exposed properties by UID
- `GET /control?uid=<urlencoded>&value=<urlencoded>` → set a value

Cannot create nodes. Useful only when the scene is pre-built and properties are right-click → Exposed.

## OSC

For live numeric/text values while the scene is playing (not for scene authoring), Notch supports OSC. The OSC Modifier node receives values into the nodegraph. Use OSC for real-time parameter modulation; use JS for structural scene work.

## When to use JS vs OSC vs HTTP vs file-load

- **JS** — scene setup, node creation, property editing, graph wiring (this skill's focus).
- **OSC** — live numeric/text values while the scene is playing (modulation, performance).
- **HTTP** — exposed-property control on Blocks/Standalone exports (production deployment).
- **External files via Reflect Resource Changes** — agentic iteration loop (this skill's workflow).
- **Native Notch Assets** — portable, reusable handoff once a setup is proven.

## What's not in this skill (yet)

- **Color property API canonical form.** Comma-separated string via `SetString` works for some color attrs, but the full convention (per-channel floats? packed RGBA?) is not fully verified.
- **Document save / project open.** Officially unsupported by Notch.
- **Exposed-property workflow end-to-end.** `Document.SetExposedPropertyValue(uid, value)` works in principle but requires pre-exposing in the .dfx; not yet exercised here.
- **`EmbedConnectedNodes()` for converting a working subgraph into an Asset.** Documented but not tested.
- **Reflect Resource Changes auto-reload root cause.** Why it doesn't fire reliably — bug or config — is unknown.

Add to this list as you discover new patterns. The skill should grow with the user's Notch work.

## Sources

- [Notch JavaScript reference](https://manual.notch.one/2026.1/en/docs/reference/javascript/)
- [Manual MCP Server](https://manual.notch.one/2026.1/en/docs/misc/manual-mcp-server/)
- [Add JS Script workflow](https://manual.notch.one/2026.1/en/docs/reference/javascript/add-a-js-script/)
- [CreateNode signature](https://manual.notch.one/2026.1/en/docs/reference/javascript/reference/layer/createnode/)
- [Web/HTTP API](https://manual.notch.one/2026.1/en/docs/reference/devices-protocols/web-http-api/)
- [OSC](https://manual.notch.one/2026.1/en/docs/reference/devices-protocols/osc/)
