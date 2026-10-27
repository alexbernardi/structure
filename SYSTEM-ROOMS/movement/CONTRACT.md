# CONTRACT: movement 1.0.0

## Inputs and outputs

`step(velocity: Vector3, wish_dir: Vector3, on_floor: bool, jump: bool, delta: float, params: Dictionary) -> Vector3`

- `velocity` current velocity (m/s, world space). `wish_dir` world-space direction, only x/z used.
- `on_floor` from the caller's physics; `jump` true on the frame the jump was requested.
- Returns the new velocity. Never mutates its arguments.

## Data ownership

Owns no state. `params` (from `default_params()`) is owned by the caller; the server sends its copy to
clients in the welcome message so prediction and validation use identical values.

## Public interface

| Function | Purpose |
|---|---|
| `default_params() -> Dictionary` | walk_speed, ground_accel, ground_decel, air_accel, gravity, jump_velocity, max_fall_speed |
| `step(...) -> Vector3` | velocity integration |
| `max_horizontal_speed(params) -> float` | upper bound used by server movement validation |
| `max_vertical_speed(params) -> float` | upper bound used by server movement validation |
| `jump_apex_height(params) -> float` | design/test helper |
| `VERSION`, `MAX_DELTA` | constants |

Load with a relative or `res://systems/movement/` preload; no `class_name` (avoids global-class cache issues).

## Dependencies

Godot 4.7 core math only. No other systems, assets or autoloads.

## Events emitted and consumed

None. Pure function library.

## Multiplayer authority

Runs on clients for prediction. The server never trusts client velocity: it validates reported positions
against `max_horizontal_speed`/`max_vertical_speed` with a tolerance budget (`world/world_state.gd`
`request_move`). Any change to the bounds is therefore a gameplay-authority change and needs the multiplayer
suite to pass. Invariant (tested with 20k random steps): no input sequence exceeds the bounds.

## Performance targets

Measured on the dev machine (see `room.json` and `AGENT-WORKSHOP/INVENTORY/PERFORMANCE-BASELINES.md`):
`movement.step` <= 2.0 µs/op; one 30 Hz server tick for 64 players <= 150 µs.

## Automated tests

`tests/test_movement_model.gd`: speed cap, diagonal normalisation, braking time, jump apex, air control,
airborne jump rejection, delta clamping, terminal velocity, bound invariant (property test), golden trajectory.

## Integration requirements

Promoted copy lives in `SANDBOX/godot/systems/movement/`. After promotion the sandbox unit and multiplayer
suites must pass (the cheat suite checks the server still corrects teleports). Changing `default_params()`
changes server validation: bump `VERSION`, regenerate the golden fixture deliberately, note it in README.
