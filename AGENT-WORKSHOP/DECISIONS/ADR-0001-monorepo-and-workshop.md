# ADR-0001: Modular monorepo with a mandatory agent workshop

Status: Accepted (2026-10-27)

## Context
Development is AI-assisted. Agents start without conversation history, so the repository itself must carry the
process, the decisions and the current state. Systems should be developed in isolation and integrated deliberately.

## Decision
One Git repository with logical boundaries (`AGENT-WORKSHOP`, `SANDBOX`, `SYSTEM-ROOMS`, `COMMON-ASSETS`, `PIPELINES`,
`INFRASTRUCTURE`, `TESTING`, `TOOLS`). `AGENTS.md` sends every agent to `AGENT-WORKSHOP/START-HERE.md`; the workshop
protocol is mandatory. One CLI (`TOOLS/cli/structure.py`) wraps every workflow so agents and humans run identical commands.

## Deviations from the bootstrap brief's tree (deliberate)
- `TESTING/harness/` added: the shared GDScript runner (`run_gd_tests.gd`) used by the sandbox and every room.
- `.runtime/` (git-ignored) holds mutable local state: per-environment world data, logs, test runs, benchmark output.
  `.tools/` (git-ignored) holds the downloaded Godot build.
- `SANDBOX/godot/systems/` and `SANDBOX/godot/assets/common/` hold read-only, hash-tracked copies of promoted systems
  and deployed assets, because Godot cannot load files outside its project folder (`res://`).
- Empty category folders (e.g. `COMMON-ASSETS/textures`) are created when their first content arrives; their purpose
  is documented in the parent README instead of placeholder files.
- System rooms carry a `room.json` and a `project.godot` in addition to the requested contract files.

## Consequences
+ Cross-cutting changes are atomic; one place for decisions and history.
- The repository will grow; large binaries must go through Git LFS (ADR-0007).
- Copies inside the sandbox need drift checks (`structure.py check`).
