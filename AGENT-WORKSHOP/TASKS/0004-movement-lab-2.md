# 0004 - Movement Lab 2.0: procedural locomotion and body dynamics

Status: in progress     Owner: agent + Alex (hardware owner, playtester)     Date: 2026-11-07
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
| 3 | Procedural gait (stride, cadence, width, height, stance/swing, speed-driven) | state-transition tests; all directions without pose pops | **user checkpoint** |
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
Status: **WAITING for the user.**

## Outcome
(filled in as phases complete)
