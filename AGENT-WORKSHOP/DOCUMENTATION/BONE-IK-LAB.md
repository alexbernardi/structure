# Bone IK laboratory - the Vitruvian skeleton (phase 1)

Laboratory `bone_ik`: branch `lab/bone_ik`, worktree `../structure-lab-bone_ik`, Godot project `LABS/bone_ik/`
(created with `lab create bone_ik --systems movement_core` from `main` `8d60133`). Task:
[0015](../TASKS/0015-bone-ik-lab.md). Research: [bone-ik-foundations.md](../RESEARCH/bone-ik-foundations.md).
Details: [proportions and joints](BONE-IK-PROPORTIONS.md), [animation import and retargeting](BONE-IK-ANIMATION.md).
Decision record: [ADR-0011 (proposed)](../DECISIONS/ADR-0011-vitruvian-rig-architecture.md).

**Status: phases 0 and 1 implemented and tested; not yet reviewed by a person.** An independent foundation for
anatomical IK and, later, physics-driven characters. It does not touch the Traverse / Movement laboratory
(`utility/movement/flat-plane`), `movement_core`, the camera or combat laboratories, or the sandbox.

## 1. Run it

```powershell
cd ..\structure-lab-bone_ik
$godot = "..\structure\.tools\godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"
& $godot --path LABS\bone_ik                                   # the Vitruvian lab (main scene)
& $godot --path LABS\bone_ik -- --preset=vitruvian --view=front
& $godot --path LABS\bone_ik -- --mode=anim --clip=Jog_Fwd --view=persp
python TOOLS/cli/structure.py lab validate                     # static checks + this lab's tests
```

(`setup` in the worktree imports the project the first time; `lab validate` also does.)

| Control | Action |
|---|---|
| Mode buttons / T N A M | T-pose (rest), neutral standing, imported animation, manual joints |
| Clip list, Play / pause (Space), speed | any of the 51 retargeted clips |
| 1 / 2 / 3 or Front / Side / Persp. | orthographic front and side, perspective orbit (right-drag, wheel) |
| Click a joint sphere, or the joint list | select a joint: its limits are drawn and read out; three sliders pose it (switches to manual) |
| Show checkboxes / G V R L X | metric grid, stature and span rulers, Vitruvian square and circle, labels, local axes, selected-joint limits, rest ghost (grey), animation-stage ghost (orange) |
| Constraints | enforce hard limits on authored clips too (limit policy ALWAYS), lossless axial alignment on/off |
| Proportions panel | presets (Modern, Vitruvian) and 16 sliders: stature, arm span, the three vertical weights, neck share, shoulder and pelvis width, upper-arm and thigh shares, hand and foot length, per-limb asymmetry |
| Readout (bottom) | measurements, the selected joint's final and incoming angles with soft / hard ranges and sources, a stage comparison (rest -> animation -> IK -> final), and every joint's angles with `~` (soft zone) and `!` (beyond hard) |

Command-line options (after `--`): `--view`, `--mode=rest|neutral|anim|manual`, `--clip`, `--time`, `--preset`,
`--select=<bone>`, `--pose=<bone>:<flex>,<abd>,<twist>;...`, `--overlays=+axes,-labels,...`,
`--capture=<absolute .png>` (renders one frame, saves it and quits - used for the stills checked in this task).

What you see: an exposed mechanical skeleton - one faceted bone per segment (blue = left, red = right, ivory =
trunk, green = twist helpers), a sphere per joint coloured by type (orange hinge, magenta ball, yellow spinal, cyan
girdle, teal ellipsoid; yellow tint in the soft zone, red when the incoming pose is beyond the hard limit). The
selected joint shows its flex, abd and twist arcs: axis colour = soft range, red = resistance zone up to the hard
limit, white = current angle.

## 2. Architecture

```
LABS/bone_ik/
  systems/bone_ik/              the future shared system (no consumers yet; version 0.1.0)
    vitruvian_rig.gd            public entry point (CONTRACT.md)
    rig/   proportions.gd  rig_builder.gd  humanoid.gd  joint_profile.gd  joint_math.gd  body_plan.gd
    data/  joint_limits.json  body_plan.json
    animation/ humanoid_clip_adapter.gd
    runtime/   pose_source / pose_probe / axial_align / joint_limit / twist_helper modifiers
  scenes/vitruvian_lab.*        the visual lab      viz/  skeleton_view.gd  lab_overlays.gd
  tests/bone_ik/                44 tests            benchmarks/bench_rig.gd      tools/retarget_report.gd
  systems/movement_core/        pinned, read-only (only its CC0 clips are used)
```

The brief's six concerns, and where each lives:

| Concern | Phase 1 | Module |
|---|---|---|
| 1. Anatomical rig definition (dimensions, hierarchy, joint frames, constraints) | done | `rig/*`, `data/*` - pure data, no nodes |
| 2. Animation adapter (imported clips, retargeting) | done | `animation/humanoid_clip_adapter.gd`, `runtime/axial_align_modifier.gd` |
| 3. IK layer (targets, procedural correction) | interface reserved, slot in the chain | phase 2: `ik/` + modifiers between `ProbeAnimation` and `ProbeIK` |
| 4. Physics adapter (bodies, physical joints, collision) | body plan data only | phase 3: builds `PhysicalBone3D`s from `body_plan.json` under a `PhysicalBoneSimulator3D` (last in the chain) |
| 5. Control layer (intended movement, animation following) | not started | phase 3: per-joint PD tracking of the animated / IK pose |
| 6. Recovery controller | not started | phase 5 |

**Modifier chain** (children of the `Skeleton3D`; the last writer wins; a modifier's output exists only inside the
skeleton's update, which is why the probes snapshot it):

```
AnimationPlayer (authored) | PoseSource (rest / neutral / manual)
  -> ProbeAnimation -> [phase 2: TwoBoneIK3D x4, influence-blended] -> ProbeIK
  -> AxialAlign (lossless) -> JointLimits (policy) -> TwistHelpers -> ProbeFinal
  -> [phase 3: PhysicalBoneSimulator3D]
```

**Stable interface** (`vitruvian_rig.gd`, version 0.1.0; draft contract in `systems/bone_ik/CONTRACT.md`):

| Call | Phase 1 behaviour |
|---|---|
| `build(proportions)` | (re)builds the skeleton; keeps mode, clip and time |
| `play(clip, from)`, `set_mode(mode)`, `set_joint_angles(bone, degrees)`, `reset_manual()` | implemented |
| `get_joint_angles(bone, stage)`, `stage_globals(stage)`, `pose_state()` | read pose state: angles per stage, transforms per stage, violations, soft loads, measurements |
| `set_limit_policy(policy)`, `set_limits_enforced(bool)`, `set_hinge_align(bool)` | implemented |
| `request_ik_target(effector, target, influence, pole)`, `clear_ik_target(effector)` | **reserved**: stores the request, returns `ERR_UNAVAILABLE` |
| `apply_impact(bone, impulse, world_point)` | **reserved**: returns `ERR_UNAVAILABLE` |
| `set_response_state(state)` | only `"animated"` returns `OK` |

## 3. Validation

Commands (from the laboratory worktree):

```powershell
python TOOLS/cli/structure.py lab validate
$godot = "..\structure\.tools\godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path LABS\bone_ik --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --dir=res://tests
& $godot --headless --path LABS\bone_ik --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --mode=bench --dir=res://benchmarks
& $godot --headless --path LABS\bone_ik --script res://tools/retarget_report.gd -- --out="$PWD\retarget.md"
```

| Suite | What it proves |
|---|---|
| `test_proportions` (8) | stature and span exact; linear scaling; weights always sum to the stature; clamping; presets (Vitruvian span = height, foot = 1/7, pubis at half height); intentional asymmetry |
| `test_rig_integrity` (8) | hierarchy = profile; rest orientations = profile at any proportions; bilateral symmetry of positions, tips and orientations; anatomical layout; tips meet child joints; edits keep the hierarchy; the imported Quaternius rests share our orientations |
| `test_joint_limits` (11) | data complete and consistent (21 joints, soft inside hard, sources defined); mirroring; rest angles; angle round trip; clamping keeps every joint inside; soft load; **bending directions** of knees, elbows, hips, shoulders, wrists, ankles, toes, girdle and spine on both sides |
| `test_animation_retarget` (4) | track policy on all 51 clips; Idle, Walk, Jog_Fwd and Sprint: world orientations equal the source, constant bone lengths, planted feet stay planted, lowest sole matches the source, no violation after alignment; alignment is lossless on awkward clips |
| `test_rig_runtime` (7) | modifier order; rest / neutral; manual pose clamped while the animation stage keeps the input; measure-only policy; twist helpers; animation through the chain; rebuild keeps playing; reserved interfaces |
| `test_body_plan` (2) | every animation bone rides on exactly one of 16 bodies; masses sum to the body mass; armour adds mass per body |
| `test_vitruvian_lab` (4) | the scene builds, switches modes and cameras, sliders pose joints, proportion edits rebuild everything |

Results (this task): **44 passed, 0 failed** (lab suite); `lab validate` result and the template test are in the task
note. Benchmarks (GDScript, this machine): joint limits for 21 joints 0.15 ms, axial alignment 0.13 ms, animation
sample + full chain 0.27 ms per frame, rig definition from proportions 0.13 ms. Retargeting: 0.0000 degrees and 0 m on
all 51 clips; 17 / 51 clips anatomically clean after alignment (table in BONE-IK-ANIMATION.md).

**Not verified by automation**: how the skeleton looks in motion and whether the proportions look believable to a
person (checked only in still captures: front T-pose, side neutral, perspective Jog_Fwd, a clamped manual pose, the
Vitruvian preset); the lab's mouse interaction (exercised headless through its functions, not with a real mouse).

## 4. Known compatibility constraints

- Clips must be imported with the humanoid `BoneMap` and the importer's default rest normalisation ("overwrite axis");
  clips with foreign rests need `RetargetModifier3D` or re-import first.
- Fingers, eyes and jaw are not rig bones; their tracks are dropped (rigid hands).
- The Root track is dropped: the controller owns root motion.
- Foot geometry differs from the Quaternius rig (our ankle is lower), so pitched feet leave up to a few centimetres of
  contact error until phase 2 foot IK.
- Authored clips exceed per-segment limits by convention (section 5 of BONE-IK-ANIMATION.md); under the default
  policy they are measured, not clamped.
- No skinned mesh yet: twist helpers are placed and driven but unused.
- Physics backend: the project uses `DEFAULT`, which in Godot 4.7.2 is **GodotPhysics3D** (verified). Phase 3 should
  run on Jolt (ADR-0011, needs approval).

## 5. Proposed phase 2 - IK foundation (not started; needs the user's go-ahead)

Goal: hands and feet reach targets on top of authored animation, respecting limb lengths, bending directions and the
joint profile, blended without snapping. Not integrated into Traverse.

1. **Solvers**: one `TwoBoneIK3D` per limb (four settings in one node, or four nodes) in the reserved slot, targets and
   poles from `request_ik_target` (Node3D targets created by the rig). Analytic and deterministic (good for
   multiplayer: the same target gives the same pose). Pole defaults from anatomy: knees forward (+Z of the pelvis
   frame), elbows backward-down; climbing poses override them.
2. **Influence**: per effector 0..1 on the modifier's `influence`, ramped (critically damped, configurable time) so
   switching IK on or off never snaps; `LimitAngularVelocityModifier3D` after IK as a safety net.
3. **Constraint coupling**: IK output passes `AxialAlign` and `JointLimits` (policy PROCEDURAL clamps it). Where the
   clamp moves the end effector, measure the residual and, if needed, iterate once (re-aim the pole) - a cheap
   alternative to a full constrained solver. Wrist and ankle orientation come from the target's basis (palm and sole
   normals), clamped to the wrist / ankle limits.
4. **Scapulohumeral rhythm**: girdle elevation and posterior rotation as a function of humeral elevation (about 1:2
   above 30 degrees, Inman 1944), so overhead reaches and hangs do not overload the glenohumeral range.
5. **Tests (the brief's five)**: (1) reach a fixed target (error < 5 mm inside reach, graceful full extension outside);
   (2) feet planted on uneven ground (steps, slopes) with pelvis lowering; (3) two hands on a wall; (4) arms overhead
   to hang (shoulders within limits, girdle rhythm); (5) knees bent and feet repositioned while hanging, including
   **feet pushing on the wall** (the foot target is a contact with a normal, not just a position).
6. **Metrics**: end-effector error, joint-limit excess before clamping, soft load, pose continuity (maximum angular
   velocity and acceleration per joint across target changes), all reported by the lab and asserted in tests.
7. **Remaining retarget classes** from phase 1: chain redistribution (spine, neck), foot turnout transfer, reach-cone
   swing limits for shoulders and hips (Wilhelms & Van Gelder 2001).

## 6. Design notes for phases 3-5 (recorded, not implemented)

- **Muscle-like physics (3)**: 16 `PhysicalBone3D`s from the body plan; per joint a PD torque toward the animated pose
  with gains proportional to segment inertia, a maximum torque (strength), soft-limit resistance from `soft_load`,
  joint friction and angular damping, and a weak rest tension when nothing drives the joint. Compare passive ragdoll
  against pose tracking at 120 and 60 Hz; check stability (drift, jitter, explosion) on Jolt.
- **Partial and full ragdoll (4)**: response states animated / partial / full. An impact's impulse, location and the
  character's balance (centre of mass over the support polygon) select which bodies go physical; torque limits decide
  how much the animation is overpowered. Thresholds come from mass, armour absorption, strength and posture, never a
  single constant. Armour = mass per body + absorption + strength / resistance factors, same skeleton.
- **Recovery (5)**: pose matching against get-up clips by pelvis orientation (face up / face down), root realignment
  without teleporting, ground contact checks, temporary IK on hands and feet, blending physics influence back to 0
  with angular-velocity limits; recovery while hanging or climbing keeps the hand IK targets.
- **Multiplayer authority** (design only): the server owns impacts and response-state changes and replicates them
  as events (impact: bone, impulse, point, tick). Animated and IK poses are reproduced on every machine from replicated
  inputs and targets (TwoBoneIK3D and deterministic IterateIK3D are frame-independent). Ragdoll bodies are simulated
  locally by each client for looks, with the server's authoritative character root; only gameplay-relevant results
  (fell / recovered, final root and orientation) are authoritative. Any wire change follows VERSIONING.md.
- **Level of detail**: full (16 bodies, IK on four limbs), reduced (10 bodies, feet IK only), minimal (authored
  animation only, no bodies) chosen by distance and on-screen size; the benchmark gives the per-character budget
  (0.27 ms in GDScript today; moving the joint math to C++ or caching decompositions is the first optimisation if it
  matters).
