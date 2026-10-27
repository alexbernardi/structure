# ADR-0008: Testing strategy

Status: Accepted (2026-10-27)

## Context
Tests must exist from the first day, run headless on Windows and in Linux containers, and be easy for agents to
extend without third-party frameworks.

## Decision
- **GDScript**: one shared runner, `TESTING/harness/run_gd_tests.gd`, executed with `--script` against any Godot
  project (sandbox or room). Modes: `test` (`test_*.gd` / `func test_*(t)`), `bench` (`bench_*.gd` / `b.record()`),
  `smoke` (load every script and scene). It registers a `Logger`, so **any engine/script error during a test fails it**
  unless declared with `t.expect_engine_errors(n)`.
- **Python**: stdlib `unittest` for tooling and for orchestration suites.
- **Multiplayer**: real processes - a native headless server plus headless bot clients speaking the player protocol
  (plans: `observe`, `gather:<n>`, `cheat`, `wander`), each writing a JSON report. Suites assert on bot reports,
  server log events and saved files, and fail on unexpected engine errors in server logs.
- **Docker**: the same bots connect to containers through published ports.
- `structure.py test` runs the suites in order (check, tools, import, unit, rooms, pipeline, multiplayer, docker) and
  records a summary in `.runtime/test-results/`.

## Consequences
+ No external dependencies; identical commands for agents and humans; tests catch silent script errors.
- Process-based multiplayer tests take ~40 s; docker tests ~1-2 min including the image build.
