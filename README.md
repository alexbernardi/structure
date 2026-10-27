# STRUCTURE

An experimental, persistent, systemic multiplayer sandbox about **purpose, survival, emergence and structure**:
how civilisations build, maintain, transform and lose the structures that hold them together. A Tower (or
Stairway to Heaven) is the central organising objective - not necessarily an ending.

**Current phase: bootstrap foundation (0.1.0).** The repository contains the development workshop, a minimal
dedicated-server multiplayer sandbox with one gameplay loop (gather a resource, contribute it to a shared
construction site that persists), one isolated system room, an asset pipeline example, and the tooling to
build, test, version, snapshot and integrate safely. No art direction, lore or large systems yet - by design.

## Quick start (Windows, PowerShell)

Requirements: Python >= 3.11, Git (+ Git LFS), Docker Desktop for container workflows, Blender 5.0.1 only for the
asset pipeline. Godot is downloaded and verified by `setup`.

```powershell
python TOOLS/cli/structure.py setup     # downloads pinned Godot 4.7.2 into .tools/, imports projects
python TOOLS/cli/structure.py play      # local dedicated server + game window (WASD, mouse, Space, E, Q)
python TOOLS/cli/structure.py test      # all automated suites (Docker suite needs Docker Desktop)
```

## Where things are

| Folder | Purpose |
|---|---|
| [AGENT-WORKSHOP/](AGENT-WORKSHOP/START-HERE.md) | Headquarters: start here - protocols, decisions, plans, task log, docs, inventories |
| [SANDBOX/](SANDBOX/README.md) | The playable Godot 4 project (server, client and bot roles), configs, scenarios |
| [SYSTEM-ROOMS/](SYSTEM-ROOMS/README.md) | Independent laboratories for gameplay systems (`_TEMPLATE`, `movement`) |
| [COMMON-ASSETS/](COMMON-ASSETS/README.md) | Shared asset library: specs/sources, runtime files, metadata, manifest |
| [PIPELINES/](PIPELINES/README.md) | Spec -> Blender script -> GLB -> validation -> Godot |
| [INFRASTRUCTURE/](INFRASTRUCTURE/README.md) | Docker, environments, toolchain pins, build manifests, snapshots |
| [TESTING/](TESTING/README.md) | Test harness, integration/multiplayer suites, performance baselines, fixtures |
| [TOOLS/](TOOLS/README.md) | `structure.py` developer CLI, diagnostics, visualisation |

Agents: read [AGENTS.md](AGENTS.md) first.
