# Room: {{ROOM_NAME}}

TODO one paragraph: what this system is for and why it is developed in isolation.

## Status

| Item | State |
|---|---|
| Version | 0.1.0 (`room.json`, `src/system.gd` `VERSION`) |
| Status | experimental (experimental -> candidate -> stable) |
| Consumers | none yet |

## How to run

```powershell
python TOOLS/cli/structure.py room test {{ROOM_NAME}}      # isolated tests
python TOOLS/cli/structure.py room bench {{ROOM_NAME}}     # benchmarks vs room.json targets
python TOOLS/cli/structure.py room promote {{ROOM_NAME}}   # integration gateway (blocked until the contract is complete)
```

Open `SYSTEM-ROOMS/{{ROOM_NAME}}/project.godot` in the Godot editor for interactive experiments.

## Layout

`src/` promotable code - `tests/` isolated tests - `benchmarks/` measurements - `fixtures/` test data -
`tools/` room-specific scripts - `experiments/` competing variants - `integration/` promotion notes.
Delete folders you do not need; add a short README to any folder whose purpose is not obvious.

## Changelog

- 0.1.0 - created from `SYSTEM-ROOMS/_TEMPLATE`.
