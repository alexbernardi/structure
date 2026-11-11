# 0007 - Movement Lab 5.0: unified, intentional, upgradeable traversal

Status: in progress. Date: 2026-11-10. Branch: `benchmark/opus-traversal` (worktree `../structure-opus-traversal`,
from baseline `c3a5b49`). Scope: `utility/movement/flat-plane/` and workshop records only. No sandbox, protocol or
save-format change.

## Goal

Turn the 4.0 automatic vault into the base of one traversal system: vaults only on a Space press inside a visible,
predictable interaction region; jump, vault, mantle and (capability-granted) air jump chosen by one selector from
sensed geometry, momentum and character capability; numerical upgrades and new abilities layered through composable
modifiers on one controller (human, one cybernetic upgrade, one temporary magical effect).

## Acceptance criteria

1. Running at a wall never vaults without a press. A press inside the region vaults; outside it (or at an
   infeasible obstacle) the normal jump happens. Invalid presses never snap, rotate or teleport the body.
2. Presses are buffered (press during a vault's descent or just before landing chains into the next obstacle) and
   a short late window still vaults; later presses at a climbable obstacle mantle instead.
3. Authored 3.0/4.0 animations are kept; added moves use authored clips from the same CC0 package.
4. Attributes have units and defaults; modifiers (add / multiply / override, timed, sourced) combine in a fixed
   order, are removable, and never write the tuned baseline. Capabilities are separate from numbers.
5. Upgrades change feasibility and execution (heights, reach, impulse, gravity, costs), not animation speed only.
6. Expanded course: heights, depths, consecutive walls, angles, invalid regions, mixed elevation, upgrade gates.
7. Debug overlay shows sensed geometry, the interaction region, candidates and the selected path.
8. Existing suites keep passing (traversal tests updated to press Space, not weakened); new tests cover the above.

## Validation plan

Baseline focused traversal 17/17 (worktree, 2026-11-10). Focused suites while iterating; full utility regression
before each commit; headless lane trials with per-tick collider overlap checks as in 4.0.

## Progress

Status: implemented and objectively tested; awaiting the user's playtest (KI-024). Details, controls, architecture
and measurements: [Movement Lab 5.0](../DOCUMENTATION/MOVEMENT-LAB-5.md).

- Setup: the assigned branch did not exist; with the user's approval it was created from `c3a5b49` in its own
  worktree. Baseline there: focused traversal 17/17, full utility regression 499/499.
- Intentional vault: `vault_action.gd` keeps a planned, collision-checked `opportunity` inside an interaction
  region and never commits on its own. `traversal_controller.gd` commits on Space (early press arms the unchanged
  4.0 approach; late press uses `Planner.timing_at`). Presses outside the region are the normal jump.
- Unified selection: vault > mantle > jump on the ground; grab > air jump > buffer in the air; hold to grab; presses
  in a move's second half chain. Buffering mirrors the core's jump buffer tick for tick.
- Mantle / ledge grab with authored `ClimbUp_1m` (new extract `UAL2_Climb.glb`, byte-verified by the extraction
  tool; the vault extract is untouched), contacts measured by `tools/audit_climb_clip.gd`, root motion warped onto
  the measured ledge; air jump with authored `DoubleJump`.
- Capability layer in `capability/`; planner limits now come from attributes (defaults equal the 4.0 constants).
- Course lanes D-G; overlay draws the interaction region, ledges and mantle paths; readout says what Space will do.
- Tests: the 4.0 vault suite was changed only to press Space when a vault is offered (no assertion relaxed); the
  vault A/B and the course benchmark press the same way. New: 12 intent tests, 6 capability tests.
- One fix during validation: timed modifiers expired one tick late from float accumulation (now 1e-6 tolerance).
- Results: focused traversal 30/30, capabilities 6/6, Playground 6/6; final full utility regression **518/518**. Static
  `check`: 20 errors, all pre-existing links to the 4.0 evidence in the git-ignored `.runtime/` (absent in a fresh
  worktree); none from this task. Benchmark and native captures: see the 5.0 document.
- Open: user playtest and visual approval (KI-024); fall-landing overlap not isolated (KI-025); mantle has no hand
  IK; ledge grabs have no hang/shimmy; physical MIDI not exercised for 5.0 (no new MIDI controls were added).

Next steps: playtest lanes A-G with each profile; tune `vault_window`, `vault_late_window`, `mantle_reach` and
`grip_reach` by feel; then the next capabilities (wall run with the authored `WallRun_*` clips, slide with
`Slide_*`) as new rows in the selection table.
