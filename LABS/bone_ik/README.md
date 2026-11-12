# bone_ik laboratory - the Vitruvian skeleton

Created by `python TOOLS/cli/structure.py lab create bone_ik --systems movement_core` from an approved `main`.
Branch `lab/bone_ik`, in its own worktree. Pinned systems and the base commit: `lab.json`.

## Goal

A reusable anatomical skeleton for Structure: a parameterised humanoid ("Vitruvian rig") with anatomical joint
limits that plays the project's authored animations, as the foundation for IK (phase 2), muscle-like physics
(phase 3), partial / full ragdoll (phase 4) and physical recovery (phase 5). Phase 1 = the skeleton; done when it
is believable, symmetric, configurable, bends the right way, respects documented limits, plays authored clips and
is runnable and documented, with the Traverse / Movement laboratory untouched.

- Open `LABS/bone_ik` in Godot: the main scene `scenes/vitruvian_lab.tscn` is the Vitruvian workbench.
  `scenes/lab.tscn` is the scaffold's test ground with the approved movement character (kept, tested).
- The system under development is `systems/bone_ik/` (entry point `vitruvian_rig.gd`, draft `CONTRACT.md`). It is
  not a package room yet (no consumer), so `lab.json` lists no `develops` entry; its tests run in the `labs` suite.
- `systems/movement_core/` is a pinned, read-only copy; only its CC0 clips are used.
- Documentation: `AGENT-WORKSHOP/DOCUMENTATION/BONE-IK-LAB.md` (run, architecture, results, phase 2 plan),
  `BONE-IK-PROPORTIONS.md`, `BONE-IK-ANIMATION.md`, `RESEARCH/bone-ik-foundations.md`, ADR-0011 (proposed), task 0015.
- Process: [LABORATORY-PIPELINE.md](../../AGENT-WORKSHOP/PROTOCOLS/LABORATORY-PIPELINE.md) - `lab validate`,
  `lab sync` (bring in newer `main`), `lab promote bone_ik`.
