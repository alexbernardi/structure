# Bone IK foundations - phase 0 research (task 0015)

Research for the `bone_ik` laboratory: what the pinned engine offers for skeletons, IK and physical characters,
what that means for a Vitruvian rig, and what the reference video could and could not tell us. **Verified** means
probed from the pinned Godot 4.7.2-stable binary in this repository (scripts kept out of the repo; the results are
quoted here). **Documented** means taken from Godot's official docs or release articles. **Inferred** is our reading.

## 1. Engine and physics backend (verified)

| Fact | Value | How |
|---|---|---|
| Engine | Godot 4.7.2-stable (official, `ed1daf0bf`) | `Engine.get_version_info()` in the lab project |
| `physics/3d/physics_engine` in Structure projects | `DEFAULT` (not set in any `project.godot`) | `ProjectSettings` probe |
| Allowed values | `DEFAULT`, `Jolt Physics`, `GodotPhysics3D`, `Dummy` | the setting's hint string |
| **What `DEFAULT` runs** | **GodotPhysics3D**, not Jolt | a box dropped and rotated for 90 ticks gives identical positions under `DEFAULT` and `GodotPhysics3D` (0.003244, 0.494736, -0.183855) and different ones under `Jolt Physics` (0.030227, 0.499847, -0.199643) |
| Jolt available | yes, built in (`physics/jolt_physics_3d/*` settings exist) | settings probe |

So Jolt is the default only for projects that name it (new projects get it written into `project.godot`); every
Structure project currently simulates with Godot Physics. Phase 1 simulates nothing, so this does not matter yet.
For phases 3-5 (joint-driven ragdolls) Jolt is the better candidate (sub-stepped constraint solver, more stable
joint chains; Godot's own recommendation since 4.4). Switching the laboratory project to Jolt is a one-line setting,
but it changes the physics model, so it is **proposed in ADR-0011 for the user's approval**, not done.

## 2. Skeleton, profile and retargeting (verified + documented)

- **`Skeleton3D`**: bones with rest and pose transforms; `motion_scale` scales position tracks; modifiers run in the
  skeleton's own deferred update (`modifier_callback_mode_process`: idle / physics / manual + `advance()`).
  **Observed**: a modifier's output exists only during that update. Outside it `get_bone_pose_*` returns the
  unmodified input (animation or code), so modifier results never accumulate, and diagnostics must snapshot inside
  the chain (our `PoseProbeModifier`).
- **`SkeletonProfileHumanoid`** (56 bones: 23 body, 30 fingers, eyes, jaw; root `Root`, scale base `Hips`): its
  reference pose is a T-pose facing **+Z with the character's left at +X**, every bone's +Y pointing down the bone.
  We dumped all 56 reference transforms; the global bases are the rig's rest orientations.
- **`BoneMap` + importer rest fixer**: imported humanoids (the Quaternius GLBs in `movement_core`) are renamed to the
  profile and their rests are **overwritten with the profile's orientations** ("overwrite axis"); position tracks are
  divided by `motion_scale` (the hips height). Verified on `UAL1_Standard.glb`: `A_TPose` keys equal the rests,
  the Hips key is (0, 1.0, -0.0547) = rest / 0.9167, and every normalised rest basis equals the profile's within
  0.01 degrees. **Consequence (the key design decision)**: a rig built with the profile's rest orientations accepts
  any such clip with no rotation conversion at all, whatever its proportions.
- **`RetargetModifier3D`** (4.4+) retargets at runtime between a source and a target that share a profile, keeping
  the target's own rests. Not needed when the rest orientations are already the profile's; kept in mind for rigs with
  foreign rests (a future skinned character).

## 3. IK and constraint modifiers (verified class list, documented behaviour)

Present in the binary (ClassDB): `SkeletonModifier3D` -> `IKModifier3D` -> `TwoBoneIK3D`, `ChainIK3D` ->
`IterateIK3D` -> `FABRIK3D`, `CCDIK3D`, `JacobianIK3D`; `ChainIK3D` -> `SplineIK3D`; `JointLimitation3D` ->
`JointLimitationCone3D`; `LookAtModifier3D`, `BoneConstraint3D` (`AimModifier3D`, `CopyTransformModifier3D`,
`ConvertTransformModifier3D`), `BoneTwistDisperser3D`, `LimitAngularVelocityModifier3D`, `ModifierBoneTarget3D`,
`SpringBoneSimulator3D`, `PhysicalBoneSimulator3D`, `RetargetModifier3D`, the deprecated `SkeletonIK3D`.

| Class | Useful for | Notes |
|---|---|---|
| `TwoBoneIK3D` | arms and legs (phase 2) | analytic, deterministic; target + pole node or pole direction; `use_virtual_end`, `extend_end_bone`; per-setting chains (`setting_count`) |
| `FABRIK3D`, `CCDIK3D`, `JacobianIK3D` | spine, neck, fingers, multi-joint reach | `max_iterations`, `min_distance`, `angular_delta_limit`, `deterministic` (state carried between frames unless deterministic, which is the multiplayer-friendly mode); per-joint rotation axis and `JointLimitation3D` |
| `JointLimitationCone3D` | IK joint limits | one property: `angle` (a symmetric cone) plus the joint's right axis and rotation offset. **Too coarse for anatomy** (no asymmetric flexion/extension, no twist range, no hinge). A forum report (4.6 beta) says FABRIK/Jacobian behave unexpectedly with cone limits. Hence our own anatomical limit modifier after the IK stage |
| `LimitAngularVelocityModifier3D` | smoothing deterministic IK and transitions | caps per-bone angular speed; candidate for phase 2 influence blending and phase 5 recovery |
| `BoneTwistDisperser3D` | twist bones | spreads a descendant's twist along a chain; it needs the twist bones *in* the chain, which would break humanoid track semantics, so our helpers are leaf bones driven by `TwistHelperModifier` |
| `SkeletonModifier3D.influence` | layering | blends a modifier's result with its input; the basis for "IK influence without snapping" |

Ordering (documented): modifiers run in child order of the `Skeleton3D`; the last writer wins. Our chain fixes the
order and reserves the IK slot (`BONE-IK-LAB.md`).

## 4. Physical bones and active ragdolls (documented + inferred)

- **`PhysicalBone3D`** (a `PhysicsBody3D` per simulated bone) under **`PhysicalBoneSimulator3D`** (a modifier, 4.3+):
  joint types none / pin / cone / hinge / slider / 6DOF with limits; `mass`, `friction`, `linear/angular_damp`,
  `apply_impulse`, `_integrate_forces` with a custom integrator. Simulation can start for a subset of bones
  (`physical_bones_start_simulation(bones)`) - the hook for **partial ragdolls**. As a modifier, its `influence`
  blends physics and animation.
- **What a muscle-like body needs** (literature and common practice, inferred for Godot):
  1. *Pose tracking*: per joint, a PD (spring-damper) torque `tau = k_p * angle_error - k_d * relative_angular_velocity`
     towards the animated target pose, applied in `_integrate_forces` or through 6DOF angular motors. Gains scale
     with segment inertia so light and heavy bodies behave the same (stable PD: Tan, Liu & Turk 2011, "Stable
     Proportional-Derivative Controllers", IEEE CG&A).
  2. *Torque limits* (`max_torque_nm` per joint) so impacts can overpower muscles: this is what separates "subtle
     secondary motion" from "knocked over".
  3. *Soft limits*: resistance rising through the soft zone to the hard limit (our `soft_load` 0..1 is that input),
     plus joint friction and angular damping.
  4. *Rest tension*: a weak tracking of a relaxed pose when no animation drives a joint (a limp body is the special
     case of zero gains).
  5. *Mass distribution*: segment masses and inertia from anthropometry (de Leva 1996 fractions, already in the body
     plan) - armour adds mass and changes inertia without changing the skeleton.
  6. *Balance*: centre of mass over the support polygon decides between "stagger" (partial) and "fall" (full).
- **Stability** (inferred, to be measured in phase 3): small-mass segments (hands, feet) next to heavy ones (trunk)
  make stiff chains; Jolt's sub-stepping and velocity/position step settings help; 120 Hz physics (the laboratory's
  rate) is the target; joint chains should be checked for drift and explosion at 60 Hz too.

## 5. The reference video

URL: <https://www.youtube.com/watch?v=yY6vck8SuCY&t=319s>. **What could be accessed**: its oEmbed record - title
"Improving ragdolls forever", channel "Lincoln Margison - Game Development" (`@LincolnMargison`). **What could not**:
the video itself, its description, chapters or transcript (the page body is not served to automated fetchers, and no
transcript or write-up was found by search). **Therefore nothing here describes what the video demonstrates.** Its
techniques are neither listed as demonstrated nor inferred from it. The techniques in section 4 come from general
practice and the cited literature. Action for the user: a short summary or the timestamps of the parts that matter
(anatomical limits, muscle behaviour, ragdoll motion) would let phase 3 compare against it directly.

## 6. Anthropometry and joint ranges (sources)

Details, tables and the values used: `DOCUMENTATION/BONE-IK-PROPORTIONS.md`.

- Vitruvius, *De architectura*, Book III ch. 1 (the canon of proportions); Leonardo da Vinci, *Vitruvian Man*
  (c. 1490, Gallerie dell'Accademia, Venice) - conceptual frame: arm span = height, foot = 1/7, hand = 1/10, the
  pubis at half height, the navel as the circle's centre. Used as a preset and an overlay, not as data.
- Winter D.A., *Biomechanics and Motor Control of Human Movement* (4th ed., 2009), segment lengths as fractions of
  stature after Drillis & Contini (1966).
- de Leva P. (1996), Adjustments to Zatsiorsky-Seluyanov's segment inertia parameters, *J Biomech* 29(9):1223-1230
  (joint-centre-based segment lengths and mass fractions; the upper-arm mass fraction 0.0271 was cross-checked against
  a secondary table during this task; the other values are from the paper as commonly reproduced and were not
  re-verified against the full text here, which was not reachable).
- Joint ranges: AAOS (1965) normative values (cross-checked against several secondary reproductions: shoulder
  flexion 180 / extension 60, hip flexion 120 / extension 30, knee 135, ankle dorsiflexion 20 / plantarflexion 50;
  sources disagree on hip extension 20 vs 30), Norkin & White (2016), Soucie et al. (2011), White & Panjabi (1990)
  for spinal segments, Ludewig et al. (2009) and Inman et al. (1944) for the shoulder girdle.
- Joint-limit models in animation: Wilhelms J., Van Gelder A. (2001), Fast and easy reach-cone joint limits,
  *Journal of Graphics Tools* 6(2):27-41 (spherical-polygon swing limits; the planned successor of our elliptical
  swing cones for shoulders and hips).

## Sources consulted online during this task

- Godot release article, Inverse kinematics returns to Godot 4.6: <https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/>
- Godot class reference, IKModifier3D (4.6): <https://docs.godotengine.org/en/4.6/classes/class_ikmodifier3d.html>
- Godot forum, The new IK solvers don't work as expected with a joint limitation: <https://forum.godotengine.org/t/the-new-ik-solvers-dont-work-as-expected-with-a-joint-limitation/130095>
- de Leva 1996 bibliographic record: <https://www.scinapse.io/papers/1997861712>
- YouTube oEmbed record of the reference video (title and channel only).
