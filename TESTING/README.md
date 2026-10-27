# TESTING

| Folder | Contents |
|---|---|
| `harness/run_gd_tests.gd` | shared GDScript test/benchmark/smoke runner for every Godot project |
| `unit/tools/` | Python unit tests for the tooling (`structure.py test tools`) |
| `multiplayer/` | native server + bot clients suite (`test multiplayer`) |
| `integration/` | Docker suite: containers, persistence, Scenario B (`test docker`) |
| `performance/baselines/` | recorded benchmark baselines (`structure.py bench ... --record`) |
| `fixtures/worlds/` | world documents of each released schema version (compatibility guarantees) |

GDScript unit tests live inside their Godot project (`SANDBOX/godot/tests/`, `SYSTEM-ROOMS/<room>/tests/`) because
Godot can only load files from its own project. Full guide: `AGENT-WORKSHOP/DOCUMENTATION/TESTING.md`.
