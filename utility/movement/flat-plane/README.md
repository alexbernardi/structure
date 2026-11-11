# Movement laboratory (flat plane) - workbench of movement_core

A standalone Godot project ([ADR-0009](../../../AGENT-WORKSHOP/DECISIONS/ADR-0009-utility-tree.md)) for developing,
playing and tuning the player character's movement. Since Movement Core 1.0 it is the **workbench** of the approved
package [`movement_core`](../../../SYSTEM-ROOMS/movement_core/README.md)
([ADR-0010](../../../AGENT-WORKSHOP/DECISIONS/ADR-0010-shared-systems-and-laboratories.md)):

- `systems/movement_core/` - the package source (the only place movement code is edited). Its public entry point is
  `movement_character.gd`; its interface is the room's [CONTRACT](../../../SYSTEM-ROOMS/movement_core/CONTRACT.md).
- Everything else is laboratory-only and never ships: `scenes/` (the obstacle-course scene `flat_plane.tscn`, the
  treadmill, MIDI monitor, comparison scenes), `world/` (lanes A-P), `midi/` and `tuning/`, the legacy procedural
  animation (`animation/gait_*`, `body_*`, `springs*`, `walk_*`, `character/walk_visual.tscn`), `tools/` (clip
  audits, captures), `presets*/`, `config/`, `tests/` (about 550) and `benchmarks/`.

```powershell
& '<repo>\.tools\godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe' --path utility/movement/flat-plane res://scenes/flat_plane.tscn -- --landmark=lane_o --traversal-debug
python TOOLS/cli/structure.py room test movement_core    # this project's suite
python TOOLS/cli/structure.py room bench movement_core   # Movement Core targets
```

Controls and lanes: [MOVEMENT-LAB-5.md](../../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-LAB-5.md). Changing movement:
[LABORATORY-PIPELINE.md](../../../AGENT-WORKSHOP/PROTOCOLS/LABORATORY-PIPELINE.md) section 2.
