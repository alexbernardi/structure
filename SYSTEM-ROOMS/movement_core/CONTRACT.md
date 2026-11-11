# CONTRACT: movement_core 1.0.0

The stable interface other systems and laboratories may rely on. Everything not listed here is private and may
change in any minor version. Architecture and internals: [MOVEMENT-CORE.md](../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-CORE.md).

## Inputs and outputs

**Input frame** (one per physics tick, `movement_character.simulate(frame, dt)`):

| Key | Type | Meaning |
|---|---|---|
| `move` | `Vector2` | stick / WASD: x = right, y = forward, length <= 1 |
| `yaw` | `float` | camera heading in radians (0 looks along -Z); `move` is relative to it |
| `jump_pressed` | `bool` | Space went down this tick (jump, vault, climb, catch, pull up, flip from a crouch) |
| `jump_held` | `bool` | Space is held |
| `sprint` | `bool` | sprint held |
| `crouch` | `bool` | crouch held (crouch; at speed: slide; while hanging: let go) |

`movement_character.empty_frame(yaw)` returns a neutral frame. `dt` must be `1.0 / movement_character.TICK_RATE`
(120 Hz): the movement and traversal are tuned and tested at that rate.

**Outputs**: the body's transform and velocity (`velocity()`), `state`, the signals below, `snapshot()`, and the drawn
character (`present(delta)` once per rendered frame).

## Data ownership

The character owns its body, collider, movement core state, traversal state, capability layer (modifiers, resources)
and presentation. Callers own the input frames, the world geometry and the camera. Baseline parameters
(`params`, `traversal_params`, `locomotion_params`) belong to the character and may be tuned by the owner; effective
values come from the capability layer. Modifiers are created by the caller and owned by the character once added.

## Public interface

`res://systems/movement_core/movement_character.gd` (extends `Node3D`; no `class_name`, preload it):

| Member | Purpose |
|---|---|
| `VERSION`, `TICK_RATE`, `STATES`, `TRAVERSAL_STATES` | constants |
| `build()` | assemble (called by `_ready` if not called first); set `presentation`, `traversal_clips`, parameters before |
| `simulate(frame, dt)` | one fixed tick |
| `present(delta, animate := true)` | one rendered frame of the drawn character |
| `drive_self`, `input_yaw` | let the node read the keyboard and drive itself |
| `register_input_actions()` (static), `empty_frame(yaw)` (static) | input helpers |
| `state`, `current_state()`, `velocity()`, `grounded()`, `traversing()` | movement state |
| `can(capability)`, `attribute(id)`, `snapshot()` | capabilities and effective attributes |
| `add_modifier(modifier)`, `remove_modifier(id)` | equipment, upgrades, spells, injuries (`capability/movement_modifier.gd` `make(...)`) |
| `set_traversal_enabled(on)` | restrict / allow every traversal move |
| `apply_impulse(impulse) -> bool` | knockback; refused while a traversal move owns the body |
| `spawn(transform)`, `teleport(position, basis)`, `respawn()`, `note_teleport()` | placement |
| `set_presentation(on)`, `toggle_skeleton_view()`, `create_debug_overlay()` | presentation and debugging |
| `body`, `visual`, `animation`, `traversal`, `capabilities` | read-only access for diagnostics and tools; not for writing |

Also stable: `capability/movement_modifier.gd` (`make`, ops add / mul / set / cap / floor, grants, revokes, durations),
the attribute ids and capability ids in `capability/movement_attributes.gd`, the example modifiers in
`capability/movement_profiles.gd`, the input frame in `movement/input_source.gd`, and the action names in
`movement/input_actions.gd`.

**Mount**: every consumer project mounts the package at `res://systems/movement_core/` (installed by
`structure.py room install movement_core <project>`). Internal paths are absolute under that mount.

## Dependencies

Godot 4.7 (Forward+ for the drawn character; headless works). No other systems, autoloads or `class_name`s. Bundled
assets: Quaternius Universal Animation Library 1 and 2 (CC0) in `assets/quaternius/` (three GLBs, the bone map).

Project requirements: physics ticked at 120 Hz by whoever calls `simulate` (the node's own `drive_self` uses
`_physics_process`, so set `physics/common/physics_ticks_per_second=120` for it); physics interpolation recommended.
World geometry on collision layer 1; the character is on layer 2 and collides with layer 1 only. Input actions
`move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `crouch` (registered at runtime if missing).
Coordinates: Y up, -Z forward, metres, seconds, radians.

## Events emitted and consumed

Emitted by `movement_character.gd`: `landed(impact_speed)`, `respawned`, `state_changed(previous, current)`,
`traversal_started(move)`, `traversal_finished(move)`, `capabilities_changed`. Consumed: none (the caller pushes
input frames).

## Multiplayer authority

Not yet networked. The character is deterministic per tick for a given input frame sequence (fixed `dt`, no random
numbers; the only clock reads time the vault planner for telemetry), which is what server-authoritative movement with client prediction
needs, but the sandbox server still validates movement with the `movement` room's model. Wiring this character into
the authoritative server (input messages, server simulation, snapshots, reconciliation) is a separate, versioned
change that must bump the protocol version (`PROTOCOLS/VERSIONING.md`). `snapshot()` is the state to replicate.

## Performance targets

Measured on the development machine by `structure.py room bench movement_core` (targets in `room.json`): one
`simulate` tick on flat ground and one `present` frame of the drawn character, headless.

## Automated tests

In the workbench (`utility/movement/flat-plane/tests/`, about 550 tests): movement core, collision body, every
traversal move and its refusals, capabilities and modifiers, authored animation and IK, the skeleton view, terrain
feet, hanging and corners. In the sandbox (`SANDBOX/godot/tests/unit/test_movement_core.gd`): the installed package
loads, a character is built in a minimal world with no laboratory code, runs, jumps, mantles a box, reports its state
and events to another node, and takes and loses a modifier.

## Integration requirements

Consumers install a pinned version (`structure.py room install movement_core <project> [--version X.Y.Z]`); the
copy is read-only and `structure.py check` reports drift. Minor versions add to this contract without breaking it;
a major version may break it and must ship migration notes in the room README. A consumer's tests that use the
character must pass before a promotion into `main`.
