## Ghidra CLI - Reverse Engineering

When user wants to reverse engineer a binary — import/analyze with Ghidra, decompile functions, edit symbols or types, find strings/bytes/crypto, walk cross-references, build call graphs, patch bytes, or run Ghidra scripts headlessly — read `~/.claude/skills/ghidra-cli.md`.

Driver is the Rust CLI from [akiselev/ghidra-cli](https://github.com/akiselev/ghidra-cli), which talks to a long-lived Java bridge inside Ghidra's JVM (fast repeated queries, no JVM startup per command).

Trigger phrases: "ghidra", "reverse engineer", "decompile", "disassemble", "binary analysis", "x-ref", "cross reference", "analyzeHeadless", "patch binary", "call graph", "find strings in binary", "ghidra script"
