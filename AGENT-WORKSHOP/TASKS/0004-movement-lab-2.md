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

## Posture, foot roll and upper-body bones (user feedback, 2026-11-07)
User, with a reference walk-cycle image (skeleton overlay: yellow spine, cyan neck/head, magenta shoulder and hip lines, teal pelvis): add the upper torso and
head "bones" and match the reference; review the primitive shapes; the cycle feels robotic because "when the heel hits the ground the toe is pointing too far
up and only a moment after ... does the toe start animating"; at the widest stride the leg triangle should be "more underneath the torso not to the front";
"lets straighten their spine for default".
- Foot timing: the heel and toe rockers now start/end moving (`roll_flow`, default 1; 0 = the old hold-then-roll). The swing hands over the foot's rotation and
  acceleration whole; `velocity_match` (KI-016, kept at 0.7) now scales only the ankle's speed. `heel_rise_at` 0.71 -> 0.55 (the old value crammed the
  31 deg push-off into the last 0.1 cycle, so the rear heel was only 7 deg up at the other foot's heel strike; now ~15 deg). Smoothness at 1.6 m/s: worst
  foot acceleration 268 vs 656, knee 472 vs 850 against the old timing.
- Stride placement: new `midstance_at` (default 0.40 of stance; was effectively 0.5). At heel strike the ankles are 0.27 m ahead / 0.31 m behind the hip
  at 1.4 m/s (was well in front).
- Spine: `torso_lean` now tilts the straight trunk at the waist (default 14 -> 4 deg); new `spine_curve` (default 0) is the hunch; new `head_level` (default 1)
  keeps the face level. The hunch came from the 14 deg lean being split onto the chest with the head following it.
- Bones: drawn by the overlay with `view_joints` from the existing 15 skeleton bones (no bones added, so the sandbox, clips and tests keep their skeleton).
- Shapes: one `mesh_specs` table for build and rig changes; egg pelvis, squashed-capsule spine and chest, egg head with a nose, hands. The rig editor's
  chest/head handles read the same geometry. The sandbox character gets the shapes too.
- New bank "Posture & Roll" appended to `config/gait_bindings.json`; generated presets refreshed (`first_defaults` maps the old look onto the new
  parameters); the user's `tuned_20261107_060205.json` is untouched and still carries torso lean 14, which now means a 14 deg straight lean.
- Validation: **422/422** utility tests (new: toe drops at heel strike, ankle under the hip at `midstance_at`, foot keeps turning at toe-off); `check` passes;
  side-view renders inspected at 0, 0.04, 0.08, 0.125, 0.25 and 0.375 of the cycle against the reference's contact/down/passing/up frames, plus the foot
  pitch over the whole cycle (toe peaks +15 deg at contact and is already at +7 deg by 0.04; no hold). Not verified: how it looks in motion to the user.
- Noted, not changed: the user's `stand_height` 0.9 keeps both knees ~40 deg bent at heel strike and at midstance (the reference's legs are nearly straight);
  the user's `elbow_bend` 57 deg holds the forearms forward at passing where the reference's arms hang.

## Knee extension and direct ankle-path editing (2026-11-07)
User: the knees stay too rigid/bent, and editing the Achilles/ankle's drawn path may be the key.
- Plan: keep analytic leg IK and planted-foot constraints. Raise default `stand_height` from 0.90 to 0.95 and `pelvis_bob` from 0.032 to 0.040.
  Baseline on the tuned rig at 1.55 m/s: stance knee 39.3-48.1 deg, swing maximum 70.4 deg. Updated: stance 17.3-36.7 deg, swing maximum 60.6 deg.
  A 0.94 height was also measured but exceeded the existing 3% hip-sine residual threshold on the original rig at 1.6 m/s; 0.95 preserves that regression.
- Add P-toggle path editing: horizontal landing/push-off handles adjust stride extent and placement; a two-axis swing handle controls clearance and
  a smooth swing-only forward offset; a hip-height handle controls stance extension. Keep ground contact exact, use normal gait parameters/presets/MIDI,
  and preserve pause state when switching between path/proportion editing. No new dependencies or physics changes.
- Acceptance: visible knee extension below 20 deg and swing flexion above 55 deg at the default speed/rig; dragging changes the displayed path,
  with no changes to planted travel or continuity at lift-off/landing; mirrored/perspective side views work; limits/cancel/pause and preset round-trips tested.
- Validation: full utility suite **430/430** passed; after adding viewport-routing and edited-path skeleton-slip regressions, the final focused gait run
  passed **69/69**. `structure.py check`: 0 errors/warnings; `git diff --check` passes. Mirrored and perspective drags, clamping, cancellation, pause restoration,
  MIDI access, preset round-trips, contact continuity and planted-slip constraints are covered.
- Rendered the editor at the swing handle: knee flexion 60/18 deg, all four handles visible. Reopened the native treadmill with the updated `default`
  preset, MIDI enabled and no unused remote-debugger connection; verified a responsive side-view window, hip height 0.95 and roughly 1 mm/s measured slip.
  The new bank is appended without overwriting existing bindings. User-saved tuning and editor re-saves remain untouched. Subjective motion/editor feel
  still awaits the user's feedback.

## Reference-led walk and camera defaults (2026-11-07)
- Request: face right-to-left like the supplied contact/down/passing/up strip, match its skeleton proportions, build the airborne path from those
  landmarks, make the front view discoverable, and default to perspective. This remains a visual walking prototype, not validation of run/turn/terrain modes.
- Plan: record approximate image-space landmarks (not motion capture); fit a constrained, derivative-matched swing through Passing and Up; move hip-rise
  timing towards Up and match the arm poses/proportions. Retain the former procedural model through a `reference_fit` blend for comparison.
- Camera/UI: default to the opposite side and perspective, add visible front/side and pose-checkpoint buttons, preserve P editing in perspective.
- Acceptance: reference swing knots are actually interpolated; planted travel and endpoints remain valid; body ratios and key-pose angles are measured;
  forward projects left in the default view; front is reachable by button/key without changing projection; saved user presets and physics remain untouched.
- Validation planned: targeted and shared tests, rendered contact/down/passing/up and front views, updated docs/defaults, then reopen the lab.
- Implemented: annotated landmarks in `walk_reference.gd`; C2 swing through Passing/Up; fitted Down/Up hip timing; reference arm/elbow samples;
  near-equal thigh/shin lengths and approximately 0.71 hip-to-shoulder/leg ratio. Former procedural swing/hip/arms remain available with `reference_fit=0`.
  The new control occupies the unused View & Playback strip-4 fader. Default presets also restore graph blend and playback.
- Camera/UI: right-to-left `side-left` and perspective by default; visible Side, Front, Other side, 3/4, four reference poses, Play/Pause and Reference default.
  Camera interpolation is disabled for discrete preset jumps (avoids first-frame perspective projection errors); framing accounts for the HUD and resizing.
- Iteration: the first fitted middle segment scraped the toe between Passing and Up. Replaced that hard-floor contact with a smooth, bounded late-segment
  clearance correction that preserves the measured knots and their derivatives; tested >1 mm airborne clearance at 0.8/1.55/2.0 m/s and bounded zero-clearance edits.
  Default ankle velocity matching is now 1. The reference motion needed 128 clip samples rather than 96 to retain the existing <1 mm baked-ankle tolerance.
  Endpoint acceleration tests sample closer to the shorter segment boundaries with a stricter tolerance; contact, symmetry and speed-change guards remain intact.
- Measurements: original rig at 1.2 m/s has maximum joint motion 0.056 rad/120 Hz tick. At 1.6 m/s peak local foot/knee acceleration is 399/787
  rad/cycle-squared; this is a stronger reference pose, not lower acceleration everywhere. Passing/Up support and swing knee angles fit the annotated drawing within 10 degrees.
- Verified: **441/441 utility tests passed**, 30 files; static check 0 errors/0 warnings; `git diff --check` clean.
  Rendered Contact/Down/Passing/Up and front views. Exercised the actual native Reference default, Passing, Front, Side and Play buttons;
  verified unobscured perspective framing and a responsive, playing treadmill (PID 23048, detached `treadmill-reference-lab`).
  The former treadmill exited gracefully. User-named tuning preset and unrelated editor re-saves were not changed.
- Remaining acceptance: the drawing's projected lengths and foot ground rows are inconsistent with a literal fixed-length 3D trace.
  Contact/Down are less exact than Passing/Up; this is a reference-guided walking prototype, not a validated basis for all other movement modes.

## Treadmill running prototype (2026-11-07)
- User feedback: the reference walk is "really great"; the playground's default 4.5 m/s is faster than a walk. Requested running work on the treadmill.
- Scope: opt-in running in the existing visual gait planner, not a sped-up walk. Keep the approved walk/default and original movement physics unchanged.
  No automatic playground gait transitions, terrain foot IK or separate sprint technique in this slice.
- Plan: separate run tuning (4.5 m/s starting point), sub-half-cycle stance and genuine no-contact flight, heel recovery/knee drive, hip compression in support
  and rise in flight, bent-elbow arm swing/forward lean. Reuse planted-foot planning, smooth interpolation, IK and graph sampling.
  Add Walk/Run controls, mode-aware pose buttons and path editor, flight readout, appended MIDI bank and saved run preset.
- Acceptance: walk output remains unchanged when run mode is off; contact points travel at belt speed; both soles clear the belt during the flight interval;
  knee flexion clearly differs from walking; no endpoint discontinuities, ground penetration or invalid poses at representative run speeds.
  Actual skeleton, clip-only sampling, parameter changes, presets, MIDI, camera and editor must all agree.
- Validation: focused gait/run/scene/graph tests, then full utility regressions and static checks; rendered contact/compression/toe-off/flight and front views;
  reopen the native treadmill in running mode and verify it is responsive. Visual approval remains the user's next checkpoint.
- Implemented: independent `run_` cycle/upper-body values, 34% stance and 32% total flight at the 4.5 m/s default; recovery/knee-drive swing,
  support compression, flight rise and bent-elbow arms. Walk/Run, dynamic pose checkpoints, active-profile path edits/cancellation, flight diagram,
  Running bank 11 and a shipped `run` preset are wired. Existing banks and user-named presets are preserved.
- Iteration: the first early knee-drive knot caused overreach, excessive hip lowering and a grounded leading sole during nominal flight.
  Moving that knot later, lifting knee drive and moderating hip excursion fixed interior-flight clearance without loosening contact or IK constraints.
  The 128-sample clip missed the 1 mm ankle requirement at 6 m/s (1.058 mm); running now uses 192 samples, while walking remains at 128.
  The launch option is `--gait-mode=run`, not generic `--mode`, which collided with the repository harness's `--mode=test`.
- Measured at 2.5 / 4.5 / 6 m/s: peak recovery-knee flexion 143.3 / 153.2 / 164.3 degrees; support at 4.5 m/s spans 35.1-74.3 degrees.
  Default hip lowering is 0 / 71 / 153 mm. All planned ankles are reachable and no sole penetrates the belt.
  Actual skeleton tests with and without additive correction, over 200 scrub positions per speed, measured worst ankle error **0.395 mm**
  and minimum sampled interior-flight sole clearance **6.2 mm**. Planted slip stays below **3 mm/s**; running endpoint/internal-knot acceleration
  retains the existing walking tolerance. Tests also cover stationary running, exact walk preservation, MIDI/preset round trips and mode-switch drag cancellation.
- Verified: **456/456 utility tests passed**, 31 files, including all 93 gait-focused tests. Rendered Contact, Compression, Toe-off, Flight and Front.
  Repository static check: 0 errors/0 warnings; `git diff --check` clean.
  Gracefully closed the verified playground; reopened the persistent treadmill with `--gait-mode=run` (PID 1284, parent 23252, detached `treadmill-running-lab`).
  Exercised native Run default, Flight, Walk/Run, Front/Side and Play controls. Confirmed 1.55 vs 4.5 m/s, Running bank 11, connected MIDI HUD,
  perspective framing and advancing frames; left the run playing. This does not claim a new physical-controller playtest.
- Remaining: user visual tuning of the run (especially compression and high-speed reach), production walk/run transitions and terrain support.
  Physics, playground speed/collider/proportions and the user's saved tuning remain untouched. This is not a running-reference or sprint match.

### Running reference-map follow-up
- Mapped the supplied five-frame cycle to **Contact / Down / Passing / Flight**. The Flight checkpoint is placed late enough in the true airborne interval
  to match the image's folded lead knee and extended trailing leg; the pose buttons continue to follow edits to stance timing.
- Updated the run-only defaults to 30% stance per foot (40% total flight), 0.12 m recovery, 0.30 stance placement and 0.05 m hip excursion. The walking
  profile remains unchanged. Added a C2-zero sole-clearance correction to the late landing segment and denser run-only endpoint derivatives so the landing
  stays airborne until the reference's flight pose and hands over cleanly to contact.
- Validation: **457/457 utility tests passed** across 31 files; focused running suite **11/11**; `structure.py check` reports 0 errors/0 warnings and
  `git diff --check` passes. Actual-skeleton checks measured a maximum ankle error of **0.524 mm** and minimum sampled interior-flight clearance of
  **2.4 mm**, with no planted-foot slip or floor penetration. Restarted the native treadmill with `--gait-mode=run --view=side-left` (PID 23380) and
  confirmed its window responds; the user can now visually review the mapped cycle in the lab.

### Visible running flight follow-up
- User: "there is no flight". The contact flags already showed 40% flight, but the hips barely rose and both soles skimmed the belt.
- Corrected the reference mapping: the five frames cover one step, so Passing is late support on the same foot (5/6 of stance) and Flight is 37.5%
  through the next airborne interval (0 / 0.125 / 0.25 / 0.375 at 30% stance). The previous 0.5 / 0.92 placement was wrong.
- Added `run_flight_lift` (0.10 m): the hips and both airborne feet rise together, C2-zero at toe-off and landing, so leg shapes, reach and contacts are
  unchanged. Added `run_knee_drive` (0.30 m) and reshaped the run swing: higher heel recovery (`run_step_height` 0.12 -> 0.34 m) that lingers behind
  the hips, then a knee-drive knot just past the landing point. Fixed a landing-clearance margin that blew up near touchdown (a 25 cm late hop
  followed by a stamp); the foot now settles onto the belt.
- At 4.5 m/s Flight: hips +9.8 cm vs Contact (drawing ~11), trailing toe 17 cm / leading sole 37 cm (drawing ~17 / 36-38), knees 42 / 89 degrees
  (drawing ~33 / 87). Running bank 11: knob 2 = knee drive, knob 6 = flight lift (replacing duplicate speed/hip-bob knobs). Walk is bit-identical.
- Validation: **459/459 utility tests passed** (31 files; running suite 13/13, including new flight-lift and soft-landing tests). The running
  acceleration-continuity check now uses a coarser difference step plus one-sided cubic extrapolation; the old 0.0002 step measured float32 Vector3
  rounding, while the swing knots are continuous to about 0.1 stride/cycle^2. `structure.py check` 0 errors/0 warnings; `git diff --check` passes.

### 7 m/s starting run speed follow-up
- User: "can we actually have the starting run speed be like 7m/s?" (7 m/s = 15.7 mph = 25.2 km/h, about a 3:50 mile; Bolt's 9.58 s 100 m
  averages 10.44 m/s = 23.4 mph and peaks near 12.4 m/s = 27.8 mph).
- `run_speed` default 4.5 -> **7.0**, max 6 -> **8** (the model's `MAX_SPEED`). The 4.5 m/s tuning crouched about 30 cm at 7 m/s to keep the long
  step within reach, so contact time `run_duty_factor` 0.30 -> **0.22** (minimum 0.25 -> 0.18, also in `RunReference.phases`), `run_step_length`
  1.5 -> **1.4** (still the step at 4.5 m/s; 1.87 m at 7) and `run_swing_peak` 0.28 -> **0.32**. At 7 m/s: 225 steps/min, 0.117 s contacts, 56%
  flight, 33 mm reach lowering, support knee 42-58 degrees, Flight hips +11 cm, soles 18 / 39 cm, knees 44 / 104. The Run button tooltip, the run
  preset and the run values stored in the shipped example presets follow the new defaults (the user's `tuned_*` preset is untouched).
- Fixed a handoff precision bug exposed by the shorter contact: running toe-off/landing derivatives were second differences of single-precision
  `Vector3` stance samples over a 0.0002-cycle step, off by up to ~30% in acceleration; at 22% stance the toe dipped 3.8 micrometres into the belt and
  the sole clamp kinked the motion (continuity mismatch 8.7 vs the 4.0 limit). Running now samples the stance in double precision
  (`_stance_exact`): worst mismatch 0.33 at the default and under 1.4 for stances 0.18-0.40. Walk verified bit-identical (8400 sampled poses).
- Tests now target the default run speed for the reference fit and sweep 2.5 / 4.5 / 7 / 8 m/s (scene tests 2.5 / 4.5 / 7); new test for the 7 m/s
  default cycle. Validation: **460/460 utility tests passed** (31 files; running suite 14/14).

### Form match to the new side-view photo
- User supplied a left-facing sprinter photo. Tuned the treadmill Flight checkpoint toward its forward trunk lean, bent forward thigh/knee, long trailing
  leg and opposing bent arms; rendered and visually compared the 7 m/s side-left pose.
- Running defaults now use a **15-degree** trunk lean, **50-degree** arm swing and **90-degree** elbow bend. Reduced heel recovery to **0.20 m** and
  knee-drive height to **0.18 m**, moved recovery timing to **0.34**, and shaped the swing knots to keep the trailing ankle back and the leading ankle
  close to the hips. The walk remains untouched. At Flight: rear/lead thigh angles about **-30 / 63 degrees**, knee flexion **19 / 94 degrees**,
  leading ankle 17 cm ahead of the hips; Passing's recovering foot is 14 cm behind the hips.
- At 7 m/s, the shorter **1.35 m** base step scales to **1.80 m**, **233 steps/min** and **0.113 s** contact; reach safety lowers the requested hip
  path by **56 mm**. The raised lead sole is 27 cm above the belt; stance remains 22%, flight share 56%.
- Added pose assertions for the forward lean, counter-swinging bent arms and leading/trailing leg shape. Updated the run preset, shipped example presets,
  parameter reference, movement-lab docs and this note; left the user's `tuned_*` preset alone.

### Longer-stride, powered takeoff follow-up
- User requested a longer stride that reads as jumping forward from the legs. Kept the belt at 7 m/s and the photo-matched trunk/arms, but changed
  the base step to **1.65 m**, giving **2.20 m per step / 4.40 m per full stride**, **191 steps/min** (previously 233), and **18%** stance.
  Ground contact remains **0.113 s**; each flight interval grows **0.144 -> 0.201 s**, covering **1.01 -> 1.41 m** at belt speed.
- Running now loads at one quarter of stance and rises through toe-off (`run_pelvis_bob` **0.12 m**). Only support feet, including the toe-off
  endpoint, determine constant hip lowering. Airborne feet recover within reach through a C2-rounded radius constraint rather than pulling every
  pose into a crouch; clearance remains enforced with extreme edits. The approved walk's calculations remain unchanged.
- At 7 m/s: loaded support knee **46 degrees**, toe-off **25 degrees**, upward pelvis speed **1.19 m/s**; hip excursion **21 cm**, constant
  lowering **16 mm** (previously 56 mm). At Flight: rear/lead knees **13 / 91 degrees**, soles **23 / 35 cm** above the belt. Recovery height
  **0.30 m**, knee-drive height **0.26 m**, recovery timing **0.28**. Moved the later knot to 76% of the remaining swing to retain a soft landing.
- Persisted defaults and all seven shipped presets; the user's `tuned_*` preset is untouched. Updated parameter docs, current lab documentation and
  reach/push-off tests. Added exact step/cadence/airtime/travel bounds, smooth hip-wave and recovery-independent-posture checks, sub-millimetre late-hop
  coverage, and 8 m/s real-skeleton coverage. Contact acceleration now uses a close four-point scalar-double stencil: the former extrapolation reached
  into the later swing-reach correction rather than measuring the contact limit.
- Validation: **462/462 utility tests passed** (31 files), including all 16 running tests and random-setting sole-clearance checks. Actual
  skeleton ankle error stays below **0.88 mm** across 2.5 / 4.5 / 7 / 8 m/s; planted-foot slip remains below 3 mm/s. Static checks: 0 errors /
  0 warnings. All 13 running values match across the seven shipped presets. Rendered Contact, Down, Passing, toe-off and Flight.
  Whitespace check passes. Native treadmill restarted in Run / side-left and verified responsive.

### Shift-to-run in the Movement Playground
- User requested the treadmill running gait in the obstacle testing zone while Shift is held, and the reference walking gait otherwise.
- The live sprint input frame now selects `gait_params.run_mode` before the body simulation tick; releasing sprint clears it. This reuses the already-mapped Shift action, treadmill run profile and existing 4.5 m/s walk / 1.6x sprint physics. Updated the HUD hint and movement-lab docs.
- Added a scene regression that checks the Shift action is read by live input, walk/run visual modes switch in both directions, physical speeds remain 4.5 / 7.2 m/s, and movement parameters are unchanged.
- Validation: Shift switch test passed; flat-plane scene **30/30** and complete utility suite **463/463** passed. `structure.py check`: 0 errors /
  0 warnings; `git diff --check` passes. The Movement Playground native window is open and responsive.

### Run-only Playground and circling performance
- Request: normal movement should run at 6 m/s, Shift should multiply speed by 2, and circling currently feels laggy.
- Plan: persist the new physical defaults without changing acceleration/collision rules; keep the run profile active independently of Shift, preserve
  crouch/jump handling, and ensure the gait clock handles 12 m/s. Measure the render/animation path under constant and varying turns before changing it.
- Acceptance: 6 / 12 m/s on open ground, running with and without Shift, unchanged treadmill walk controls, no per-frame full-cycle animation rebakes
  during steady circles, preserved graph controls and foot placement. Validate targeted tests, full utility suite, static checks and native restart.
- Implemented 6 m/s normal running and 2x Shift sprint in movement defaults and shipped movement presets; retained the intentional 5 m/s `strafe_lab`
  override. The Playground keeps `run_mode` enabled independently of Shift; crouch/jump fallback and the movement algorithm are unchanged.
  The treadmill still defaults to a 7 m/s run and retains its separate walk. Extended the model/run-speed range to 15 m/s so 12 m/s sprint and
  momentum-preserving turn overspeed use their real cadence, rather than the old 8 m/s clamp.
- Root cause of circling stalls: exact floating-point speed was part of the full animation-loop cache key, triggering up to 193 pose/IK samples and
  16-track rewrites every frame. Gait/rig edits still regenerate the full loop, but speed changes now replace only the two interpolation keys at
  the current phase, at exact speed. Scrubs refresh their own pair; phase, native graph controls and per-character clip ownership are preserved.
- `bench_gait_turning` before/after, 60 warm-up + 360 measured frames per case, real scene presentation plus movement-core stepping (headless CPU,
  not GPU frame rate or real collision throughput):
  - Straight 6 m/s: p95 **1.318 -> 0.936 ms**, 0 -> 0 full bakes.
  - Steady circles (6.104-6.106 m/s actual): p95 **32.495 -> 2.644 ms**, 192 -> 0 full bakes.
  - Varying/tight circles (6.250-6.597 m/s actual): p95 **33.125 -> 2.891 ms**, 360 -> 0 full bakes.
  - Sprint circles (12.211-12.212 m/s actual): **2.573 ms p95**, 0 full bakes. The old 0.899 ms timing used an incorrectly capped 8 m/s gait clock.
- Added exact-speed regression coverage for continuous jitter, abrupt sprint changes, both body-blend extremes, arbitrary frozen scrubs, idle,
  loop boundaries and stable key counts. Extended running model sweeps through 15 m/s and skeleton sweeps through 12 m/s; max ankle error **0.899 mm**.
  Scene tests confirm 6 / 12 m/s, Shift release back to 6 with the run form retained, and restored walk values cannot select walking in the Playground.
- Intentionally remeasured physics defaults at 120 Hz: top/sprint speed **6 / 12 m/s**, 95% normal speed in **0.1333 s**, 2 s distance **11.6250 m**,
  stop **0.1583 s / 0.3578 m**, reverse zero/95% **0.075 / 0.200 s**, 90-degree turn minimum/recovery **4.7339 m/s / 0.1167 s**.
  Jump metrics and 60/120-Hz tolerances are unchanged. Updated default-sensitive tuning tests; ramp tests measure peak height because the faster
  runner can already leave the finite ramp before the observation ends.
- Validation: targeted speed/cache/core/baseline checks passed, then the full utility suite **465/465** passed (31 files).
  An earlier full run exposed remaining old-default test fixtures and one unchanged body-update timing test at 99 us; after fixing the fixtures
  and closing the old rendering Playground, the unchanged 80 us budget passed at 77.3 us/update. No timing threshold was relaxed.
  Regenerated the parameter reference and updated current-state/controls/performance/limitation documentation.
- Final checks: `structure.py check` reports **0 errors / 0 warnings** and `git diff --check` passes. A native Vulkan smoke capture shows the actual
  running pose and **12.00 m/s** readout with the restored startup state (no preset override). Reopened the normal interactive Movement Playground,
  **PID 15060**, verified its window is responsive and its runtime log has no errors or warnings. Visual feel at 6 / 12 m/s awaits the user's feedback.

## Outcome
Paused by the user at a good stopping point on 2026-11-07, mid-task. Done: phase 0 (audit, baselines, guards), phase 1 (analytic springs, user-confirmed),
phase 2 (procedural body inertia, user approved the variables), and a treadmill gait lab with a procedural walk, live-editable proportions, a drag-and-drop
handle editor, 7 MIDI banks, and the user's own tuning saved as the defaults (412 automated tests). Not done: phases 3-9 proper (the gait is not in the
sandbox yet, foot IK on terrain, technique flags, banks A/C, preset A/B, telemetry and recording, guided playtests) and the 0003 phase 4 hardware checkpoint.
The subsequent graph follow-up above integrates walking into the sandbox and exposes AnimationTree editing in both scenes;
the later reference walk received positive user feedback, and the running follow-up above adds a verified treadmill prototype.
These do not complete the remaining production gait/terrain phases. Running appearance still needs user feedback. Next steps and limits:
[MOVEMENT-LAB-2.md](../DOCUMENTATION/MOVEMENT-LAB-2.md) sections 7 and 9. To resume: read that page, then the open items at the top of this note.
