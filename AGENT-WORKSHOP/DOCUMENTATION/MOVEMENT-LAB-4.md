# Movement Lab 4.0 - authored running vault checkpoint

Branch: `task/0006-fluid-traversal-vault`. Task: [0006](../TASKS/0006-fluid-traversal-vault.md).
Research and design notes: [fluid traversal](../RESEARCH/fluid-traversal.md).
**Implemented and objectively verified; awaiting human visual/MIDI approval.** One traversal move only: Run -> Anticipate ->
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
| **V** | Side view; follows vault travel without the collider hump. Lane C uses a closer, wider outside view, inside the course's back wall |
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
| B (z -30) | 1.0 m walls at 20 and 40 degrees; 0.6 m and 1.4 m deep | Vault 20 degrees; refuse 40 degrees (`too_angled`). Ordinary collision slides the runner sideways around its edge, off the lane centre line. Re-align to reach the depth walls: vault 0.6 m deep; refuse 1.4 m (`too_deep`) and stop at it |
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
Independent re-verification compared both extracts against the supplied originals: all 195 animation samplers
per extract, channel targets, accessor types/dimensions, skeleton nodes and licence bytes match.
The [integrity report](../../.runtime/movement-lab-4-verification/asset-integrity.json) records the source/extract hashes.

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
   - A read-only approach preview can start during initial acceleration. Physical arming still requires at least
     2 m/s; the preview cannot move the body or trigger an action.
   - Arms inside the anticipation window and eases the approach to the vault's ground speed, which it reaches
     exactly at the planned takeoff distance.
   - Then drives the collider kinematically along a smooth hump with full collision response every tick.
     More than 0.15 m horizontal or 0.25 m vertical tracking error aborts it, and the movement core takes over.
   - On landing, returns to the planned exit speed over 0.12 s.
4. **Presentation** (`animation/authored_animation.gd`):
   - The vault is a state in the existing AnimationTree, seeked to the action's clip time; it has no clock of its own.
   - Jog/sprint share a script-owned clock. Initialize it once on logical Run entry, not every frame the
     AnimationTree still displays the previous state during a crossfade.
   - On Run entry only, select the left/right support phase using the predicted acceleration and approach easing.
     This does not jump the phase of an already-running loop.
   - While armed, the run cadence is steered within 0.8-1.25x, so the gait reaches the vault's entry foot at takeoff.
   - After the vault, the run resumes at the phase that continues the vault's last steps.
   - The flat-floor foot IK pauses during the vault. The support hand is pinned to its planned contact point by
     `animation/two_bone_correction.gd`, an analytic two-bone IK with skeleton-space targets.
     It replaces `TwoBoneIK3D`, which solved targets set during a frame one rendered frame late under physics
     interpolation.
5. **Cameras**: the orbit and side cameras follow `follow_offset()`. That is the clip's travel and landing height,
   without the collider hump or the pose-fitting dip, so the view stays level over a wall and rises smoothly
   onto a deck. The side view eases its height at 5/s. Both render-driven cameras disable their own physics
   interpolation because their targets are already interpolated. Lane C's side and comparison cameras stay
   4 m outside the lane, inside the back wall, with a wider 60-degree field of view.
   Step-ups interpolate the visual offset between ticks.

## Validation

- Focused traversal/MIDI: **17 passed, 0 failed** (16 vault tests and the Traversal bank test).
  Authored Playground/comparison: **6 passed, 0 failed**, including both lane C camera sightlines.
  Final camera changes were checked with these targeted suites, native rendering and the final full regression.
- Latest full utility regression: **499 passed, 0 failed**, about 185 seconds, with no other Movement Lab running.
  Three earlier full runs had 498 passes and one failure in the unchanged legacy update-cost check:
  83.9, 81.8 and 85.5 us/update against its 80 us limit. A stale session-owned Playground was still running.
  After closing it, the full suite passed; the isolated check and **37/37** legacy-module run also passed.
  Neither the legacy implementation nor its threshold was changed. Earlier failures and the final process
  preflight are retained; close other lab instances before comparing CPU timings.
- **Clip and plans**
  - Clip numbers re-measured from the import.
  - Bounded timing at 2-14 m/s.
  - Every planner limit and rejection reason.
  - Silhouette zones match dense capsule sampling.
  - Sampled visual-body clearance and hand reach are checked separately from physical-cylinder clearance.
    The collision cylinder is not a claim that every visual primitive fits inside it.
- **Lanes** (scripted runs from each landmark):
  - Lane A vaults all four walls at 3, 6 and 12 m/s approaches, including the first sprint takeoff, then stops at
    the 1.60 m wall (x about 17.47 m, exit speed 0).
  - Lane B vaults the 20-degree wall and refuses the 40-degree wall. It contacts that wall and slides sideways
    around its edge under ordinary collision response; straight input does not hold it permanently at the wall.
  - A separate depth-wall trial starts at x -5: vaults 0.6 m depth, rejects 1.4 m and stops at x about 7.95 m.
  - Lane C vaults both walls and runs out at 6 m/s.
  - A blocked-ceiling trial rejects the vault and stops safely.
  - All recorded trials have **zero aborts and zero overlap ticks** with the actual collision cylinder, inset
    **2 mm** to exclude contact tolerance. Each tick is checked, not just the planned trajectory.

  Measured on lane A:

  | Approach | Takeoff phases | Largest collider step per 120 Hz tick |
  |---|---|---|
  | 3 m/s | 0.036-0.038 | 0.073 m |
  | 6 m/s | 0.040-0.042 | 0.112 m |
  | 12 m/s | **first 0.04583**, then 0.046-0.052 | 0.138 m |

  The authored entry phase is 0.025; every takeoff is checked within 0.05 cycles, with no sprint exemption.
  Sprint approaches ease toward the maximum **8 m/s vault travel**, rather than remaining at 12 m/s over the wall.
  The largest lane C collider step is 0.206 m at its actual step-up.

  The old first-sprint result (0.785) was also contaminated by the fixture's direct body teleport, which appeared
  as a >5,000 m/s visual-speed sample. Trials now use the public scene teleport and assert zero measured teleport
  speed. A separate regression exercises a delayed graph transition and checks that the Run clock keeps advancing.

- **Robustness**
  - Steering away, slowing and stopping disarm the vault; a jump press cannot break it.
  - With the clip missing, or traversal off, the character keeps running.
  - With traversal on but no vault, physics is bit-identical to traversal off.
  - Active vault trajectories and action clocks are bit-identical with rendered animation enabled or disabled.
- **Live frames** (physics interpolation on): tests check foot targets within 5 mm and the fully planted hand
  within 10 mm. Native Vulkan captures cover all four lane A vaults, the first sprint vault, both lane C vaults
  and full-3D orbit-camera hand contact. Their telemetry records zero aborts and a maximum **2.19 mm** fully
  planted hand error, below the 10 mm contact bound. Final native side-camera logs contain no interpolation
  warnings or engine errors.
- **Cameras** (live frames):

  | Measure | Lane A (hump 0.84 m, dip 0.24 m) | Lane C (+0.25 m deck) |
  |---|---|---|
  | Follow height range | within 1 mm of level | 0 -> +0.250 m |
  | Orbit / side height range | within 1 mm of level | about +0.22 / +0.13 m, side step under 0.012 m per tick |
- **MIDI** (`test_traversal_bank_uses_verified_midi_mapping_and_round_trips_presets`): synthetic events through the
  real learned SMC-MIXER mapping drive bank 5's four sliders, switch traversal off and on live, and show and hide
  the overlay. A preset round trip restores anticipation and the traversal switch.
  This does not replace the physical-controller test.

Headless CPU (`benchmarks/bench_traversal_vault.gd`, development machine, other lab windows closed;
compare only on the same machine):

| Measure | Result |
|---|---|
| Whole tick, lane A with 4 vaults, traversal on | p50 0.221 ms, p95 0.283 ms, max 1.677 ms |
| Whole tick, open ground, traversal on / off | p50 0.178 / 0.165 ms, p95 0.204 / 0.188 ms |
| Physics + perception mean, lane A / open on / open off | 0.070 / 0.059 / 0.049 ms |
| Fresh vault plan, 6 / 12 m/s (memoized afterwards) | 1.312 / 1.266 ms |
| Vault profile build, once per clip | 8.631 ms (89 samples) |
| Silhouette zones | 0.663 ms |

Both benchmark cases passed. These headless CPU timings are not GPU/frame-rate guarantees.

### Retained verification evidence

Local reports live under the ignored `.runtime/movement-lab-4-verification/`; they are not shipped with a clone.
They retain results rather than relying on an earlier session's unverified test-count claim.

| Evidence | Contents |
|---|---|
| [Verification summary](../../.runtime/movement-lab-4-verification/verification-summary.json) | Final report totals and hashes of the tested changed GDScript files |
| [Focused report](../../.runtime/movement-lab-4-verification/focused.json), [log](../../.runtime/movement-lab-4-verification/focused.log) | Per-test results and machine-readable `VAULT_LANE_RESULT` records |
| [Playground report](../../.runtime/movement-lab-4-verification/playground.json) | MIDI/presets, authored A/B and final camera visibility checks |
| [Full report](../../.runtime/movement-lab-4-verification/full-suite.json), [log](../../.runtime/movement-lab-4-verification/full-suite.log) | Final 499/499 regression, including the camera repairs |
| [Process preflight](../../.runtime/movement-lab-4-verification/full-suite-context.json), [earlier loaded run](../../.runtime/movement-lab-4-verification/full-suite-live-playground.json) | No competing lab in the final run; earlier legacy timing failure preserved |
| [Legacy module](../../.runtime/movement-lab-4-verification/legacy-module.json), [isolated check](../../.runtime/movement-lab-4-verification/legacy-cost-recheck.json) | Independent passing timing rechecks |
| [Benchmark](../../.runtime/movement-lab-4-verification/benchmark.json) | Recorded CPU samples |
| [Native telemetry summary](../../.runtime/movement-lab-4-verification/native-results.json) | Per-capture counts, contact errors and warnings; distinguishes superseded camera captures |
| [Lane A poses](../../.runtime/movement-lab-4-verification/native-a-final/vault_a_0.png), [sprint poses](../../.runtime/movement-lab-4-verification/native-a-sprint/vault_a_sprint_0.png) | Native side-view samples |
| [Lane C contact](../../.runtime/movement-lab-4-verification/native-c-final/side_contact.png), [orbit contact](../../.runtime/movement-lab-4-verification/native-orbit/orbit_contact.png) | Native side/full-3D inspection |
| [Playtest readiness](../../.runtime/movement-lab-4-verification/playtest-readiness.json), [startup log](../../.runtime/movement-lab-4-verification/playtest.log) | Checkpoint relaunched at lane A; responsive native window and clean startup verified |

## Limitations

See [known issues](../INVENTORY/KNOWN-ISSUES.md) KI-020 to KI-023.

- **Pose dip**: the authored hand sits above low tops, so on a 0.80 m wall the drawn root drops up to 0.24 m below
  the takeoff ground while the hand is planted. Cameras ignore it; whether it reads well is part of the visual review.
- **Steep angle at sprint speed**: some steep approaches leave the support hand out of reach. The verified case is
  12 m/s at a 1.0 m high, 0.2 m deep wall angled -34 degrees (just inside the 35 degree limit). It is refused
  (`out_of_reach`) rather than vaulted with a hovering hand; the character stops at the wall.
- **Authored clip timing**: the run's linear keyframes still show as hip-acceleration spikes. They are part of the
  source clip, not a fitting error.
- **Scope**: static box-like obstacles only; moving or irregular tops are refused or untested.

## Reproduce diagnostics

Close other Movement Lab windows before the full suite or benchmark; their load affects the strict CPU checks.

```powershell
$proof = "$PWD\.runtime\movement-lab-4-verification"
New-Item -ItemType Directory -Force $proof | Out-Null
& $godot --headless --path utility\movement\flat-plane --log-file "$proof\focused.log" --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --filter=test_traversal --report="$proof\focused.json"
& $godot --headless --path utility\movement\flat-plane --log-file "$proof\playground.log" --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --filter=test_authored_playground --report="$proof\playground.json"
& $godot --headless --path utility\movement\flat-plane --log-file "$proof\full-suite.log" --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --filter=test_ --report="$proof\full-suite.json"
& $godot --headless --path utility\movement\flat-plane --log-file "$proof\benchmark.log" --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --mode=bench --dir=res://benchmarks --filter=bench_traversal --report="$proof\benchmark.json"
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
