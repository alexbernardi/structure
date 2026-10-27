# ADR-0006: System rooms as standalone Godot projects, promoted by hash-tracked copy

Status: Accepted (2026-10-27)

## Context
Systems must be designed, tested and benchmarked independently, then consumed by the sandbox through stable
interfaces without duplicated logic. Godot can only load resources inside its own project folder.

## Decision
- Each room is a minimal Godot project (`project.godot`) with `README/SPEC/CONTRACT.md`, `room.json` (version, status,
  public interface, dependencies, integration target, benchmark targets) and `src/ tests/ benchmarks/ experiments/
  fixtures/ tools/ integration/`. This is the smallest isolation mechanism that is independently runnable headless
  and openable in the editor.
- Room code uses relative preloads only, so `src/` works unchanged at `SANDBOX/godot/systems/<name>/`.
- `structure.py room promote` (integration gateway) checks contract completeness, tests, measured benchmarks and
  declared dependencies, copies `src/`, writes `INTEGRATION.json` (hashes, versions, benchmarks), runs the sandbox
  suites and rolls back automatically on failure. `structure.py check` fails on edits made directly in the sandbox copy.
- `_TEMPLATE` scaffolds new rooms (`room new`); its contract placeholders block promotion until written.

## Consequences
+ The sandbox consumes exactly the tested code; drift is detectable; rollbacks are file copies or git reverts.
- Copies exist twice in the repository (small text files; acceptable).
- Rooms that need other systems must declare them; cross-room dependencies are not automated yet.
