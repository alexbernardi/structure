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
| Treadmill gait lab: reference walk, running prototype, proportions and path editors | 11 banks; Walk/Run, right-to-left perspective, front/side and mode-specific pose buttons | user liked the reference walk; running is tested/rendered, awaiting visual feedback |
| Generated walk via editable AnimationPlayer/AnimationTree in both scenes | implemented; 3 editable graph controls, MIDI/presets | automated and rendered-scene smoke checks; human acceptance pending |
| Remaining 2.0 phases 3-9 (terrain IK, production run/turn transitions, technique flags, banks A/C, preset A/B, telemetry, playtests) | treadmill run prototype only; remaining work outstanding | |

Validation: **465/465** tests passed in the latest full utility run (31 test files), including reference landmarks, the 7 m/s treadmill default, 6 / 12 m/s Playground movement,
running flight/landing/contact/IK, speed-changing clip accuracy, scrubbing, presets/MIDI, camera controls and perspective HUD framing. Repository static checks also pass. They prove the
maths, the plumbing and the invariants below. They do not prove that anything *looks* right or *feels* right: that needs a person.

## 2. Launch

Godot 4.7.2 lives in `.tools/godot/4.7.2-stable/` after `structure.py setup`. From the repository root:

| What | Command |
|---|---|
| Movement Playground (internally the flat-plane sandbox, with obstacles) | `godot --path utility/movement/flat-plane` |
| **Treadmill gait lab** (side view of the walk, proportions) | `godot --path utility/movement/flat-plane res://scenes/gait_treadmill.tscn` |
| **Running treadmill** | `godot --path utility/movement/flat-plane res://scenes/gait_treadmill.tscn -- --gait-mode=run` |
| Spring diagnostic | `godot --path utility/movement/flat-plane res://scenes/spring_diagnostic.tscn` |
| MIDI monitor / learn | `godot --path utility/movement/flat-plane res://scenes/midi_monitor.tscn` |
| All utility tests | `python TOOLS/cli/structure.py test check utility` |

Options (after `--`): `--no-hardware`, `--no-tuning`, `--no-window-state`, `--midi-config=`, `--tuning-bindings=`, `--preset-dir=`,
`--tuning-state=`, `--screenshot=<png> [--screenshot-frame=N]`, `--quit-after=<s>`. The lab also takes `--view=side|side-left|front|back|three-quarter`
and `--gait-mode=walk|run`, plus any parameter as `--gait.<id>=<v>`, `--rig.<id>=<v>`, `--body.<id>=<v>` (e.g. `--gait.freeze=1 --gait.scrub=0.25`).
The explicit gait mode wins over the restored preset. For deterministic command-line pose captures, use `--no-tuning --no-hardware` so saved presets
cannot override other parameter arguments. The namespaced option avoids the shared test harness's `--mode=test`.
The sandbox and the lab open on the left half of the screen on their first run, the spring diagnostic centred; windows can be moved and resized (F6/F7/F8 snap, F11 fullscreen).
The playground always uses the running profile for normal ground movement: **6 m/s**, or **12 m/s** while holding **Shift** (the default **2x** multiplier).
Releasing Shift returns to 6 m/s without switching gait. These are physical speed targets; the existing acceleration, momentum, collision, crouch and jump rules
are unchanged, so tight turns can briefly exceed the target. The treadmill keeps its separate **1.55 m/s walk** and **7 m/s run** defaults and Walk/Run controls.
The shipped movement defaults and example presets use the new multiplier; the `strafe_lab` example retains its intentional 5 m/s base-speed override.

**Keys, both scenes:** F3 cycle the HUD, F4 binding editor, PgUp/PgDn bank, `[` `]` preset, F5 save the current values as a preset,
Home reset everything, B body dynamics on/off.
**Sandbox / Movement Playground:** WASD run, mouse look, Space jump, hold **Shift** to sprint, Ctrl/C crouch, R respawn, Esc frees the mouse.
**Lab:** Space freeze/resume the cycle, `,` `.` step it, 1-5 camera views, wheel zoom, Ctrl+wheel resize the character, T belt,
**E edit proportions**, **P edit the ankle path**. Backspace resets the active editor's parameters; Escape cancels an ankle-path drag.
The default is **right-to-left in perspective** (`side-left`). **1 / Side** returns there, **2 / Other side** reverses the camera,
**3 / Front** faces the character, **4** shows the back, **5 / 3/4** shows three-quarter. Changing view does not change projection.
**Contact / Down / Passing / Up** pause at cycle positions 0 / 0.125 / 0.25 / 0.375; **Play** or Space resumes.
**Reference default** reloads the matched gait, proportions and full-speed/full-blend animation graph, and returns to the reference side.
**Walk / Run** switch profiles and select **Walk Cycle / Running** on the controller. In Run, the pose buttons become
**Contact / Down / Passing / Flight**, using the current stance duration; **Run default** restores the shipped run preset.
Switching mode restarts the cycle without an artificial body-spring impulse; it is a lab comparison, not a blended gameplay transition.
Existing parameter locks remain respected. Older saved user presets are untouched and can restore their earlier settings.

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
| `tests/`, `benchmarks/` | 31 test files; `bench_baseline`, `bench_springs`, `bench_body`, `bench_gait`, `bench_walk_animation`, `bench_gait_turning` |

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
- **Stance:** the foot is fixed to the ground and rolls heel, flat, toe. In the hips' frame it moves back at exactly the belt speed; the
  lab measures this on the posed skeleton and reports foot slip (below 3 mm/s at 0.8, 1.2 and 1.8 m/s). The ankle passes under the hip at `midstance_at`
  of the stance (0.34), so at heel strike the legs straddle the hips instead of reaching out in front. The rockers use a quintic that starts moving
  (`roll_flow` = 1): the toe starts dropping the instant the heel lands and the foot is still turning at toe-off; 0 is the old hold-then-roll easing.
  The reference default starts heel rise at 0.42 of stance and reaches 75 degrees toe-down at toe-off.
- **Swing:** piecewise quintic Hermite through toe-off, Passing, Up and the next heel strike; common velocities/accelerations make the joins C2.
  `velocity_match` now defaults to 1 so the ankle matches stance speed as well as acceleration and foot rotation at handover.
  A smooth, bounded clearance correction prevents the descending toe from scraping between Passing and Up without moving those landmarks.
  Very low user clearance settings can still engage the sole safety floor. `swing_forward` bows only the airborne path with zero endpoint velocity/acceleration.
  `reference_fit=0` retains the former single-segment path and clearance bump.
- **Hips:** a twice-stride sinusoid fitted to the measured hip heights, low near Down (phase 0.10), high near Up (0.35), rather than at Passing.
  When reach is insufficient the entire wave is lowered by a constant; the local safety limit prevents a planted foot lifting. At 0.8-2.0 m/s on the
  original rig the fitted-sine residual is 0.7-0.9 %. The knee never locks: `knee_min_flex`.
- **Legs:** analytic sagittal two-bone IK for the rig's real bone lengths. Pelvis yaw and tilt move the hips; the thighs undo them so legs stay in the forward plane.
- **Arms and trunk:** smooth interpolation through reference arm/elbow poses, with the existing amplitude, timing and effect switches; shoulders counter-rotate.
  At `reference_fit=0` the former cosine arm swing returns.
  Posture (`Visual.trunk_posture`, shared by the live pose and the generated clip): `torso_lean` tilts the whole straight trunk at the waist, `spine_curve`
  curls the chest (60 %) and neck (40 %) for a hunched back (default 0 = straight), and `head_level` turns the head back by both so the face stays level.
- Step length grows with speed as `speed^0.42` unless switched off; cadence follows from speed and step length.

Measured (`tools/gait_smoothness.gd`, original rig, 1.6 m/s): reference defaults give maximum local foot/knee angular accelerations of 399/787
rad/cycle-squared, versus 344/618 in the preceding knee-extension revision. Matching a more pronounced reference pose is not a claim that every acceleration falls.
At 1.2 m/s, maximum joint change is 0.056 rad per 120 Hz tick. The default has full velocity matching; lower settings intentionally trade away that smoothness (KI-016).

### Reference fit and its limits
`animation/walk_reference.gd` records approximate image-space hip, shoulder, knee and ankle landmarks from the user's five-pose drawing.
Mean projected thigh/shin lengths are about 74/72 pixels; the default fixed-length rig uses 0.46/0.44 m before overall scale.
Hip-to-shoulder / total leg length is about 0.71 in both the drawing and rig. The torso is longer relative to the legs, the limbs slimmer,
and the hands shorter and thinner in side view. Original sandbox bone lengths remain unchanged.

After aligning each drawing at its hips, the airborne ankle is about 28.4 % of the way from push-off to landing at Passing and 73.6 % at Up.
The fitted path interpolates those fractions. At the defaults, Passing is phase 0.7492 with an approximately 80-degree toe-down foot;
Up is 0.8746 with a 12-degree toe-down foot. Passing/Up knee angles are within 10 degrees of the annotated drawing for both legs.
The reference fit is a constraint-based approximation, not motion capture or a literal pixel trace: projected limb lengths and apparent ground heights vary,
and the Contact/Down poses are less exact. A shared ground plane, fixed bone lengths and planted-foot travel take precedence over impossible 2D lengths.

`reference_fit` blends the reference swing, hip timing and arms (1, default) against the former procedural model (0), without changing proportions.
It is on **View & Playback, strip 4 fader**, beside the orthographic switch on knob 4. Use **Reference default** for a clean comparison rather than
trying to recover it by individually undoing old tuning. This is a walking reference pass, not approval of a foundation for run/turn/terrain modes.

**Body shapes.** `Visual.mesh_specs(dims)` is the one table of primitive shapes, used by `build()` and `apply_rig()` alike (so the sandbox gets them too):
an egg-shaped pelvis, the spine and chest as capsules squashed front-to-back, an egg head centred forward of the neck with a nose, and flat hands on the
forearms (extra meshes `Hand` / `Nose` beside each bone's `Mesh`). With `view_joints` the overlay draws the skeleton like the reference: spine yellow,
neck and head cyan, hip and shoulder lines magenta, arms to the fingertips in the side's colour, pelvis centre teal. These are drawn from the existing 15
bones; no bones were added.

### Running prototype
Running is opt-in on the treadmill (`run_mode=1`); the factory walk is unchanged. The Playground keeps running selected independently of Shift.
The treadmill run starts at **7 m/s** (15.7 mph, about a 3:50 mile pace; the belt goes to **15 m/s**). There the step is **2.20 m**
(`run_step_length` 1.65 m is the step at 4.5 m/s, scaled by speed^0.65), cadence is **191 steps/min**,
each foot is planted for **18%** of its cycle (**0.113 s** of ground contact) and there is **64% total flight**, split between the feet's contacts.
The cyan support-chart bands and **FLIGHT** readout indicate those intervals. The actual soles, not only contact flags, clear the belt in the tested
interior-flight samples. Each airborne interval lasts **0.201 s**, covering **1.41 m** at belt speed, versus 0.144 s / 1.01 m in the previous
1.80 m-step profile. This is intentionally a longer, more bounding run, rather than faster leg turnover. A full two-step stride is **4.40 m**.

The pose buttons follow the running reference image (`animation/run_reference.gd`), whose frames cover **one step, half a cycle**:
Contact is the heel strike, Down is 5/12 of the stance (loaded), Passing is 5/6 of the stance (still on the same foot, the recovering foot coming
through high), and Flight is 37.5% of the way through the following airborne interval. At the default 18% stance these are
0 / 0.075 / 0.150 / 0.300.

**Visible flight:** `run_flight_lift` (default **0.10 m**) raises the hips and both airborne feet together during each airborne interval, with zero
height, slope and curvature at toe-off and landing, so leg shapes, reach limits and contacts are unchanged. It scales in with speed and fades as
stance approaches 50%. With the 0.12 m `run_pelvis_bob`, the hips swing about 21 cm between the loaded low point and the flight apex. Running loads
early, at one quarter of stance, then extends into toe-off: at 7 m/s the support knee goes from about **46 degrees** flexion to **25 degrees**, with
the pelvis already moving upward at **1.19 m/s**. The run's
Flight pose now follows the new side-view reference: **15-degree forward trunk lean**, a lead thigh angled forward below horizontal with a bent knee,
a long trailing leg, and opposing arms with **50-degree** swing and **90-degree** elbow bend. Heel recovery is **0.30 m** at **28%** of swing;
the lead-knee drive point is **0.26 m** and keeps the foot near the hips rather than lifted high above them.
The landing clearance margin fades out at touchdown, so the foot settles onto the belt instead of hopping and then stamping down. The path keeps
the planted-foot path and endpoint derivatives; the rise is visual, not ballistic physics. Treadmill kinematics remain grounded so planned flight does
not activate the unrelated airborne fallback pose.

**Reach during running:** only planted feet determine constant hip lowering, including the toe-off endpoint. An overextended airborne foot recovers
toward its hip within the leg's reachable radius, using a C2-rounded limit instead of pulling the entire cycle into a crouch. A support margin keeps
this correction away from the contact handovers. Ground clearance remains enforced even with extreme edited settings. Walking keeps its former reach
behavior. Editing heel recovery therefore no longer changes the running support/posture trajectory.

**Running**, bank 11, holds the mode, speed, knee drive, step length, contact time, heel recovery, recovery timing/offset, stride placement, hip
excursion, flight lift, arms/elbows and lean. These have independent `run_` parameters; walking banks still edit walking values. Rig proportions, requested hip height,
knee limit, foot roll, effect switches, arm phase and the remaining torso/pelvis controls are shared.
**P** edits the active profile; a mode switch cancels an in-progress drag against its original profile. Both profiles save in ordinary presets.

Measured at 7 m/s: at Flight the hips are **19 cm** above Contact, the trailing sole is **23 cm** and the leading sole **35 cm** off the belt;
the trailing and leading knee flexions are **13 / 91 degrees**. At Passing the recovering foot is 14 cm behind the hips. These landmarks retain
the photo's forward-leaning trunk, raised/bent lead leg and extended rear leg, though the illustration's stride and exact limb angles remain an
approximate fit. Peak recovery-knee flexion is about **129 / 123 / 116 / 118 degrees** at 2.5 / 4.5 / 7 / 8 m/s; at 7 m/s the support knee ranges
about **25-46 degrees**, including toe-off. Reach safety lowers the requested hip path by **16 mm** through 7 m/s and **43 mm** at the
8 m/s sample. Slower runs share the 18% contact fraction, which can be raised on the Running bank. The step remains capped at **2.4 m**:
the Playground's 12 m/s sprint uses the same profile at a faster cadence, rather than a new sprint technique. The gait clock follows actual speed
up to 15 m/s instead of stopping at the former 8 m/s limit. This remains a procedural heel-strike prototype, not a validated production gait.

The running swing takes its toe-off and landing velocity and acceleration from one-sided differences of the planted foot over a 0.0002-cycle step.
Those samples are taken in double precision: rounding them to single-precision `Vector3`s produced handoff-acceleration errors of up to about 30%,
which at a 22% stance dipped the toe a few micrometres into the belt and kinked the motion. The walk keeps its original single-precision path, bit for bit.

### Proportions and the drag-and-drop editor
`animation/rig_params.gd` has 19 visual-only parameters (overall size, thigh, shin, ankle height, foot length, hip offset, lower torso, chest, neck, head, shoulder
offset, torso width and depth, upper arm, forearm, four limb thicknesses). `Visual.apply_rig` re-proportions the skeleton and rebuilds the meshes live; the gait
model plans for the real leg lengths, so a different body still does not slip on the belt (tested on random bodies). A **null rig is the original rig** (what the sandbox
character is built from); the parameter *defaults* are the tuned proportions.

Switch `edit_rig` on (E, or the View & Playback bank) and every joint and limb gets a handle: orange = a bone's length (drag the joint along the bone), also foot
length and ankle height; purple = a joint's offset from the centre line and torso width (front, back, 3/4 views); green = limb thickness (drag the edge), head size and torso depth.
The gait freezes while editing. Sub-step drags accumulate, dragging past a limit comes straight back, and the same parameters are on the controller (banks
Proportions 1 and 2), in presets, and in the HUD.

### Editing the ankle path
Press **P** (or `edit_path` in the **Ankle Path** bank). The drawn loop follows the ankle joint, not the toe or Achilles surface.
This is a constrained path editor, not an unrestricted spline: the planted foot must still move at belt speed and touch the ground.
The following IDs describe walking; in Run the first four path parameters resolve to their `run_` counterparts and the swing handle is **Heel recovery**.
The **Ankle Path** MIDI bank retains its walking bindings; use **Running** for running cycle adjustments.

- **Landing / Push-off:** drag horizontally to move either end while keeping the other approximately fixed (within the parameter step).
  These adjust `step_length` and `midstance_at`; vertical contact placement still comes from the foot roll.
- **Swing arc:** drag up/down for `step_height`, forward/back for `swing_forward`. The handle is at `swing_peak` within the airborne part;
  that timing remains adjustable on the controller. The endpoint positions, velocities and accelerations are unchanged by the horizontal shaping.
- **Requested hip height:** drag up to allow more extension, down for more knee bend (`stand_height`). The handle shows the requested base height;
  the model can lower the actual pelvis to keep both legs reachable. Adjust `pelvis_bob` in the same bank to change the rise over the planted leg.

Entering freezes the cycle; **Space** previews live, **comma/period** step frames, **P** exits and restores prior playback.
**Escape** cancels the current drag, **Backspace** resets the five path/hip parameters, **F5** saves them through the ordinary preset system.
P and E are mutually exclusive. Either side view works with orthographic or perspective projection; other views and zero speed display guidance instead of handles.
The HUD shows knee flexion (0 deg = straight) so extension can be compared at different frames. Saved user presets remain untouched; loading an old preset
can restore its former low hip height.

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

Gait/proportion changes regenerate the loop without resetting the phase: 128 intervals for walking, 192 for running, plus the closing key.
Speed-only changes refresh just the two samples surrounding the current phase at the exact current speed; arbitrary scrubs refresh their pair too.
Other keys remain cached until needed. This avoids full-loop rebakes on every small velocity change during a turn, without rounding speed or resetting the clock.
The more articulated paths stay within the existing 1 mm ankle-position tolerance even with the corrective additive layer disabled. The additive layer retains
the analytic foot pose and existing springs; turning it off reveals the clip's sampling approximation. Editor-keyed
changes to `walk`, `legacy` or `body` are overwritten by generation/live updates, so tweak the gait settings or graph
instead. The shipped preview clip can be scrubbed directly in AnimationPlayer without running the lab.
Regenerate the reusable scene with `--script res://tools/make_walk_scene.gd` only deliberately: this rewrites the preview
and saved node properties, not presets or MIDI mappings.

The sandbox retains its **original visual proportions and collision dimensions**, but now keeps the running profile selected.
Its speed comes from actual movement, not the treadmill's speed settings. Existing sandbox Walk Cycle and Walk Upper Body bindings are retained;
running values are available through the tuning registry/binding editor's **Run (visual)** target. Turning `gait_model` off restores the fallback;
airborne/crouched/landing poses still hand over to it automatically. Terrain IK and a separate turning gait remain absent.
Older presets that have no `graph` target leave the current graph settings unchanged; newly saved presets include them.

| File | Meaning | Regenerate |
|---|---|---|
| `config/midi_mapping.json` | verified physical mapping of the SMC-Mixer (59/59) | never by hand; use the MIDI monitor's learn |
| `config/tuning_bindings.json` | sandbox movement/body banks plus Walk Cycle, Walk Upper Body and Animation Graph | `make_tuning_files.gd` (`--add-missing-banks` appends new banks without touching edits) |
| `config/gait_bindings.json` | original seven treadmill banks plus Animation Graph, Posture & Roll and Ankle Path | `make_gait_files.gd --add-missing-banks` (append only); `--force` overwrites |
| `presets/*.json`, `presets_gait/*.json` | named parameter sets | `make_tuning_files.gd`, `make_gait_files.gd --force --presets-only` updates shipped examples without overwriting bindings or user-named presets |
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
| Earlier AnimationTree baseline (before reference fit): steady frame / 96-sample regeneration | 0.32 ms / 7.2 ms; not a measurement of the current 128-sample reference clip |

**Circling regression:** `bench_gait_turning` measures the real scene presentation update plus movement-core stepping, after 60 warm-up frames,
over 360 measured frames per case at a simulated 60 Hz. These are headless CPU costs, not GPU frame times or full collision throughput.

| Movement at a 6 m/s target | p95 before | p95 after | Full loop rebakes before / after |
|---|---:|---:|---:|
| Straight | 1.318 ms | 0.936 ms | 0 / 0 |
| Steady circles | 32.495 ms | 2.644 ms | 192 / 0 |
| Varying/tight circles | 33.125 ms | 2.891 ms | 360 / 0 |

Sprint circles now follow the actual 12.21 m/s velocity, with **2.573 ms p95** and **zero full rebakes**.
The old sprint timing was artificially cheap because its animation clock was capped at 8 m/s. Exact-speed sample refresh tests cover continuous turns,
speed jumps, loop boundaries, frozen scrubs and both body-blend extremes; running skeleton sweeps through 12 m/s stay below **0.9 mm** ankle error.
Physics baselines were intentionally remeasured for 6 / 12 m/s: at 120 Hz, 95% of normal speed in 0.133 s, 11.625 m travelled in 2 s,
and stopping in 0.158 s over 0.358 m. Jump height/timing and the existing 60/120-Hz tolerance limits are unchanged.

## 7. Known limitations

- Both scenes use generated gaits through AnimationTree; the sandbox retains original proportions. While a landing
  compression is active the legs are handed back to the simple pose.
- Running is still a prototype, now used at both normal and sprint speeds in the Playground. Turning, stopping, stairs,
  slopes and step width are not modelled (hips and feet stay in their planes).
- The explicit-Euler movement core remains step-rate dependent between 60 and 120 Hz (at 6 m/s: stop distance 10.0 %, jump apex 3 %). Documented and guarded, not fixed.
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

Review the running treadmill and Playground at 6 / 12 m/s with the user; turn/stop gaits; foot IK on ramps and stairs; technique experiments behind flags; banks A and C; preset A/B
comparison and the starting presets; telemetry and input recording; guided playtests. Each stops for the user's eyes or hands where the brief says so.
