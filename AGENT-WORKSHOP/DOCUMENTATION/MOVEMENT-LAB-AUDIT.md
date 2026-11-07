# Movement Lab audit (Phase 0 of task 0004)

Baseline of `utility/movement/flat-plane/` before "Movement Lab 2.0" changes anything. Every number here was produced
by a script in `utility/movement/flat-plane/tools/` or a test, on 2026-11-07, Godot 4.7.2-stable, Windows 11
(RTX 3090, 3440x1440). Re-run: `tools/audit.gd`, `tools/audit_baseline.gd`, `tools/audit_tables.gd`, and
`--mode=bench --dir=res://benchmarks`.

## 1. Engine and animation APIs (verified with `ClassDB`)

All of these exist in 4.7.2-stable: `Skeleton3D`, `SkeletonModifier3D`, `BoneAttachment3D`, `AnimationTree`,
`AnimationPlayer`, `SkeletonIK3D`, **`TwoBoneIK3D`**, `IKModifier3D`, `ChainIK3D`, `LookAtModifier3D`, `BoneConstraint3D`,
`CopyTransformModifier3D`, `AimModifier3D`, `SpringBoneSimulator3D`, `LimitAngularVelocityModifier3D`, `FABRIK3D`,
`CCDIK3D`, `JacobianIK3D`, `SplineIK3D`, `IterateIK3D`, `PhysicalBoneSimulator3D`.

- `TwoBoneIK3D` extends `IKModifier3D` extends `SkeletonModifier3D`. Its configuration is per-setting (`setting_count`,
  then root/middle/end bone, target node, pole node/direction, virtual end). Whether it can drive this rig is a **Phase 4
  question**; a small custom two-segment solver is the fallback the brief allows.
- `SkeletonModifier3D` children run inside the skeleton's update (default `modifier_callback_mode_process` = idle), which
  is where IK should go so it composes with the procedural pose.
- `SpringBoneSimulator3D` exists, but the brief wants our own analytic springs (Phase 1) so they are testable and tunable.

## 2. The humanoid is a genuine `Skeleton3D` with rigid segments

| Fact | Value | How checked |
|---|---|---|
| Skeleton node | `Skeleton3D`, 15 bones, one root (pelvis) | `tools/audit.gd` |
| Drawn geometry | 15 `MeshInstance3D` (box / capsule / sphere primitives), each under a `BoneAttachment3D` | audit |
| Skinning | **none**: segments are rigid and ride their bones (0 skinned meshes, 0 `Skin` resources) | audit |
| Modifiers on the skeleton | none yet | audit |
| Does a bone change reach the screen? | **Yes, immediately.** Lowering the pelvis bone from 1.01 to 0.5 m dropped the head mesh by exactly 0.510 m; rotating the shoulder 1.2 rad moved the forearm joint 0.423 m (skeleton) and the drawn forearm mesh 0.460 m, the same frame | audit, 8 frames |
| Collision | `CharacterBody3D` with a flat-bottomed `CylinderShape3D`; the visual is a *child* node that is `top_level`, not interpolated, not a `CollisionObject3D` | audit, `test_physics_presentation_split.gd` |

Consequence for later phases: bone poses can be driven directly (springs, gait, IK) and the result is visible. Because
the segments are rigid, joints will show gaps when bent far; keep angles within the limits Phase 2 sets.

## 3. Architecture and the physical / presentation split

```
scenes/flat_plane.gd      composition only (world, body, visual, camera, MIDI + tuning)
movement/movement_params.gd   21 parameters: id, unit, min, max, default, step (clamped, snapped)
movement/movement_core.gd     PURE simulation: velocity in, velocity out. No nodes, no presentation state
character/character_body.gd   CharacterBody3D: asks the world, applies the core's velocity, steps, collider resize
character/character_visual.gd Skeleton3D + primitives + procedural pose. Reads a small state dict only
character/orbit_camera.gd     view only
tuning/ ui/ midi/             controller layer (see section 5)
```

- Presentation reads physics, never the reverse. **Verified**: with a scripted run/turn/jump/crouch of 3.5 s at 120 Hz the
  body's position, velocity, grounded and crouching flags and collider are *bit-identical* with the humanoid animating,
  with animation switched off (`--no-animation`), and with the visual node deleted
  (`tests/test_physics_presentation_split.gd`). Posing with absurd inputs (1000 m/s, NaN-free extremes) never touches the
  body or collider.
- `body.step_offset` (eases stair climbs for the camera and visual) lives on the body but is presentation-only: nothing in
  the simulation reads it.
- New switch: `animation_enabled` / `--no-animation`.

## 4. Movement parameters (21, all in `MovementParams`)

| Parameter | Unit | Min | Max | Default | Step | Group |
|---|---|---|---|---|---|---|
| `max_ground_speed` | m/s | 1.0 | 15.0 | 4.5 | 0.1 | ground |
| `ground_accel` | m/s^2 | 1.0 | 120.0 | 45.0 | 1.0 | ground |
| `ground_friction` | 1/s | 0.0 | 20.0 | 7.0 | 0.1 | ground |
| `braking` | m/s^2 | 0.0 | 100.0 | 20.0 | 1.0 | ground |
| `stop_speed` | m/s | 0.1 | 5.0 | 1.0 | 0.05 | ground |
| `sprint_multiplier` | x | 1.0 | 3.0 | 1.6 | 0.05 | ground |
| `crouch_speed` | m/s | 0.5 | 6.0 | 2.0 | 0.1 | ground |
| `jump_impulse` | m/s | 1.0 | 15.0 | 5.5 | 0.1 | jump |
| `gravity` | m/s^2 | 1.0 | 60.0 | 19.6 | 0.2 | jump |
| `max_fall_speed` | m/s | 5.0 | 100.0 | 50.0 | 1.0 | jump |
| `coyote_time` | s | 0.0 | 0.5 | 0.1 | 0.01 | jump |
| `jump_buffer_time` | s | 0.0 | 0.5 | 0.1 | 0.01 | jump |
| `auto_jump` | on/off | 0 | 1 | 0 | 1 | jump |
| `air_accel` | m/s^2 | 0.0 | 200.0 | 30.0 | 1.0 | air |
| `air_speed_cap` | m/s | 0.0 | 10.0 | 1.2 | 0.05 | air |
| `air_control` | 0..1 | 0.0 | 1.0 | 0.35 | 0.01 | air |
| `max_walkable_slope` | deg | 5.0 | 85.0 | 46.0 | 1.0 | slope |
| `slope_speed_penalty` | 0..1 | 0.0 | 1.0 | 0.4 | 0.01 | slope |
| `step_height` | m | 0.0 | 0.6 | 0.35 | 0.01 | slope |
| `stand_height` | m | 1.4 | 2.2 | 1.8 | 0.01 | body |
| `crouch_height` | m | 0.8 | 1.4 | 1.1 | 0.01 | body |

Not yet parameters (hard-coded constants): body radius 0.35, step-up detection tolerances, the presentation constants in
`character_visual.gd` (gait frequencies, lean gains, easing rates), camera smoothing.

## 5. MIDI layers and current bindings

Layer 1, *physical -> logical control*: learned and **verified 59/59** on the SMC-Mixer (`config/midi_mapping.json`,
task 0003 phase 1; **not to be overwritten**). Layer 2, *logical control -> parameter/action*:
`config/tuning_bindings.json`, three banks (data, editable, validated):

**Bank 1 Ground** - faders and knobs both: strip 1 max ground speed, 2 ground acceleration, 3 ground friction,
4 braking, 5 friction stop speed, 6 sprint multiplier, 7 crouch speed, 8 unassigned.
**Bank 2 Jump & Air** - 1 jump impulse, 2 gravity, 3 terminal fall speed, 4 coyote time, 5 jump buffer,
6 air acceleration, 7 air speed cap, 8 air steering.
**Bank 3 Slope & Body** - 1 max walkable slope, 2 uphill speed penalty, 3 step-up height, 4 standing height,
5 crouching height, 6 auto-jump, 7-8 unassigned.
Each knob currently fine-adjusts the same parameter as its fader.

Buttons: strip M reset parameter, S lock/unlock, R revert to preset value, Select show details. Transport: Play respawn,
Stop reset all, Record (input recording: **placeholder, not implemented**), Rewind/Fast-forward previous/next preset,
`<<`/`>>` previous/next bank, Up save preset, Down cycle HUD, Left/Right teleport between landmarks.

Soft takeover (pickup) is in place for faders (`tuning/soft_takeover.gd`); knobs are relative and never jump.

**Gap against the brief's Phase 6 banks:** the brief's Bank A (turn/acceleration/stopping response, momentum retention,
gravity *multiplier*, air drag), Bank B (body springs) and Bank C (gait/IK) reference parameters that do not exist
yet. They arrive with Phases 2-5; the existing three banks stay as they are until then.

## 6. Baseline behaviour (Stage I controller, defaults, flat floor, core only)

| Measure | 120 Hz | 60 Hz |
|---|---|---|
| Max / sprint / crouch speed | 4.5 / 7.2 / 2.0 m/s | same |
| Time to 95 % of max speed | 0.100 s | 0.100 s |
| Distance covered in 2 s from rest | 8.794 m | 8.812 m |
| Stop from 4.5 m/s (to < 0.05 m/s) | 0.125 s, 0.229 m | 0.133 s, 0.205 m |
| Reverse: zero crossing / 95 % the other way | 0.058 s / 0.150 s | 0.067 s / 0.150 s |
| 90 degree turn at full speed: slowest speed / recovery | 3.82 m/s / 0.083 s | 3.82 m/s / 0.083 s |
| Jump apex / air time | 0.749 m / 0.558 s | 0.726 m / 0.550 s |
| Speed kept across a jump | 100 % | 100 % |

**Known limitation (new finding):** the core is explicit Euler for friction and gravity, so results depend a little on the
tick rate: stop distance 10.8 % apart, stop time 6.7 %, jump apex 3.0 % between 60 and 120 Hz (speeds are identical).
The project runs physics at 120 Hz. This is guarded by `tests/test_baseline_behavior.gd` with those tolerances; it is
not fixed here because the brief says not to replace working systems. Phase 8's 60/120 test inherits these tolerances.

## 7. Baseline cost (headless, this machine; `benchmarks/bench_baseline.gd`)

| Operation | Cost | Share of the 8333 us tick at 120 Hz |
|---|---|---|
| `core.step` ground / air | 2.3 / 2.5 us | 0.03 % |
| `body.simulate` open ground | 15.0 us | 0.18 % |
| `body.simulate` on stairs (step rays + test_move) | 29.2 us | 0.35 % |
| `visual.update_pose` (15 bones) | 7.0 us | per rendered frame |
| `scene._process` (follow + pose + readout) | 13.6 us | per rendered frame |

Huge headroom; new animation/IK work should stay in the tens of microseconds. MIDI rescan, measured earlier: 49.5 ms
blocking -> 0.07 ms on a worker thread.

## 8. Tests, presets, constraints

- **235 headless tests** in 17 files (`structure.py test utility`): MIDI events/learn/config/manager, movement core and
  params, scene (ramps, stairs, tunnel, skeleton, camera, window), tuning (soft takeover, banks, presets, bindings, scene
  integration through the real learned mapping), and the Phase 0 guards. Suite `utility` also runs in `structure.py test`.
- Shipped presets (`presets/`): `default`, `floaty`, `snappy`, `strafe_lab`, `slippery` (examples, not claims about feel).
- Constraints that apply: no `class_name`; `preload` dependencies; metres/seconds/radians; no Docker/Blender/assets;
  physics at 120 Hz with interpolation on; headless-test trap: a scene added before the tree starts re-enables its own
  processing in `_ready`, so tests must wait one frame before disabling it.
