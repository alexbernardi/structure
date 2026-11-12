# Bone IK laboratory - proportions, sources and joint definitions

Part of the [Bone IK laboratory](BONE-IK-LAB.md) (task [0015](../TASKS/0015-bone-ik-lab.md)). Data files:
`LABS/bone_ik/systems/bone_ik/rig/proportions.gd` (parameters), `data/joint_limits.json` (joints),
`data/body_plan.json` (masses). Everything here is tunable; none of it is a universal truth about bodies.

## 1. Approach

Leonardo's *Vitruvian Man* is the conceptual frame: one body inscribed in a square (its height) and a circle centred
on the navel, built from simple ratios. The numbers come from modern anthropometry instead, because the Vitruvian
canon is an aesthetic system, not a measured population (its foot of 1/7 and a shoulder of 1/4 of the height are
not modern averages). Both are available: the **modern** preset is the default; the **Vitruvian** preset applies
the canon (arm span = height, foot = 1/7, hand = 1/10, hip joints / pubis at half height) and its square and circle
are drawn as an overlay. Bones run between **joint centres** (where segments rotate), not between skin landmarks.

## 2. Parameters

All ratios are of stature, except the shares (fractions of one segment group) and the three vertical **weights**,
which are normalised to sum to 1. Editing any weight therefore keeps the stature exact and every joint valid.

| Parameter | Default | Range | Meaning |
|---|---:|---|---|
| `height` | 1.80 m | 1.0-2.6 | stature (vertex to sole) |
| `arm_span_ratio` | 1.03 | 0.90-1.15 | fingertip to fingertip in T-pose / stature; drives total arm length |
| `leg_weight` | 0.522 | 0.40-0.62 | hip joint centre height |
| `torso_weight` | 0.328 | 0.24-0.42 | hip joint line to C7/T1 |
| `head_neck_weight` | 0.150 | 0.11-0.20 | C7/T1 to vertex |
| `neck_share` | 0.37 | 0.25-0.50 | C7/T1 to the atlanto-occipital joint, share of head + neck |
| `thigh_share` | 0.493 | 0.42-0.56 | thigh share of hip-to-ankle |
| `ankle_height_ratio` | 0.039 | 0.025-0.06 | ankle joint above the sole (Winter) |
| `shoulder_width_ratio` | 0.18 | 0.13-0.26 | between the glenohumeral joint centres (biacromial breadth minus about 2 x 4.5 cm) |
| `pelvis_width_ratio` | 0.095 | 0.07-0.14 | between the hip joint centres |
| `upper_arm_share` | 0.512 | 0.44-0.58 | upper-arm share of shoulder-to-wrist |
| `hand_length_ratio` | 0.108 | 0.085-0.13 | wrist to fingertip (Winter) |
| `foot_length_ratio` | 0.152 | 0.12-0.18 | heel to toe tip (Winter) |
| `hand_width_ratio`, `foot_width_ratio`, `head_width_ratio` | 0.05 / 0.055 / 0.085 | | display only (phase 1) |
| `left/right_arm_scale`, `left/right_leg_scale` | 1.0 | 0.8-1.2 | intentional asymmetry (default symmetric) |
| `body_mass` | 75 kg | 30-250 | for the physics body plan |

Fixed in phase 1 (documented constants, `proportions.gd` / `rig_builder.gd`): torso split 0.17 pelvis (to L5/S1),
0.22 lumbar (to T12/L1), 0.25 lower thoracic, 0.36 upper thoracic; navel 0.24 of the torso above the hip line
(de Leva's lower-trunk share); small sagittal offsets of the spinal joints (behind the hip line) and the
sternoclavicular joint (in front of the spine), rounded from the normalised reference rig; heel 0.20 and ball of the
foot 0.52 of the foot length behind / ahead of the ankle.

## 3. Defaults compared with references (1.80 m)

| Segment (joint centres) | Ours, modern | Ours, Vitruvian preset | Reference | Source |
|---|---:|---:|---:|---|
| Arm span | 1.854 m (1.03) | 1.800 m (1.00) | 1.00-1.06 x stature in adult men, by ancestry | population studies; Leonardo: 1.00 |
| Hip joint height | 0.940 | 0.900 | 0.530 x H to the greater trochanter (0.954) | Winter / Drillis & Contini |
| Navel height | 1.081 (0.601 H) | 1.051 (0.584 H) | about 0.60-0.62 H | de Leva hip-to-navel share |
| Shoulder joint centres | 0.324 | 0.342 | biacromial 0.259 H outer breadth minus joint offsets | Winter; anatomy |
| Hip joint centres | 0.171 | 0.171 | about 0.72 x inter-ASIS breadth | Bell et al. (1990) regression |
| Upper arm | 0.292 | 0.281 | 0.291 (scaled from 281.7 mm at 1.741 m) | de Leva 1996 |
| Forearm | 0.278 | 0.268 | 0.278 (from 268.9 mm) | de Leva 1996 |
| Hand, wrist to fingertip | 0.194 | 0.180 | 0.108 H = 0.194 | Winter; Leonardo: 1/10 |
| Thigh | 0.429 | 0.409 | 0.437 (from 422.2 mm) | de Leva 1996 |
| Shank | 0.441 | 0.421 | 0.449 (from 434.0 mm) | de Leva 1996 |
| Foot, heel to toe | 0.274 | 0.257 | 0.152 H = 0.274 | Winter; Leonardo: 1/7 |
| Head + neck (C7/T1 to vertex) | 0.270 | 0.270 | about 0.14 H to the C7 spinous process | de Leva (vertex-cervicale) |

Our thigh and shank are about 1.5 % shorter than de Leva scaled linearly because the vertical chain is normalised to
the exact stature (summed reference segments overshoot by about 1.7 %: the landmarks overlap and the spine curves).
The de Leva lengths are as commonly reproduced; the full paper could not be re-checked here (research note).
The default matches a mean adult man. Other bodies (women, children, very tall or armoured characters) need their
own preset; ratios such as `leg_weight` and `shoulder_width_ratio` differ measurably by sex and population.

## 4. Bone hierarchy and naming

Names, parents and rest orientations are those of Godot's `SkeletonProfileHumanoid` (verified against the profile
and the imported Quaternius rig). 23 animation bones + 6 leaf twist helpers (29):

```
Root
└ Hips (pelvis; pivots mid-pelvis)
  ├ Spine (lumbar, pivot L5/S1) └ Chest (lower thoracic, pivot T12/L1) └ UpperChest (upper thoracic, mid-thorax)
  │   ├ Neck (pivot C7/T1) └ Head (pivot atlanto-occipital; tip = vertex)
  │   ├ LeftShoulder (clavicle, sternoclavicular joint) └ LeftUpperArm (glenohumeral) [+ LeftUpperArmTwist]
  │   │     └ LeftLowerArm (elbow) [+ LeftLowerArmTwist] └ LeftHand (wrist; tip = fingertip)
  │   └ RightShoulder ... (mirror)
  ├ LeftUpperLeg (hip joint) [+ LeftUpperLegTwist] └ LeftLowerLeg (knee) └ LeftFoot (ankle) └ LeftToes (MTP; tip = toe tip)
  └ RightUpperLeg ... (mirror)
```

- **Coordinate convention**: model space, metres, feet on y = 0, the character faces **+Z**, its left is **+X**,
  up is +Y (the profile's convention). Each animation bone's local +Y points along the bone; its full rest basis is
  the profile's reference basis, so the T-pose is "every local rotation = rest". Arms are horizontal with the palms
  down (forearm neutral, thumbs forward), legs vertical.
- **Twist helpers** are children of UpperArm (30 % along, counter-roll 50 %), LowerArm (60 % along, counter-roll
  40 % of the forearm's pronation) and UpperLeg (30 %, 50 %). They are never in a humanoid chain, so no animation
  track changes meaning. They exist for a future skinned body; nothing simulates them.
- **Not in phase 1**: finger bones (the profile's 30 finger bones are dropped from clips; the hand is rigid), eyes,
  jaw, a separate scapula bone (the clavicle bone stands for the whole shoulder girdle; see the joint notes).
- **Animation bones versus physical bodies**: 29 animation bones ride on 16 rigid bodies (`data/body_plan.json`):
  pelvis, abdomen (Spine + Chest), thorax (UpperChest + clavicles), head (Head + Neck), and upper arm, forearm,
  hand, thigh, shank, foot (+ toes) per side; masses from de Leva's fractions (they sum to 100 %).

## 5. Joint definitions

**Angles.** Each joint's motion is measured in the proximal segment's frame, from the joint's anatomical neutral
(the rest pose, except the shoulder, whose neutral is the arm hanging at the side: the T-pose reads as 90 degrees of
abduction). The motion is split into swing and twist about the segment's long axis: `flex` and `abd` are the swing's
rotation-vector components on two anatomical axes, `twist` is the axial rotation. This has no gimbal lock below
180 degrees of swing (Euler sequences do at the shoulder), and the angles do not depend on how the rest of the body
is posed.

**Limits.** Swing is bounded by an ellipse per quadrant (the four semi-axes are the four limits), twist by a range.
`soft` approximates clinical active range of motion (no resistance inside); `hard` approximates passive end range
plus a margin (never exceeded when limits are enforced). Between them is the resistance zone: the rig reports a
`soft_load` 0..1 per joint that phase 3 turns into progressive torque. Stiffness, damping, maximum torque and rest
tension are intentionally empty until phase 3 measures them.

**Symmetry.** The left side and the trunk are written in the data file; the right side is generated by mirroring
(rotation axes are axial vectors: (x, y, z) -> (x, -y, -z); "distal" and "proximal" swap), so the profile is
symmetric by construction. Tests check the mirroring, the round trip angles -> rotation -> angles and every bending
direction (knees back, elbows forward, hip internal rotation swings a flexed shank outward, and so on).

**Where the numbers deviate from clinical norms, and why.** Shoulder flexion / abduction are capped at 178 (the swing-
twist singularity is at 180; the arm can still be straight overhead for hanging). The upper thoracic segment has a
wider flexion and rotation budget than its segmental sum because authored clips concentrate trunk motion there (see
[BONE-IK-ANIMATION.md](BONE-IK-ANIMATION.md)). Known simplifications: one constant range per axis (real limits couple
across axes and joints - hip flexion with a straight knee, tibial rotation that vanishes at full extension), an
elliptical swing cone for the shoulder and hip (the real cones are irregular; reach cones after Wilhelms & Van Gelder
2001 are the planned successor), and one bone for the whole shoulder girdle.

| Joint (bone) | Region | Type | flex: soft / hard | abd: soft / hard | twist: soft / hard | Positive directions (flex; abd; twist) | Sources |
|---|---|---|---|---|---|---|---|
| Spine | lumbar spine L1-S1 (pivot at L5/S1) | spinal | [-15,45] / [-25,55] | [-18,18] / [-25,25] | [-8,8] / [-12,12] | flexion + / extension -; lateral flexion left + / right -; rotation left + / right - | WHITE_PANJABI, AAOS |
| Chest | lower thoracic spine T7-T12 (pivot at T12/L1) | spinal | [-10,22] / [-15,30] | [-14,14] / [-20,20] | [-18,18] / [-25,25] | flexion + / extension -; lateral flexion left + / right -; rotation left + / right - | WHITE_PANJABI |
| UpperChest | upper thoracic spine T1-T6 with rib cage (pivot mid-thorax) | spinal | [-8,20] / [-15,30] | [-10,10] / [-15,15] | [-30,30] / [-40,40] | flexion + / extension -; lateral flexion left + / right -; rotation left + / right - | WHITE_PANJABI |
| Neck | lower cervical spine C2-T1 (pivot at C7/T1) | spinal | [-40,32] / [-50,40] | [-28,28] / [-35,35] | [-35,35] / [-45,45] | flexion + / extension -; lateral flexion left + / right -; rotation left + / right - | WHITE_PANJABI, AAOS, NORKIN |
| Head | upper cervical C0-C1-C2 (pivot at the atlanto-occipital joint) | spinal | [-18,14] / [-25,20] | [-6,6] / [-10,10] | [-32,32] / [-40,40] | flexion (nod) + / extension -; lateral flexion left + / right -; rotation left + / right - | WHITE_PANJABI |
| LeftShoulder | shoulder girdle: clavicle at the sternoclavicular joint (scapula follows; scapulothoracic motion is not a separate bone in the humanoid profile) | girdle | [-5,30] / [-10,45] | [-15,15] / [-25,30] | [-5,30] / [-10,45] | elevation + / depression -; protraction + / retraction -; posterior rotation + / anterior - | LUDEWIG, INMAN, NORKIN |
| LeftUpperArm (from the hanging arm) | shoulder: glenohumeral joint (limits are for the whole shoulder complex, see notes) | ball | [-55,165] / [-70,178] | [-30,165] / [-50,178] | [-85,65] / [-100,80] | flexion + / extension -; abduction + / adduction -; internal rotation + / external - | AAOS, NORKIN, SOUCIE, INMAN |
| LeftLowerArm | elbow (humero-ulnar hinge) and forearm rotation (radio-ulnar) | hinge | [0,145] / [-8,155] | [-2,2] / [-5,5] | [-80,75] / [-90,90] | flexion + / hyperextension -; valgus / varus (near 0); pronation + / supination - | AAOS, NORKIN, SOUCIE |
| LeftHand | wrist (radiocarpal and midcarpal) | ellipsoid | [-65,75] / [-80,90] | [-30,20] / [-40,30] | [-10,10] / [-20,20] | flexion (palmar) + / extension -; radial deviation + / ulnar -; residual axial rotation (near 0) | AAOS, NORKIN |
| LeftUpperLeg | hip joint | ball | [-25,120] / [-35,135] | [-25,40] / [-35,55] | [-45,40] / [-55,50] | flexion + / extension -; abduction + / adduction -; internal rotation + / external - | AAOS, NORKIN, SOUCIE |
| LeftLowerLeg | knee (tibiofemoral) | hinge | [0,135] / [-6,150] | [-2,2] / [-5,5] | [-10,10] / [-20,20] | flexion + / hyperextension -; varus / valgus (near 0); internal tibial rotation + / external - | AAOS, NORKIN, SOUCIE |
| LeftFoot | ankle (talocrural) and subtalar joints | ellipsoid | [-45,18] / [-55,30] | [-10,15] / [-20,25] | [-15,30] / [-25,40] | dorsiflexion + / plantarflexion -; adduction + / abduction -; inversion + / eversion - | AAOS, NORKIN, SOUCIE |
| LeftToes | metatarsophalangeal joints (one bone for all toes) | hinge | [-30,60] / [-40,80] | [-5,5] / [-10,10] | [-3,3] / [-8,8] | extension (toes up) + / flexion -; adduction / abduction (near 0); axial (near 0) | AAOS, NORKIN |

Right-side joints mirror the left. Full notes per joint (what each value is compared with) are in the data file.
