# SYSTEM-ROOMS - independent development laboratories

Each room develops one gameplay system in isolation: its own tiny Godot project, spec, contract, tests,
benchmarks and experiments. Tested systems enter the sandbox only through the integration gateway
(`AGENT-WORKSHOP/PROTOCOLS/INTEGRATION-GATEWAY.md`).

| Room | Status | Summary |
|---|---|---|
| [`_TEMPLATE`](_TEMPLATE/README.md) | template | scaffold for new rooms (`structure.py room new <name>`) |
| [`movement`](movement/README.md) | stable 1.0.0, integrated | deterministic FP movement model + speed bounds used for server validation |
| [`movement_core`](movement_core/README.md) | stable 1.0.0, package (workbench `utility/movement/flat-plane`) | the approved movement character: locomotion, traversal, capabilities, authored IK presentation |

## Room contract

```
SYSTEM-ROOMS/<system>/
  README.md  SPEC.md  CONTRACT.md  room.json  project.godot
  src/  tests/  benchmarks/  experiments/  fixtures/  tools/  integration/
```

`CONTRACT.md` must cover: inputs and outputs, data ownership, public interface, dependencies, events emitted and
consumed, multiplayer authority, performance targets, automated tests, integration requirements (responsibilities
and scope are in `SPEC.md`). `room.json` mirrors the machine-checkable parts.

Package rooms ([ADR-0010](../AGENT-WORKSHOP/DECISIONS/ADR-0010-shared-systems-and-laboratories.md)) have no `src/`:
`room.json` `package` points at the source in a workbench laboratory, and every project mounts the package at
`res://systems/<room>/` (installed by `room install`), so their internal paths are absolute under that mount.

Rules: relative preloads only (package rooms: absolute under their mount), no `class_name`, no autoloads; measured benchmark targets; experiments live in
`experiments/` until promoted. Candidate future rooms: AI/A-Life, construction, interactions, inventory, economy,
factions, weather/ecology, networking/replication.
