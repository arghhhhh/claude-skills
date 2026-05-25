## ILSpy CLI - .NET Decompilation

When user wants to inspect a **managed .NET** assembly (.dll/.exe produced by C#/F#/VB.NET) — detect .NET vs native, list types/methods, decompile a type or single method, search decompiled source, or read assembly metadata — read `~/.claude/skills/ilspy-cli.md`.

Driver is `ilspy` (the `ilspy-cli` subcrate of [akiselev/ghidra-cli](https://github.com/akiselev/ghidra-cli)), which loads ILSpy's `ICSharpCode.Decompiler` engine in-process via a C# bridge. Unlike `ilspycmd`, it supports **single-method decompilation**.

**Rule of thumb**: managed .NET → `ilspy`; native binaries → `ghidra`. If unsure, run `ilspy detect <file>` first.

Trigger phrases: "ilspy", ".NET decompile", ".NET assembly", "decompile dll", "C# decompile", "managed binary", "ICSharpCode.Decompiler", "ilspycmd", "PE assembly", "decompile .exe"
