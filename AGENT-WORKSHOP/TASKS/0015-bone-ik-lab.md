# 0015 - Bone IK laboratory: Vitruvian skeleton (phases 0-1)
Status: in progress     Owner: Claude Opus 5.5 (agent)     Date: 2026-11-11

## Goal

A new, independent laboratory `bone_ik` (branch `lab/bone_ik`, worktree `../structure-lab-bone_ik`, project
`LABS/bone_ik/`) that builds the foundation for anatomical IK and, later, physics-driven characters: a parameterised,
anatomically constrained humanoid skeleton ("Vitruvian rig") that plays the project's existing authored animations.
Brief: the user's "STRUCTURE - BONE_IK LAB" prompt (2026-11-11). This task covers **phase 0 (preparation) and
phase 1 (the skeleton)** only; phases 2-5 (IK, active ragdoll, partial/full ragdoll, recovery) are designed in
[BONE-IK-LAB.md](../DOCUMENTATION/BONE-IK-LAB.md) and not implemented.

## Impact

- New: `LABS/bone_ik/` on `lab/bone_ik` (scaffolded by `lab create bone_ik --systems movement_core`, base `main`
  `8d60133`). New system code in `LABS/bone_ik/systems/bone_ik/` (not a package room yet; no consumers).
- Read-only use of the pinned `movement_core` 1.0.0 copy: only its CC0 Quaternius GLBs (listed as package assets in
  its CONTRACT) as the authored-animation source. No movement_core code is called; nothing installed is edited.
- Untouched: `main`, the Movement / Traverse laboratory (`utility/movement/flat-plane`, branch
  `benchmark/opus-traversal`), the camera and combat laboratories, the sandbox, wire and save formats.
- No new dependencies, no engine pin change (Godot 4.7.2-stable, built-in IK / physics only).

## Plan and acceptance criteria

1. Phase 0 research recorded in `RESEARCH/bone-ik-foundations.md` (engine facts probed from the pinned binary,
   IK / physics API survey, active-ragdoll techniques, the video reference and what could not be accessed).
2. Rig definition: proportions (1.80 m default, all requested parameters, presets, asymmetry), bone hierarchy
   (profile bones + twist helpers), landmarks and measurements; data-driven joint profile with sources.
3. Runtime: rig node (Skeleton3D, AnimationPlayer, modifier chain with stage probes, hard-limit modifier, twist
   helper driver), animation adapter (retarget humanoid-normalised clips, root-motion policy).
4. Visual lab scene with every requested view, overlay, readout and mode.
5. Automated tests (lab suite) for:
   - proportions (stature and span exact, scaling, validation, asymmetry);
   - rig integrity (hierarchy = profile, rest bases = profile, symmetry, invariance under proportion edits);
   - joint math (round trips, clamping, bending directions, hinge behaviour, soft load);
   - retargeting (tracks, no scale or limb-length change, global rotations identical to source, foot contact,
     limit violations per clip);
   - scene and API smoke.

Acceptance = the brief's phase 1 list: believable proportions; valid symmetric hierarchy; configurable dimensions;
correct bending directions; constrained tests respect limits; at least one authored clip retargets; runnable and
documented; Traverse behaviour unchanged.

## Validation

All in the laboratory worktree, Godot 4.7.2-stable, 2026-11-11.

| Command | Result |
|---|---|
| `python TOOLS/cli/structure.py lab validate` | **PASS**: `check` 0 errors / 0 warnings; `labs` 46 passed, 0 failed (44 bone_ik + 2 scaffold) and the freshly scaffolded `template_check` 2 / 2 |
| lab tests alone (`--dir=res://tests/bone_ik`) | 44 passed, 0 failed (proportions 8, rig integrity 8, joint limits 11, animation 4, runtime 7, body plan 2, scene 4) |
| `--mode=bench --dir=res://benchmarks` | joint limits (21 joints) 0.15 ms, axial alignment 0.13 ms, animation sample + full chain 0.27 ms per frame, rig from proportions 0.13 ms (GDScript, this machine) |
| `tools/retarget_report.gd` (51 clips) | orientation error 0.0000 deg and bone-length error 0 on every clip; 17 / 51 within all hard limits after alignment (8 before); table in `BONE-IK-ANIMATION.md` |
| still captures (`--capture`) | front T-pose, front neutral with limits, side neutral, perspective Jog_Fwd, perspective clamped manual pose, front Vitruvian preset, side ClimbUp_2m: rendered and inspected by the agent |
| isolation | `git diff main` outside `LABS/bone_ik` touches only workshop documents; `main` still `8d60133`, clean; no file of `utility/`, `SANDBOX/`, `SYSTEM-ROOMS/` or another laboratory changed |

Verified versus assumed:

- Verified by tests: everything in the acceptance list except "believable" (a human judgement) - proportions and
  stature exact, hierarchy = profile, symmetry, configurability, bending directions on both sides, constrained poses
  never beyond the hard limits, retargeting of all 51 clips, the scene and its controls (headless), the API stubs.
- Verified by measurement once: the physics backend (`DEFAULT` = GodotPhysics3D in 4.7.2).
- Not verified: the look of the skeleton in motion and of the proportions to a person; real mouse interaction; the
  reference video's content (inaccessible, KI-029); de Leva's segment lengths against the full paper (only the
  upper-arm mass fraction was cross-checked).

## Outcome

**Changes** (branch `lab/bone_ik`, commits after `a3b2d33` "lab bone_ik: create"):

- `LABS/bone_ik/systems/bone_ik/`: proportions, rig builder, humanoid bone set, swing-twist joint math, joint profile
  with lossless axial alignment, body plan; data `joint_limits.json` (21 joints, sources) and `body_plan.json`;
  humanoid clip adapter; modifiers (pose source, probes, axial alignment, limits with a policy, twist helpers); the
  rig entry point `vitruvian_rig.gd` 0.1.0 and its draft CONTRACT.
- `LABS/bone_ik/scenes/vitruvian_lab.*`, `viz/`: the visual workbench (main scene); `tests/bone_ik/` (44 tests and
  two helpers); `benchmarks/bench_rig.gd`; `tools/retarget_report.gd`. The scaffold's `lab.tscn` and its test are kept.
- Workshop: research note, three documentation pages, ADR-0011 (proposed), KI-027..029, START-HERE row, indexes.

**Decisions**: rest orientations = SkeletonProfileHumanoid's (exact retargeting of every profile-normalised clip);
anatomy as data with soft ~ clinical active range and hard ~ passive range + margin; one ordered modifier chain with
stage probes; lossless axial alignment of hinges, forearm roll and straight-limb roll splits; limit policy
PROCEDURAL by default (authored clips measured, not clamped - the brief forbids degrading working animation);
twist helpers as leaf bones; 16 physical bodies for 29 animation bones. Jolt for phase 3 is proposed, not applied.

**Open problems**: KI-027 (no human review yet; authored clips exceed per-segment limits by convention; foot contact
residue up to 2.6 cm in locomotion), KI-028 (physics backend decision), KI-029 (video). Elliptical swing cones for
shoulder and hip; no fingers; no skinned body.

**Next steps** (need the user): review the lab (`& $godot --path LABS\bone_ik` in the worktree); accept or amend
ADR-0011 (especially Jolt for phase 3); approve phase 2 as proposed in `BONE-IK-LAB.md` section 5. Nothing was pushed
or merged into `main`; promotion is `lab promote bone_ik` when the user asks.
