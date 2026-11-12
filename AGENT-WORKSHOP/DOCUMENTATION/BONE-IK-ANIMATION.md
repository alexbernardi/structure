# Bone IK laboratory - animation import and retargeting

Part of the [Bone IK laboratory](BONE-IK-LAB.md) (task [0015](../TASKS/0015-bone-ik-lab.md)). Code:
`LABS/bone_ik/systems/bone_ik/animation/humanoid_clip_adapter.gd`, `runtime/axial_align_modifier.gd`,
`rig/joint_profile.gd` (`align_axial`). Measurement: `tests/bone_ik/anim_measure.gd`, report tool
`tools/retarget_report.gd`.

## 1. Sources

The CC0 Quaternius libraries already used by the movement laboratory, read from the **pinned, read-only** copy of
`movement_core` 1.0.0 in this laboratory (`res://systems/movement_core/assets/quaternius/`, listed as package assets
in its CONTRACT; provenance in `utility/movement/flat-plane/assets/quaternius/PROVENANCE.md`):
`UAL1_Standard.glb` (43 clips), `UAL2_Climb.glb` (7), `UAL2_Traversal.glb` (`SafetyVault`) - 51 clips. Nothing is
copied, converted or edited. If the source moves, the adapter reports it missing and the rig still works without clips.

## 2. Why no conversion is needed

Godot's importer maps these GLBs to `SkeletonProfileHumanoid` with a `BoneMap` and overwrites their rest orientations
with the profile's (verified: every normalised rest basis equals the profile's within 0.01 degrees). Rotation keys
are absolute local rotations relative to those rests. The Vitruvian rig is *built* with the profile's rest
orientations at any proportions, so a key means the same rotation on both skeletons and every bone ends up with the
**same world orientation** as on the source (measured: 0.0000 degrees on all 51 clips). Only lengths differ - the
rig's own proportions - so the motion is retargeted, not copied.

## 3. What the adapter changes

| Track | Policy |
|---|---|
| Rotation of a rig bone (except Root) | copied unchanged, path renamed to `Skeleton3D:<bone>` |
| Hips position | rewritten in metres: `rig_hips_rest + (source_hips - source_hips_rest) x (rig hip-joint height / source hip-joint height)`; the source key is first multiplied by the source `motion_scale` (keys are normalised by the hips height). The rig's `motion_scale` is 1 |
| Root position (root motion) | dropped and reported (`root_motion`); never moves the skeleton |
| Position of any other bone | dropped: bone lengths come only from the rig's proportions |
| Scale tracks | dropped (no unintended scaling) |
| Fingers, eyes, jaw, leaf bones | dropped and listed per clip (`dropped_bones`) |

**Root motion ownership**: the Root bone belongs to the character controller (Traverse / `movement_core` today), which
moves the node that holds the rig. The rig uses in-place clips. A future root-motion consumer would read the clip's
Root track (e.g. `AnimationMixer.root_motion_track`) in the controller, not in the skeleton.

**Modification order** (children of the `Skeleton3D`, fixed by `vitruvian_rig.gd`):
`AnimationPlayer` or `PoseSource` -> `ProbeAnimation` -> *(phase 2 IK modifiers)* -> `ProbeIK` -> `AxialAlign` ->
`JointLimits` -> `TwistHelpers` -> `ProbeFinal` -> *(phase 3 `PhysicalBoneSimulator3D`)*. The probes snapshot the pose
after each stage so the lab can show rest, animation, IK and final transforms separately.

## 4. Axial alignment (lossless)

Measuring authored clips against the joint profile revealed three habits of the source rig that would read as
impossible joints although nothing looks wrong on screen. All three are corrected **without moving any joint**
(measured: at most 0.0000005 m of joint displacement): the correction only moves rotation about a segment's own long
axis to the segment where anatomy puts it.

1. **Sideways-bending hinges.** The forearm or shin is rotated about the upper arm / thigh axis instead of rolling the
   upper arm / thigh. Writing the hinge motion as `R(parent axis, alpha) * R(flex axis, theta) * R(own axis, phi)`,
   alpha moves to the parent's roll. The bending plane is ambiguous by 180 degrees; the reading with the smaller
   total hard-limit excess wins.
2. **Forearm rotation stored on the hand.** The hand's twist about the forearm axis moves to the forearm (pronation /
   supination happens in the forearm, where the radius turns around the ulna); the wrist keeps flexion and deviation.
3. **Straight limbs with a full extra turn.** With the elbow straight, upper-arm roll and forearm roll are
   interchangeable; the source sometimes splits them 140 + 145 degrees (= -75 modulo a turn). A 15-degree search over
   the split (only when the cheap readings still violate a limit) picks the anatomical one.

Cost: 0.13 ms per rig update in GDScript (the full frame with limits is 0.27 ms; `benchmarks/bench_rig.gd`).

## 5. Limit policy for authored clips

Even after alignment, many authored clips exceed per-segment anatomical limits. The excesses come from authoring
conventions rather than from impossible-looking poses: the source has no lumbar track (its Chest bone carries the
whole lower trunk), it nods with the Head bone alone, it turns the feet out at the ankle rather than the hip, and it
lands with 64 degrees of dorsiflexion. Clamping these by default would visibly change working animation, which the
brief rules out. The rig therefore has a **limit policy**:

- `PROCEDURAL` (default): hard limits are enforced on rest, neutral and manual poses (and, in phase 2, on IK
  output); authored playback is **measured** (violations, soft load) but not clamped.
- `ALWAYS`: authored clips are clamped too (lab toggle "Enforce hard joint limits"), to see what anatomy would change.
- `MEASURE`: nothing is clamped.

Phase 2 candidates for the remaining classes: chain redistribution (spread a concentrated spinal or cervical rotation
over Spine / Chest / UpperChest or Neck / Head while keeping the upper segment's world orientation - not lossless,
it bends the spine curve); foot turnout transfer (ankle rotation about the shin axis -> knee / hip roll); and limits
for authored-only rigs per clip family if needed.

## 6. Results (all 51 clips, default rig, 30 samples per clip)

Command: `godot --headless --path LABS/bone_ik --script res://tools/retarget_report.gd -- --out=<file>`.
Orientation error = worst world-rotation difference between the rig and the original imported skeleton over all mapped
bones. Length error = worst change of any bone length. Planted-toe error = how far the rig's toe joint leaves its
rest height while the source's toe is planted (within 1 cm). Lowest sole = lowest heel or toe-tip point on the rig /
the same point on the source scaled by leg length (both rigs penetrate a little in some clips: the source does too).

Summary:

- **Retargeting**: orientation error 0.0000 degrees and length error 0 on every clip; lowest sole points match the
  source within a few centimetres except where the source itself is far off the ground (swimming, the 2 m climb).
- **Foot placement**: planted-toe error at most 2.2-2.4 cm for walk / jog and 2.6 cm for sprint in this table
  (3.3 cm for sprint with the test's 40 samples), 7.5 cm worst (`Slide_Exit`). Cause: our ankle is anatomical (0.039 x stature) while the source's sits about 3 cm higher, so a
  strongly pitched foot lifts our toe joint differently. Phase 2 foot IK removes the residue.
- **Anatomy**: 17 / 51 clips are within every hard limit after alignment: A_TPose, Idle, Idle_Talking, Idle_Torch,
  Walk, Walk_Formal, Jog_Fwd, Sprint, Hit_Chest, Hit_Head, Interact, Driving, Pistol_Aim_Neutral, Pistol_Idle,
  Pistol_Shoot, Sitting_Idle and Sitting_Talking (8 before alignment). The remaining violations are
  the authoring conventions listed above, plus genuinely extreme poses (Death01, Roll, Fixing_Kneeling, Slide).
- Verified visually only in stills (front, side and perspective captures of rest, neutral, Jog_Fwd, a clamped manual
  pose and the Vitruvian preset); motion quality in playback needs a human review.

Clips within the hard limits after axial alignment: 17 / 51

| Clip | Source | Frames | Orientation error (deg) | Length error (m) | Planted-toe error (m) | Lowest sole ours / source (m) | Axial transfer max (deg) | Raw violations (deg beyond hard) | After axial alignment |
|---|---|---:|---:|---:|---:|---:|---:|---|---|
| A_TPose | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.000 | -0.000 / -0.008 | 0.0 | none | none |
| Crouch_Fwd | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.058 | -0.013 / -0.016 | 33.0 | Chest 7.9, UpperChest 6.3, Head 5.5, LeftLowerArm 36.2, LeftHand 4.0, RightLowerArm 68.1, LeftUpperLeg 2.0, RightLowerLeg 67.7, RightFoot 21.1, LeftLowerLeg 100.5, LeftFoot 27.0 | Chest 7.9, UpperChest 6.3, Head 5.5, LeftUpperLeg 2.0, RightFoot 21.1, LeftFoot 27.0 |
| Crouch_Idle | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.057 | -0.007 / -0.009 | 33.0 | Chest 6.3, UpperChest 6.8, Head 4.4, LeftLowerArm 36.2, LeftHand 4.0, RightLowerArm 63.6, LeftUpperLeg 0.9, RightLowerLeg 50.1, LeftLowerLeg 51.8 | Chest 6.3, UpperChest 6.8, Head 4.4, LeftUpperLeg 0.9 |
| Dance | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.013 | -0.006 / -0.009 | 20.4 | LeftLowerArm 69.7, RightLowerArm 58.4, LeftFoot 2.3, RightLowerLeg 4.3, Chest 3.9, Head 1.4, LeftLowerLeg 4.7 | LeftFoot 2.3, Chest 3.9, Head 1.4 |
| Death01 | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.010 | -0.008 / -0.013 | 128.4 | RightLowerArm 72.1, RightLowerLeg 110.7, Head 15.9, LeftLowerArm 100.6, LeftLowerLeg 61.8, RightFoot 7.8, RightHand 64.0, LeftHand 55.6, RightUpperArm 19.0 | Head 15.9, RightFoot 7.8, RightLowerArm 8.9, LeftUpperArm 17.9 |
| Driving | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.020 | 0.019 / -0.008 | 59.9 | LeftLowerArm 59.3, LeftHand 20.1, RightLowerArm 38.6, RightHand 39.9, LeftLowerLeg 64.4, RightLowerLeg 61.4 | none |
| Fixing_Kneeling | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.030 | -0.055 / -0.021 | 81.8 | RightLowerArm 52.8, RightLowerLeg 51.5, Head 20.4, LeftLowerLeg 125.0, RightHand 61.8, LeftFoot 26.5, LeftLowerArm 74.0, LeftUpperLeg 38.1, RightFoot 35.8, Chest 7.0, UpperChest 7.3, RightUpperArm 28.8, LeftUpperArm 27.2, LeftHand 36.7 | Head 20.4, LeftFoot 26.5, LeftUpperLeg 38.1, RightFoot 35.8, Chest 7.0, UpperChest 7.3, RightUpperArm 7.1 |
| Hit_Chest | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.013 | -0.013 / -0.008 | 40.8 | RightLowerArm 28.1, LeftLowerLeg 2.2, RightLowerLeg 22.9, LeftLowerArm 12.4 | none |
| Hit_Head | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.007 | -0.007 / -0.008 | 41.0 | RightLowerArm 26.9, RightLowerLeg 23.8 | none |
| Idle | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.007 | -0.008 / -0.009 | 41.0 | RightLowerArm 27.0, RightLowerLeg 24.3 | none |
| Idle_Talking | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.007 | -0.008 / -0.009 | 52.4 | LeftLowerArm 68.7, LeftHand 32.4, RightHand 20.7, RightLowerLeg 23.9 | none |
| Idle_Torch | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.007 | -0.007 / -0.009 | 69.0 | LeftLowerArm 44.2, LeftHand 8.3, RightLowerArm 27.1, RightLowerLeg 24.2, LeftLowerLeg 0.7 | none |
| Interact | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.007 | -0.008 / -0.009 | 83.9 | LeftLowerArm 48.5, RightLowerArm 26.9, RightLowerLeg 24.3, LeftHand 41.2 | none |
| Jog_Fwd | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.024 | -0.034 / -0.019 | 43.7 | LeftLowerArm 84.1, RightLowerArm 85.0, RightLowerLeg 2.9, LeftLowerLeg 14.6 | none |
| Jump | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.021 | -0.155 / -0.152 | 42.4 | Head 4.6, LeftHand 7.2, LeftLowerLeg 96.0, LeftFoot 5.8, RightLowerLeg 43.9, RightFoot 1.9 | Head 4.6, LeftFoot 5.8, RightFoot 1.9 |
| Jump_Land | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.033 | -0.017 / -0.015 | 68.8 | Head 7.2, LeftHand 7.2, LeftLowerLeg 63.5, LeftFoot 11.5, RightLowerLeg 108.6, LeftLowerArm 43.5, RightFoot 34.0, RightLowerArm 33.8, Chest 1.4, UpperChest 1.4 | Head 7.2, LeftFoot 11.5, RightFoot 34.0, Chest 1.4, UpperChest 1.4 |
| Jump_Start | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.031 | -0.160 / -0.155 | 62.3 | LeftLowerArm 40.2, RightLowerArm 69.4, LeftLowerLeg 100.7, RightLowerLeg 110.0, RightFoot 28.6, LeftShoulder 3.5, RightShoulder 0.7, Chest 17.1, LeftFoot 20.2, LeftHand 7.2, LeftUpperLeg 1.8, Head 0.5 | RightFoot 28.6, LeftShoulder 3.5, RightShoulder 0.7, Chest 17.1, LeftFoot 20.2, LeftUpperLeg 1.8, Head 0.5 |
| PickUp_Table | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.008 | -0.006 / -0.009 | 42.3 | RightLowerArm 26.8, RightLowerLeg 24.7, LeftLowerLeg 4.7, LeftLowerArm 67.4, RightFoot 14.9, Head 3.6 | RightFoot 14.9, Head 3.6 |
| Pistol_Aim_Down | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 78.9 | Chest 10.6, UpperChest 10.8, Head 11.6, LeftLowerArm 16.6, LeftHand 58.9, RightUpperArm 2.8, RightLowerArm 3.9, RightHand 18.7, RightLowerLeg 22.5 | Chest 10.6, UpperChest 10.8, Head 11.6 |
| Pistol_Aim_Neutral | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 79.3 | LeftLowerArm 37.0, LeftHand 59.3, RightUpperArm 29.1, RightLowerArm 7.0, RightHand 17.9, RightLowerLeg 22.5 | none |
| Pistol_Aim_Up | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 112.9 | Head 14.3, LeftUpperArm 46.2, LeftLowerArm 18.8, LeftHand 61.3, RightUpperArm 71.0, RightHand 18.3, RightLowerLeg 22.5 | Head 14.3 |
| Pistol_Idle | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 82.9 | LeftLowerArm 42.8, LeftHand 62.9, RightUpperArm 29.3, RightLowerArm 14.5, RightHand 18.9, RightLowerLeg 22.5 | none |
| Pistol_Reload | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 96.4 | LeftLowerArm 82.0, LeftHand 59.3, RightUpperArm 29.1, RightLowerArm 84.0, RightHand 76.4, RightLowerLeg 22.5, LeftShoulder 6.9 | LeftShoulder 6.9, RightLowerArm 5.5 |
| Pistol_Shoot | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 79.3 | LeftLowerArm 50.4, LeftHand 59.3, RightUpperArm 35.9, RightLowerArm 27.3, RightHand 18.9, RightLowerLeg 22.5 | none |
| Punch_Cross | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.028 | -0.028 / -0.009 | 118.9 | Chest 5.9, LeftLowerArm 109.6, RightLowerArm 117.0, LeftLowerLeg 14.3, RightLowerLeg 26.6, Head 3.4, LeftFoot 2.5 | Chest 5.9, Head 3.4, LeftFoot 2.5 |
| Punch_Jab | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.017 | -0.018 / -0.009 | 72.9 | Chest 2.5, LeftLowerArm 116.1, RightLowerArm 112.4, LeftLowerLeg 14.3, RightLowerLeg 26.0, RightFoot 5.2, RightHand 14.7 | Chest 2.5, RightFoot 5.2 |
| Push | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.027 | 0.001 / -0.011 | 90.0 | Head 9.8, LeftUpperArm 82.1, RightUpperArm 68.5, RightHand 19.1, LeftLowerLeg 88.2, LeftFoot 26.0, RightFoot 23.6, RightLowerLeg 58.2 | Head 9.8, LeftHand 2.1, RightHand 10.2, LeftFoot 26.0, RightFoot 23.6 |
| Roll | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.030 | -0.031 / -0.040 | 116.5 | LeftLowerArm 132.2, RightLowerArm 77.4, LeftLowerLeg 88.6, RightLowerLeg 125.6, RightFoot 32.4, RightUpperArm 6.2, LeftHand 52.9, LeftFoot 16.8, Head 31.6, Chest 1.6, UpperChest 1.6, LeftUpperLeg 22.6, RightUpperLeg 53.8 | RightFoot 32.4, LeftFoot 16.8, Head 31.6, Chest 1.6, UpperChest 1.6, LeftHand 22.1, LeftUpperLeg 22.6, RightUpperLeg 53.8 |
| Sitting_Enter | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.035 | -0.007 / -0.009 | 59.1 | RightLowerArm 65.6, RightLowerLeg 45.8, LeftLowerLeg 56.3, LeftLowerArm 20.8, RightHand 40.1, LeftHand 33.2 | RightHand 16.6 |
| Sitting_Exit | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.048 | -0.007 / -0.008 | 96.4 | LeftHand 80.4, RightLowerArm 85.3, RightHand 52.7, LeftLowerLeg 55.8, RightLowerLeg 45.1, LeftLowerArm 76.5 | LeftHand 47.4, LeftLowerArm 6.1, RightHand 13.2 |
| Sitting_Idle | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.030 | 0.030 / -0.008 | 58.6 | LeftHand 31.7, RightLowerArm 53.5, RightHand 39.8, LeftLowerLeg 54.5, RightLowerLeg 32.4, LeftLowerArm 13.0 | none |
| Sitting_Talking | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.031 | 0.030 / -0.008 | 76.2 | LeftLowerArm 62.8, LeftHand 56.2, RightLowerArm 53.3, RightHand 44.0, LeftLowerLeg 54.5, RightLowerLeg 35.0 | none |
| Spell_Simple_Enter | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 50.4 | RightLowerArm 27.8, RightLowerLeg 23.9, LeftLowerLeg 23.9, RightFoot 18.2, LeftLowerArm 12.6, RightHand 3.7, Head 4.4 | RightFoot 18.2, Head 4.4 |
| Spell_Simple_Exit | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.006 | -0.006 / -0.008 | 50.4 | Head 4.4, LeftLowerArm 12.6, RightHand 3.7, LeftLowerLeg 23.9, RightLowerLeg 23.9, RightFoot 18.2, RightLowerArm 27.5 | Head 4.4, RightFoot 18.2 |
| Spell_Simple_Idle | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.002 | -0.001 / -0.008 | 61.9 | Head 4.5, RightHand 3.7, LeftLowerLeg 26.3, RightLowerLeg 25.0, RightFoot 18.5, LeftLowerArm 14.7, RightLowerArm 14.2 | Head 4.5, RightFoot 18.5 |
| Spell_Simple_Shoot | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.002 | -0.002 / -0.008 | 127.4 | Head 4.5, LeftHand 14.3, RightHand 3.7, LeftLowerLeg 24.1, RightLowerLeg 26.1, RightFoot 18.2, RightLowerArm 1.4, LeftLowerArm 7.5 | Head 4.5, RightFoot 18.2 |
| Sprint | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.026 | -0.043 / -0.045 | 43.7 | LeftLowerArm 84.0, RightLowerArm 85.0, LeftLowerLeg 20.5 | none |
| Swim_Fwd | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.024 | -0.281 / -0.312 | 80.5 | Head 8.4, LeftShoulder 13.6, LeftLowerArm 87.2, LeftHand 39.9, RightShoulder 13.6, RightLowerArm 87.2, RightHand 53.2, LeftLowerLeg 107.0, RightLowerLeg 107.0, LeftUpperArm 6.9, RightUpperArm 2.1, LeftUpperLeg 8.8, RightUpperLeg 9.0 | Head 8.4, LeftShoulder 13.6, RightShoulder 13.6, LeftUpperArm 6.9, RightUpperArm 2.1, LeftUpperLeg 8.8, RightUpperLeg 9.0 |
| Swim_Idle | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.037 | -1.420 / -1.416 | 11.2 | LeftLowerArm 23.2, RightLowerArm 15.2, LeftLowerLeg 1.9 | LeftLowerLeg 1.9 |
| Sword_Attack | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.021 | -0.025 / -0.018 | 86.1 | Chest 10.2, LeftLowerArm 43.7, RightLowerArm 34.5, LeftLowerLeg 58.5, RightLowerLeg 89.9, RightFoot 16.7, Head 13.3, RightHand 28.4, LeftFoot 23.1, UpperChest 26.0, RightUpperLeg 4.3, Neck 2.8, LeftShoulder 3.3 | Chest 10.2, RightFoot 16.7, Head 13.3, RightLowerArm 28.5, LeftFoot 23.1, RightHand 29.0, UpperChest 26.0, RightUpperLeg 4.3, Neck 2.8, LeftShoulder 3.3 |
| Sword_Idle | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.017 | -0.017 / -0.009 | 35.3 | Chest 7.8, LeftLowerArm 35.1, RightLowerArm 25.3, LeftLowerLeg 37.6, RightLowerLeg 59.8, RightFoot 16.4 | Chest 7.8, RightFoot 16.4 |
| Walk | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.022 | -0.047 / -0.037 | 15.2 | LeftLowerArm 13.2, RightLowerArm 12.9 | none |
| Walk_Formal | UAL1_Standard.glb | 30 | 0.0000 | 0.000000 | 0.020 | -0.046 / -0.037 | 33.6 | LeftLowerArm 18.9, RightLowerArm 16.0 | none |
| ClimbUp_1m | UAL2_Climb.glb | 30 | 0.0000 | 0.000000 | 0.000 | 0.032 / 0.007 | 54.8 | LeftLowerArm 55.8, RightLowerArm 85.0, RightLowerLeg 101.5, Chest 34.5, LeftLowerLeg 111.5, LeftHand 21.4, Head 4.9, RightUpperLeg 1.3, RightFoot 12.4, LeftUpperLeg 7.9 | Chest 34.5, Head 4.9, RightUpperLeg 1.3, LeftHand 4.6, RightFoot 12.4, LeftUpperLeg 7.9 |
| ClimbUp_2m | UAL2_Climb.glb | 30 | 0.0000 | 0.000000 | 0.039 | -0.305 / -0.304 | 105.9 | LeftLowerArm 129.6, RightLowerArm 132.4, RightHand 33.7, RightUpperLeg 1.0, LeftLowerLeg 110.1, RightLowerLeg 112.1, RightFoot 36.3, Chest 10.4, UpperChest 2.5, Head 14.8, LeftUpperLeg 6.1, LeftUpperArm 1.9, LeftHand 52.3 | RightUpperLeg 1.0, RightFoot 36.3, Chest 10.4, UpperChest 2.5, Head 14.8, LeftUpperLeg 6.1, LeftUpperArm 4.8, RightUpperArm 5.7, RightHand 3.0, LeftHand 1.5 |
| DoubleJump | UAL2_Climb.glb | 30 | 0.0000 | 0.000000 | 0.034 | -0.149 / -0.135 | 69.0 | Chest 18.2, LeftLowerArm 54.9, LeftHand 7.2, RightLowerArm 69.3, LeftLowerLeg 115.2, LeftFoot 33.4, RightLowerLeg 116.6, RightFoot 5.6, Head 5.5 | Chest 18.2, LeftFoot 33.4, RightFoot 5.6, Head 5.5 |
| JogToFlip | UAL2_Climb.glb | 30 | 0.0000 | 0.000000 | 0.026 | -0.029 / -0.036 | 104.7 | LeftLowerArm 73.0, RightLowerArm 85.0, LeftFoot 26.1, RightLowerLeg 92.8, RightUpperArm 31.9, LeftUpperArm 37.4, RightFoot 39.0, Chest 8.5, UpperChest 9.7, Head 32.2, LeftLowerLeg 117.4, RightUpperLeg 10.6 | LeftFoot 26.1, LeftUpperArm 38.7, LeftLowerArm 19.0, RightFoot 39.0, Chest 8.5, UpperChest 9.7, Head 32.2, RightUpperLeg 10.6 |
| Slide | UAL2_Climb.glb | 30 | 0.0000 | 0.000000 | 0.000 | 0.042 / -0.010 | 54.2 | Chest 7.4, UpperChest 6.7, Head 45.2, LeftLowerArm 76.4, RightLowerArm 36.9, LeftUpperLeg 11.3, LeftLowerLeg 124.0, LeftFoot 9.6, RightFoot 7.0 | Chest 7.4, UpperChest 6.7, Head 45.2, LeftUpperLeg 11.3, LeftFoot 9.6, RightFoot 7.0 |
| Slide_Exit | UAL2_Climb.glb | 30 | 0.0000 | 0.000000 | 0.075 | -0.063 / -0.049 | 52.7 | Chest 11.4, UpperChest 5.8, Head 36.2, LeftLowerArm 76.4, RightLowerArm 85.0, LeftUpperLeg 25.1, LeftLowerLeg 139.7, LeftFoot 4.2, RightFoot 33.1, LeftHand 27.5, RightLowerLeg 105.7 | Chest 11.4, UpperChest 5.8, Head 36.2, LeftUpperLeg 25.1, LeftFoot 4.2, RightFoot 33.1, LeftLowerLeg 2.7 |
| Slide_Start | UAL2_Climb.glb | 30 | 0.0000 | 0.000000 | 0.045 | -0.050 / -0.039 | 54.1 | LeftLowerArm 104.6, RightLowerArm 85.0, LeftLowerLeg 135.7, RightFoot 13.2, Chest 11.0, RightLowerLeg 34.3, UpperChest 5.1, Head 38.4, LeftHand 7.5, LeftUpperLeg 17.6, LeftFoot 4.6 | RightFoot 13.2, Chest 11.0, UpperChest 5.1, Head 38.4, LeftHand 7.8, LeftUpperLeg 17.6, LeftFoot 4.6 |
| SafetyVault | UAL2_Traversal.glb | 30 | 0.0000 | 0.000000 | 0.007 | -0.025 / -0.035 | 69.8 | LeftLowerArm 63.1, RightLowerArm 95.6, LeftLowerLeg 126.2, RightHand 49.8, LeftFoot 12.2, RightLowerLeg 123.3, Head 7.7, RightFoot 16.1, Chest 22.8, LeftHand 3.0, RightUpperLeg 14.8 | LeftFoot 12.2, Head 7.7, RightFoot 16.1, Chest 22.8, RightUpperLeg 14.8 |
