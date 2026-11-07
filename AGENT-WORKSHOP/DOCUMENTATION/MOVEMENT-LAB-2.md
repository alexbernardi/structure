# Movement Lab 2.0: what exists, how to run it, how it works

Status as of 2026-11-07 (branch `task/0004-movement-lab-2`, task note [0004](../TASKS/0004-movement-lab-2.md)). A development
utility under `utility/movement/flat-plane/` (ADR-0009), not part of the game. Everything here uses Godot primitives only.
Parameter tables and MIDI bank layouts are generated from the code: [MOVEMENT-LAB-PARAMETERS.md](MOVEMENT-LAB-PARAMETERS.md).
Phase 0 audit and baselines: [MOVEMENT-LAB-AUDIT.md](MOVEMENT-LAB-AUDIT.md). Controller hardware: [SMC-MIXER-HARDWARE.md](SMC-MIXER-HARDWARE.md).

## 1. Where things stand

| Piece | State | Who verified what |
|---|---|---|
| MIDI integration (task 0003 phase 1) | done, 59/59 controls mapped and verified on the SMC-Mixer | user, on hardware |
| Flat-plane sandbox, movement core (0003 phases 2-3) | done, playtested; feedback (jolting, arms, window) fixed | user: "this is a great start" |
| Live MIDI tuning in the sandbox (0003 phase 4) | built, now 9 banks, presets, HUD, binding editor | **hardware checkpoint never confirmed by the user** |
| 2.0 phase 0: audit, baselines, guards | done | automated |
| 2.0 phase 1: analytic spring library + diagnostic scene | done | user confirmed all four visual checks |
| 2.0 phase 2: procedural body inertia (torso, pelvis, head, arms, landing) | done, 3 banks | user: "all of these variables are good" (approval of the variables; not a check of every behaviour) |
| Treadmill gait lab: walk, side view, proportions, drag-and-drop editor | built, now 8 banks | user: "a good stopping point"; smoothness and feel of the editor were not individually confirmed |
| Generated walk via editable AnimationPlayer/AnimationTree in both scenes | implemented; 3 editable graph controls, MIDI/presets | automated and rendered-scene smoke checks; human acceptance pending |
| Remaining 2.0 phases 3-9 (terrain IK, run/turn gait, technique flags, banks A/C, preset A/B, telemetry, playtests) | not started | |

Tests: **420** headless tests in 28 files, all passing; repository static checks also pass. They prove the
maths, the plumbing and the invariants below. They do not prove that anything *looks* right or *feels* right: that needs a person.

## 2. Launch

Godot 4.7.2 lives in `.tools/godot/4.7.2-stable/` after `structure.py setup`. From the repository root:

| What | Command |
|---|---|
| Sandbox (third-person character on a flat plane) | `godot --path utility/movement/flat-plane` |
| **Treadmill gait lab** (side view of the walk, proportions) | `godot --path utility/movement/flat-plane res://scenes/gait_treadmill.tscn` |
| Spring diagnostic | `godot --path utility/movement/flat-plane res://scenes/spring_diagnostic.tscn` |
| MIDI monitor / learn | `godot --path utility/movement/flat-plane res://scenes/midi_monitor.tscn` |
| All utility tests | `python TOOLS/cli/structure.py test check utility` |

Options (after `--`): `--no-hardware`, `--no-tuning`, `--no-window-state`, `--midi-config=`, `--tuning-bindings=`, `--preset-dir=`,
`--tuning-state=`, `--screenshot=<png> [--screenshot-frame=N]`, `--quit-after=<s>`. The lab also takes `--view=side|side-left|front|back|three-quarter`
and any parameter as `--gait.<id>=<v>`, `--rig.<id>=<v>`, `--body.<id>=<v>` (e.g. `--gait.freeze=1 --gait.scrub=0.25`).
The sandbox and the lab open on the left half of the screen on their first run, the spring diagnostic centred; windows can be moved and resized (F6/F7/F8 snap, F11 fullscreen).

**Keys, both scenes:** F3 cycle the HUD, F4 binding editor, PgUp/PgDn bank, `[` `]` preset, F5 save the current values as a preset,
Home reset everything, B body dynamics on/off.
**Sandbox:** WASD, mouse, Space, Shift, Ctrl/C, R respawn, Esc frees the mouse.
**Lab:** Space freeze/resume the cycle, `,` `.` step it, 1-5 camera views, wheel zoom, Ctrl+wheel resize the character, T belt,
**E edit the proportions by dragging handles**, Backspace (while editing) reset the proportions.

## 3. Architecture

```
 physics (120 Hz, authoritative)            presentation (per rendered frame, never read by physics)
 -----------------------------------        -------------------------------------------------------------
 movement/movement_core.gd   (step)         animation/springs.gd        analytic spring library (phase 1)
 character/character_body.gd (collider,     animation/body_dynamics.gd  torso/pelvis/head/arm springs from kinematics
   step-up, signals)                        animation/gait_model.gd     phase-driven foot paths + leg IK + hips + arms
 movement/movement_params.gd (21 params)    animation/*_params.gd       body, gait, rig parameter sets (ParamSet)
            |                                           |
            |  kinematics (velocity, accel, heading)    |  pose dictionaries {dyn, gait}
            +------------------------------------------>  character/character_visual.gd  (pose calculation, 15 bones, primitive meshes)
                                                               |
                                            animation/walk_animation.gd -> AnimationPlayer/AnimationTree -> Skeleton3D

 midi/*  (device, learn, verified mapping)  ->  tuning/*  (registry, bindings, soft takeover, presets)  ->  any ParamSet
 scenes/flat_plane.gd (sandbox)   scenes/gait_treadmill.gd (lab)   ui/*  (HUD, binding editor, gait overlay, rig editor)
```

**Invariants, each guarded by tests**
- Physics is identical with the body model on, off or absent, and with animation disabled or the visual deleted (bit-identical trajectories).
- Every presentation parameter is tagged `affects: visual`; none is read by the simulation. The HUD shows the tag.
- With no gait pose, no body pose and the original rig, the visual is the original pose (compared bone by bone and mesh by mesh).
- Defaults are clamped, snapped and unit-labelled; NaN falls back to the default; bad MIDI cannot move anything past its range.

### File map (`utility/movement/flat-plane/`)

| Folder | Contents |
|---|---|
| `movement/` | `movement_core.gd`, `movement_params.gd` (21 simulation parameters), `input_source.gd`, `input_actions.gd` (key bindings incl. the tuning shortcuts) |
| `character/` | `character_body.gd`, `character_visual.gd` (skeleton, poses, `apply_rig`), `walk_visual.tscn` (editor-visible primitives, AnimationPlayer/Tree), `orbit_camera.gd` |
| `animation/` | `spring_math.gd`, `springs.gd`, `spring_metrics.gd`; `param_set.gd`; body/gait/rig parameter sets and models; `graph_params.gd`, `walk_animation.gd`, `walk_tree.tres` |
| `midi/` | device discovery, events, catalog of the 59 controls, behaviour detection, MIDI learn, config, manager |
| `tuning/` | `tunable_registry.gd` (any object with the parameter-set interface), `tuning_bindings.gd` (banks), `tuning_engine.gd`, `soft_takeover.gd`, `preset_store.gd`, `tuning_system.gd` |
| `ui/` | `tuning_hud.gd`, `binding_editor.gd`, `gait_overlay.gd`, `rig_editor.gd` |
| `scenes/` | `flat_plane`, `gait_treadmill`, `spring_diagnostic`, `midi_monitor`, `window_state.gd`, `controller_panel.gd` |
| `config/` | `midi_mapping.json` (learned, verified: do not overwrite), `tuning_bindings.json`, `gait_bindings.json` |
| `presets/`, `presets_gait/` | named parameter sets (JSON). `presets_gait/default.json` is the saved default; `first_defaults.json` the values before the first tuning session |
| `tools/` | `make_tuning_files.gd`, `make_gait_files.gd`, `make_param_docs.gd`, `make_walk_scene.gd` (generators), `gait_smoothness.gd` (measurement), `audit*.gd`, `mapping_tool.gd` |
| `tests/`, `benchmarks/` | 28 test files; `bench_baseline`, `bench_springs`, `bench_body`, `bench_gait`, `bench_walk_animation` |

## 4. The pieces in a little more depth

### Analytic springs (phase 1)
`x'' = -k(x-g) - c(v-q)` is solved exactly as a propagator on `(x-g, v-q)` for an under-, critically or over-damped spring with the goal
moving linearly. Results do not depend on the step size (15 Hz to 1 kHz agree to 1e-9), stay finite for any input, and compose exactly. Scalar, Vector3 and
rotation springs share it; joint limits remove outward velocity. A naive Euler spring is kept only to show it explodes at 12 Hz / 30 fps.

### Body dynamics (phase 2)
Springs for torso pitch/yaw/roll, pelvis weight shift, gait bob and sway, landing compression with rebound, facing lag, head
stabilisation and arm follow-through, driven by the physics body's mean acceleration since the last frame (so the result does not depend on
how many ticks fell in a frame). Ten switches (a master and nine effects) isolate each effect. Landing compression is done through the knees so the
feet stay planted.

### Procedural gait (treadmill lab)
The walk plans where each **ankle** goes and solves the legs from that:
- **Stance:** the foot is fixed to the ground and rolls heel, flat, toe (quintic easing). In the hips' frame it moves back at exactly the belt speed; the
  lab measures this on the posed skeleton and reports foot slip (below 3 mm/s at 0.8, 1.2 and 1.8 m/s).
- **Swing:** a quintic Hermite path from the toe-off pose to the next heel strike. `velocity_match` = 1 leaves and lands with the stance foot's velocity
  and acceleration (no jolt); lower values are a crisper, less smooth landing. Plus a clearance bump, a toe-lift and a floor under the sole.
- **Hips:** a sinusoid at twice the stride frequency, highest over a stance leg. When the stride is too long for the legs the whole sine is lowered by a constant
  amount computed per setting, so planted feet never lift and the hip path stays a clean sine (within 1.3 % of a pure sine for the factory values at 0.6-2.0 m/s,
  2.7 % for the saved defaults, whose small loading dip adds a little). The knee never locks: `knee_min_flex`.
- **Legs:** analytic sagittal two-bone IK for the rig's real bone lengths. Pelvis yaw and tilt move the hips; the thighs undo them so legs stay in the forward plane.
- **Arms and trunk:** counter-swing against the opposite leg with a timing offset, elbows that deepen with the swing, shoulders counter-rotating against the pelvis.
- Step length grows with speed as `speed^0.42` unless switched off; cadence follows from speed and step length.

Measured trade-off in the saved defaults: `velocity_match` 0.7 makes the knee's acceleration at heel strike about 3x sharper than at 1.0 (14.7x the median at
1.2 m/s versus 5.0x; `tools/gait_smoothness.gd`). The foot-flat slap after heel strike is set by `foot_flat_at`.

### Proportions and the drag-and-drop editor
`animation/rig_params.gd` has 19 visual-only parameters (overall size, thigh, shin, ankle height, foot length, hip offset, lower torso, chest, neck, head, shoulder
offset, torso width and depth, upper arm, forearm, four limb thicknesses). `Visual.apply_rig` re-proportions the skeleton and rebuilds the meshes live; the gait
model plans for the real leg lengths, so a different body still does not slip on the belt (tested on random bodies). A **null rig is the original rig** (what the sandbox
character is built from); the parameter *defaults* are the tuned proportions.

Switch `edit_rig` on (E, or the View & Playback bank) and every joint and limb gets a handle: orange = a bone's length (drag the joint along the bone), also foot
length and ankle height; purple = a joint's offset from the centre line and torso width (front, back, 3/4 views); green = limb thickness (drag the edge), head size and torso depth.
The walk freezes while editing. Sub-step drags accumulate, dragging past a limit comes straight back, and the same parameters are on the controller (banks
Proportions 1 and 2), in presets, and in the HUD.

### Tuning layer
Two data layers, both editable: the learned physical-to-logical mapping (`midi_mapping.json`) and logical-control-to-parameter bindings in banks. Faders use soft
takeover (no jump when switching banks or presets), knobs step by the parameter's step, buttons reset, lock, revert, select, toggle, switch banks and presets, save,
respawn or teleport. Any object with the parameter-set interface can register as a target (`movement`, `body`, `gait`, `rig`); presets save every registered target.

## 5. Configuration and data

### Editing the walk in Godot

Both the treadmill and third-person sandbox now instance
[walk_visual.tscn](../../utility/movement/flat-plane/character/walk_visual.tscn). Open that scene in the utility project's
Godot editor to inspect its primitive skeleton, **AnimationPlayer** and **AnimationTree**. The shared graph is
[walk_tree.tres](../../utility/movement/flat-plane/animation/walk_tree.tres).

The AnimationPlayer contains a generated `walk` loop (one second = one normalized stride), `RESET`, and two live,
single-pose clips: `legacy` for idle/air/crouch/landing fallback, and `body` for rest-relative additive dynamics.
The tree, not the procedural visual code, writes the bones:

`Walk -> WalkSeek -> WalkSpeed -> WalkBlend -> Locomotion -> BodyAdd -> output`

- **WalkBlend / blend_amount**: 1 = generated walk, 0 = original procedural fallback.
- **BodyAdd / add_amount**: 1 = existing body dynamics/composition, 0 = sampled walk without that additive layer.
- **WalkSpeed / scale**: playback multiplier; also synchronizes the planner and treadmill belt. Physics is unaffected.
- **Locomotion / blend_amount** and **WalkSeek / seek_request** are scene-driven: ground/air/crouch/landing handover and
  freeze/scrub respectively. Do not manually drive those, or rename the connected nodes used by the adapter.

For live editing, run [gait_treadmill.tscn](../../utility/movement/flat-plane/scenes/gait_treadmill.tscn) or
[flat_plane.tscn](../../utility/movement/flat-plane/scenes/flat_plane.tscn) from Godot, select **Remote**, expand the
character's Visual, select AnimationTree, and adjust the three controls above in its Parameters inspector.
These changes sync to `graph.walk_blend`, `graph.body_blend` and `graph.playback_speed`; the **Animation Graph** MIDI bank
puts them on strips 1, 2 and 3 (fader coarse, knob fine), with normal pickup, reset/lock/revert and F5 preset persistence.
To set startup graph values, edit those same Parameters on the local reusable visual scene and save it.
Graph layout/connection edits are saved in the shared `.tres`. Enabling editable children is needed to edit an instance
instead of the reusable scene.

Gait/proportion changes regenerate the 96-sample walk loop without resetting the phase. The additive layer retains
the analytic foot pose and existing springs; turning it off reveals the clip's sampling approximation. Editor-keyed
changes to `walk`, `legacy` or `body` are overwritten by generation/live updates, so tweak the gait settings or graph
instead. The shipped preview clip can be scrubbed directly in AnimationPlayer without running the lab.
Regenerate the reusable scene with `--script res://tools/make_walk_scene.gd` only deliberately: this rewrites the preview
and saved node properties, not presets or MIDI mappings.

The sandbox retains its **original visual proportions and collision dimensions**, but uses the saved gait settings.
Its speed comes from actual movement, not the treadmill's `walk_speed` setting. Two added sandbox banks expose Walk
Cycle and Walk Upper Body. Turning `gait_model` off restores the fallback; airborne/crouched/landing poses still hand over
to it automatically. No separate run gait or terrain IK is implied by this integration.
Older presets that have no `graph` target leave the current graph settings unchanged; newly saved presets include them.

| File | Meaning | Regenerate |
|---|---|---|
| `config/midi_mapping.json` | verified physical mapping of the SMC-Mixer (59/59) | never by hand; use the MIDI monitor's learn |
| `config/tuning_bindings.json` | sandbox movement/body banks plus Walk Cycle, Walk Upper Body and Animation Graph | `make_tuning_files.gd` (`--add-missing-banks` appends new banks without touching edits) |
| `config/gait_bindings.json` | original seven treadmill banks plus Animation Graph | `make_gait_files.gd --add-missing-banks` (append only); `--force` overwrites |
| `presets/*.json`, `presets_gait/*.json` | named parameter sets | `make_tuning_files.gd`, `make_gait_files.gd --force` (the example presets are starting points, not claims about realism) |
| `%APPDATA%/Godot/app_userdata/MIDI Movement Lab - flat plane/` | window placement, last bank and preset | delete to forget |

The MIDI layout of every bank is in [MOVEMENT-LAB-PARAMETERS.md](MOVEMENT-LAB-PARAMETERS.md) (regenerate with `tools/make_param_docs.gd`).
The controller sends every message on two ports; auto mode accepts one. It is in DAW/Mackie mode: faders are pitch bend, knobs relative CC16-23, buttons notes.

## 6. Measurements (this machine, headless; compare only against the same machine)

| Item | Cost |
|---|---|
| Baseline: `core.step` / `body.simulate` / `visual.update_pose` / `scene._process` | 2.3 us / 15 us (29 on stairs) / 7.6 us / 13.6 us |
| Springs: scalar / vector / rotation step | 1.5 / 2.0 / 4.2 us |
| Body dynamics update (all effects) / master off; `scene._process` with / without it | 68 us / 3 us; 91 us / 20 us |
| Gait: update at a steady speed / `pose_at` | 52 us / 46 us |
| Gait: `cycle_for` on a cache miss (while a setting or the speed changes) / `Visual.apply_rig` | 1.2 ms / 1.3 ms |
| AnimationTree treadmill frame at steady speed / 96-sample walk clip regeneration | 0.32 ms / 7.2 ms; regeneration occurs on gait, rig or speed changes, not camera/playback/scrub edits |

## 7. Known limitations

- Both scenes use the generated walk through AnimationTree; the sandbox retains original proportions. While a landing
  compression is active the legs are handed back to the simple pose.
- Walking only: running, turning, stopping, stairs and slopes are not modelled by the gait; step width is not modelled (hips and feet stay in their planes).
- The explicit-Euler movement core is 3-11 % step-rate dependent between 60 and 120 Hz (stop distance 10.8 %, jump apex 3 %). Documented and guarded, not fixed.
- Vector3 and Quaternion are single precision: positions in the gait model are good to about 1e-7 m, and tests are written with that in mind.
- `velocity_match` below 1 deliberately trades the heel-strike hand-over smoothness for a crisper landing (see section 4).
- The sandbox's live-tuning hardware checkpoint (task 0003 phase 4) was never confirmed; treat it as unverified until it is.
- Input recording and playback are not implemented (the controller's record button says so).

## 8. Things learned that are easy to get wrong

- A scene added before the tree starts (or from `SceneTree._initialize`) runs `_ready` later, and that `_ready` re-enables its own `_process`: after `add_child`,
  `await process_frame` and then disable processing. This caused double-stepping bugs in tests.
- `Camera3D.unproject_position` uses the previous frame's transform: after changing the view, wait one frame before hit-testing (tests do).
- The headless viewport is 64x64: drag distances in tests must be scaled to the viewport, and two handles can overlap on screen.
- GDScript has no `%e` format; `:=` fails on untyped `Variant` or dictionary reads (annotate the type); a `Control` member named `rotation` clashes.
- `Quaternion.angle_to` loses precision near zero; measure small rotations through the rotation vector.
- The tuning shortcuts are input actions registered by `movement/input_actions.gd`: every scene that uses the tuning layer must call `Actions.register()` (the
  lab did not at first; there is now a test).
- Working copies on Windows are CRLF (git normalises them): edit with tools that preserve line endings.

## 9. Next steps

Verify the animation graph interactively in both scenes; add run and turn gaits; foot IK on the ramps and stairs; technique experiments behind flags; banks A and C; preset A/B
comparison and the starting presets; telemetry and input recording; guided playtests. Each stops for the user's eyes or hands where the brief says so.
