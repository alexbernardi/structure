# Testing

## Suites (`python TOOLS/cli/structure.py test [suite ...]`)

| Suite | Covers | Needs | Typical time |
|---|---|---|---|
| `check` | static repo checks (`structure.py check`) | Python | < 2 s |
| `tools` | Python tooling: compat rules, snapshot safety, env validation, GLB validator, build tags, room hashing | Python | < 1 s |
| `import` | Godot import of every project + smoke load of every sandbox script/scene | Godot | ~10 s |
| `unit` | sandbox GDScript unit tests: world rules, persistence safety, protocol validation, config, world gen, asset import | Godot | ~5 s |
| `rooms` | each room's tests in isolation + a room scaffolded from `_TEMPLATE` (tests + benchmark); package rooms are tested in their workbench (`utility`) | Godot | ~10 s |
| `utility` | standalone utilities: the movement laboratory, i.e. the `movement_core` workbench suite (about 550 tests) | Godot | ~4 min |
| `labs` | every laboratory under `LABS/` + a laboratory scaffolded from `LABS/_TEMPLATE` with every package system installed | Godot | ~10 s |
| `pipeline` | asset library/manifest/consumer hashes + GLB validation (`--with-blender`: regenerate and compare bytes) | Python (+Blender) | < 1 s |
| `multiplayer` | native server + bot processes: two-client sync, cooperation, cheat suite, protocol mismatch, server full, graceful and crash persistence, data-dir lease, newer-schema refusal; the real client run headless (`--allow-headless`) following live events and exiting through the window-close path | Godot | ~50 s |
| `docker` | builds `structure-server:test`; container serves native bots; persistence across re-creation; graceful `docker stop`; Scenario B isolation | Docker | ~1-2 min |

Results summary: `.runtime/test-results/summary-<UTC>.json`. Logs of process tests: `.runtime/test-runs/<suite>-<UTC>/<test>/`.

## Writing GDScript tests

Files `test_*.gd` (extends `RefCounted`) in a project's `tests/`; methods `func test_<name>(t) -> void`.
Optional `before_each()` / `after_each()`. Each method gets a fresh instance. Coroutines (`await`) are supported.

| Assertion | Meaning |
|---|---|
| `t.ok(cond, msg)` | condition is true |
| `t.eq(actual, expected, msg)` / `t.ne(a, b, msg)` | type-aware equality (int/float and String/StringName compare by value) |
| `t.near(actual, expected, tol, msg)` | floats or `Vector3` within tolerance |
| `t.fail(msg)` | unconditional failure |
| `t.expect_engine_errors(n)` | the test intentionally provokes `n` engine errors |

Any unexpected engine or script error while a test runs fails it (captured with a `Logger`).

Benchmarks: `bench_*.gd` with `func bench_<name>(b)`; time exactly the measured loop and call
`b.record(name, ops, elapsed_usec, extra := {})`. Room targets live in `room.json` (`max_us_per_op`).

Run directly: `godot --headless --path <project> --script <repo>/TESTING/harness/run_gd_tests.gd -- --mode=test|bench|smoke --dir=res://tests [--filter=x] [--report=<abs.json>]`.

## Writing multiplayer tests

Use `structure_cli.procs`: `ServerProcess(...).start_and_wait_ready()`, `start_bot(...)`/`finish_bot(...)` or
`run_bot(...)`, `server.events("evt")`, `server.stop()` (graceful) / `server.kill()` (crash). Bot plans: `observe`,
`gather:<n>`, `cheat`, `wander` (+ `--bot-wait-players`, `--bot-until-progress`, `--bot-hold`). Assert on the bot's JSON
report, server log events and the saved `world.json`; call `assert_no_engine_errors` for the server log.

## Fixed seeds and determinism

World layouts derive from the seed with an engine-independent mixer (`world_gen.gd mix_seed`, value pinned by a test).
Benchmarks default to seed 4242. The movement room keeps a float32 golden trajectory (bit-exact on Windows).

## Not automated yet

Rendering/visual checks of the windowed client (a screenshot mode exists: `--screenshot=<abs.png>`), real human input
(see playtest task notes, e.g. `TASKS/0002-first-play-session.md`), Linux-native clients, and cross-machine networking.
Human sessions: the client logs a `client.session` summary on close - use it plus the server log as the playtest record.
