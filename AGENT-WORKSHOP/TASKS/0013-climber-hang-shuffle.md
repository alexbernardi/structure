# 0013 - Movement Lab 5.6: climber hang posture, coordinated shuffle, leg jitter

Status: implemented and objectively tested; awaiting the user's playtest. Date: 2026-11-11.
Branch: `benchmark/opus-traversal` (follows [0012](0012-skeleton-ik-corners.md)). Scope: `utility/movement/flat-plane/`
and workshop records.

## Request (summary)

From the user's playtest of lane O (with a rock-climber reference photo): the braced hang posture is wrong - it should be
the efficient climber position (arms straight, hips in near the wall, legs long with the knees turned out, toes on the
wall); work on the hanging shuffle; the legs glitch back and forth.

## Findings (measured: a per-frame trace of the drawn feet on lane N, idle then shimmying both ways)

- Leg jitter: while shimmying the leading foot re-steps every 0.2 s (it trails the 0.16 m trigger again the moment a
  step ends), each step swinging it 10 cm off the wall and back: 5 Hz in-out pumping. The `break` after the first foot
  that wants a step always picks the same foot, so the other is never re-planted: it hangs stretched toward its old
  place (0.3 m off the wall, rising 0.6 m) and snaps 12 cm in one frame when the shimmy stops.
- A foot whose contact flickers (reach limit) jumps between the wall and the dangle instantly (no per-foot blend).
- The hips bob about 3 cm at the hand-step rate: the body hangs from the mean of the drawn hands, including the lifted one.
- Posture: the grip frame's lean correction pivots the whole body about the hands, so the hips end 0.5 m out with the
  knees up at the chest and the shins down the wall - not the reference's position.

## Plan

1. Braced posture: shoulders at a straight arm's length below the lip, the torso pitched (about the shoulders) so the
   hips sit about 0.25 m from the face; head / chest clearance handled by moving the shoulders out, not the hips. The
   feet staggered (one higher, one lower; knees bent about 115 and 150 degrees), knees turned out to the sides, each
   foot pointing into the wall with its toes on the face (the foot oriented from the sole geometry, heel slightly low).
2. A coordinated shuffle: one gait cycle per stride of travel along the lip (lead hand, lead foot, trail hand, trail
   foot), each limb stepping to its slot plus half a stride; steps finish by time when the shimmy stops, then limbs
   re-centre one at a time; a hand never reaches past the real ledge end. The body hangs from the planted hands (no
   bob from a lifted hand). Per-foot brace weights blend a foot that loses or finds the wall.
3. Tests: no foot reversal jitter and no frame jumps while idle and shimmying, every foot re-planted during a shimmy,
   the posture numbers (hips in, feet staggered, knees out, toes on the wall), existing hang / corner suites still pass.

## Changes

- `animation/authored_animation.gd`:
  - braced body (`_braced_body`): shoulders `BRACE_SHOULDER_OUT` 0.38 m out at `BRACE_ARM` 0.98, squared to the hands
    (the authored grip frame's shoulder twist removed), torso pitched about the shoulders to `BRACE_HIP_OUT` 0.30 m,
    head / chest clearance by moving the shoulders out (`_into_face`); blended with the dangle by the brace weight;
  - hang height from the shuffle's widest spread (`_hand_spread`) for the braced and the dangling hang;
  - feet (`_brace_feet`, `_foot_contact`, `_braced_foot_basis`, `_foot_frame`, `_knee_pole`): staggered knee angles
    (105 / 150 degrees) solved for the ankle height, toes on the face, foot into the wall (turned out 18 degrees,
    heel 12 degrees low), ankle under its hip, knee forward as far as it clears the face (9 cm) then turned out;
    per-foot brace weights (`_foot_w`); foot moves `foot_moves` per side;
  - the shuffle (`_advance_gait`, `_step_time`, `_shuffle_lead`, `_move_hands`, `_start_hand_step`, `_top_under`,
    `_start_foot_step`, `_hand_rest`): a 0.32 m stride cycle, quarter-cycle events, half-a-stride leads, a hand queue,
    catch-up and settle; the body hangs from `_hand_rest` (no lifted-hand bob);
  - removed: `STEP_TRIGGER`, `STEP_TIME`, `STEP_OVERSHOOT`, `FOOT_STEP_TRIGGER`, `FOOT_STEP_TIME`, `BRACE_BELOW_HIP`,
    `FOOT_BRACE_OFF`, `BRACE_SHOULDER_OFF` (the event-triggered stepping and the knees-up brace).
- `capability/movement_attributes.gd`, `traversal/mantle_action.gd`: `shimmy_speed` default 0.6 m/s (was 0.9).
- `tools/capture_traversal.gd`: `--view=body` and `--view=legs`.
- Tests: `tests/test_traversal_56.gd` (2); `test_traversal_55.gd` braced-hang assertions updated to the new posture.

## Validation

- `tests/test_traversal_56.gd` 2/2. Still hang on lane N: both feet braced; hip joints 0.35 m from the face; toes on
  it (within 1.0 cm); each foot points into the wall (0.93); left foot 0.17 m above the right; knees 0.10 m clear of
  the face and turned out (3 cm past their hips); arms at 0.92 of their length, alike (difference 0.0002); the feet
  still (0.02 mm). Shuffling right then left: no foot reversal, largest foot move 3.4 cm per frame, 14 moves per foot,
  hands alternate (`RLRL...`, 3 repeats at the reversal and the settle), never both hands off, hips level within 0.3 mm,
  no pull, arms at least 0.91; released, everything settled in 0.18 s with no leg stretched (0.97 of its length).
- Before the fix (same trace): the leading foot pumped off the wall 5 times a second, the other foot hung stretched
  0.3 m off it and snapped 12 cm, the hips bobbed 3-12 cm.
- All `test_traversal*` suites: 63/63 on an unloaded run; under load `test_traversal_vault`
  `test_cameras_follow_the_vault_travel_without_hump_or_dip` fails on lane C's side-camera ease (0.013-0.016 m step
  against 0.012, real frame time); the 5.5 commit fails it the same way under the same load (checked in a temporary
  worktree: 0.0126 / 0.0136 m), so it is not caused by this change (KI-024).
- Full utility regression: 550 passed, 1 failed (that camera test), 217 s.
- `structure.py check`: only the 20 pre-existing broken links to the ignored `.runtime/` 4.0 evidence.
- Native Vulkan captures inspected (`hang3` body / back / legs, skeleton and solid; `corner` back / body): upright
  near the wall with the arms up and nearly straight, the feet staggered with the toes on the face, the high knee
  turned out; the same posture reaching for and turning round the outside corner. Feel still needs the user's playtest.

## Limitations

- The stagger is fixed (left foot high); it does not swap with the direction of travel.
- Stride, timing and leads are tuned by measurement and stills, not yet by feel.
- The torso's twist and lean come from one authored grip frame, squared up procedurally; there is no authored hang.

## Next steps

Playtest lanes N and O; tune `SHUFFLE_STRIDE`, `BRACE_HIP_OUT`, the knee angles and `shimmy_speed` by feel; consider
swapping the high foot with the direction of travel.
