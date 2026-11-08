# Movement Lab 4.0 - authored running vault checkpoint

Branch: `task/0006-fluid-traversal-vault`. Task: [0006](../TASKS/0006-fluid-traversal-vault.md).
Research and design notes: [fluid traversal](../RESEARCH/fluid-traversal.md).
**Implemented and objectively tested; not yet visually approved.** One traversal move only: Run -> Anticipate ->
Vault -> Land -> Run. Mantle, slide, climb and roll wait until the user approves this vault.
The approved [3.0 authored locomotion](MOVEMENT-LAB-3.md) and the movement core, defaults (6 m/s run,
12 m/s Shift), collision body and learned SMC-MIXER mapping are unchanged.
With traversal off, or on but with no vault happening, physics is bit-identical to 3.0.

## Run and compare

From the repository root in PowerShell:

```powershell
$godot = ".\.tools\godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path utility\movement\flat-plane res://scenes/flat_plane.tscn -- --landmark=vault_a
& $godot --path utility\movement\flat-plane res://scenes/locomotion_comparison.tscn -- --trial=vault --lane=a
```

Run straight at a wall: the vault is automatic and needs no button. A press of Jump while the vault is armed is
ignored, so it cannot break the vault. Steering away from the obstacle, slowing below 2 m/s or a changed obstacle
disarms it, and the character keeps running.

| Key / option | Effect |
|---|---|
| **T** / **Shift+T** | Next / previous test landmark; `vault_a`, `vault_b`, `vault_c` face down the vault lanes |
| **F10** or `--traversal-debug` | Traversal debug overlay (legend below) |
| **V** | Side view; follows the vault travel without the collider hump |
| **F9** | The 3.0 locomotion A/B (default recording). For the vault A/B use `--trial=vault` as above |
| `--landmark=<name>` | Start at a landmark |
| `--no-traversal` | Start with traversal off (approved 3.0 behaviour; walls simply block) |
| `--no-traversal-clip` | Test aid: behave as if the vault clip were not installed |

`--trial=vault` (`--lane=a|b|c`) feeds one deterministic recording (stand, run down the lane at the default speed,
stop) to two physics worlds. **A** is the approved authored baseline with traversal off; **B** is the same with
traversal on. Both use side cameras that follow the vault travel. The recording is
`config/vault_trial.json` (`tools/make_vault_trial.gd`); it is a scripted input, not a human performance.

Overlay legend: yellow = probe hits (face, top, back, landing); cyan = planned collider path;
magenta = planned visual root path; white = takeoff point and travel direction; green = support-hand target
(bright while bearing weight); orange = velocity; red = visual root minus body.
The readout also shows the vault state and the last rejection reason.

### Vault course

Three 3 m-wide lanes run toward +X with an obstacle every 9 m; walls are 0.35 m deep unless stated.

| Lane | Obstacles | Expected |
|---|---|---|
| A (z -25) | 0.80, 0.95, 1.10, 1.25 m walls; 1.60 m wall | Vault all four; refuse 1.60 m (`too_high`) and stop at it |
| B (z -30) | 1.0 m walls at 20 and 40 degrees; 0.6 m and 1.4 m deep | Vault 20 degrees; refuse 40 degrees (`too_angled`), which blocks a straight run from the landmark. Steer around it to reach the depth walls: vault 0.6 m deep; refuse 1.4 m (`too_deep`) and stop at it |
| C (z -35) | 1.0 m wall onto a +0.25 m deck, a 0.2 m step, a 1.45 m wall down 0.45 m to the ground | Vault both walls (onto the deck, then down to the ground); climb the step with eased presentation |

## MIDI and presets

Bank 5, **Traversal**, follows the 3.0 Authored Animation bank. Faders set and knobs fine-adjust; switches use the
existing toggle behaviour. Presets and the learned mapping are preserved; new presets also capture `traversal.*`.

1. Anticipation, 0.15-0.6 s, default 0.35: time ahead of takeoff at which the vault arms and eases the approach.
2. Transition response, 0.06-0.3 s, default 0.12: crossfade into and out of the vault (visual only).
3. Contact correction, 0-1, default 1: strength of the planted-hand IK and torso lean onto the support arm (visual only).
4. Momentum continuity, 0-1, default 0.6: share of a faster approach speed kept on landing.
5. Traversal on/off, default on.
6. Debug overlay on/off, default off.

The vault's playback rate, stride stretch, takeoff distance, body path, pose fitting and contact window are derived
from the approach speed, the measured obstacle and the clip. They are not tuning parameters. Full tables: the
generated [parameter reference](MOVEMENT-LAB-PARAMETERS.md).

## Source

The paid **Quaternius Universal Animation Library 2**, supplied by the user, is CC0. Its `SafetyVault` is the only
running vault in the package and the only clip taken from it. `tools/extract_glb_clips.py` copies that animation, the
reference skeleton and its mesh from the 134-animation GLBs without changing any keyframe bytes. The in-place and
root-motion extracts (720 KB each) replace committing the 20 MB originals. Hashes, licence and the excluded files
are in [provenance](../../utility/movement/flat-plane/assets/quaternius/PROVENANCE.md). The original download stays
in the ignored `AGENT-WORKSHOP/DOWNLOADS/`. No clip is fabricated; with the clip missing, the character keeps running.

The clip retargets through the same native `BoneMap` as 3.0. `tools/audit_vault_clip.gd` measured it on the original
rig at mannequin scale. `traversal/vault_clip.gd` holds those numbers, and the tests re-measure them from the import.

| Measure | Value |
|---|---|
| Length | 22 frames at 30 fps, 0.7333 s |
| Root travel | linear, 4.358 m/s at mannequin scale (2.901 m source x 1.1018) |
| Entry / exit | starts on a left-foot run contact; left foot leaves at 0.05 s, lands at 0.69 s |
| Support hand | right hand lowest at 0.13 s, lifts from 0.30 s |
| Authored obstacle | none: the hand sits about 0.1 m above any top the knees clear |

## Architecture

Perception -> planning -> physical action -> presentation. Each stage only reads the previous one; nothing in
presentation moves the body.

1. **Perception** (`traversal/obstacle_probe.gd`): Godot ray and shape queries only. It measures the face, top,
   depth, approach angle, landing ground and headroom ahead of the feet. It also overlap-tests a crouch-height
   cylinder at sampled points along the collider's planned path, both when arming and at takeoff.
   It returns explicit reasons (`not_a_wall`, `too_angled`, `blocked`, ...).
2. **Planning** (`traversal/vault_planner.gd`, pure functions over `vault_profile.gd`): one measured obstacle and the
   approach speed in, a timed plan or a rejection reason out. The profile measures the clip once on the mannequin:
   body capsules, sole points, hand and shoulder paths, and the run phases matching the vault's entry and exit.
   - Timing: ground speed 3-8 m/s; playback rate 0.8-1.45x (the run cadence bounds); stride stretch 0.85-1.3x.
   - Height 0.6-1.25 m, approach within 35 degrees, depth up to 0.9 m, landing -0.6 to +0.3 m.
   - The visual body is lifted by an exact warp that keeps every limb 3 cm above the top. It may dip up to 0.15 m
     and lean up to 18 degrees onto the support arm while the hand is planted, so the hand reaches the top.
     A top still more than 2 cm out of reach is refused (`out_of_reach`). Plans are memoized per obstacle and speed.
3. **Physical action** (`traversal/vault_action.gd`), on the fixed physics tick:
   - Arms inside the anticipation window and eases the approach to the vault's ground speed, which it reaches
     exactly at the planned takeoff distance.
   - Then drives the collider kinematically along a smooth hump with full collision response every tick.
     More than 0.15 m horizontal or 0.25 m vertical tracking error aborts it, and the movement core takes over.
   - On landing, returns to the planned exit speed over 0.12 s.
4. **Presentation** (`animation/authored_animation.gd`):
   - The vault is a state in the existing AnimationTree, seeked to the action's clip time; it has no clock of its own.
   - While armed, the run cadence is steered within 0.8-1.25x, so the gait reaches the vault's entry foot at takeoff.
   - After the vault, the run resumes at the phase that continues the vault's last steps.
   - The flat-floor foot IK pauses during the vault. The support hand is pinned to its planned contact point by
     `animation/two_bone_correction.gd`, an analytic two-bone IK with skeleton-space targets.
     It replaces `TwoBoneIK3D`, which solved targets set during a frame one rendered frame late under physics
     interpolation.
5. **Cameras**: the orbit and side cameras follow `follow_offset()`. That is the clip's travel and landing height,
   without the collider hump or the pose-fitting dip, so the view stays level over a wall and rises smoothly
   onto a deck. The side view eases its height at 5/s. Step-ups are interpolated between ticks, so the visual no
   longer sinks below a tread for one frame.

## Validation

- Full utility regression: **495 passed, 0 failed** (35 files). `tests/test_traversal_vault.gd` holds the 13 vault
  tests; `tests/test_authored_playground.gd` holds the Traversal bank test.
- **Clip and plans**
  - Clip numbers re-measured from the import.
  - Bounded timing at 2-14 m/s.
  - Every planner limit and rejection reason.
  - Silhouette zones match dense capsule sampling.
  - Every planned pose keeps the whole warped body clear with the hand in reach.
- **Lanes** (scripted runs from each landmark):
  - Lane A vaults all four walls on the authored foot and stops at the 1.60 m wall.
  - Lane B vaults the 20 degree wall and refuses the 40 degree wall.
  - Lane C vaults both walls.
  - A manual scripted check started past lane B's 40 degree wall: the 0.6 m deep wall is vaulted and the 1.4 m
    deep wall is refused (`too_deep`), stopping the run.

  Measured on lane A:

  | Approach | Takeoff phases | Hand error | Largest collider step per 120 Hz tick |
  |---|---|---|---|
  | 3 m/s | 0.036-0.038 | 0.0 mm | 0.073 m |
  | 6 m/s | 0.041-0.042 | 1.1 mm | 0.112 m |
  | 12 m/s | 0.785, then 0.046-0.052 | 0.0 mm | 0.138 m |

- **Robustness**
  - Steering away, slowing and stopping disarm the vault; a jump press cannot break it.
  - With the clip missing, or traversal off, the character keeps running.
  - With traversal on but no vault, physics is bit-identical to traversal off.
- **Live frames** (physics interpolation on): feet and the support hand are on their targets.
- **Cameras** (live frames):

  | Measure | Lane A (hump 0.84 m, dip 0.24 m) | Lane C (+0.25 m deck) |
  |---|---|---|
  | Follow height range | within 1 mm of level | 0 -> +0.250 m |
  | Orbit / side height range | within 1 mm of level | up to +0.224 / +0.128 m, side step 0.010 m per tick |
  | Orbit vertical acceleration p95 / max | 22 / 33 m/s² before, 0.04 / 0.08 after | 17.5 p95 after |
  | Side vertical acceleration p95 / max | 149 / 828 m/s² before, 0.01 / 0.02 after | 7.9 p95 after |

- **Stair steps**: lane C run-phase orbit acceleration max fell from 429 to 38 m/s², and the visual root max from
  6,532 to 353 m/s².
- **MIDI** (`test_traversal_bank_uses_verified_midi_mapping_and_round_trips_presets`): synthetic events through the
  real learned SMC-MIXER mapping drive bank 5's four sliders, switch traversal off and on live, and show and hide
  the overlay. A preset round trip restores anticipation and the traversal switch.
  This does not replace the physical-controller test.

Headless CPU (`benchmarks/bench_traversal_vault.gd`, development machine; compare only on the same machine):

| Measure | Result |
|---|---|
| Whole tick, lane A with 4 vaults, traversal on | p50 0.213 ms, p95 0.265 ms, max 1.685 ms |
| Whole tick, open ground, traversal on / off | p50 0.180 / 0.164 ms, p95 0.290 / 0.195 ms |
| Physics + perception mean, lane A / open on / open off | 0.068 / 0.062 / 0.048 ms |
| Fresh vault plan, 6 or 12 m/s (memoized afterwards) | 1.30 ms |
| Vault profile build, once per clip | 8.8 ms |

The lane A maximum is consistent with a tick that builds a fresh plan (1.30 ms); this is not separately measured.

## Limitations

See [known issues](../INVENTORY/KNOWN-ISSUES.md) KI-020 to KI-022.

- **Pose dip**: the authored hand sits above low tops, so on a 0.80 m wall the drawn root drops up to 0.24 m below
  the takeoff ground while the hand is planted. Cameras ignore it; whether it reads well is part of the visual review.
- **Short sprint run-up**: at 12 m/s the cadence steer (at most 1.25x) can miss the entry foot from a short
  run-up (first lane A wall: phase 0.785). The vault still plays, starting on the off foot.
- **Steep angle at sprint speed**: some steep approaches leave the support hand out of reach. The verified case is
  12 m/s at a 1.0 m high, 0.2 m deep wall angled -34 degrees (just inside the 35 degree limit). It is refused
  (`out_of_reach`) rather than vaulted with a hovering hand; the character stops at the wall.
- **Authored clip timing**: the run's linear keyframes still show as hip-acceleration spikes. They are part of the
  source clip, not a fitting error.
- **Scope**: static box-like obstacles only; moving or irregular tops are refused or untested.

## Reproduce diagnostics

```powershell
& $godot --headless --path utility\movement\flat-plane --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --filter=test_traversal
& $godot --headless --path utility\movement\flat-plane --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --mode=bench --dir=res://benchmarks --filter=bench_traversal
& $godot --headless --path utility\movement\flat-plane --script res://tools/audit_vault_clip.gd
& $godot --headless --path utility\movement\flat-plane --script res://tools/make_vault_trial.gd
```

Re-extracting the clip needs the ignored original download:

```powershell
cd utility\movement\flat-plane
python tools\extract_glb_clips.py ..\..\..\AGENT-WORKSHOP\DOWNLOADS\Unreal-Godot\UAL2.glb assets\quaternius\UAL2_Traversal.glb SafetyVault
python tools\extract_glb_clips.py ..\..\..\AGENT-WORKSHOP\DOWNLOADS\Unreal-Godot\UAL2_RM.glb assets\quaternius\UAL2_Traversal_RM.glb SafetyVault
```

**Next checkpoint:** user review of the vault in the Playground (all three lanes, side view and overlay), in the vault
A/B and with the physical MIDI controller. No further traversal moves until it is approved.
