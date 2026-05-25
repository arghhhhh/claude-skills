// Notch sunset skybox + IBL build script (Notch 2026.1) - v0.4
//
// KEY DISCOVERY (probe v0.3 -> v0.4):
//   Property names in JS are prefixed by their attribute-panel category.
//   e.g. "Brightness" must be written as "Attributes.Brightness".
//   The manual's "Transform.Position X" was the same convention all along.
//
// Architecture:
//   Video Loader (sunset PNG) [Load External File = on, Filename = abs path]
//        ├──> Skybox          (visible background)
//        └──> Environment Image ──> Sky Light  (IBL: tints reflections)

var IMAGE_PATH = "C:/Users/Joss/Desktop/Projects/Work/G45/sunset-equirect.png";

var done = false;

function Initialize() {
    Log("=== Notch Sunset Skybox Build v0.5 ===");
}

function Update() {
    if (done) return;
    done = true;

    var layer = Document.GetLayer(0);
    if (!layer) { Log("ERROR: no layer 0"); return; }

    var root = layer.GetNode(0);
    if (!root) { Log("ERROR: no root"); return; }
    Log("Root: " + root.GetName());

    cleanupByPrefix(layer, "SUNSET_");

    // Place new nodes near the Javascript Node so the user actually sees
    // them without panning. Notch's UI auto-refreshes; off-screen placement
    // was what made it look unrefreshed.
    var jsn = layer.FindNode("Javascript Node");
    var ox = 0, oy = 0;
    if (jsn && jsn.GetNodeGraphPosition) {
        var p = jsn.GetNodeGraphPosition();
        if (p && p.length >= 2) { ox = p[0] - 700; oy = p[1]; }
    }
    Log("Placement origin: (" + ox + ", " + oy + ")");

    // ---- 1. Video Loader ----
    var loader = create(layer, "Video::Video Loader");
    if (!loader) return;
    loader.SetName("SUNSET_LOADER");
    loader.SetNodeGraphPosition(ox, oy);
    addChild(root, loader);

    // Enable external-file loading and set the path. Notch booleans are ints (0/1).
    setI(loader, "Attributes.Load External File", 1);
    setS(loader, "Attributes.Filename", IMAGE_PATH);

    // ---- 2. Skybox ----
    var skybox = create(layer, "3D::Skybox");
    if (skybox) {
        skybox.SetName("SUNSET_SKYBOX");
        skybox.SetNodeGraphPosition(ox + 250, oy);
        addChild(root, skybox);
        // Image Source Mapping enum: 0=Spherical, 1=Dual Paraboloid, 2=Equirectangular
        setI(skybox, "Attributes.Image Source Mapping", 2);
        setF(skybox, "Attributes.Brightness", 1.0);
        setF(skybox, "Attributes.Size", 1.0);
        wire(loader, skybox, "Skybox Image");
    }

    // ---- 3. Environment Image ----
    var envimg = create(layer, "Lighting::Environment Image");
    if (envimg) {
        envimg.SetName("SUNSET_ENVIMG");
        envimg.SetNodeGraphPosition(ox + 250, oy + 120);
        addChild(root, envimg);
        setI(envimg, "Attributes.Image Source Mapping", 2); // Equirectangular (VR 360)
        wire(loader, envimg, "Envmap Image");
    }

    // ---- 4. Sky Light ----
    var skylight = create(layer, "Lighting::Sky Light");
    if (skylight) {
        skylight.SetName("SUNSET_SKYLIGHT");
        skylight.SetNodeGraphPosition(ox + 500, oy + 120);
        addChild(root, skylight);
        setF(skylight, "Attributes.Brightness", 1.0);
        // Try the most likely input connector name for the env image
        wire(envimg, skylight, "Envmap Image") ||
        wire(envimg, skylight, "Environment Image");
    }

    Log("--- Done v0.5. UI auto-refreshes; new nodes placed left of the Javascript Node. ---");
}

// ===== helpers =====

function cleanupByPrefix(layer, prefix) {
    var victims = [];
    var n = layer.GetNumNodes();
    for (var i = 0; i < n; i++) {
        var nd = layer.GetNode(i);
        if (nd && nd.GetName().indexOf(prefix) === 0) victims.push(nd.GetName());
    }
    Log("Cleanup: " + victims.length + " " + prefix + "* node(s)");
    for (var j = 0; j < victims.length; j++) {
        var f = layer.FindNode(victims[j]);
        if (f && f.DeleteNode) {
            try { f.DeleteNode(); Log("  deleted " + victims[j]); }
            catch (e) { Log("  err delete: " + e); }
        }
    }
}

function create(layer, group) {
    var n = layer.CreateNode(group);
    if (n) Log("OK CreateNode \"" + group + "\"");
    else   Log("FAIL CreateNode \"" + group + "\"");
    return n;
}

function addChild(parent, child) {
    try { parent.AddChild(child); Log("  + " + parent.GetName() + " -> " + child.GetName()); return true; }
    catch (e) { Log("  err AddChild: " + e); return false; }
}

function wire(src, dst, inputName) {
    if (!src || !dst) return false;
    try {
        dst.AddInput(src, inputName);
        Log("  ~ " + src.GetName() + " -> " + dst.GetName() + "." + inputName);
        return true;
    } catch (e) { Log("  err AddInput \"" + inputName + "\": " + e); return false; }
}

function setF(node, name, value) {
    node.SetFloat(name, value);
    var v = node.GetFloat(name);
    if (v === value) Log("  = " + node.GetName() + "." + name + " = " + v);
    else Log("  ! " + node.GetName() + "." + name + " readback=" + v + " (wanted " + value + ")");
}

function setI(node, name, value) {
    if (!node.SetInt) { Log("  ! no SetInt for " + name); return; }
    node.SetInt(name, value);
    var v = node.GetInt ? node.GetInt(name) : undefined;
    if (v === value) Log("  = " + node.GetName() + "." + name + " = " + v);
    else Log("  ! " + node.GetName() + "." + name + " readback=" + v + " (wanted " + value + ")");
}

function setS(node, name, value) {
    node.SetString(name, value);
    var v = node.GetString(name);
    if (v === value) Log("  = " + node.GetName() + "." + name + " = \"" + v + "\"");
    else Log("  ! " + node.GetName() + "." + name + " readback=\"" + v + "\" (wanted \"" + value + "\")");
}

Initialize();
