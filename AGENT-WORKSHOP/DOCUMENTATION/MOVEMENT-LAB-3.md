# Movement Lab 3.0 - authored locomotion review checkpoint

Branch: `task/0005-movement-lab-3`. Task: [0005](../TASKS/0005-movement-lab-3.md).
**Implemented and objectively tested; not visually approved.** This is the isolated movement utility,
not the multiplayer sandbox. Physics, collision, camera controller and the learned SMC-MIXER mapping are unchanged.
Normal movement remains 6 m/s; Shift remains 12 m/s. There is no active walking animation.

## Run and compare

From the repository root in PowerShell:

```powershell
$godot = ".\.tools\godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path utility\movement\flat-plane res://scenes/locomotion_comparison.tscn
& $godot --path utility\movement\flat-plane res://scenes/flat_plane.tscn
& $godot --path utility\movement\flat-plane res://scenes/animation_reference.tscn
```

Run one interactive lab at a time so they do not contend for MIDI inputs. In A/B, use **Playground** for keyboard
movement; **F9** returns to the comparison. Comparison uses perspective side cameras; the Playground's orbit camera
is untouched. **A** is the preserved procedural run; **B** defaults to authored playback. B's legacy switch changes
the system live, without changing its body, velocity or physical parameters. Pause/replay buttons control the recording.

The comparison feeds the same stored 3,000-frame, 120 Hz scripted input recording to separate physics worlds.
They share one physical parameter object, avoiding both parameter drift and collisions between copies.
The 25-second recording includes 0, 1, 2, 4, 6 and 8 m/s targets, turning, jumping, stopping and crouching.
It is a prerecorded deterministic test sequence, not a recording of a human's controller performance.
Both scene instances use the existing collision body and movement simulation.

## MIDI and presets

Three existing physical banks plus one **Authored Animation** bank replace the nine-bank Playground default.
In bank 4, faders set and knobs fine-adjust:

1. Transition duration: 0.06-0.35 s, default 0.16 s.
2. Cadence multiplier: 0.85-1.15x, default 1.
3. Stride scale: 0.9-1.1x, default 1.
4. Acceleration-driven lean intensity: 0-1.5x, default 1.
5. Flat-ground foot IK on/off, default on.
6. Legacy procedural baseline on/off, default off.

F3 cycles the tuning HUD, PageUp/PageDown change banks, and F5 saves a preset. Soft takeover, relative knobs,
locks and the verified physical MIDI mapping remain in the existing tuning system. The A/B scene starts at bank 4.
Existing presets are preserved; their `body`, `gait` and `graph` targets are explicitly labelled **Legacy** and cannot
affect authored poses. New presets capture the separate `locomotion` target as well. A separate remembered UI state
avoids restoring an incompatible old bank index.

For the full original control layout, launch with
`-- --legacy-animation --tuning-bindings=res://config/tuning_bindings.json`.
The original treadmill, walking editor and all old presets remain available, but are not the gameplay default.
See the generated [parameter reference](MOVEMENT-LAB-PARAMETERS.md).

## Phase 1 audit: what was actually wrong

The old character already used a **15-bone Skeleton3D**, 15 bone attachments and 18 rigid primitive meshes, not a
custom transform-only rig. In graph mode there was one final writer, AnimationTree, not several racing bone setters:

- GaitModel generated analytic leg/pelvis/arm trajectories.
- BodyDynamics supplied spring offsets.
- CharacterVisual composed gait, spring and fallback poses.
- WalkAnimation generated/updated a clip and its additive residual; AnimationTree wrote the bones.
- Direct pose setters were the graph-disabled fallback. Rig changes wrote rests only on setup/proportion edits.

Complexity came from the number of composed pose sources and independent clocks, rather than simultaneous writes.
The planner used horizontal velocity and `rate = speed / (2 * step_length)`. Its separate graph-speed control could
change animation without changing physical displacement. No world-space foot locking existed, so turning could slide.

The requested side-view legacy samples cover both walk and run at all six speeds. Steady straight-belt measurements:

| m/s | Walk cadence, steps/min | Walk maximum support slip, m/s | Run cadence, steps/min |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 1 | 86.4 | 0.0006 | 96.7 |
| 2 | 129.1 | 0.0007 | 123.2 |
| 4 | 193.0 | 0.0008 | 157.0 |
| 6 | 244.2 | 4.4922 | 181.0 |
| 8 | 300.0 | 6.0080 | 200.1 |

At 4 m/s, walking was already geometrically stretched/crouched even without large straight-line slip.
At 6/8 m/s the walk exceeded practical reach and slid badly. This did not justify changing physics.
The preserved procedural run had near-zero straight-belt support slip; that never proved naturalness or turning contact.
The earlier circling rebake fix and its original benchmark are retained; see [2.0](MOVEMENT-LAB-2.md).

## Authentic source and native retargeting

The official free **Quaternius Universal Animation Library Standard** is CC0 and contains 43 animations in combined
Godot-compatible GLBs. Original bytes, license, inventory, hashes and source URLs are in
[PROVENANCE](../../utility/movement/flat-plane/assets/quaternius/PROVENANCE.md). No fabricated clips, Blender or
conversion framework were used.

The original 65-bone reference was verified before retargeting. Godot's native `BoneMap` /
`SkeletonProfileHumanoid` import normalizes rests, names and position tracks. A 23-bone target copies those normalized
rests and scales translations uniformly to a 1.01 m hip height. Primitive capsules, ellipsoids and shoes retain the
mannequin presentation; no source character mesh appears in gameplay.

Runtime clips: `Idle`, `Jog_Fwd`, `Sprint`, `Jump_Start`, `Jump`, `Jump_Land`, `Crouch_Idle`, `Crouch_Fwd`.
There is **no separate Fall clip** in Standard; Fall uses the real `Jump` air loop. Crouch clips preserve an existing
controller capability, not a new physical state. The original source scene plays uncorrected 1x clips; add
`-- --mannequin` to inspect the primitive target without the locomotion model.

## Runtime and calibration

Physical state -> Idle/Run/Jump/Fall/Land (plus existing crouch) -> native AnimationTree -> small corrections -> skeleton.
AnimationPlayer owns the curated clips; its autonomous mixer is inactive during graph playback.
The old graph, gait generator and body spring model are disabled in authored mode.

- In-place animation only. Root-motion output has no consumer and never moves CharacterBody3D.
- Root-motion reference displacement is 5 m / 0.9333 s for jog and 5.5 m / 0.6667 s for sprint.
  Those speeds are multiplied by the target's uniform proportion scale.
- Playback reads actual interpolated body displacement, excluding teleports, rather than input wish speed.
- Native cyclic-mutable synchronization aligns differently sized jog/sprint loops; measured source foot phases agree.
- Cadence is hard-bounded to 0.8-1.45x. Total stride correction is limited to 0.9-1.1x and 0.10 m at each foot;
  no limb lengths change. Low speed blends idle/run rather than producing extreme slow-motion running.
- State transitions crossfade. Physical apex/contact control air/land transitions; landing does not wait for the full
  1.2667-second source clip. Jump_Start is front-loaded: its hip is already near its held air height by about 0.067 s.
- Only acceleration lean (maximum 0.10 rad), bounded stride IK and flat-ground shoe clearance are active corrections.
  Native TwoBoneIK is followed by preservation of the authored ankle orientation. No independent oscillation layers.

| Actual m/s | Settled cadence | Total stride scale |
|---:|---:|---:|
| 0 | 0.800 (idle plays normally) | 1.000 |
| 1 | 0.800 | 0.900 |
| 2 | 0.800 | 0.900 |
| 4 | 0.800 | 0.900 |
| 6 | 1.005 | 1.000 |
| 8 | 1.033 | 1.000 |
| 12 | 1.320 | 1.000 |

## Validation and measured limitations

- Full utility regression: **479 passed, 0 failed**.
- Original clip names/paths/playback, 23-bone mapping, fixed limb lengths, source/target trajectories within 1 mm.
- Real collision-body replay: bit-identical positions and velocities for legacy/authored, including animation-disabled
  frames; actual 0/1/2/4/6/8 m/s targets reached. Existing 6/12 speeds and obstacle tests still pass.
- No missing clips, invalid animation paths, non-finite poses, duplicate active graphs, or unlimited playback rates.
- Final modifier targets within 2 mm, ankle orientation retained, no >20 cm ankle discontinuity per 120 Hz sample;
  no >10 cm hip discontinuity across the tested start/stop/jump/fall/land/crouch sequence.
- Synthetic events pass through the **real learned hardware mappings**, including fader pickup and live legacy switching;
  new/legacy preset round trips pass. This does not replace the user's physical-controller acceptance test.

Native rendered shoe-corner diagnostic, after rendering completes (not stale pre-render skeleton reads):

| m/s | Minimum sole, IK off (mm) | Minimum sole, IK on (mm) | Near-floor corner slip p95, IK on (m/s) |
|---:|---:|---:|---:|
| 0 | -1.86 | -0.120 | 0.043 |
| 1 | -80.02 | -0.001 | 2.914 |
| 2 | -82.26 | -0.001 | 5.857 |
| 4 | -34.56 | -0.001 | 2.424 |
| 6 | -25.73 | -0.041 | 2.874 |
| 8 | -50.88 | -0.116 | 3.578 |
| 12 | -49.50 | -0.001 | 10.058 |

Grounding demonstrably removes flat-floor penetration with a maximum observed 83.6 mm correction, so it is enabled.
**It is not a world-space foot lock or terrain IK.** A planting experiment increased sliding and was removed.
The slip diagnostic counts shoe corners below 3 cm for consecutive samples, including rolling/near-contact swing;
it is not equivalent to the legacy planner's known stance/contact labels. The large low-speed/sprint readings are
an explicit remaining concern, not a passed acceptance threshold. Turning, slopes and steps need human review.

Headless presentation-update CPU, 360 measured turning frames after warm-up, no physics/draw cost:

| m/s | Legacy p95 (ms) | Authored p95 (ms) |
|---:|---:|---:|
| 4 | 0.570 | 0.155 |
| 6 | 0.683 | 0.151 |
| 8 | 0.680 | 0.153 |
| 12 | 1.696 | 0.155 |

This is not a GPU/frame-rate benchmark. The original [turning benchmark](../../utility/movement/flat-plane/benchmarks/bench_gait_turning.gd)
is unchanged apart from explicitly selecting legacy. The new comparison benchmark feeds identical turning velocities
and times the presentation update. Subjective naturalness, weight transfer and visual loop quality remain unapproved.

## Reproduce diagnostics

```powershell
& $godot --headless --path utility\movement\flat-plane --script "$PWD\TESTING\harness\run_gd_tests.gd"
& $godot --headless --path utility\movement\flat-plane --script "$PWD\TESTING\harness\run_gd_tests.gd" -- --mode=bench --dir=res://benchmarks --filter=bench_authored
& $godot --path utility\movement\flat-plane --script res://tools/audit_locomotion.gd -- --out-dir=C:\your\capture-directory
& $godot --path utility\movement\flat-plane --script res://tools/audit_authored_locomotion.gd -- --out-dir=C:\your\capture-directory
```

Both audit tools save measurements plus side-view pose sheets; headless saves measurements only.
Native audit samples must be read after `frame_post_draw`, since a screenshot yield otherwise changes the coroutine
phase and can make a pre-render read report the previous frame as the current corrected pose.
`prepare_authored_assets.gd` regenerates native import mappings; follow it with Godot's `--headless --editor --import`.
`make_locomotion_trial.gd` regenerates the explicit shared recording; `make_tuning_files.gd` without `--force` preserves
existing bindings/presets. No Docker or Blender is involved.

**Next checkpoint:** user side-view and MIDI review. Do not mark the overall naturalness/Definition of Done approved
until that happens. Assess the low-speed blend, residual sliding and sprint first, rather than adding more tuning knobs.
