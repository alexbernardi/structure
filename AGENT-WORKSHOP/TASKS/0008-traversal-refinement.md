# 0008 - Movement Lab 5.1: vault variation, authorization, airborne climbing

Status: implemented and objectively tested; awaiting the user's playtest. Date: 2026-11-10.
Branch: `benchmark/opus-traversal` (continues task [0007](0007-unified-traversal.md)). Scope: `utility/movement/flat-plane/`
and workshop records. Design and controls: [Movement Lab 5.0 / 5.1](../DOCUMENTATION/MOVEMENT-LAB-5.md).

## Goal and acceptance criteria

1. Consecutive vaults respond to angle, speed, height and stride instead of replaying one pose; hand contact stays
   on its target (under 10 mm) for both hands.
2. No path starts a vault without a new, valid press inside the window: contact, held Space and stale presses never
   do; a missed window has a predictable consequence (the jump).
3. Airborne presses catch reachable ledges (rising, at the apex or falling) and turn into a mantle or a climb-over;
   no automatic launch on contact; respects reach, grip strength, clearance and capabilities.
4. The lane F test bar becomes a solvable, explained challenge through the general system.
5. Existing suites keep passing; new regression tests and diagnostics.

## Root causes found

- Missed window -> mantle: the controller fell through from a refused vault to the mantle; the mantle's standing
  check tested only the centre point, so on the 0.6 m lane B wall the collider overhung the far edge and tipped over.
- Held Space while airborne against a wall triggered a ledge grab (hold-to-grab).
- The test bar: every vault arc intersects the bar (correctly refused `blocked`), and no other move could get over
  a 0.35 m-thin wall, so nothing was possible.
- Airborne face probes started 0.3 m above the feet (missed ledges at foot level); lateral top probes ignored the
  face angle (diagonal ledges read as `narrow`); a flat cylinder on a sloped top read as no standing room.

## Changes

- `traversal/traversal_controller.gd`: `_authorize()` gate and grants; `press_age` (0.3 s hard limit), 0.2 s catch
  buffer; missed-window rule; no hold-to-grab; air press -> catch > air jump > buffer; `catch_preview` for the overlay.
- `traversal/mantle_action.gd`: full-footprint standing room, slope-aware fit and crest, uneven/angled tops, airborne
  probes from 0.1 m to the grip reach, `catch_distance`, `grip_strength`, climb-over (`kind: over`) with a hang-drop
  landing and a clear fall; refuses unauthorized starts.
- `traversal/vault_action.gd`: commit requires the grant; `vaultable_ahead()`; support side from the face angle
  (left-hand plans mirror the obstacle through the unchanged planner, fallback to the other hand); turn and side in
  the presentation.
- `traversal/clip_mirror.gd`, `tools/audit_mirror.gd`; mannequin builds `SafetyVault_Mirror`; profile measures its
  entry/exit phases; `authored_animation.gd`: `VaultMirror` state, left-arm chain, variant choice at takeoff,
  steering to either entry foot, swing-phase body turn, speed pitch, variant-aware exit phase.
- Attributes `catch_distance`, `grip_strength` (cybernetic +0.25 m, +5 m/s).
- Course: lane F test bar documented and labelled; lane H (irregular tops, angled and mixed-height walls).
- Overlay label, catch-reach band, contact points; readout names the support hand.
- Tests: `tests/test_traversal_refinement.gd` (7). Two 5.0 tests updated to the new rules (the 1.9 m ledge needs a
  second press to catch; contact presses are grounded-only); no assertion was relaxed except as stated below.

## Validation

- Reproduction first: the refinement suite failed on the old code (lane B late press -> mantle; held Space -> grab).
- Traversal suites (vault 16, intent 12, refinement 7, 5.1 variation included): **37/37**.
- Variation results (headless, 6 m/s unless stated): lane D square walls alternate right/left hand (3 right, 4 left in
  the native run); +25/-25 degree walls take opposite hands and turn the body by +/-0.26 rad; sprint vaults pitch
  0.12-0.14 rad vs 0.056 at 6 m/s; hand error about 1 mm (left and right) after the turn was moved to the swing phase
  (it was 12-15 mm while the turn acted during the plant). Takeoff entry-foot error: under 0.06 at 6 m/s; under 0.12
  for sprints on lane D's 6 m spacing (0.05-0.10 measured; 4.0's 0.05 bound was for 9 m spacing). The presentation
  reads the real-time interpolation fraction (as in 4.0), so these presentation numbers vary slightly between runs;
  physics is deterministic.
- Native Vulkan captures (`tools/capture_traversal.gd` cases rhythm, angled, bar, catch): both variants render with
  coherent limbs and the hand on the wall (hand error 0.000 m in the readout); the test bar catch-over and the falling
  catch complete. Visual quality and feel are not approved by these frames: they need the user's playtest.
- Full utility regression: **525 passed, 0 failed** (about 194 s; 5.0 was 518/518).

## Limitations

- One authored vault (and its mirror); no new authored vault styles (the package has no other vault clip). Height,
  depth and speed variation is the 4.0 planner's lift/dip/stretch plus the speed pitch.
- Climb-over reuses the running climb clip; no hang, shimmy or drop animation (the fall/land states take over).
- Catches need the stick toward the ledge; catching from a standstill below a ledge works only if the jump reaches it.
- Sprint takeoffs on tight spacing can be about 0.1 gait cycles off the entry foot; the vault crossfade covers it.

## Next steps

Playtest lanes D, F (test bar), H and the 1.9 m / 3.0 m ledges with each profile; tune `catch_distance`, `grip_reach`,
`CATCH_BUFFER`, the turn share and speed pitch by feel.
