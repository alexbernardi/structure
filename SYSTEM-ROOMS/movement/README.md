# Room: movement

Deterministic first-person movement model. **Status: stable**, integrated into the sandbox as
`SANDBOX/godot/systems/movement/` (see `integration/README.md`).

## Status

| Item | State |
|---|---|
| Version | 1.0.0 (`src/movement_model.gd` `VERSION`) |
| Consumers | `client/player_controller.gd` (prediction), `world/world_state.gd` (server speed validation) |
| Tests | `tests/test_movement_model.gd` - 10 tests incl. 20k-step random property test and golden trajectory |
| Benchmarks | `benchmarks/bench_movement_model.gd` - targets in `room.json` |

## How to run

```powershell
python TOOLS/cli/structure.py room test movement     # isolated tests (this folder is its own Godot project)
python TOOLS/cli/structure.py room bench movement    # benchmarks vs room.json targets
python TOOLS/cli/structure.py room status movement   # integrated? drift? pending changes?
python TOOLS/cli/structure.py room promote movement  # integration gateway (see AGENT-WORKSHOP/PROTOCOLS/INTEGRATION-GATEWAY.md)
```

Open `SYSTEM-ROOMS/movement/project.godot` in the Godot editor to experiment in isolation.

## Layout

| Folder | Purpose |
|---|---|
| `src/` | The promotable implementation (only this folder is copied into the sandbox) |
| `tests/` | Isolated tests; `trajectory_sim.gd` is a shared helper, not a test |
| `benchmarks/` | Measured performance; targets live in `room.json` |
| `fixtures/` | `golden_trajectory.json` - determinism reference |
| `tools/` | `make_golden.gd` - regenerate the fixture after an intentional model change |
| `experiments/` | Alternative implementations under evaluation (none yet) |
| `integration/` | Promotion notes and history |

## Changelog

- 1.0.0 (2026-10-27) - initial model: ground/air acceleration, braking, jump, gravity, fall cap; speed bounds.
