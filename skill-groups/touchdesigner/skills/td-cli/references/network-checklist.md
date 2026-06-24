# Creating Networks — Checklist

Run through this when building an operator network from scratch. Each item maps to a trap documented in `gotchas.md`.

1. `import td`; use `td.lowercaseTypeCHOP` (not uppercase globals)
2. Track every op you `create()` in a list; call `parent.layout(ops=new_ops)` at end of task (not as you go)
3. Wire inputs: `child.inputConnectors[0].connect(parent.outputConnectors[0])`
4. `renderTOP`: `par.camera`, `par.geometry`, `par.lights` (not wires)
5. `feedbackTOP`: wire + `par.top` to **same** independent upstream node
6. `poptoSOP`: `par.pop = pop_op` (not a wire — SOP has no POP connectors)
7. Audio-reactive params: `par.expr = "..."` (not `par.val`)
8. 3D rotation: at `geometryCOMP` level, not POP/SOP level
9. `noisePOP` time animation: `par.t4d` (not `tx/ty/tz`)
10. Verify parameter names against the gotchas table before setting
11. `display=True, render=True` on output SOP inside `geometryCOMP`
12. Skip `geo.par.pathsop` — cook loop risk; use display/render flags
13. Absolute paths in expressions inside COMPs referencing outside ops
14. After bulk `create()`, verify actual node names (suffix collisions)
