# ADR-0011: The Vitruvian rig - profile-oriented anatomical skeleton, data-driven joint profile, physics on Jolt

Status: Proposed (2026-11-11, task 0015). Laboratory-internal until the user accepts it; nothing outside
`lab/bone_ik` depends on it.

## Context

The `bone_ik` laboratory builds a reusable anatomical skeleton for IK and, later, physics-driven characters, while
keeping the project's authored-animation workflow (Quaternius CC0 clips through Godot's humanoid import). Evidence
gathered in phase 0-1 (research note `RESEARCH/bone-ik-foundations.md`):

- Godot's importer overwrites humanoid rests with `SkeletonProfileHumanoid`'s orientations; every imported clip's
  rotation keys are relative to those orientations (verified to 0.01 degrees).
- Godot's `JointLimitationCone3D` is a single symmetric cone: it cannot express hinge joints, asymmetric flexion /
  extension or twist ranges.
- Authored clips contain non-anatomical but visually harmless rotations (sideways hinges, forearm roll on the hand,
  a full extra turn on straight arms) and concentrate spine / neck motion in single bones.
- `physics/3d/physics_engine = DEFAULT` runs GodotPhysics3D in 4.7.2 (verified behaviourally); Jolt is built in.

## Decision

1. **Rest orientations = the humanoid profile's**, positions = anthropometric proportions. Any clip imported with the
   humanoid BoneMap plays with no rotation conversion; only the Hips translation is rescaled (by hip-joint height).
   Canonical names and hierarchy are the profile's 23 body bones; extra bones are leaf helpers only.
2. **Anatomy is data**: proportions (ratios of stature, vertical weights normalised to the stature), joint profile
   (`joint_limits.json`: frames, swing-twist ranges with soft and hard limits, sources; right side mirrored) and body
   plan (`body_plan.json`: 16 rigid bodies for 29 animation bones, de Leva masses).
3. **One ordered modifier chain** owned by the rig: source -> probe -> IK slot -> probe -> lossless axial alignment
   -> anatomical limits (policy: procedural poses clamped, authored playback measured) -> twist helpers -> probe ->
   physics slot. Our own limit modifier replaces `JointLimitationCone3D` for anatomy.
4. **Proposed, needs approval**: the laboratory project sets `physics/3d/physics_engine = "Jolt Physics"` when phase 3
   starts (not before), because joint-driven ragdolls are a stability problem and Jolt is Godot's recommended 3D
   engine. Engine pin unchanged; other projects unchanged.

## Consequences

- (+) Any profile-normalised humanoid clip retargets exactly (0.0000 degrees on 51 clips); proportions are free.
- (+) Joint limits, sources and masses are reviewable and tunable without code; tests assert symmetry and directions.
- (+) IK and physics have reserved places in the chain and in the interface; diagnostics separate the stages.
- (-) Rigs with foreign rest orientations (a future skinned character) need re-import or `RetargetModifier3D`.
- (-) Per-segment limits judge authored clips harshly (17 / 51 clean); hence the measure-only default for authored
  playback, and chain redistribution as phase 2 work.
- (-) Elliptical swing cones approximate the shoulder and hip; reach cones are the planned successor.
- Follow-up: phase 2 plan in `DOCUMENTATION/BONE-IK-LAB.md`; a package room `SYSTEM-ROOMS/bone_ik` only when another
  project consumes the system.

## Alternatives considered

- Copy the Quaternius rests (what `movement_core` does) - ties proportions to one source rig; no anatomical frames.
- Engine IK joint limits only (`JointLimitationCone3D`) - cannot express hinges, asymmetric ranges or twist.
- Euler-angle limits - gimbal lock at the shoulder; swing-twist avoids it below 180 degrees.
- Stay on GodotPhysics3D for phase 3 - possible, but weaker joint stability; to be measured if Jolt is not approved.
