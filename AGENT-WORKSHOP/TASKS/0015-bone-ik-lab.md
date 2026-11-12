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

To be filled with commands and results (step 6).

## Outcome

To be filled (step 7).
