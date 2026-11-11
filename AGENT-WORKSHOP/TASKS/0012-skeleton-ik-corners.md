# 0012 - Movement Lab 5.5: skeleton overlay, terrain foot IK, braced hang, corners

Status: implemented and objectively tested; awaiting the user's playtest. Date: 2026-11-11.
Branch: `benchmark/opus-traversal` (follows [0011](0011-hang-reach-shimmy.md)). Scope: `utility/movement/flat-plane/`
and workshop records. Design and controls: [Movement Lab 5](../DOCUMENTATION/MOVEMENT-LAB-5.md) (5.5 section).

## Request (summary)

Biomechanical stick-skeleton view of the real runtime skeleton with the body at 40 % opacity (toggleable); better
foot IK (steps, slopes, uneven ground, landings, braced hanging) and hand IK (ledges, mantles, catches, pull-ups,
asymmetric corner grips); an athletic hang with the feet braced on the wall; hanging traversal around outside and
inside corners (no teleport, invalid corners rejected); test lanes and debug markers; preserve everything.

## Findings

- Foot IK assumed a flat floor at the character's root: it only lifted a sinking foot (10 cm cap), kept the authored
  foot angle, never moved the pelvis.
- The authored ClimbUp_2m grip frame is a braced climber pose; 5.4 replaced its legs with a dangle.
- The shimmy stopped at every face end. The stick is camera-relative, so after any turn "right" would point away from
  the new wall (a let-go).
- The quick mantle (ClimbUp_1m) had no hand IK; its left hand plants 0.167-0.333 s (audit).

## Changes

- `animation/skeleton_overlay.gd` (new): joints / rods of the real skeleton from `skeleton_updated` (final pose),
  colour-coded sides, larger hands and feet with finger pointers, no depth test. `authored_mannequin.set_body_alpha`
  (40 %, depth pre-pass). `flat_plane.toggle_skeleton_view` (K, `--skeleton-view`), help line.
- `animation/authored_animation.gd`:
  - terrain foot IK (`_terrain`): heel / toe / swing-lookahead rays, fast-rise / eased-fall smoothing, pelvis drop,
    stance-weighted tilt to the surface (35 degree limit), and a per-sole-corner guard against sinking; the flat-ground
    correction and its bound are unchanged;
  - braced hang (`_brace_feet`): contacts 0.65 m below the hip by rays, ankle 8 cm off the wall, knees up (pole), brace
    blend after the catch, stiffer and more damped swing when braced, shoulders 8 cm further out, feet stepping;
    dangle fallback;
  - hands on a two-wall lip path round corners (`_hand_slot`, `_path_point`, `_path_x`), each hand oriented to its own
    wall; a planted hand beyond reach pulls the body toward it (any direction);
  - quick-mantle hand pin (`_mantle_hand`): held where it lands, palm on the real top, authored wrist rise kept,
    released as the arm straightens;
  - `debug_contacts` (hand / foot targets, normals, lip path, ground), `final_knees`, telemetry.
- `traversal/mantle_action.gd`: corners (`_try_corner`, `_arc`, `_advance_turn`, `_forget_corner_behind`): inside /
  outside detection, 25-135 degree turns, new-ledge check, collider samples along the arc, committed arc with the
  facing turning, refusal reasons; `ledge_top` takes a direction; presentation carries `corner` and `turning`.
- `traversal/traversal_controller.gd`: the hang stick is latched in the ledge frame it was first pushed in.
- `traversal/mantle_clip.gd`: `HAND_PLANTED`, `HAND_OFF` from the audit.
- `traversal/vault_debug.gd`: contact markers and the hang hint (braced / dangling, turning, why stopped).
- `world/flat_plane_world.gd`: lane N's flush 3.6 m block, lanes O and P.
- `tools/capture_traversal.gd`: `--skeleton`, cases `corner`, `stairs`, `step`; the hand camera turns with the wall.
- Tests: `tests/test_traversal_55.gd` (6); `test_traversal_hang.gd` updated (the long wall now ends at a lip step;
  braced arms bend slightly more).

## Validation

- `tests/test_traversal_55.gd` 6/6: the skeleton view draws the hands where the IK put them (0.00000 m) through 26
  body parts at 40 %, and K again restores the solid body; standing across the 0.2 m step each sole on its own level
  (0.000 m) with the pelvis down 0.20 m; on the 15 degree slope the feet lie on it (0.1 degrees from its normal);
  flat ground unchanged; no sole corner sinks into a tread or a pad (0.0000 m / 0.0001 m); braced hang: both feet on
  the wall, ankles 8-10 cm off it, hips 0.50 m out, knees 0.44 m above the feet and 9 cm off the wall, hands on the lip;
  under the shelf nothing to brace on, the body dangles; outside corner: hung around (an arc, largest step 7.5 mm),
  hands 90 degrees apart at the corner, grip within 3 cm all the way, no overlap, then on along the north face and
  pulled up from it; inside corner: turned to face the second wall and on along it; the thin wall's corner refused
  with the hang kept; the quick mantle's left hand planted 18 frames, palm 1.4 cm above the top, no drift, error 0.1 mm.
- All `test_traversal*` suites: **61/61**.
- Native Vulkan captures (`--skeleton`, inspected): the braced hang in profile (knees forward and up, feet on the wall,
  hips out, arms to the lip); the corner from behind (left hand on the west face, right hand round on the north face,
  body turning between them); walking the stairs (feet landing on the treads; the view is too distant for detail).
  Feel still needs the user's playtest.
- Full utility regression: **549 passed, 0 failed** (about 217 s; 5.4 was 543/543).

## Limitations

- A corner is one committed arc (reversing the stick mid-corner does not turn back); one corner at a time, at the
  hang's height only (no climbing up or down a corner).
- The braced feet use one fixed height below the hip; the stair test walks up only.
- The capture camera jumps round with the wall at a corner (presentation of the capture tool only).
- Rigid hands (23-bone mannequin): the palm lies on the top instead of fingers curling.

## Next steps

Playtest lanes O and P with K and F10 on; tune the brace height and knee pole by feel; descend stairs in a test; allow
reversing out of a corner; vertical moves along corners (climbing up / down).
