---
version: 1.0.0
---

# Ghidra CLI Skill

Use this skill to drive Ghidra headless reverse-engineering tasks through the `ghidra` CLI (from [akiselev/ghidra-cli](https://github.com/akiselev/ghidra-cli)) — a Rust wrapper that talks to a long-lived Java bridge running inside Ghidra's JVM.

## Setup

- **Binary**: `ghidra` (Rust CLI; installs to `~/.cargo/bin/ghidra`)
- **Verify**: `ghidra version` and `ghidra doctor`
- **Not installed?**
  - CLI: `cargo install --git https://github.com/akiselev/ghidra-cli --locked`
  - JDK 17+: `winget install Microsoft.OpenJDK.21` / `brew install openjdk@21` / `sudo apt install openjdk-21-jdk`
  - Ghidra itself: `ghidra setup` (auto-download) **or** download from https://ghidra-sre.org and `ghidra config set ghidra_install_dir <path>` (or export `GHIDRA_INSTALL_DIR`).

`ghidra doctor` reports the install path, Java version, project directory, and config file location — run it first if anything looks off.

## How the bridge works

The CLI connects to a `GhidraCliBridge.java` GhidraScript running inside `analyzeHeadless`. The bridge **stays loaded between commands** so queries are sub-second after the first one.

- Bridge **auto-starts** on the first command that needs it (`import`, `analyze`, query commands).
- One bridge per project — each project has its own port file under the projects dir, so multiple projects can run concurrently.
- Manual control: `ghidra start --project <p> --program <name>`, `ghidra status`, `ghidra stop`, `ghidra restart`.
- Use `ghidra ping` for a fast liveness check.

## Output formats

- TTY → compact human-readable
- Pipe → compact JSON (auto)
- `--json` / `--pretty` to force
- `--fields "name,address,size"` to select columns

When parsing programmatically, always pass `--json` to be explicit.

## Typical workflow

```bash
# One-time per binary
ghidra project create myproj
ghidra import ./target.exe --project myproj --program target
ghidra analyze --project myproj --program target

# Now query (bridge already running)
ghidra function list --project myproj
ghidra decompile main --project myproj
ghidra x-ref to 0x401000 --project myproj
```

Set defaults to avoid repeating `--project` / `--program`:
```bash
ghidra set-default project myproj
ghidra set-default program target
```

## Command map

### Project / program

```bash
ghidra project create <name>
ghidra project list
ghidra project delete <name>
ghidra import <binary> --project <p> [--program <name>]
ghidra analyze --project <p> [--program <name>]
ghidra program list --project <p>
```

### Functions

```bash
ghidra function list                                    # all functions
ghidra function list --filter "size > 100"              # expression filter
ghidra decompile <name|address>                         # C-ish decompilation
ghidra decompile main --with-vars --with-params         # include locals/params
ghidra disasm <address> --instructions 20               # assembly listing
ghidra function set-signature <fn> --signature "int foo(int x, char *y)"
ghidra function set-return-type <fn> --type void
ghidra function set-calling-convention <fn> --convention __cdecl
ghidra function set-var-type <fn> --var local_10 --type "MyStruct *"
```

### Symbols

```bash
ghidra symbol list
ghidra symbol create <addr> <name>
ghidra symbol rename <old> <new>     # or: ghidra rename <old> <new>
```

### Types

```bash
ghidra type list                                    # struct/enum/typedef/...
ghidra type get <name>                              # full details
ghidra type create <name>                           # empty struct
ghidra type add-field <struct> --name fd --type int
ghidra type del-field <struct> --name fd
ghidra type create-enum <name> --values "A=0,B=1,C=2"
ghidra type typedef <alias> <base_type>
ghidra type rename <old> <new>
ghidra type delete <name>
```

### Cross-references

```bash
ghidra x-ref to <address>     # who references this?
ghidra x-ref from <address>   # what does this reference?
```

### Search

```bash
ghidra find string "password"
ghidra find bytes "90 90 90"
ghidra find function "*crypt*"
ghidra find crypto              # known crypto constants
ghidra find interesting         # heuristic suspicious patterns
ghidra strings list             # all defined strings
```

### Call graphs

```bash
ghidra graph calls                          # full call graph
ghidra graph callers <fn> --depth 3
ghidra graph callees <fn> --depth 3
ghidra graph export dot -o graph.dot        # render with Graphviz
```

### Comments

```bash
ghidra comment get <addr>
ghidra comment set <addr> "note" --comment-type EOL
ghidra comment list
```
Note: `--comment-type` currently always falls back to `EOL` (CLI/bridge key mismatch in 0.1.x).

### Patching

```bash
ghidra patch bytes <addr> "90 90"
ghidra patch nop <addr> --count 5          # CLI parses --count, runtime patches one addr
ghidra patch export -o patched.bin
```

### Scripts

```bash
ghidra script list
ghidra script run myscript.py              # Python or Java Ghidra script
ghidra script python "print(currentProgram)"
```

### Misc

```bash
ghidra stats        # function/instruction/data counts
ghidra summary      # high-level program summary
ghidra dump ...     # export memory / data
ghidra diff ...     # diff between programs
ghidra batch commands.txt   # run many commands from a file
```

## Filtering expressions

Many `list` commands accept `--filter "<expr>"`. Operators: `>`, `<`, `>=`, `<=`, `==`, `!=`, `&&`, `||`, plus `name`, `address`, `size`, `kind` fields. Example: `--filter "size > 200 && name != FUN_*"`.

## Operational tips

- **First command per binary is slow** (Ghidra import + auto-analysis). Subsequent queries hit the warm bridge and are sub-second.
- **Always `analyze` before querying** — function names, types, and decompilation depend on Ghidra's analyzers having run.
- **Pin a project** with `set-default` when iterating, otherwise pass `--project` every call.
- **Bridge stuck?** `ghidra status` → `ghidra restart`. Port files live under the project directory shown by `ghidra doctor`.
- **JSON for parsing**, human format for reading. Don't try to parse the human format — the column layout isn't stable.
- **Multi-binary concurrent analysis** works: separate projects = separate bridges = separate ports.

## When NOT to use this skill

- For raw `analyzeHeadless` invocations with custom postScripts unrelated to the bridge — call `analyzeHeadless` directly.
- For Ghidra UI / SLEIGH editing / extension development — open the Ghidra GUI.
