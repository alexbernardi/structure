# Integration: movement

| Field | Value |
|---|---|
| Target | `SANDBOX/godot/systems/movement/` |
| Record | `SANDBOX/godot/systems/movement/INTEGRATION.json` (version, source hash, benchmarks, git commit) |
| Consumers | `client/player_controller.gd`, `world/world_state.gd` |
| Rollback | `git revert` of the promotion commit, or the automatic copy in `.runtime/promotions/` |

Promote with `python TOOLS/cli/structure.py room promote movement`; check state with `room status movement`.
`structure.py check` fails if the sandbox copy is edited directly (hash drift).

## History

- 1.0.0 - initial integration (bootstrap).
