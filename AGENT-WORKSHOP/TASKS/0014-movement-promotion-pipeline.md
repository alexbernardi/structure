# 0014 - Movement System promotion and the laboratory pipeline

Status: in progress. Date: 2026-11-11. Branch: `benchmark/opus-traversal` -> integration branch -> `main` (local).
Brief: "STRUCTURE - Movement System Promotion & Integration Pipeline" (the user; next: combat and weapons).
User decisions: promote `benchmark/opus-traversal` (not `copilot-fusion`, which was not inspected); merge into local
`main`, do not push.

## Inspection (before changes)

- One repository, remote `origin` (GitHub, public). Local `main` = `c3a5b49`, 16 commits ahead of `origin/main`
  (movement lab 2.0-4.0, never pushed); `origin/main` has nothing newer. `benchmark/opus-traversal` branched at
  `main`'s tip (merge-base = `main`), so `main` has not moved since the laboratory started.
- Worktrees: `structure` (main), `structure-opus-traversal` (this branch). Other branches: `copilot-fusion` (the other
  benchmark agent, at `c3a5b49`), `opus5.5`, `task/0003..0006` - none touched.
- Existing pipeline: ADR-0006 rooms (`SYSTEM-ROOMS/<room>/src` -> `SANDBOX/godot/systems/<room>`, hash-checked,
  `room promote` with gates and rollback). The `movement` room is the sandbox's server-validated FP model; the
  movement laboratory is a utility (ADR-0009: "never promoted").
- The movement code preloads absolute `res://` paths; its preload closure from the character's entry points is 35
  scripts, 3 GLBs and a bone map - no MIDI, tuning, world or legacy-animation code. The sandbox ticks physics at 60 Hz;
  movement is tuned at 120 Hz (dt is explicit, so a caller can tick it at 120 Hz).

## Plan and acceptance

1. Package the core inside the laboratory (`systems/movement_core/`, `git mv`, history kept), add the public entry
   point `movement_character.gd`, keep every laboratory test passing (552 before).
2. Package room `SYSTEM-ROOMS/movement_core` (1.0.0, CONTRACT, SPEC, changelog), pinned installs, release tags,
   `check` drift / version warnings; ADR-0010.
3. Laboratory tooling: `lab create / init / sync / validate / promote / list`, `LABS/_TEMPLATE`, `test labs`.
4. Reuse proof in the main project: `SANDBOX/godot/tests/unit/test_movement_core.gd` (input, run, jump, mantle,
   events to another node, modifier add / remove) with no laboratory code.
5. Documentation in AGENT-WORKSHOP; then promote with the tool itself (`lab promote --branch benchmark/opus-traversal
   --merge`), tag `movement_core/v1.0.0`.

## Validation

To be recorded.
