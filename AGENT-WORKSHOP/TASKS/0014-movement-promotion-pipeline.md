# 0014 - Movement System promotion and the laboratory pipeline

Status: done; `main` updated locally (not pushed). Date: 2026-11-11. Branch: `benchmark/opus-traversal` -> integration branch -> `main` (local).
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

## Results

- **Movement Core 1.0.0**: 39 files moved with `git mv` into `utility/movement/flat-plane/systems/movement_core/`
  (82 files with `.uid` / `.import` / assets), 71 files' references rewritten, public entry point
  `movement_character.gd`; laboratory-only input actions split out. Audit: no laboratory references, debug prints or
  randomness in the package; the only clock read times the vault planner (telemetry).
- **Room** `SYSTEM-ROOMS/movement_core` (CONTRACT with the required sections, SPEC, README with version table,
  integration history); release tag `movement_core/v1.0.0` at `84c88fd`.
- **Tooling**: `packages.py` (install / status / drift / compatibility / release tags), `labs.py` (create, init,
  sync, validate, promote, list), `room install` / `room release`, suite `labs`, `check` covers package consumers;
  `LABS/_TEMPLATE` (120 Hz project, test ground with the character, smoke tests).
- **Main game**: `movement_core` 1.0.0 installed in `SANDBOX/godot/systems/movement_core/`;
  `tests/unit/test_movement_core.gd` (3 tests) builds the character with no laboratory code, drives it from the
  `move_forward` action (6 m/s), jumps (landing reported), mantles a 1.4 m block (`traversal_started` / `finished`
  "mantling" heard by a listener node), and adds / removes a modifier (speed x1.5, an air jump, slide revoked and
  restored; cybernetic legs raise the mantle height and removing them restores it).

## Validation

- Workbench suite after the move: 552 passed, 0 failed (222 s). `room bench movement_core`: simulate tick 63.8 us,
  present frame 173.8 us (targets 250 / 700 us). Python tool tests: 13 new, all pass.
- All gates on the branch: check, tools, import, unit, rooms, utility, labs, pipeline, multiplayer - PASS
  (docker not run: not needed for this change). `check`: 0 errors, 0 warnings, after the 4.0 docs' 20 links to
  git-ignored local evidence became plain paths.
- **Promotion** (`lab promote --branch benchmark/opus-traversal --merge`): the first attempt stopped before merging
  (no git identity on this machine; the tool misreported it as a conflict - fixed: identity preflight, honest
  message); the second merged cleanly into `integrate/...` from `main` `c3a5b49`, passed check, tools, import (incl.
  `setup`), unit, rooms, utility, labs there, and fast-forwarded `main` to the validated merge **`84c88fd`**. A
  follow-up promotion against the moved `main` (1 ahead, 1 behind) merged, passed every gate and fast-forwarded
  `main` to `99f55ea`, removing its integration worktree (the first one, inside `.runtime`, hit Windows' 260-character
  limit: integration worktrees are now short sibling folders, removed with long-path support). The last tooling fix
  (below) is promoted the same way; the final `main` commit is in START-HERE / the closing report.
- **Laboratory trial** (from `main`, then removed): `lab create pipeline_trial --systems movement_core@1.0.0`
  installed from the release tag with the same hash as the source; `lab validate` passed; `lab sync` merged `main`;
  a deliberate conflict (both sides edited `LABS/README.md` line 1) was reported by `lab promote --base trial/base`
  (file listed, `main` and the lab untouched) and by `lab sync --base trial/base` (merge left in progress, nothing
  overwritten, `git merge --abort` restored it). Found: a fresh lab looked dirty after its first import (Godot `.uid`
  files) - fixed (`lab init` imports before its commit; re-checked: 0 changes after `lab validate`, 38 `.uid` files committed).
- Not verified: the movement character's feel inside a laboratory scene other than the workbench (the template's test
  ground was only run headless); `git push` (the user's step).

## Manual actions for the user

- Publish when ready: `git push origin main` and `git push origin movement_core/v1.0.0` (local `main` was already 16
  commits ahead of `origin/main` before this task).
- Set a git identity on this machine (`git config --global user.name` / `user.email`); promotions here used the
  `GIT_AUTHOR_*` / `GIT_COMMITTER_*` variables with the identity already used on this branch.
- Next: `python TOOLS/cli/structure.py lab create combat --systems movement_core`.
