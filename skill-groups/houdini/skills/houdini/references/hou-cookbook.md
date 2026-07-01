# hou (HOM) & VEX Cookbook

Non-obvious truths about Houdini's Python (`hou`/HOM) and VEX that silently break `execute_houdini_code` scripts and wrangles. **Read before writing Python.** Current as of Houdini 21.0.

## `execute_houdini_code` runs in the Houdini session

Put `import hou` at the top of every script — don't assume `hou` is pre-injected. The bridge blocks dangerous patterns (`hou.exit`, `os.remove`, `subprocess`, **and `__import__`/`exec`**) unless you pass `allow_dangerous:true`.

`execute_houdini_code` returns captured stdout (`--- Stdout ---` section), so `print(...)` is your return channel. Multi-line scripts are awkward to quote through mcporter on the CLI — **spaces and `+`/`/`/`=` break `key:value` parsing**. Hex-encode and decode in one line — and because this uses `__import__`/`exec`, add `allow_dangerous:true`:

```
npx mcporter call houdini.execute_houdini_code allow_dangerous:true \
  code:"exec(__import__('binascii').unhexlify('<hex>').decode(), globals())"
```

## Contexts — OBJ vs SOP vs LOP

Node *type* is context-specific. Geometry SOPs live **inside** a `geo` OBJ; you can't create a `box` SOP at `/obj`:

```python
import hou
geo = hou.node("/obj").createNode("geo", "my_geo")   # OBJ-level container
box = geo.createNode("box", "my_box")                # SOP inside the geo  ✓
# hou.node("/obj").createNode("box")  ✗ — wrong context
```

`createNode` returns the actual node object — use it directly. Names collide and auto-suffix (`box1`, `box2`); read `node.name()`/`node.path()` back rather than assuming.

## Wiring inputs

```python
merge.setInput(0, box)          # input 0 <- box's output 0
merge.setInput(1, sphere)
# multi-input helper:
for i, src in enumerate([box, sphere]): merge.setInput(i, src)
```

## Parameters — `parm` vs `parmTuple`, set vs eval

```python
box.parm("sizex").set(2.0)                    # single component
box.parmTuple("size").set((2.0, 1.0, 3.0))    # vector parm (size = sizex,sizey,sizez)
val = box.parm("sizex").eval()                # evaluated value (follows expressions)
node.parm("file").set("$HIP/geo/out.bgeo.sc") # string parm
```

- **`parm` is one channel; `parmTuple` is the whole vector.** `node.parm("t")` returns `None` — the components are `tx`/`ty`/`tz`, and the tuple is `node.parmTuple("t")`.
- `.eval()` returns the cooked value; `.rawValue()` returns the unexpanded string/expression.
- Expressions: `node.parm("tx").setExpression("$F/24.0")`; keyframes: `node.parm("tx").setKeyframe(hou.Keyframe(...))`.

## Geometry access cooks the node

`node.geometry()` returns the cooked SOP geometry (triggers a cook). It's only valid on SOPs:

```python
geo = box.geometry()
pts  = geo.points()                         # list of Point
n    = len(pts)
p0   = pts[0].position()                     # hou.Vector3
cd   = geo.pointFloatAttribValues("Cd")     # flat tuple, fast bulk read
has  = geo.findPointAttrib("Cd") is not None # check before reading
```

Prefer bulk `*AttribValues()` over per-point loops for large geo. Check attribute existence with `findPointAttrib`/`findPrimAttrib`/`findGlobalAttrib` before reading.

## Display / render flags & cooking

```python
out.setDisplayFlag(True)     # what the viewport shows
out.setRenderFlag(True)      # what renders
node.cook(force=True)        # force a recook
errs = node.errors()         # list of error strings — check after cook
```

Programmatically created nodes don't always inherit the display flag — set it on the terminal SOP explicitly.

## VEX wrangle gotchas

The Attribute Wrangle's `snippet` parm holds the code; the `class` parm sets what it runs over:

```python
w = geo.createNode("attribwrangle", "wr")
w.setInput(0, box)
w.parm("class").set(2)   # Run Over: 0=Detail 1=Primitives 2=Points 3=Vertices 4=Numbers
w.parm("snippet").set('@P.y += 1.0;')
```

VEX attribute **type prefixes** — the type is declared by the prefix, and getting it wrong silently creates the wrong attribute:

| Prefix | Type | Example |
|---|---|---|
| `@P` | vector (position, implicit) | `@P.y += 1.0;` |
| `@Cd` | vector (color, implicit) | `@Cd = {1,0,0};` |
| `f@` | float | `f@mass = 1.5;` |
| `i@` | int | `i@id = @ptnum;` |
| `v@` | vector3 | `v@up = {0,1,0};` |
| `p@` | vector4 / quaternion | `p@orient = ...;` |
| `s@` | string | `s@name = "a";` |
| `4@` / `3@` | matrix4 / matrix3 | `4@xform = ident();` |

- **Bound attributes need the right prefix on first use** — `@myattr` without a prefix defaults to float and won't match an existing int/vector attribute; it reads as 0.
- **Groups**: read/write via `i@group_<name>` or the `@group_<name>` shorthand (1/0 membership).
- **`@ptnum`, `@numpt`, `@Time`, `@Frame`** are built-ins; don't redeclare them.
- Validate before cooking cook-dependent tools: `validate_vex code:"..." wrangle_type:"point"`.

## USD / LOP stage access

```python
lop = hou.node("/stage/mynode")
stage = lop.stage()                    # Usd.Stage (read-only snapshot at this LOP)
prim  = stage.GetPrimAtPath("/World/geo/sphere")
attr  = prim.GetAttribute("radius"); val = attr.Get()
```

LOP `stage()` is a **cooked snapshot** at that node — to *edit* USD, use an Edit-context LOP (e.g. a Python LOP or `set_usd_attribute`), not `attr.Set()` on the snapshot.

## Cleanup

```python
node.destroy()   # removes the node (and children for a subnet/geo)
```

## Returning data

`print()` to stdout (captured). Emit a marker + join fields:

```python
print("RESULT::" + "|".join([f"nodes={len(hou.node('/obj').children())}", f"ver={hou.applicationVersionString()}"]))
```
