# ADR-0009: `utility/` tree for standalone development utilities

Status: Accepted (2026-11-06, requested by the user in the "MIDI Movement Lab" brief). Amended by
[ADR-0010](ADR-0010-shared-systems-and-laboratories.md): a utility may be the workbench of a package room
(`utility/movement/flat-plane` holds `movement_core`'s source), whose versions are installed into other projects.

## Context
The MIDI Movement Lab (task [0003](../TASKS/0003-midi-movement-lab.md)) is a tuning tool, not gameplay and not a
system room: it has no contract with the sandbox, no persistence in the world, and is not promoted. The user specified
the location `utility/movement/flat-plane/`. ADR-0001 fixed the top-level layout, so a new top-level folder is a layout
change that needs approval - the brief is that approval.

## Decision
- `utility/<area>/<tool>/` holds independently launchable Godot projects used for experiments and tuning
  (first: `utility/movement/flat-plane/`). Each has its own `project.godot`, `README.md`, `tests/` and `config/`.
- Utilities use Godot primitives only, no new external dependencies, no Docker or Blender.
- Utilities never write into `SANDBOX/` or `SYSTEM-ROOMS/`. Findings flow back through the normal route: a tuned
  parameter set is exported as a preset (JSON) and, when it matters, becomes input to a system room proposal.
- The CLI treats utility projects like other Godot projects (`setup` imports them; suite `utility` runs their tests).
- Code follows `PROTOCOLS/CONVENTIONS.md` (no `class_name`, `preload` dependencies, pure logic separated from nodes).

## Consequences
+ Experiments are isolated from the multiplayer sandbox; breaking one cannot break the other.
+ Same runner, same conventions, same CLI.
- Another Godot project to import and test; shared code is not shared (Godot cannot load outside `res://`), so a
  utility that needs a system copies it deliberately.

## Alternatives considered
`SYSTEM-ROOMS/` - rooms are promoted into the sandbox and carry a contract; a tuning lab is not promoted.
`SANDBOX/godot/` - would couple an experiment to the network build and its version rules.
