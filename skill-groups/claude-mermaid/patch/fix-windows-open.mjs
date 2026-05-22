#!/usr/bin/env node
/**
 * Idempotent patch for the claude-mermaid Windows browser-open bug (<= v1.6.3).
 *
 * getOpenCommand() returns the bare string "start" on Windows. `start` is a
 * cmd.exe builtin, not an executable, so execFile()/spawn() fail with
 * `spawn start ENOENT`. That unhandled error crashes both the MCP server
 * (after every mermaid_preview call) and `claude-mermaid --serve`.
 *
 * This rewrites the two call sites to launch the browser via `cmd /c start`
 * on Windows and to never let a failed browser-open crash the process.
 *
 * Re-run this after every `npm install -g claude-mermaid` (updates overwrite
 * node_modules). Safe to run repeatedly — it detects an already-patched file.
 *
 * Upstream: https://github.com/veelenga/claude-mermaid
 */
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = execSync("npm root -g", { encoding: "utf8" }).trim();
const buildDir = join(root, "claude-mermaid", "build");

const targets = [
  {
    file: join(buildDir, "handlers.js"),
    old: `        const openCommand = getOpenCommand();
        const child = spawn(openCommand, [serverUrl], { detached: true, stdio: "ignore" });
        child.unref();`,
    new: `        const isWin = process.platform === "win32";
        const openCommand = isWin ? "cmd" : getOpenCommand();
        const openArgs = isWin ? ["/c", "start", "", serverUrl] : [serverUrl];
        const child = spawn(openCommand, openArgs, { detached: true, stdio: "ignore" });
        child.on("error", () => { });
        child.unref();`,
  },
  {
    file: join(buildDir, "serve.js"),
    old: `    await execFileAsync(getOpenCommand(), [galleryUrl]);`,
    new: `    try {
        if (process.platform === "win32") {
            await execFileAsync("cmd", ["/c", "start", "", galleryUrl]);
        }
        else {
            await execFileAsync(getOpenCommand(), [galleryUrl]);
        }
    }
    catch {
        // Browser open is best-effort — never crash the server over it.
    }`,
  },
];

let patched = 0;
for (const t of targets) {
  let src;
  try {
    src = readFileSync(t.file, "utf8");
  } catch {
    console.warn(`skip: ${t.file} not found — is claude-mermaid installed?`);
    continue;
  }
  if (src.includes(t.new)) {
    console.log(`already patched: ${t.file}`);
  } else if (src.includes(t.old)) {
    writeFileSync(t.file, src.replace(t.old, t.new));
    console.log(`patched: ${t.file}`);
    patched++;
  } else {
    console.warn(`skip: ${t.file} — patch target not found (claude-mermaid version may differ)`);
  }
}

console.log(patched ? `Done — ${patched} file(s) patched.` : "Nothing to patch.");
