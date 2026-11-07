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
| 2 | Body inertia: torso, pelvis, head/shoulders, arm swing as springs driven by simulated velocity, acceleration, angular velocity; each effect switchable; joint limits | tests on pose response; run/stop/turn/reverse with MIDI | **user checkpoint** |
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
- Debugging notes worth keeping: (a) a probe that ran from `SceneTree._initialize` fought the scene's own `_process`
  because `_ready` had not run yet - wait one frame before disabling a scene's processing (fixed in all scene tests);
  (b) the first physics-identity test failed for the same reason (body stepped twice per tick), not because of animation.

## Outcome
(filled in as phases complete)
