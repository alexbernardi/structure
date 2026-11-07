# 0004 - Movement Lab 2.0: procedural locomotion and body dynamics

Status: in progress - paused at a stopping point chosen by the user on 2026-11-07     Owner: agent + Alex (hardware owner, playtester)     Date: 2026-11-07
Branch: `task/0004-movement-lab-2` (from `task/0003-midi-movement-lab` at `9d384a1`)

## Goal
Upgrade `utility/movement/flat-plane/` (not a rebuild) toward spring-based body response, procedural gait, foot IK and
momentum experiments, all tunable live through the existing SMC-Mixer layers. Stage I stays grounded and human; the
architecture must leave room for augmented abilities later. Brief: Phases 0-9 (audit, springs, body inertia, gait, foot IK,
technique experiments, MIDI banks, presets and A/B, telemetry and tests, guided playtests).

## Open items carried over (read first)
- **Task 0003 Phase 4 hardware playtest ("checkpoint 6") was never confirmed by the user.** Live tuning is implemented and
  covered by 225 automated tests including events through the real learned mapping, but fader/knob/button behaviour on the
  actual hardware and the F4 editor are **unverified**. Nothing in this task treats them as verified.
- Two earlier visual items (jolt fix, arm direction) were reported "great start" by the user, not formally signed off.

## Impact
- Code: `utility/movement/flat-plane/` only (+ `TOOLS/cli` unchanged). No sandbox, room, protocol or schema change.
- New this phase: `--no-animation` switch, baseline metrics/benchmarks/tools, three guard test files.
- Layering rules for all new work: the physical controller (`movement/`, `character_body.gd`) must keep working with
  presentation off and must never read presentation state; new presentation lives in new modules fed by a small state dict.

## Phase 0 findings (details: [MOVEMENT-LAB-AUDIT.md](../DOCUMENTATION/MOVEMENT-LAB-AUDIT.md))
1. Godot 4.7.2 has `SkeletonModifier3D`, `TwoBoneIK3D`, `LookAtModifier3D`, `LimitAngularVelocityModifier3D`, AnimationTree etc.
2. The humanoid is a genuine `Skeleton3D` (15 bones) with rigid, unskinned primitive segments on `BoneAttachment3D`; bone
   changes reach the screen in the same frame (pelvis 1.01 -> 0.5 m moved the head exactly 0.510 m).
3. Physics is **bit-identical** with animation on, off, or with the visual deleted (scripted 3.5 s run, 420 ticks).
4. 21 movement parameters; 3 MIDI banks; baseline behaviour and cost recorded; all guarded by tests.
5. New limitation found: explicit-Euler core gives 3-11 % tick-rate dependence (jump apex, stop distance) between 60 and 120 Hz.

## Plan
| Phase | Deliverable | Verification | Owner of acceptance |
|---|---|---|---|
| 0 | Audit, baselines, guards, this plan | done: 235 tests | agent |
| 1 | `animation/springs.gd`: analytic scalar / Vector3 / angular springs, target velocity, amplitude, limits, reset and teleport | regime, RK4-reference, dt-consistency, stability-sweep tests; **spring diagnostic scene** | **user checkpoint** |
| 2 | (built, awaiting checkpoint) Body inertia: torso, pelvis, head/shoulders, arm swing as springs driven by simulated velocity, acceleration, angular velocity; each effect switchable; joint limits | tests on pose response; run/stop/turn/reverse with MIDI | **user checkpoint** |
| 3 | (first slice built: treadmill gait lab, awaiting checkpoint) Procedural gait (stride, cadence, width, height, stance/swing, speed-driven) | state-transition tests; all directions without pose pops | **user checkpoint** |
| 4 | Foot placement + IK (rays, planting, slope alignment, knee limits, pelvis height) using `TwoBoneIK3D` if the rig allows, else a small custom solver | reachability, plant-release, stair/ramp tests; ramp and stairs already in the sandbox | **user checkpoint** |
| 5 | Technique experiments behind feature flags (momentum, air strafing, braking asymmetry, slope speed, optional hop/slide) | each flag: off = baseline unchanged (guard tests), on = measured delta from recorded inputs | user playtest |
| 6 | MIDI banks A/B/C as specified; keep existing banks; soft takeover; nonlinear curves | extreme/invalid MIDI tests; synthetic events through the learned mapping | **hardware checkpoint** |
| 7 | Presets and A/B comparison (+ physics-vs-visual tags, export diffs) | serialization tests | user |
| 8 | Visualisation, recording/replay with documented tolerances, 60/120 Hz tests, benchmarks | tests + cost report | agent |
| 9 | Guided playtests A-E after each milestone | recorded in this note | user |

Rules kept throughout: separate branch and recoverable commits; presentation never feeds physics; every new effect has an
off switch and unit-labelled, clamped parameters; no claim of visual/physical/hardware acceptance without the user.

## Validation (running log)
- Phase 0, 2026-11-07: `structure.py test utility` 235/235; baselines in the audit doc; benchmarks recorded.
- Phase 1, 2026-11-07: **282/282** (47 new: 36 spring tests, 11 diagnostic tests). Automated results only - the visual
  checkpoint below is NOT yet confirmed by the user.
  - Exactness: matches a 0.2 ms RK4 reference to ~1e-6 in 8 regimes x 3 frequencies with a moving goal; steps compose
    exactly (M(d1+d2) = M(d2)M(d1), 400 random cases, 1e-9); results identical from 15 Hz to 1 kHz (1e-9).
  - Regimes: underdamped overshoot equals exp(-pi z / sqrt(1-z^2)) within 2e-4 and first-peak time within 2 ms for
    z = 0.05..0.9; successive-peak ratio equals exp(-2 pi z / sqrt(1-z^2)); critical and overdamped never overshoot and
    never cross; critical settles faster than any overdamped; undamped conserves energy to 1e-9 over 100 s and keeps its
    frequency (150 cycles / 100 s at 1.5 Hz).
  - Stability: 7 frequencies (0-1000 Hz) x 11 damping ratios (0-1000) x 8 timesteps (1 ms - 1 s) x 200 steps: all
    finite, energy never grew; 40 random moving/jumping-target runs bounded; dt = 0, negative, NaN, huge, NaN/INF/1e9
    parameters all handled; NaN targets are rejected and a corrupted state snaps back.
  - A naive semi-implicit Euler spring (kept only for comparison) is rate-dependent (240 vs 60 Hz differ) and explodes at
    12 Hz / 30 fps, where the analytic spring stays bounded.
  - Vector and rotation springs are single precision (Godot's Vector3/Quaternion): ~1e-6 per step, ~1e-5 accumulated over
    hundreds of steps, bounded. Scalar uses doubles. Documented in `animation/springs.gd`.
  - Cost: Scalar 1.45 us, Vector 1.95 us, Rotation 4.19 us per step (cached coefficients); 2.9 us when dt changes every call.
- Debugging notes worth keeping: (a) a probe that ran from `SceneTree._initialize` fought the scene's own `_process`
  because `_ready` had not run yet - wait one frame before disabling a scene's processing (fixed in all scene tests);
  (b) the first physics-identity test failed for the same reason (body stepped twice per tick), not because of animation;
  (c) `Quaternion.angle_to` loses ~1e-4 rad near zero (acos) - measure rotation error via the rotation vector;
  (d) GDScript has no `%e` format; (e) `rotation` clashes with `Control.rotation`.
- Phase 2, 2026-11-07: **338/338** (56 new). Automated results only - the Phase 2 checkpoint below is NOT yet confirmed.
  - Model (nimation/body_dynamics.gd, parameters nimation/body_params.gd, generic set nimation/param_set.gd): torso pitch/yaw/roll,
    pelvis weight shift, gait bob/sway, landing compression with rebound, facing lag, head stabilisation and arm
    follow-through, all springs from Phase 1; hard joint limits; 10 switches (master + 9 effects) each tested on and off.
  - ~40 `body.*` parameters, every one tagged `affects: visual` and shown in the HUD detail line; none is read by the simulation.
  - Guard: physics trajectories (position, velocity, grounded over a run/turn/jump/stop script) are bit-identical with the
    model on, with it switched off, and with animation disabled.
  - Scene wiring: the model gets the mean physics acceleration since the last frame, so the result does not depend on how many
    ticks fell in a frame. Landing compression is done through the knees (feet stay planted, tested). B toggles the model.
  - MIDI: banks Body Springs / Body Effects / Body Detail appended to the shipped bindings with `tools/make_tuning_files.gd --add-missing-banks`;
    every body parameter is reachable; synthetic events through the learned mapping change the values live; presets save/restore both targets.
  - Cost: `BodyDynamics.update` 68 us (all effects), 3 us with the master off; `scene._process` 91 us on vs 20 us off (about 1 % of a 144 Hz frame).
  - Existing presets only list movement parameters, so loading one leaves the body parameters alone; presets that cover both come in Phase 7.
- Gait lab (treadmill), 2026-11-07: **389/389** (51 new). Automated results only - the checkpoint below is NOT yet confirmed.
  - Model (`animation/gait_model.gd`, parameters `animation/gait_params.gd`): a phase-driven planner of where each ANKLE goes, then analytic
    sagittal two-bone IK for the real bone lengths. Stance: the foot rolls heel -> flat -> toe and is fixed to the ground, so in the hips'
    frame it moves back at exactly the walking speed. Swing: a Hermite path from toe-off to the next heel strike that leaves and lands
    moving like the stance foot, plus a clearance bump and a floor under the sole. A reach assist lowers the hips (smooth minimum) just
    enough that a planted foot is never pulled off the ground; the amount is reported (about 0-5 mm at the default 1.2 m/s).
  - 43 `gait.*` parameters with units and ranges, 14 switches (master, auto step length, foot roll, 9 effects, freeze) plus view switches.
    Defaults chosen by measurement (cadence 113 steps/min at 1.2 m/s, hip excursion 4 cm, knee flexion 14 degrees at midstance), not by taste.
  - Verified: planted point fixed to the ground and exactly on it at 40 random settings (worst gap below 1e-6 m); no sole point under the ground at 60
    random settings x 200 phases; swing path has no jump at toe-off/heel strike at any setting and matches the stance foot's velocity; the legs
    reproduce every planned ankle to 1e-5 m; double support = 2 x stance - 1; left/right half a cycle apart; each switch zeroes exactly its effect;
    NaN/inf inputs and 150 random settings give finite poses; no joint moves faster during a speed sweep than in steady walking at the top speed.
  - Through the real skeleton: posed ankles within 0.2 mm of the plan; feet stand on the ground within 0.5 mm; the legs stay in the forward plane
    whatever the pelvis does; the gait pose fades out in the air or when crouching; with no gait pose the visual is unchanged.
  - Scene (`scenes/gait_treadmill.tscn`): side orthographic camera, belt at the walking speed, planted-foot slip measured on the posed skeleton
    (below 3 mm/s at 0.8/1.2/1.8 m/s; the measurement is shown to detect a deliberate mismatch). MIDI banks Walk Cycle / Pelvis & Torso / Feet & Arms /
    Toggles / View & Playback in `config/gait_bindings.json`; every parameter reachable; presets in `presets_gait/` (default, stroll, brisk, stiff_robot, shuffle:
    starting points, not claims of realism).
  - Not done in this slice: the walk is not wired into the flat-plane sandbox yet (the sandbox still uses its original gait); landing compression
    is not combined with the gait pose (a landing hands the legs back to the simple pose); step width and running are out of scope for now.

## Phase 1 checkpoint (needs the user)
Spring diagnostic: `godot --path utility/movement/flat-plane res://scenes/spring_diagnostic.tscn`
(plots target, response, velocity, measured vs theoretical overshoot; three-regime overlay; naive-Euler comparison; rotation
dial). **Verify:** underdamped rings and overshoots, critical settles fastest without overshoot, overdamped is slower;
the readout's measured overshoot matches the theory line; at 12 Hz / 30 Hz tick the red naive spring explodes while the
cyan one does not; the dial's actual arrow always takes the short way round.
Status: **CONFIRMED by the user on 2026-11-07** ("All of it looked right" - all four checks).

## Phase 2 checkpoint (needs the user)
Run the sandbox: `godot --path utility/movement/flat-plane`. **Verify by eye:** the torso leans
forward as you accelerate and back as you brake; sharp turns roll it toward the inside; reversing makes the body swing round
through its spring rather than snapping; a hard landing compresses the knees and rebounds; the head stays steadier than the
torso; B switches between the spring body and the old pose. **Verify with the controller:** on banks 4-6 (Body Springs, Body Effects,
Body Detail) the faders and knobs change the motion immediately, and the Body Effects faders turn each effect off on its own.
Status: user reply on 2026-11-07: "okay all of these variables are good" - taken as approval of the body variables and banks. It was not a
check-by-check confirmation of every behaviour above, so those stay recorded as reported, not individually verified. The user then asked
to focus on the look of the **walk** from the side, on a treadmill, with its own bank of variables and toggles (running comes later):
see the gait lab below.

## Gait lab checkpoint (needs the user)
Run: `godot --path utility/movement/flat-plane res://scenes/gait_treadmill.tscn` (first run opens on the left half of the screen).
**Look at:** the side view while the belt runs at 1.2 m/s; then Space to freeze and `,` / `.` to step through the cycle (or the *cycle position* fader);
the white loop is the planned ankle path, the green ring is the planted contact point that must slide back with the belt, the bars at the
bottom show stance and swing. **Compare with the toggles bank:** each `fx_*` switch removes one effect, `foot_roll` off gives a flat-footed
walk, `gait_model` off shows the original walk. Keys 1-5 change the camera, wheel zooms, T toggles the belt, B the body dynamics.
**Judge:** does the foot placement, heel-to-toe roll, knee bend, hip bob/sway/rotation and arm swing read as a human walk, and which
variables are missing? Status: the user's first reply asked for a smoother hip motion and for editable proportions (next section); a later reply called it
"a good stopping point". Neither reply individually confirmed the walk's look, so that stays **not confirmed**; the saved defaults below are the user's own tuning.

## Gait lab revision after the first look (user feedback, 2026-11-07)
User: "i have some good settings on default, we will start from there on out building out the different modes. first off tho. the model is
like bouncing jarringly. where when I want a reference video its a smooth sine wave up and down. The movement is alittle clanky right now.
also can you make it so ... change in limb size and position. a setting that then lets me drag and drop".
- Their live tweaks were not saved (the state file shows bank 1 and preset "default"), so the shipped defaults are the baseline; saving a
  preset (Up button / F5) keeps a tuned set.
- Measured before changing anything (hip height against a best-fit sine at twice the stride frequency): residual 8-10 % of the amplitude at an easy
  walk and 15-24 % at 1.6-2.0 m/s. The loading-response dip (default 10 mm) and the reactive reach assist were the causes. Joint accelerations
  also spiked at heel strike (5-16x the median) because swing and stance were handed over with velocity only.
- Changes: loading dip default 0 (still on the Pelvis & Torso bank); hip path is a pure sinusoid and, when the stride needs it, the whole sine is
  lowered by a constant amount computed per setting (no reactive kink); the knee never locks (new "Knee never straighter than", default 12 deg);
  rolls use quintic easing and the swing is a quintic Hermite that matches the stance foot's velocity AND acceleration; the clearance bump is
  cubic-flat at both ends. Now: hip path within 1.3 % of a sine (0.6-2.0 m/s), ankle acceleration continuous across toe-off/heel strike.
  Hips are 20 mm lower at the default 1.2 m/s than before, and the foot-flat slap after heel strike remains (tunable: *Foot flat at*).
- Proportions: ``animation/rig_params.gd`` (19 parameters: scale, bone lengths, ankle height, foot length, hip and shoulder offsets, torso
  width/depth, neck, head, limb thickness), all visual-only; defaults reproduce the original rig exactly (tested bone by bone and mesh by mesh).
  ``Visual.apply_rig`` re-proportions live; the gait model plans for the actual leg lengths (planted-foot slip stays under 3 mm/s with a
  different body). Controller banks "Proportions 1" and "Proportions 2"; presets save them; the default preset restores them.
- Drag and drop: switch ``edit_rig`` on (key E, or View & Playback bank, strip 5 knob) and every joint and limb gets a handle. Orange = bone length
  (drag the joint along the bone; also foot length and ankle height), purple = joint offset / torso width (front, back, 3/4 views), green =
  thickness (drag the limb's edge; also head size and torso depth). The walk freezes while editing and resumes afterwards; Backspace resets the
  proportions; Ctrl+wheel resizes the whole character (also the *Overall size* fader).
- Validation: **410/410** (21 new). Hip sine fit, knee limit, acceleration continuity, rig bone-by-bone, mesh-by-mesh defaults, random bodies
  (posed ankles within 0.3 mm of the plan, soles on the ground), drag maths incl. clamping and sub-step drags, view-dependent handles, freeze/resume.
  Cost: ``cycle_for`` 1.2 ms on a cache miss (only while a setting or the speed changes), 52 us per steady frame, ``apply_rig`` 1.3 ms.
- Not verified by me: that the walk now *looks* smooth to a human eye, and how the drag handles feel with a real mouse. That is the checkpoint.
- Correction, same day: "defaults reproduce the original rig exactly" above held until the defaults were saved (next section). The original rig is now
  ``RigParams.ORIGINAL`` and is what a null rig means; the tests compare the original values and the sandbox visual bone by bone.

## Defaults saved from the user's live tuning (user request, 2026-11-07)
User: "save all the values now for default that it currently is set at. still going to tweak this later. but save it. document what we've done inside of
the movement workshop". The live values existed only in the running window, so the user pressed the controller's Up button (save preset); that produced
``presets_gait/tuned_20261107_060205.json`` (kept untouched as the record). Its gait and proportion values are now the parameter defaults in
``animation/gait_params.gd`` and ``animation/rig_params.gd`` (body parameters were unchanged), and ``presets_gait/default.json`` is regenerated from them
(verified equal to the saved preset, gait and rig). The values before the session are kept as ``presets_gait/first_defaults.json``.
- Gait: walk 1.55 m/s, step 0.61 m, hip height 0.90, velocity match 0.7, foot clearance 0.065 m, peak 0.53, knee limit 13 deg, heel strike 15 deg, toe-off 31 deg,
  heel rise 0.71, bob 32 mm, loading dip 2 mm, sway 18 mm, pelvis rotation 4.5 deg, shoulder counter 7.5 deg, torso lean 14 deg, arm swing 27 deg, elbow bend 57 deg,
  arm timing +9 deg, zoom 0.8. Proportions: size 0.91, thigh 0.495, shin 0.48, ankle 0.075, foot 0.255, torso 0.30, chest 0.255, neck 0.035, head 0.1225, shoulder
  0.215, upper arm 0.295, torso width 0.96 and depth 1.1, shin and forearm thickness 0.0575 and 0.0425.
- Measured on these values (``tools/gait_smoothness.gd``): hips within 2.7 % of a pure sine; the knee's acceleration at heel strike is 14.7x its median at
  1.2 m/s because velocity match 0.7 deliberately breaks the smooth hand-over (5.0x at 1.0). Recorded as KI-016; the user's value is kept.
- Tests were made independent of the default values (they read them from the definitions), and the rig step for limb thickness became 0.5 mm so the
  original radii are representable. **412/412** utility tests.
- Bug found and fixed while doing this: the lab never registered the tuning input actions, so F3/F4/F5/PgUp/PgDn/[ ]/Home did nothing there (only the
  controller buttons worked). ``Actions.register()`` is now called and tested.
- Documentation: new [MOVEMENT-LAB-2.md](../DOCUMENTATION/MOVEMENT-LAB-2.md) (status, launch, architecture, design, limits, lessons) and the generated
  [MOVEMENT-LAB-PARAMETERS.md](../DOCUMENTATION/MOVEMENT-LAB-PARAMETERS.md); KI-013..017, performance numbers, START-HERE and the task index updated.

## Animation graph follow-up (implemented; interactive acceptance pending)

User approved generated walk clips plus a real, editor-visible AnimationPlayer/AnimationTree in **both** treadmill and
third-person sandbox. Preserve captured defaults and MIDI mapping. Plan: serialize a reusable primitive visual scene and
blend tree; generate gait clips from the existing planner; layer the existing procedural fallback and body dynamics through
the tree without competing bone writers; expose graph values to the registry/presets/MIDI; test poses, regeneration,
playback, persistence and physics separation. Terrain IK and a distinct running gait remain out of scope.

Acceptance: open the reusable visual scene in Godot and edit the graph; live gait/proportion edits regenerate the walk;
both scenes animate through the tree; saved user values remain unchanged; relevant automated tests pass. Human animation
and controller acceptance must still be requested after automated verification.

Implemented an editor-visible reusable primitive rig with AnimationPlayer, generated `walk`/`RESET` clips, live
`legacy`/`body` clips and the shared blend tree. The visual now calculates pose dictionaries; the tree is the sole
per-frame bone writer in both scenes. Each character owns its animation library. Original sandbox proportions/collider
and all saved preset/MIDI data are preserved; gait and graph targets join its registry. Appended two walk banks and
Animation Graph to the sandbox; only Animation Graph to the treadmill. Existing banks are not reassigned.

Graph controls: WalkBlend, BodyAdd and WalkSpeed, synchronized bidirectionally with MIDI/registry/presets. Live rig/gait
changes regenerate the clip without phase reset. Fixed the coupled treadmill double-time-scale bug; belt, planner and
tree now share one clock. Additive poses use the current rig's RESET origin, including after resizing. Synthetic-port
scene tests disable OS rescan to avoid replacing their injected test ports during long runs.

Validation: **420/420 utility tests in 28 files**; headless editor import succeeded, and `structure.py check` reports
**0 errors / 0 warnings**. Tests include graph output, raw generated ankle placement within 1 mm on
73 sampled default phases, clip isolation, rig regeneration, native playback clock, preset round-trip and bit-identical
physics with/without animation. Vulkan GUI renders of both scenes completed without engine errors and were inspected
for visible humanoid/ground placement (not a smoothness or hardware verdict). Measured steady treadmill frame **0.32 ms**;
96-sample clip regeneration **7.2 ms**. 64 samples failed the 1 mm accuracy criterion (1.214 mm); 96 passes while costing
less than the original 128-sample 9.25 ms bake. Re-generation is synchronous during speed/settings changes.

Known limits: distinct running/turning gaits and terrain IK remain absent; the sandbox reads real movement speed and
keeps its original rig, whereas the treadmill keeps the user's tuned rig. Generated/live clips are not durable hand-keyed
assets; edit planner values or the graph. Remote graph edits persist via F5; old presets without a graph target retain it.
Follow-up: user verifies the graph blends/playback in both scenes and the new MIDI bank, then reports any jolts/pose issues.

## Outcome
Paused by the user at a good stopping point on 2026-11-07, mid-task. Done: phase 0 (audit, baselines, guards), phase 1 (analytic springs, user-confirmed),
phase 2 (procedural body inertia, user approved the variables), and a treadmill gait lab with a procedural walk, live-editable proportions, a drag-and-drop
handle editor, 7 MIDI banks, and the user's own tuning saved as the defaults (412 automated tests). Not done: phases 3-9 proper (the gait is not in the
sandbox yet, foot IK on terrain, technique flags, banks A/C, preset A/B, telemetry and recording, guided playtests) and the 0003 phase 4 hardware checkpoint.
The subsequent graph follow-up above integrates walking into the sandbox and exposes AnimationTree editing in both scenes;
it does not complete the remaining gait/terrain phases. Not individually human-confirmed: how the new graph-driven walk
looks and how the handles feel. Next steps and limits:
[MOVEMENT-LAB-2.md](../DOCUMENTATION/MOVEMENT-LAB-2.md) sections 7 and 9. To resume: read that page, then the open items at the top of this note.
