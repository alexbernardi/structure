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

(recorded at the end of the task)
