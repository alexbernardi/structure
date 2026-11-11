# 0009 - Movement Lab 5.2: catch-and-hang, sharp angles, two-handed pull-up, crouch slide

Status: implemented and objectively tested; awaiting the user's playtest. Date: 2026-11-10.
Branch: `benchmark/opus-traversal` (continues tasks [0007](0007-unified-traversal.md), [0008](0008-traversal-refinement.md)).
Scope: `utility/movement/flat-plane/` and workshop records. Design and controls:
[Movement Lab 5](../DOCUMENTATION/MOVEMENT-LAB-5.md) (5.2 section).

## Root causes

- **Extra Space presses.** Scripted jumps at the 1.9 m ledge with one extra press already climbed at every distance
  (0.8-2.4 m runs and standing jumps). The real gap: airborne contact did nothing on its own, and a catch needed a
  press while the ledge was within 0.45 m and the 0.2 s buffer was open. A player who touched the wall first and then
  pressed - after sliding down to the ground - got a jump instead, and needed another jump and press.
- **Sharp angles.** The climb probed one ray along the stick and refused faces more than 50 degrees off it; the
  climb also travelled along the stick, not across the face, and sideways momentum was dropped. Lateral top probes
  sat past a thin fence's back face (0.08 m) and found nothing.
- **Covered wall.** The top probe started inside or below whatever was above the top and reported `too_high`
  instead of `no_headroom`.

## Changes

- `traversal/mantle_action.gd`: `HANG` phase (`begin_hang`, `can_hang`, `drop`); fan of probes (7 directions, all
  face heights), up to three faces tried nearest first, climb square to the face; tangential momentum kept on exit;
  two clips on one physical path (ClimbUp_1m quick climb, ClimbUp_2m pull-up from its grip frame); top probe from
  under any overhead geometry; TOP_INSET 0.04 m; hang-drop allowance 1.9 m.
- `traversal/pullup_clip.gd` (root keys and audited contacts), `tools/audit_pullup_clip.gd`.
- `traversal/traversal_controller.gd`: catch on contact (only on ticks the airborne body slides along a wall-like
  surface) into the hang; hang input (one press pulls up, crouch or stick back lets go, refused climbs keep the hang
  and say why); `_authorize(..., needs_press)`; crouch slide (`_try_slide`, `_slide_tick`, `_end_slide`), slide on
  landing with crouch held.
- `character/character_body.gd`: `height_override`, `can_rise_to()`.
- `capability/movement_attributes.gd`: slide attributes (min speed, boost, friction, drag, steer, slope gain, end
  speed, max speed, height), stamina per slide, `slide` capability.
- `animation/authored_animation.gd`: Pullup, SlideStart/SlideLoop/SlideExit states (authored, seeked by their
  action's clock; slide playback follows slide speed); two-handed grip IK on the lip from the authored grip frame;
  generic transitions between all traversal states.
- Assets: `UAL2_Climb.glb` re-extracted with ClimbUp_2m and the three slide clips (byte-verified tool); provenance
  updated.
- Course lanes I (fences 30/45/60/75 degrees, 7 m long), J (2.2/2.6 m walls, thin 2.4 m, covered 2.6 m, 3.0 m),
  K (slide: bars with 1.0 m clearance, 12 degree ramps), L (vault, mantle, pull-up, slide in one run).
- Overlay/readout: HANGING and SLIDE states with their controls.
- Tests: `tests/test_traversal_52.gd` (7), two one-press probes in `tests/test_traversal_refinement.gd`.

## Validation

- All `test_traversal*` suites (vault, intent, refinement, 5.2): **46/46**.
- Hang: 2.2 and 2.6 m walls caught on contact, held while Space is only held, one press pulls up; exactly two presses
  in all; both hands pinned within 3 cm of the lip while hanging; no overlap or snap (largest step under 0.15 m);
  back to locomotion on top. An early second press climbs directly; crouch lets go; the covered wall is refused for
  headroom; the thin 2.4 m wall is pulled over; 3.0 m: human out of reach, cybernetic caught and climbed.
- Fences: 30 degrees vaulted, 45/60/75 degrees climbed over square to the fence with at least 1 m/s kept along it;
  60 degrees from the air by a catch; no overlap.
- Slide: no slide at walking speed; a sprint slide starts above 11 m/s, only slows on flat ground, passes under both
  1.0 m bars (a crouch-walk cannot); never stands into a bar; steering never exceeds slide_steer per tick; shorter
  uphill, faster downhill from a run; a slide jump keeps the slide's speed.
- Combined lane L: vault, mantle, catch, pull-up and slide in one run, no overlap.
- Native Vulkan captures (`tools/capture_traversal.gd` hang, slide): the pull-up shows the chest coming over a 2.6 m
  top with both hands on it; the slide shows the authored low slide pose at 11.7 m/s. Motion quality and feel still
  need the user's playtest.
- Full utility regression: **534 passed, 0 failed** (about 200 s; 5.1 was 525/525).

## Limitations

- No shimmy along the edge, no wall climbing above the hang, no hang from a ledge with no wall below it.
- The climb uses the body's perpendicular foot point on the face: at a fence's end the climb is refused (narrow),
  even when the middle of the fence is a step away.
- Slide is not yet chained into a vault (a crouched body does not vault); the slide collider is a short cylinder,
  not a lying capsule; the authored slide is a low, lying slide (it reads well at sprint speed, less so slow).
- The vault keeps its 35 degree limit; sharper approaches climb over instead (slower than a vault).
- Hanging costs no stamina yet.

## Next steps

Playtest lanes I-L; tune slide friction/drag/steer and the catch-on-contact distance by feel; then slide-to-vault,
shimmy, and stamina drain while hanging.
