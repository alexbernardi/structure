# ADR-0002: Godot 4.7.2-stable, GDScript, pinned toolchain

Status: Accepted (2026-10-27)

## Context
The brief asks for a stable, supported Godot 4.x, GDScript first, reproducible builds, and a Windows-native client
with Linux server containers. Godot was not installed on the development machine.

## Decision
- Pin **Godot 4.7.2-stable** (latest stable release, 2026-08-18) in `INFRASTRUCTURE/builds/toolchain.json` with the
  SHA-256 of each official archive (Windows x86_64 for development, Linux x86_64 for containers).
- `structure.py setup` downloads the pinned archive into `.tools/`, verifies the hash and imports all projects.
  `STRUCTURE_GODOT` overrides the binary (used by the tools container).
- Export templates (`Godot_v4.7.2-stable_export_templates.tpz`, 1.28 GB) are recorded but **not required**: the sandbox,
  the tests and the server container run the project directly. They are needed only to ship standalone executables
  (`windows_release_x86_64.exe`, `linux_release.x86_64`, plus debug variants).
- GDScript only. Runtime and system code use explicit `preload` constants instead of `class_name`, so a fresh checkout
  runs headless without the editor's global class cache.
- Forward+ renderer for the client (Godot falls back automatically when unsupported).

## Consequences
+ One command bootstraps a machine; downloads are integrity-checked; versions are visible everywhere (`versions`).
- Upgrading Godot is an explicit change: update pins + `project.godot` `config/features`, rebuild images, run all suites
  (`structure.py check` detects mismatches between toolchain.json, Dockerfile and project.godot).

## Alternatives
Godot 4.6 (older, still supported) - no reason to start behind. C# - adds a .NET toolchain without current need.
