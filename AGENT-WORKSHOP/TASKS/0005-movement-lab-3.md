# 0005 - Movement Lab 3.0: natural locomotion

Status: in progress. Date: 2026-11-08. Branch: `task/0005-movement-lab-3`.

## Goal

Replace active procedural locomotion with authentic Quaternius authored animation, preserving primitive visuals and
the current controller, physics, camera, verified MIDI mapping and legacy baseline. Grounded gameplay uses idle/run,
not walking. Reduce active animation tuning to four controls plus IK/legacy toggles. Human visual acceptance is required.

## Starting point and impact

- Branched from `task/0004-movement-lab-2` at `f29f5e1`, carrying forward its existing uncommitted reference-walk/run work.
  Those changes are not new 3.0 work and must not be discarded. The 2.0 runtime remains available while source playback is validated.
- Scope: `utility/movement/flat-plane/` and directly related workshop documentation only.
- No movement-core, collision, camera, multiplayer, MIDI hardware mapping, Docker, Blender or toolchain changes.
- The user's 3.0 brief explicitly authorizes importing CC0 animation/reference assets, a narrow exception to ADR-0009's
  original primitives-only/no-external-assets constraint. The final mannequin remains primitive geometry.
- Engine: existing Godot 4.7.2-stable. No new framework or package.

## Plan and gates

1. Audit actual bone writers, clocks, rig, displacement coupling and foot sliding. Record legacy side-view poses at
   0, 1, 2, 4, 6 and 8 m/s, including the problematic walking stress case without enabling gameplay walking.
2. Obtain the official Quaternius Universal Animation Library's smallest Godot-compatible CC0 set. Inventory actual
   filenames/clips, provenance and hashes. Verify animation on the original reference character in Godot first.
   If files require manual delivery, request them; never invent replacement clips.
3. Only after the source gate: native humanoid retargeting to a compatible primitive Skeleton3D; retain selectable legacy.
4. Idle/Run/Jump/Fall/Land through AnimationPlayer/AnimationTree; smooth transitions, in-place playback, bounded
   distance-aware cadence and limited stride correction. No animation-driven body movement.
5. One simplified animation bank: transition duration, cadence multiplier, stride scale, lean intensity; optional
   IK and legacy toggles. Preserve old presets as explicitly legacy settings.
6. Side-view A/B using identical recorded inputs and physical settings; live switching, objective diagnostics.
7. Automated mapping/path/clip/blending/contact/rate/IK/writer-isolation/physics tests, requested speed trials and
   CPU benchmark. Notify the user when the authored run is ready for side-view and MIDI review.

## Validation

- First milestone: reproducible legacy pose/metric capture, unchanged production pipeline, authentic source clips
  visibly playing on their original skeleton, scene-load/path/animation checks.
- Later: compare physics trajectories bit-for-bit; retain the existing turning benchmark and legacy controls.
- Record commands and measured results below. Do not equate automated success with naturalness or user approval.

## Results

Audit and original-source playback passed before retargeting. The authored Playground, native primitive target,
four-control MIDI bank and recorded-input A/B comparison are implemented.

- Official CC0 Standard assets acquired; 43 actual clips inventoried. Native source and retarget tests pass.
- Original 2.0 work preserved, including an exact pre-3.0 session archive. No commits or history rewrites.
- Full utility regression: 479/479 passed; subsequent focused authored ownership/contact tests: 6/6 passed.
- Recorded collision-body trajectories are bit-identical across legacy/authored/animation-disabled presentation.
- Requested speed trials and native side-view sheets recorded; flat-floor IK reduces maximum shoe penetration
  below 0.2 mm in the steady-speed diagnostic. An unsuccessful world-planting experiment was removed.
- CPU presentation-update p95: authored 0.151-0.155 ms versus legacy 0.570-1.696 ms at 4/6/8/12 m/s.
- Synthetic MIDI tests use the learned SMC-MIXER mappings; old presets and new parameter round trips pass.
- Native reference, Playground and side-view comparison launch successfully.
- Repository static checks: 0 errors/0 warnings; whitespace checks pass. Seven authoritative movement, collision,
  camera/input and MIDI source/config files match the pre-3.0 archive byte-for-byte.

Full diagnosis, commands, actual clip inventory, calibration, measured metrics and limitations:
[Movement Lab 3.0](../DOCUMENTATION/MOVEMENT-LAB-3.md).

Session captures: `ml3-audit/legacy_walk.png`, `legacy_run.png`, `authored_run.png`, `authored_ik_off.png`,
`legacy_metrics.json`, `authored_metrics.json`; source/target screenshots and CPU JSON are also retained in session files.
The input recording is persisted in the utility as `config/locomotion_trial.json`.

## User review and remaining limitations

In the 2026-11-08 Movement Lab 4.0 brief, the user confirmed that A/B testing was successful and the authored
animations look excellent. The authored motion is the approved foundation for subsequent work, not a system to replace.
This statement does not independently confirm every physical MIDI control or resolve the diagnostic limitations below.
Residual near-floor slip (especially low speed and 12 m/s), terrain/turn contact and overall weight transfer are not
declared solved. Foot IK is flat-ground clearance only; no terrain raycasts or world-space planting are shipped.
