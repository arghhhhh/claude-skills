# Notch JS — Confirmed Working Patterns

Reusable, battle-tested JavaScript patterns for authoring Notch scenes. Read this when you're writing any non-trivial script — copy these helpers into your build script rather than re-deriving them.

## Idempotent CreateNode (find-or-create)

The most important pattern. Always check before creating, so re-runs don't pile up duplicates:

```js
function findOrCreate(layer, group, name, x, y) {
    var existing = layer.FindNode(name);
    if (existing) return existing;
    var n = layer.CreateNode(group);
    if (!n) { Log("FAIL CreateNode: " + group); return null; }
    n.SetName(name);
    n.SetNodeGraphPosition(x, y);
    return n;
}
```

## Two-state safety (load passive, arm via key)

Import-time mutation can wreck a project. The proven pattern: load script in a passive "log only" mode, arm it via a keypress.

```js
var ENABLE_MUTATION = false;       // flip to true OR press B to arm
var HAS_RUN = false;

function runTask() {
    if (!ENABLE_MUTATION || HAS_RUN) return;
    HAS_RUN = true;
    // ... actual mutations
}

function Init()   { Log("[BRIDGE] Loaded passive. Press B to arm."); }
function Update() { runTask(); }
function OnKeyPress(key) {
    if (key == "B") { ENABLE_MUTATION = true; HAS_RUN = false; runTask(); }
}
```

## Graph snapshot for self-awareness

Before mutating, dump the current graph so the agent (you, reading the log) knows what already exists:

```js
function snapshotGraph(layer) {
    var n = layer.GetNumNodes();
    Log("GRAPH_BEGIN|nodes=" + n);
    for (var i = 0; i < n; i++) {
        var nd = layer.GetNode(i);
        var name = nd.GetName();
        var type = nd.GetCategoryAndType ? nd.GetCategoryAndType() : "?";
        var pos  = nd.GetNodeGraphPosition();
        Log("GRAPH_NODE|i=" + i + "|name=" + name + "|type=" + type + "|pos=" + pos[0] + "," + pos[1]);
    }
    Log("GRAPH_END|nodes=" + n);
}
```

Then grep the log for `GRAPH_` to reconstruct state in the agent context.

## Rewire-idempotent inputs

`AddInput` doesn't reject duplicates. Always `RemoveInput` first when rewiring:

```js
function wire(dst, src, inputName) {
    try { dst.RemoveInput(src, inputName); } catch(e) {}
    dst.AddInput(src, inputName);
}
```

## Find root robustly

Don't assume `layer.GetNode(0)` is the root. Search by name or type:

```js
function findRoot(layer) {
    var r = layer.FindNode("Root");
    if (r) return r;
    var n = layer.GetNumNodes();
    for (var i = 0; i < n; i++) {
        var nd = layer.GetNode(i);
        var type = nd.GetCategoryAndType ? nd.GetCategoryAndType() : "";
        if (type.indexOf("Root") >= 0) return nd;
    }
    return layer.GetNode(0); // last-resort fallback
}
```

## Try-multiple-candidates setter

When you don't know the exact `Category.Property` name, probe a list:

```js
function trySetFloatAny(node, names, value) {
    for (var i = 0; i < names.length; i++) {
        node.SetFloat(names[i], value);
        if (node.GetFloat(names[i]) === value) return names[i];
    }
    return null;
}
trySetFloatAny(material, ["BSDF.Brightness", "BRDF.Brightness", "Attributes.Brightness"], 1.6);
```
