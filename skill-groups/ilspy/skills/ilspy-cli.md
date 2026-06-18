---
version: 1.1.0
---

# ILSpy CLI Skill

Use this skill to decompile .NET assemblies via the `ilspy` CLI ([akiselev/ilspy-cli](https://github.com/akiselev/ilspy-cli) — standalone repo as of June 2026, previously a subcrate of `akiselev/ghidra-cli`). It is a Rust front-end that loads the ILSpy `ICSharpCode.Decompiler` engine in-process via a small C# bridge — fast, agent-friendly, and supports **single-method decompilation** (which `ilspycmd` cannot do).

## When to use this vs Ghidra

- **Use `ilspy`** for any **managed .NET** binary (PE files with a `CLR header`, `.dll`/`.exe` produced by C#/F#/VB.NET/etc.). Ghidra's output for .NET is poor; ILSpy gives clean C#.
- **Use `ghidra`** for native binaries, mixed-mode binaries' native portions, or when you need x-refs / patching / call graphs.
- **`ilspy detect <file>`** classifies a file as `.NET` or native — run it first when unsure.

## Setup

- **Binary**: `ilspy` (installs to `~/.cargo/bin/ilspy`)
- **Verify**: `ilspy --version` then `ilspy doctor`
- **Not installed?**
  - `cargo install --git https://github.com/akiselev/ilspy-cli --locked`
  - Needs .NET 8 SDK to build, .NET 8+ runtime to run (`winget install Microsoft.DotNet.SDK.8`).
- **Bridge DLL**: the build script produces `IlSpyBridge.dll` under `<repo>/target/release/bridge/`. Copy that folder to a stable location and set `ILSPY_BRIDGE_DIR` to survive `cargo clean`.

## Output formats

| Flag | Format | Use |
|------|--------|-----|
| (default) | Table / compact | Human + agent reading in TTY |
| `--json` | Minified JSON | Pipe / parse |
| `--pretty` | Indented JSON | Inspect JSON manually |
| `--compact` | One line per item | Agent grep / tail |

## Commands

### Detect

```bash
ilspy detect MyApp.dll                       # → ".NET 8.0 [ilspy]" or "native"
ilspy detect "C:\Program Files\MyApp" --recursive
```

Cheap and runtime-free — does NOT load the .NET runtime, just reads the PE header.

### List

```bash
ilspy list types MyLib.dll                                   # all types
ilspy list types MyLib.dll --filter Controller               # name substring
ilspy list types MyLib.dll --kind class                      # class|interface|struct|enum|delegate
ilspy list methods MyLib.dll --type MyNamespace.MyClass      # methods of one type
```

### Decompile

```bash
ilspy decompile MyLib.dll                                    # full assembly (large!)
ilspy decompile MyLib.dll --type MyNamespace.MyClass         # one type
ilspy decompile MyLib.dll --type MyNamespace.MyClass --method DoWork   # one method
```

**Tip**: always narrow to `--type` (and `--method` if you know it). Full-assembly dumps are huge for real libraries.

### Search

```bash
ilspy search MyLib.dll "ConnectionString"        # regex over decompiled source
ilspy search MyLib.dll "Aes\\.Create"
```

Search runs decompilation under the hood — slower than `list`, faster than dumping everything and grepping yourself.

### Info

```bash
ilspy info MyLib.dll          # framework, type count, references
```

### Doctor

```bash
ilspy doctor                  # .NET runtime + bridge DLL load check
```

## Operational tips

- **Always `ilspy detect` first** when the user hands you an unknown `.dll`/`.exe` — managed or native changes which tool to use.
- **Narrow before decompiling**: `list types --filter X` → `list methods --type X.Y` → `decompile --type X.Y --method Z`.
- **Save large outputs to a file** via shell redirect rather than echoing huge decompilations to chat.
- **Strong-naming / signing don't matter** — ILSpy reads metadata directly.
- **Obfuscated assemblies** (Dotfuscator, ConfuserEx, etc.): you'll get valid C# but with mangled names. ILSpy doesn't deobfuscate; pair with `de4dot`-style tools first if needed.
- **`ILSPY_BRIDGE_DIR` env var** overrides the default bridge search path. Set this on any machine where you've moved the bridge folder.

## What this CLI does NOT do

- No assembly **editing/patching** (use `dnSpy`/`AsmResolver` for that).
- No **runtime instrumentation** (use `Harmony`/`MonoMod`).
- No **IL listing** — output is high-level C#. For raw IL, use `ildasm` or `dotnet-ildasm`.
- No **resource extraction** beyond what shows up in metadata.
