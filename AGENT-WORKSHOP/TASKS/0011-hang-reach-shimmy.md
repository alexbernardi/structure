# 0011 - Movement Lab 5.4: reach from the body, hand placement, dangling hang, shimmy

Status: implemented and objectively tested; awaiting the user's playtest. Date: 2026-11-11.
Branch: `benchmark/opus-traversal` (follows [0010](0010-crouch-flip.md)). Scope: `utility/movement/flat-plane/`
and workshop records. Design and controls: [Movement Lab 5](../DOCUMENTATION/MOVEMENT-LAB-5.md) (5.4 section).

## Request

"3 m should be normal human and that should be determined by where the hands could land, so dependent upon jump power
and height of the model. Can the model feel like rag doll when hanging and can you skirt left and right? Focus on
getting the hand bones properly placed for hanging."

## Findings

- The catch limit was a fixed `grip_reach` of 2.1 m above the feet, unrelated to the body.
- Mannequin (`tools/audit_hand_reach.gd`): shoulders 1.587 m, upper arm 0.302 m, forearm 0.300 m, so the wrist reaches
  2.19 m above the soles with the arm straight up. Hand bone frame: +Y to the fingers, +Z the palm.
- The hand mesh was an ellipsoid centred on the wrist with its long axis across the arm (15 cm wide, 10 cm long).
- No hang or shimmy clip exists in UAL1 or UAL2 (all 43 + 134 clips listed; `GetOffWall_2m` is a hop off a wall top).

## Changes

- **Reach** (`traversal/mantle_action.gd`): `hand_reach(body)` = stand height x `REACH_RATIO` 1.306 + `grip_reach`
  (now the extra reach of an upgrade, default 0; cybernetic +0.25, spell +0.3), evaluated from the body's position so
  the jump decides it; `base_hand_reach` for powered moves; a pull-up from a hang is never powered (the catch was the
  reach). Overlay reach band uses it. Lanes E and J: the "upgrades only" ledges are 3.6 m; lane J's 3.0 m wall is
  the human-reach wall.
- **Hang depth**: the collider hangs at arm's length (`hand_reach - DANGLE_SLACK` 0.12, 2.23 m for the human) where
  there is room, else as low as the ground allows (never above the authored grip); the pull-up from a deeper hang
  spreads its warp over a longer start.
- **Shimmy** (`mantle_action._shimmy`, `ledge_top`): `shimmy_wish` from the stick along the ledge (dead zone 0.35, set
  in `traversal_controller._hang_input`), `shimmy_speed` attribute (0.9 m/s), 5 m/s^2; moves only while the top and a
  wall-like face continue under the leading hand + 8 cm at the same height and the collider can move; else stops
  (`shimmy_block` "end" / "blocked"). The hang's plan origin follows, so a press pulls up from the new place.
- **Drawn hang** (`animation/authored_animation.gd` `_hang` and helpers): hand places found by rays per hand (top and
  face), wrist 4.5 cm out / 2.4 cm up, palm-down fingers-over orientation through the foot-orientation modifier, arm IK
  with elbows out and back; body placed from the hands (shoulders at 0.97 of the arm, 0.22 m off the wall, pitched out
  until head and chest clear the face); pendulum swing (pitch, bounce off the wall; sideways as a parallelogram with
  a third of the tilt); legs on a soft hip (spring 60, damping 5) via the leg IK, off the wall and the ground; spread
  hands lift the body so planted wrists stay within reach; hands step one at a time with a lift and a small overshoot;
  blend in and out over 0.15 s; telemetry `hang_swing`, `hand_steps`, `two_hands_moving`, `final_hands`.
- **Hand mesh** (`character/authored_mannequin.gd`): from the wrist toward the fingers, 19 x 9 x 4.4 cm.
- Course lane N; capture case `hang3` (`--view=side|back|close|profile`, own camera on the hands, overlay off);
  `tools/audit_hand_reach.gd`; tests `tests/test_traversal_hang.gd` (5); reach tests in `test_traversal_intent.gd` and
  `test_traversal_52.gd` moved to 3.6 m with a new "human catches 3.0 m" case.

## Validation

- `tests/test_traversal_hang.gd` 5/5: the reach model matches the skeleton (wrist overhead 2.190 m + 0.16 vs 2.351 m);
  a 0.2 m shorter body reaches 0.26 m less; a human jump catches 3.0 m and the sprained ankle's jump does not; hanging,
  both wrists on their grip points (error 0.000 m after the lift), 1.5-2.4 cm above the top and 4.5-5.0 cm out from
  the face, fingers and palm aligned (cos 1.00), arms at >= 0.91 of their length, head 5 cm off the wall, feet 35 cm off
  the wall and 1.0 m off the ground; the catch swings the body out 0.064 rad and it settles (0.0001 rad after 3.5 s); a
  shimmy swings it 0.24 rad sideways; the legs lag 0.07 rad; the shimmy runs at 0.90 m/s, stops 0.32 m short of the
  wall's end with both hands on it (`end`), comes back, 28 hand moves, never both hands off, grip error 0.000 m, then
  pulls up from the new place; hang depth 2.23 m on the 3.0 and 2.6 m walls (feet 0.37 m up on the 2.6 m wall).
- All `test_traversal*` suites: **55/55**.
- Native Vulkan captures (`--case=hang3`, inspected): profile shows the forearm rising to the lip, the wrist bent over
  the edge and the hand flat on the top into the wall; the side view shows the catch swing out and back and the body
  hanging angled out from the hands, head clear; the back view shows the hands moving alternately along the lip, the
  legs swinging sideways after the body with the torso nearly level, and the stop at the wall's end. Feel still needs
  the user's playtest.
- Full utility regression: **543 passed, 0 failed** (about 215 s; 5.3 was 538/538). A first run alongside the native
  captures had one timing failure (legacy `test_body_dynamics` cost 82.2 us vs an 80 us budget under that load); it
  passed alone twice and the unloaded full run is clean.

## Limitations

- The hang pose is procedural on the pull-up's grip frame (no authored hang or shimmy clip in UAL1/UAL2); the swing is
  spring-damped secondary motion, not a physics ragdoll.
- Rigid hands (the 23-bone mannequin has no fingers): the palm lies on the top instead of the fingers curling over.
- The shimmy stops at corners and gaps (no turning a corner, no hop across a gap); hanging and shimmying cost no
  stamina.
- One arm hangs a little straighter than the other (the authored grip pose is slightly asymmetric).

## Next steps

Playtest lane N (catch, hang, shimmy to the end, pull up) and lane J (3.0 m human, 3.6 m cybernetic); tune the swing
(`SWING_*`, `LEG_*`) and `shimmy_speed` by feel; then corner shimmy, a hop across short gaps, and stamina while hanging.
