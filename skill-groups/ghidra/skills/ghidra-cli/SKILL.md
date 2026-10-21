---
version: 1.2.0
name: ghidra-cli
description: Reverse engineer native binaries headlessly with Ghidra via the `ghidra` CLI (akiselev/ghidra-cli) — import/analyze, decompile functions, edit symbols and types, find strings/bytes/crypto, walk cross-references, build call graphs, patch bytes, run scripts.
---

# Ghidra CLI Skill

Use this skill to drive Ghidra headless reverse-engineering tasks through the `ghidra` CLI (from [akiselev/ghidra-cli](https://github.com/akiselev/ghidra-cli)) — a Rust wrapper that talks to a long-lived Java bridge running inside Ghidra's JVM.

## Setup

- **Binary**: `ghidra` (Rust CLI; installs to `~/.cargo/bin/ghidra`)
- **Verify**: `ghidra version` and `ghidra doctor`
- **Not installed?**
  - CLI: `cargo install --git https://github.com/akiselev/ghidra-cli --tag v0.2.2 --locked --force ghidra-cli` (trailing package name required)
  - **Full JDK** (needs `javac` + `jdk.compiler`; a JRE silently fails): 21 for Ghidra 12.x, 17 for older. `winget install Microsoft.OpenJDK.21` / `brew install openjdk@21` / `sudo apt install openjdk-21-jdk`
  - Ghidra 11+: `ghidra setup` (auto-download) **or** download from https://ghidra-sre.org and `ghidra config set ghidra_install_dir <path>` (or export `GHIDRA_INSTALL_DIR`).

`ghidra doctor` reports the install path, selected JDK, project directory, and config file, and compiles the bridge script as a real health check — run it first if anything looks off.

The CLI picks the JDK itself and passes it to Ghidra as `JAVA_HOME` (PATH doesn't matter). Override: `--java-home <jdk>`, config `java_home`, or `GHIDRA_CLI_JAVA_HOME`.

## How the bridge works

The CLI connects to a `GhidraCliBridge.java` GhidraScript running inside `analyzeHeadless`. The bridge **stays loaded between commands** so queries are sub-second after the first one.

- Bridge **auto-starts** on any command that needs it; launches with `-preScript -noanalysis`, so readiness is fast and analysis runs afterwards as a job.
- One bridge per project — each project has its own port file under the projects dir, so multiple projects can run concurrently.
- Program operations run serialized on one Ghidra thread; extra requests get **job IDs** and wait in a FIFO (256 deep) instead of failing. `ping`, `status`, `jobs`, `cancel` stay responsive during a long analysis — a slow `analyze` no longer looks like a dead bridge.
- Manual control: `ghidra start --project <p> --program <name>`, `ghidra status`, `ghidra stop`, `ghidra restart`.
- Jobs: `ghidra jobs [ID]` (active, queued, last 100), `ghidra cancel [ID]` (cooperative; defaults to the active job; queued jobs drop immediately).
- Use `ghidra ping` for a fast liveness check.

## Output formats

- TTY → compact human-readable
- Pipe → compact JSON (auto)
- `--json` / `--pretty` to force
- `--fields "name,address,size"` to select columns

When parsing programmatically, always pass `--json` to be explicit. CSV joins array cells (`tags`, `operands`, `params`) with `;`.

## Global flags

Go before or after the subcommand: `ghidra --project P --program bin function list`.

| Flag | Effect |
|---|---|
| `--project <P>` / `--program <PROG>` | Target (also per-subcommand) |
| `--projects-dir <DIR>` | Where projects live (overrides `ghidra_project_dir` / `GHIDRA_PROJECT_DIR`). Default on Windows: `%LOCALAPPDATA%\ghidra-cli\projects` |
| `--java-home <PATH>` | Full JDK for Ghidra |
| `-v`/`-vv`/`-vvv`, `-q` | Log verbosity / quiet |

⚠ Ghidra 12.1+ rejects project dirs with a dot-prefixed component (`~/.cache`, `~/.ghidra`) — never pass one to `--projects-dir`.

## Typical workflow

```bash
# One-time per binary — import starts the bridge AND auto-analyzes
ghidra project create myproj
ghidra import ./target.exe --project myproj --program target

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
ghidra project info [<name>]
ghidra project delete <name>                            # removes .gpr/.rep, stops its bridge
ghidra import <binary> --project <p> [--program <name>] # import + auto-analyze; reports function_count
ghidra import <binary> --no-analyze                     # import only (still persisted)
ghidra import <binary> --detach                         # return now; bridge keeps going (watch with `jobs`)
ghidra analyze --project <p> [--program <name>]         # re-run analysis on an imported program
ghidra program list --project <p>
ghidra program export --format <fmt> -o <out>           # json, xml, c/cpp, binary/bin, gzf, ascii/asm, hex, html
ghidra program close | delete
```

### Functions

```bash
ghidra function list                                    # all functions
ghidra function list --filter "size > 100"              # expression filter
ghidra function list --tag crypto --tag init            # tag filter (repeatable = AND); --untagged for none
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

### Function tags

```bash
ghidra tag list [--function <fn>]          # all tags (name, comment, use count) or one fn's
ghidra tag get <name>                      # functions carrying the tag
ghidra tag create <name> [--comment "…"]
ghidra tag add <fn> <tag>... [--no-create] # auto-creates missing tags unless --no-create
ghidra tag remove <fn> <tag>... | --all
ghidra tag rename <old> <new>
ghidra tag set-comment <name> "…"          # "" clears
ghidra tag delete <name>                   # detaches from every function
```
Names are case-sensitive (no `,` or `;`). `add`/`remove` are idempotent. Function rows carry a sorted `tags` array: `--fields name,address,tags`, `--filter "tags ~ 'crypto'"`. Unknown tag → error with a "Did you mean" hint.

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
ghidra comment set <addr> "note" --comment-type EOL    # EOL (default) | PRE | POST | PLATE
ghidra comment list
```

### Patching

```bash
ghidra patch bytes <addr> "90 90"
ghidra patch nop <addr> --count 5          # NOPs 5 consecutive instructions; rolls back all if any addr has none
ghidra patch export -o patched.bin
```

### Scripts

```bash
ghidra script list
ghidra script run myscript.py              # Python or Java; resolved to an absolute path, stdout captured
ghidra script run report.py -- arg1 arg2   # positional args after --
ghidra script run dump.py --expect out.csv:10   # fail unless out.csv exists with >=10 rows (repeatable; --allow-empty)
ghidra script python "print(currentProgram)"
ghidra script java "println(currentProgram);"
```
Scripts run on the job lane — `ghidra cancel` works on them.

### Misc

```bash
ghidra stats        # function/instruction/data counts
ghidra summary      # high-level program summary
ghidra dump ...     # export memory / data
ghidra diff ...     # diff between programs
ghidra batch commands.txt   # run many commands from a file
```

## Filtering expressions

`list` commands (`function`, `strings`, `symbol`, `type`, `query`, `dump`) accept `--filter "<field><op><value>"`, applied client-side with `--sort`/`--offset`/`--count`.

| Op | Meaning |
|---|---|
| `=` `!=` `>` `>=` `<` `<=` | compare (`=`, not `==`) |
| `~` `^` `$` | contains / starts with / ends with (case-insensitive) |
| `=~` | regex (case-insensitive) |
| `AND` `OR` `NOT` (or `&&` `\|\|` `!`), `( )` | combine |
| `IN [a,b]`, `EXISTS`/`EMPTY`/`NULL` | set / existence |

Example: `--filter "size > 200 AND NOT name ^ 'FUN_'"`. Array fields (`tags`, `operands`) match if any element matches; `!=` means no element equals. A bare word (`--filter PK`) is rejected — use `name~PK`. No globs.

`--limit` defaults to 1000; `--limit 0` = all rows (use for complete dumps).

## Operational tips

- **First command per binary is slow** (Ghidra import + auto-analysis). Subsequent queries hit the warm bridge and are sub-second.
- **`import` already analyzes** — only run `analyze` after `import --no-analyze` or to re-run analyzers.
- **Pin a project** with `set-default` when iterating, otherwise pass `--project` every call.
- ⚠ **Never pipe a command that auto-starts the bridge** (`ghidra import … | tail`, `| jq`, `| head`). ✅ Verified on Windows/Git Bash with 0.2.2: the JVM inherits the pipe, so the pipeline blocks until the bridge exits (an import "hung" 10 min after finishing analysis in 17s). Output is complete; only the pipe never closes. Run the first command unpiped (or `> file`), then pipe freely once the bridge is up.
- **Bridge busy?** `ghidra jobs` to see what's running → `ghidra cancel` → `ghidra restart` only if `ping` fails. Port files live under the project directory shown by `ghidra doctor`.
- **Timeouts** are mostly unbounded by default. Env overrides: `GHIDRA_CLI_DECOMPILE_TIMEOUT` (s, `0`=unbounded), `GHIDRA_CLI_OP_TIMEOUT` (analyze/import), `GHIDRA_CLI_READ_TIMEOUT` (per-request, 300s), `GHIDRA_CLI_LAUNCH_TIMEOUT` (180s), `GHIDRA_CLI_CONNECT_DEADLINE` (60s), `GHIDRA_CLI_SHUTDOWN_TIMEOUT` (drain before kill, 300s).
- **JSON for parsing**, human format for reading. Don't try to parse the human format — the column layout isn't stable.
- **Multi-binary concurrent analysis** works: separate projects = separate bridges = separate ports.

## When NOT to use this skill

- For raw `analyzeHeadless` invocations with custom postScripts unrelated to the bridge — call `analyzeHeadless` directly.
- For Ghidra UI / SLEIGH editing / extension development — open the Ghidra GUI.
