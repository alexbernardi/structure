# 0010 - Movement Lab 5.3: crouch flip

Status: implemented and objectively tested; awaiting the user's playtest. Date: 2026-11-10.
Branch: `benchmark/opus-traversal` (follows [0009](0009-hang-angles-slide.md)). Scope: `utility/movement/flat-plane/`
and workshop records. Design and controls: [Movement Lab 5](../DOCUMENTATION/MOVEMENT-LAB-5.md) (5.3 section).

## Request

"Add a flip for when the player hits space mid crouch."

## Design

- Authored motion: UAL2 `JogToFlip` (CC0, the same paid package; a 1.2 s running front flip), added to the
  `UAL2_Climb.glb` extract with the byte-verifying tool. Audit (`tools/audit_flip_clip.gd`): deepest crouch 0.10 s,
  feet off 0.13 s, upside down 0.52 s, toes down 0.80 s with 340 degrees turned, standing 1.10 s. The in-place export
  keeps the hips' own 1.2 m rise (its pelvis track equals the root-motion export's), so the root-motion arc is not used.
- A **physics** flip: Space while crouched (crouch held on the ground, or sliding) jumps at `flip_impulse`, keeps all
  horizontal momentum (a slide's included) and leaves with at least `flip_forward` along the motion / stick / view.
  Gravity, air control and collisions stay the movement core's; the crouch collider stands in for the tucked body.
- The clip's airborne part (0.10-0.80 s) is spread over the real airtime, predicted each tick from the ground below
  (rate clamped 0.6-3x); turned and still falling, the ordinary fall and landing take over.
- Presentation: the drawn character is lowered by the clip's own hip rise, scaled by the flip state's actual blend
  weight (AnimationTree fade), and clamped so the pose actually drawn never puts a foot, hand or the head below the
  ground under the body (push-off: feet stay down while the legs extend).
- Central authorization (`_authorize("flip")`): recent press, capability `flip`, stamina (`stamina_cost_flip` 6),
  standing room (refused under a bar: nothing jumps, the slide goes on). Without the capability or stamina the press is
  the ordinary jump / slide jump. Presses while upside down (before 0.70 s) buffer; one inside the jump buffer before
  the landing chains another flip.

## Changes

- `traversal/flip_clip.gd` (measured hips and lowest-point tables, phases, `drawn_drop`), `tools/audit_flip_clip.gd`.
- `traversal/traversal_controller.gd`: `_try_flip`, `_flip_observe` (airtime-tracked clock), `_time_to_ground`, flip
  presentation (`time`, `heading`, `drop`, `height`), buffered presses while upside down, cost, cancel.
- `animation/authored_animation.gd`: `Flip` state seeked by the flip clock, heading locked to the flip direction, no
  foot correction while flipping, `_state_weight()` and the drawn-pose ground clamp (`flip_drop` telemetry).
- `capability/movement_attributes.gd`: `flip_impulse`, `flip_forward`, `stamina_cost_flip`, base capability `flip`;
  `movement_profiles.gd`: cybernetic +1.5 m/s flip impulse, sprained ankle revokes `flip`.
- `character/authored_mannequin.gd`: loads `JogToFlip`. Asset re-extracted (1,518,000 bytes, sha256 `f8cad083...cc7c`),
  provenance updated.
- `world/flat_plane_world.gd`: lane M (`lane_m`, `lane_m_deck`). Readout / overlay: FLIP state, "CROUCH Space: FLIP",
  "SLIDE ... Space: FLIP". `tools/capture_traversal.gd`: `flip`, `slideflip` cases.
- Tests: `tests/test_traversal_flip.gd` (4); the 5.2 slide-jump test's comment notes that the press is now a slide flip.

## Validation

- `tests/test_traversal_flip.gd` 4/4: standing Space is a jump, crouch + Space flips (take-off at flip_impulse, 2 m/s
  forward, turn complete at the landing, `Flip` state shown, drawn feet never more than 6 cm below the ground, no snap
  in the drawn hips relative to the body, costs stamina, along the view); slide flip keeps the slide's 11.8 m/s and
  turns fully; an injured body's crouched press is the plain slide jump; off the 1.0 m deck the flight is 0.78 s and
  onto the 0.5 m box 0.58 s (flat 0.66 s), both fully turned and landing where expected; refused under the 1.0 m bar
  (`flip: no_headroom`, nothing jumps, the slide goes on); a press upside down is `buffered`; one just before the
  landing chains a second flip.
- All `test_traversal*` suites: **50/50** (46 earlier + 4).
- Native Vulkan captures (`tools/capture_traversal.gd --case=flip / slideflip`), inspected as contact sheets: the
  standing flip pushes up out of the crouch, dives forward, passes upside down around 0.5 s and comes round to about
  320 degrees by 0.74 s, with the shadow showing the body's own arc; the slide flip pops up from the lying slide pose
  and turns fully while covering about 7.8 m. Feel, timing and the 0.12 s blend out of the slide still need the user's
  playtest.
- Full utility regression: **538 passed, 0 failed** (about 206 s; 5.2 was 534/534).
- `structure.py check`: only the 20 pre-existing broken links to ignored `.runtime/` 4.0 evidence.

## Limitations

- Front flip only (one authored clip): no back or side flips; the flip direction is fixed at take-off (air control
  moves the body, the turn keeps its heading).
- The collider during the flip is the crouch cylinder, not the tucked body: next to a bar or wall the drawn hands or
  head can pass through it. A capture pressed just before lane K's bar flew over it.
- The blend from the lying slide pose to the flip's upright push-off is 0.12 s (the traversal transition response).
- A chained flip re-seeks the same `Flip` state from its landing pose to the take-off crouch without a crossfade (both
  crouched poses; not yet inspected in motion).

## Next steps

Playtest lane M and a flip out of a sprint slide on lane K; tune `flip_impulse` / `flip_forward` by feel; consider a
back flip (crouch + Space + stick back) if a suitable authored clip is available.
