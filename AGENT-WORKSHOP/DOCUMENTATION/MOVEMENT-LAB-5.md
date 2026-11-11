# Movement Lab 5.0 - unified, intentional, upgradeable traversal

Branch: `benchmark/opus-traversal`. Tasks: [0007](../TASKS/0007-unified-traversal.md) (5.0),
[0008](../TASKS/0008-traversal-refinement.md) (5.1), [0009](../TASKS/0009-hang-angles-slide.md) (5.2),
[0010](../TASKS/0010-crouch-flip.md) (5.3), [0011](../TASKS/0011-hang-reach-shimmy.md) (5.4), [0012](../TASKS/0012-skeleton-ik-corners.md) (5.5),
[0013](../TASKS/0013-climber-hang-shuffle.md) (5.6). Builds on the [4.0 vault](MOVEMENT-LAB-4.md) and the approved
[3.0 authored locomotion](MOVEMENT-LAB-3.md); both are preserved.

## 5.6: the climber's hang, the hanging shuffle, no leg jitter

Task [0013](../TASKS/0013-climber-hang-shuffle.md). From the user's playtest with a rock-climber reference.

- **The climber's efficient position (braced).** Arms straight and alike: the shoulders hang a straight arm below the
  lip 0.38 m from the face, squared to the hands (the authored grip frame twists them; braced they line up level with
  the hands) at the height that still reaches the shuffle's widest spread. The torso pitches about the shoulders so the
  hip joints sit 0.30 m from the face: in close, the weight on the feet; if the head or chest would touch the face the
  shoulders lean out, not the hips. The feet are staggered (the left knee bent to 105 degrees, the right to 150), each
  on its own wall contact below its hip with the toes on the face (1 cm off), the foot pointing into the wall, turned
  out 18 degrees, heel 12 degrees low (oriented from the mannequin's sole geometry); each knee goes forward over its
  foot as far as it clears the face by 9 cm and turns out to its own side beyond that. A foot that finds or loses the
  wall blends (no snapping). Where nothing is in reach (under a shelf) it dangles as before.
- **The hanging shuffle.** One gait cycle per 0.32 m of travel along the lip: lead hand, lead foot, trail hand, trail
  foot (the lead side is the side of travel). Each limb moves once a cycle to where it is centred on its place over the
  cycle - the lead hand reaches ahead, the trail hand gathers up to it - never past the real ledge end (the reach
  shortens until the top is under the hand), and never both hands at once (a turn that comes while the other hand is
  moving waits for it). Limbs trailing too far move out of turn; once the stick is released they re-centre one at a
  time. The body hangs from the hands' places on the lip (not a lifted hand), so it no longer bobs. Default
  `shimmy_speed` 0.6 m/s (was 0.9: four limb moves every 0.36 s was a scramble).
- **Leg jitter (fixed).** The 5.5 brace re-stepped the leading foot every 0.2 s (a 5 Hz in-out pump off the wall) and
  never re-planted the other foot, which then hung stretched toward its old place and snapped 12 cm when the shimmy
  stopped; the body bobbed about 3 cm with each hand move (it hung from the lifted hand) and up to 12 cm where a spread
  hand was out of reach. Measured after: no foot reversal, largest frame move 3.4 cm, the hips level within 1 mm.
- **Reach and match; legs round corners** (follow-up). The lead hand reaches 0.40 m past the hang point and the trail
  hand matches up 0.12 m from it (hands 0.12-0.69 m apart over a 0.45 m stride). Round a corner the feet keep their
  walls until they can step on (contacts on the body's wall, the corner's walls, then the foot's own), stay braced
  while in reach, move one at a time and bow out round an outside corner; the ground is found under the hips (from
  the hands it found the block's top and the legs flew up to it).
- Tools: `capture_traversal.gd --view=body` (the whole climber in profile) and `--view=legs` (hips and feet on the wall).

## 5.5: skeleton view, foot IK on real ground, braced hang, corners

Task [0012](../TASKS/0012-skeleton-ik-corners.md).

- **Skeleton view (K, `--skeleton-view`).** The real runtime skeleton drawn from its final pose on every skeleton
  update (after the clips, the IK and every correction - a test checks the drawn hands against the IK result):
  joints as spheres, bones as rods, left limbs orange, right cyan, pelvis / spine / head white, hands and feet larger
  with a finger pointer; drawn through the body, which switches to 40 % opacity (depth pre-pass, so the silhouette
  stays one clean shape). F10 adds the contact markers: hand IK targets with the wall each hand grips (yellow), braced
  foot contacts with the wall normal (green), the lip path (magenta), the arc round a corner (purple), the ground under
  each foot with its normal (blue); the label says braced / dangling, turning a corner, or why a shimmy stopped.
- **Foot IK on real ground.** Under each foot a ray finds the real surface under the heel, the toes and (for a swinging
  foot) just ahead of the toes; the authored swing height is kept above it; rising ground is taken quickly and
  falling ground eased; the pelvis drops so the lower foot reaches (standing across a 0.2 m step: both soles on their
  own level, pelvis -0.20 m); planted feet tilt to the surface (stance-weighted, up to 35 degrees); finally no sole
  corner may sit below its own ground (a sole across a step edge is held by the higher tread). On flat ground it
  changes nothing.
- **Braced hang** (posture and foot stepping replaced in 5.6). The feet come up onto the wall like a climber's: each foot on a real wall contact found by a ray
  0.65 m below its hip, ankle 8 cm off the wall, knees up toward the chest; the brace comes in just after the catch,
  steadies the swing out from the wall and holds the shoulders 8 cm further out; feet move one at a time along the
  wall while shimmying and re-plant on the new wall round a corner. Where there is no wall within a leg's reach
  (under a shelf) the body dangles as in 5.4.
- **Corners.** When the ledge does not go on straight under the leading hand, the shimmy looks for an inside corner
  (a wall across the path) or an outside corner (the face's end face); the new wall must be turned 25-135 degrees, its
  top must go on at the same height past the leading hand, and the collider must fit at eight points along the arc.
  The hang point then travels that arc while the body turns to the new wall (no teleport); the hands follow a two-wall
  lip path, so for a moment each grips a different wall (asymmetric grip, each hand oriented to its own wall); a hand
  left behind pulls the body toward it. Refused corners keep the hang (`corner_angle`, `corner_ledge`,
  `corner_blocked`). The stick is read in the ledge frame it was first pushed in until released, so holding "right"
  goes round the corner and on along the next wall.
- **Mantle hand.** The quick mantle's planted left hand is held where it landed along the ledge, palm on the real top,
  keeping the authored wrist rise, and lets go as its arm straightens.
- Lanes: N (its +z end now meets a flush 3.6 m block: the lip steps up and the shimmy stops), O (`lane_o`,
  `lane_o_inside`, `lane_o_thin`, `lane_o_shelf`: a free-standing block, an inside L, a thin wall whose end refuses, a
  shelf over a recessed wall), P (`lane_p`, `lane_p_step`: uneven pads, a 0.2 m step, 0.15 m stairs, a 15 degree slope).

## 5.4: reach from the body, hands on the lip, dangling hang, shimmy

Task [0011](../TASKS/0011-hang-reach-shimmy.md).

- **Reach comes from the body and the jump.** The hands catch a top up to the body's overhead reach above wherever the
  jump has put the feet: stand height x 1.306 (the 1.8 m mannequin's wrist reaches 2.19 m with the arm straight up,
  + 0.08 m of fingers over the lip + 0.08 m of shoulder stretch = 2.35 m; a test checks it against the skeleton) +
  `grip_reach`, now the extra reach of an upgrade (0 for a human, +0.25 cybernetic, +0.3 spell). A standing jump's
  0.77 m apex puts a 3.0 m lip in reach; the sprained ankle's weaker jump does not; a shorter body reaches less. The
  "upgrades only" ledges on lanes E and J are now 3.6 m.
- **Hands on the lip.** Each hand's place is found by rays at that hand (the real top just past the face, and the
  face): wrist 4.5 cm out from the face and 2.4 cm above the top, fingers over the top pointing into the wall, palm
  down; the arms reach up to them (elbows out and back). The mannequin's hand mesh was fixed: it was centred on the
  wrist with its long axis across the arm; it now runs from the wrist toward the fingers.
- **Dangling hang (procedural, presentation only).** No hang clip exists in either library, so the pull-up's grip
  frame is placed and corrected: the body hangs from the hands at arm's length, pitched out about the hands until the
  head and chest clear the face; a damped pendulum swing (set going by the catch, bouncing off the wall, about 0.37 Hz)
  pitches it out from the wall, and starting or stopping a shimmy swings it sideways as a parallelogram (both arms
  together, the torso tilting a third as much); the legs follow through a soft hip, kept off the wall and the
  ground. Spread hands pull the drawn body up so each planted wrist stays within its arm. The collider hangs at arm's
  length where there is room (2.23 m below the top for the human), else as low as the ground allows.
- **Shimmy.** While hanging, stick left / right moves along the ledge at `shimmy_speed` (0.9 m/s), only while the top
  and the face continue under the leading hand and 8 cm beyond at the same height, and the body has room; at a wall's
  end or a gap it stops (the overlay's hang line stays). Hands move one at a time, the trailing one first set off as
  the leading hand, lifting off and reaching a little ahead. One press pulls up from wherever the hang has moved to.
- Lane `lane_n`: a 3.0 m wall 8 m long, a 0.6 m gap and a 4 m wall, a 2.6 m wall.

## 5.3: crouch flip

Task [0010](../TASKS/0010-crouch-flip.md). **Space while crouched** - Ctrl held on the ground (standing still or
crouch-walking), or during a slide - is a front flip (authored UAL2 `JogToFlip`). Space standing up is still the
ordinary jump; without the `flip` capability (the sprained ankle revokes it) a crouched press is the ordinary jump or
slide jump, as before.

- **Physics, not a scripted path:** a jump at `flip_impulse` (6.5 m/s: about 1.05 m of rise and 0.66 s in the air)
  that keeps all horizontal momentum (a sprint slide flips at 11.8 m/s) and leaves with at least `flip_forward`
  (2 m/s) along the facing - the motion, or the stick, or the view when standing still. Gravity, air control and
  collisions stay the movement core's.
- **The turn follows the airtime:** each tick the time to the ground below is predicted and the clip's airborne part
  (0.10-0.80 s) is spread over it, so a flip off the 1.0 m deck turns slower (0.78 s) and one onto the 0.5 m box faster
  (0.58 s), both upright on landing. Turned and still falling (a long drop): the ordinary fall and landing take over.
- **Height belongs to the body:** the in-place clip lifts its own hips 1.2 m; the drawn character is lowered by that
  rise (by the flip pose's blend weight), never so far that the pose actually drawn puts a foot, hand or the head
  below the ground under the body - during the push-off the feet stay down while the legs extend.
- **Rules:** central authorization (recent press, capability, stamina 6, standing room: under the 1.0 m bars the press
  is refused and the slide goes on); presses while upside down are buffered (no catch or air jump) and one inside the
  jump buffer before the landing chains the next flip (crouch still held); crouch held through a fast landing slides.
- New attributes `flip_impulse`, `flip_forward`, `stamina_cost_flip`, capability `flip`; the cybernetic legs add 1.5 m/s
  of flip impulse. Lane `lane_m` (also `lane_m_deck`): open ground, a 1.0 m deck to flip off, a 0.5 m box to flip
  onto, a 1.0 m bar (no room).

## 5.2: catch-and-hang, sharp angles, two-handed pull-up, crouch slide

Task [0009](../TASKS/0009-hang-angles-slide.md). How to use each move:

| Move | Input | Notes |
|---|---|---|
| Catch and hang | jump into a high edge (top at least 1.5 m above the feet, hanging feet clear of the ground); no press | both hands grip the lip (authored `ClimbUp_2m` grip frame, two-hand IK); Ctrl or stick back lets go; 5.4: stick left / right shimmies |
| Pull up | Space once while hanging | `ClimbUp_2m` pull-up and step over onto the top, or over a thin top and down the far side; refused climbs keep the hang and say why |
| Early catch | Space in the air as the body reaches the edge | climbs at once (no hang), the press is never lost |
| Fence / sharp angle | Space near it, or in the air near it | vault up to 35 degrees; beyond, climb over square to the face keeping the speed along it |
| Slide | Ctrl while running at 4.5 m/s or more (or Ctrl held through a landing) | runs on momentum: drag, slope gravity, limited steering; 0.8 m collider; Space: slide jump (5.3: a slide flip); release Ctrl to stand where there is room |

New attributes: `slide_min_speed`, `slide_boost`, `slide_friction`, `slide_drag`, `slide_steer`, `slide_slope_gain`,
`slide_end_speed`, `slide_max_speed`, `slide_height`, `stamina_cost_slide`; capability `slide`. Pull strength and
reach use `mantle_strength`, `grip_reach`, `catch_distance`, `grip_strength` (the cybernetic upgrade raises them).

New lanes: `lane_i` (fences 30-75 degrees), `lane_j` (2.2 / 2.6 m walls, thin 2.4 m, covered 2.6 m, 3.0 m; also
`lane_j_thin`, `lane_j_covered`), `lane_k` (slide: 1.0 m-clearance bars, 12 degree ramps; `lane_k_plateau`),
`lane_l` (vault, mantle, pull-up, slide).

## 5.1 refinement: variation, authorization, airborne climbing

The selection rules now read (they replace the 5.0 table further down; held Space no longer grabs):

| Situation | Order tried |
|---|---|
| New Space press on the ground | vault (inside its region) > **missed window** (a vaultable obstacle closer than the region: ordinary jump, never a climb) > mantle onto / climb over a top that is not a vault (too deep, too high, a platform) > jump |
| New Space press in the air | **catch** a ledge in reach, then mantle onto it or **climb over** a narrow top > air jump (capability) > keep looking for a ledge for 0.2 s / the landing buffer |
| Space during a vault / mantle | first half: swallowed; second half: buffered, chains into the next move on landing |
| Held Space, contact, a press older than 0.3 s | nothing |

**Unintended vaults (fixed).** Reproduced: a press after the window at the 0.6 m-deep lane B wall fell through to a
mantle whose standing check let the collider overhang the far edge, so the body climbed on and tipped over - a vault
from contact in all but name; and held Space caught walls in the air. Now every move start goes through
`TraversalController._authorize()` (recent press, capability, resources), and `vault_action.commit()` /
`mantle_action.start()` refuse without its grant. A press near a vaultable obstacle after its window is the ordinary
jump with the refusal "missed window". Mantle standing room needs the whole footprint on the top.

**Vault variation.** The authored `SafetyVault` (right hand, left-foot entry) now has its exact mirror
(`SafetyVault_Mirror`: left hand, right-foot entry), generated by reflecting every bone-local key
(`traversal/clip_mirror.gd`; the rest skeleton is symmetric within 0.0007, `tools/audit_mirror.gd`). Which variant,
and how it is shaped, follows the encounter, never chance:

| Encounter | Effect |
|---|---|
| Face angled more than 8 degrees | the hand on the side where the face comes first plants (planned by mirroring the obstacle through the unchanged planner); if that hand cannot reach, the other is tried |
| Square face | the stride decides: the approach steers toward whichever variant's entry foot is nearer, and the variant is picked at takeoff from the actual gait phase. On lane D (6 m spacing) consecutive vaults alternate right / left |
| Angle | the body turns up to 0.6 x the angle (max 0.36 rad) toward the face normal as the hand releases and the legs swing through; travel stays on the planned line |
| Speed | torso pitch into the vault: none at 4 m/s, 0.14 rad at 9 m/s and above; playback rate and stride stretch already followed speed |
| Height, depth | body lift, support dip and hold length (4.0 planner) |
| Previous vault | the run resumes at the exit phase of the variant shown, so the next takeoff continues the gait |

**Airborne catching and climbing.** A new press in the air catches a ledge when the face is within
`catch_distance` (0.45 m) of the body, the top is 0.2 m to `grip_reach` (2.1 m) above the feet, the body is falling
no faster than `grip_strength` (7 m/s), and the top has headroom. It then mantles if the whole footprint fits on the
top, or climbs over a top up to 0.9 m deep and drops to a landing within `landing_tolerance` + 1.5 m. Tops may be
uneven (0.2 m across the hands), sloped (up to about 41 degrees) or angled. The cybernetic upgrade adds 0.25 m catch
distance and 5 m/s grip strength. All checks are physics queries; no obstacle has a script.

**The lane F test bar** (`lane_f_bar`): a 1.0 m wall with a 0.3 x 0.15 m bar 1.2 m beyond it at 1.68-1.83 m. Any
vault arc hits the bar, so the vault is refused as `blocked`, which is why it could not be passed before. It is now
solved by the general system: press at the wall (missed window: a jump), press again in the air to catch the wall
top and climb over into the 0.88 m gap, then crouch under the bar - or jump and press again to catch the bar and
climb over it.

**Diagnostics** (F10): a label over the character says what Space does now (VAULT / late / CATCH -> mantle or climb
over / no catch: reason / vault window missed) and what the last press did and why the preferred move was refused;
an airborne blue/grey band shows the catch reach; red crosses are the body's contact points. The readout names the
vault's support hand.

**Course lane H** (`lane_h`, `lane_h_walls`): seven uneven crates, a sloped top, a 1.3 m ledge at 30 degrees, then
vault walls at +25 and -25 degrees, 1.1 m and 0.7 m.

Validation, results and limitations for 5.1: [task 0008](../TASKS/0008-traversal-refinement.md).

## What changed (5.0)

- **Vaulting is intentional.** Running at a wall never vaults. Space inside the vault's interaction region vaults;
  Space anywhere else is the normal jump. The 4.0 vault (planner, clip, hand IK, cameras, entry-foot steering) is
  unchanged underneath; only what starts it changed.
- **One traversal controller** (`traversal/traversal_controller.gd`) is the body's only action. It reads Space and
  picks one move by fixed rules from sensed geometry, motion and capability:

  | Situation | Order tried |
  |---|---|
  | Space on the ground | vault (inside its region) > mantle (climbable top in reach) > jump |
  | Space in the air (no coyote) | ledge grab (top within grip reach) > air jump (capability) > buffer until landing |
  | Holding Space while airborne into a ledge | ledge grab (jump-and-grab) |
  | Space during a vault / mantle | first half: swallowed; second half: buffered, chains into the next move on landing |

- **Mantle / ledge grab** (`traversal/mantle_action.gd`): authored `ClimbUp_1m` (same CC0 UAL2 package as the vault),
  motion-warped so its planted hand and foot meet the measured face and top. The collider follows its own
  collision-checked path (rise while closing on the face, then over the top), driven kinematically like the vault.
- **Capability layer** (`capability/`): character attributes with units, composable modifiers, capability grants,
  resource pools. Demonstrated with a baseline human, a cybernetic upgrade, a timed spell and an injury.
- **Air jump** for the spell, with the authored `DoubleJump` clip.
- **Course lanes D-G** next to the vault lanes, and a richer F10 overlay.

## Play it

```powershell
$godot = ".\.tools\godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path utility\movement\flat-plane res://scenes/flat_plane.tscn -- --landmark=vault_a --traversal-debug
& $godot --path utility\movement\flat-plane res://scenes/flat_plane.tscn -- --landmark=lane_e --profile=cyber
```

| Key / option | Effect |
|---|---|
| Space | Jump / vault / mantle / grab / air jump (see the table above); hold in the air to grab ledges |
| 1 / 2 / 3 / 4 | Baseline human (clear modifiers) / toggle cybernetic legs / cast the zephyr spell (25 s) / toggle sprained ankle |
| `--profile=cyber,magic,injury` | Start with modifiers |
| T / Shift+T | Landmarks, now including `lane_d`, `lane_d_pair`, `lane_e`, `lane_e_ledge`, `lane_e_gate`, `lane_f`, `lane_f_drop`, `lane_g`, `lane_g_top` |
| F10 | Overlay (below); V side view; F9 / `--trial=vault` A/B (B presses Space whenever a vault is offered) |

The readout's second line says what Space would do (`PRESS SPACE TO VAULT`, `(late)`), the character, its
capabilities and pools, and what the last press did and why the preferred move was refused.

Overlay additions: a ground band along the approach is the vault interaction region (green = a press vaults now,
lime = a late press, grey = the band where it would once the obstacle qualifies; white tick = nominal takeoff);
blue/yellow cross = a ledge seen by the last mantle evaluation (blue = climbable); cyan / magenta = an active
mantle's collider path and warped authored root.

### Course

| Lane | Contents | What it exposes |
|---|---|---|
| A-C | 4.0 vault lanes, unchanged | heights, angle, depth, decks; now need Space |
| D (z -25) | five 1.0 m walls 6 m apart, a pair 3.6 m apart, a 0.8 m wall | rhythm; the pair needs a press during the first vault's descent (chain) |
| E (z -31) | 1.0 m block 2.5 m deep, 1.4 m platform, 1.9 m ledge, 3.0 m ledge, 1.6 m wall | mantle vs vault, jump-and-grab, upgrade gates |
| F (z -37) | wall under a low bar, 2 m deck ending in a wall over a 2 m drop, 0.4 m post, 30 degree wall, block under an overhang | invalid regions: blocked path, bad landing, narrow, angled, no headroom |
| G (z -43) | 1.2 m platform with a wall on it, 5 m gap, second platform, drop, wall | mixed elevation; the gap needs a sprint or an air jump |

## Interaction region (vault)

At approach speed `v`, with nominal takeoff distance `d0` (from the clip timing):

- far edge: `d0 + v * vault_window` (0.35 s by default; its baseline is the tuned Anticipation control);
- near edge: the larger of `d0 - vault_late_window` (0.2 m) and the closest takeoff the authored stride bounds allow
  (`Planner.latest_takeoff`).

A press between the far edge and `d0` arms the eased 4.0 approach (entry-foot steering, exact takeoff). A press inside
`d0` takes off at once with `Planner.timing_at`: the stride is shortened so the authored hand contact still lands
on the wall, and the playback quickens so the ground speed is kept. Presses closer still mantle when there is a
top to stand on, otherwise jump. Every vault offered is already planned and collision-checked; a press can never
start a move that was not validated, so invalid presses cannot snap, rotate or teleport.

Buffering mirrors the movement core's jump buffer (0.1 s, same tick arithmetic), so with nothing to traverse a
buffered press jumps exactly when the core's own buffer would have. On the first tick on the ground after a fall,
or out of a move, the vault looks ahead immediately so a buffered press can vault on landing. Coyote jumps are
untouched.

## Capability architecture

```
movement params (MIDI-tuned)  ┐
traversal params (MIDI bank 5)├─ baselines (never written)
profile attributes (human)    ┘
          + modifiers [add, mul, set, cap, floor]  ->  effective values  ->  movement core / planners / costs
          + grants / revokes                       ->  capabilities     ->  which moves the selector may try
```

- `capability/movement_attributes.gd`: every traversal attribute with unit, range, default and meaning (vault
  height/depth/lift/window/late window, landing tolerance, mantle height/reach/strength/exit speed, grip reach,
  momentum conservation, recovery time, air jumps and impulse, stamina/energy/heat/mana capacities, rates and
  per-move costs). Movement-core parameters (speed, acceleration, jump impulse, gravity, air control ...) are
  upgraded through the same stack by their existing ids.
- `capability/movement_modifier.gd`: a sourced (training, cybernetic, equipment, magic, injury, environment, buff,
  debuff), optionally timed bundle of effects. Per attribute: `(base + sum(add)) * prod(mul)`, then the highest
  priority `set`, then the lowest `cap` / highest `floor`, then the legal range. Order of insertion never matters.
- `capability/movement_capabilities.gd`: recomputes every effective value from its baseline on any change, so
  removal is exact; with no modifiers no arithmetic is applied (bit-identical to 4.0). Timed modifiers count down
  on the physics tick.
- `capability/movement_resources.gd`: stamina regenerates on the ground; energy and heat gate powered moves;
  heat at capacity locks powered moves out until it falls below half; mana pays for air jumps. A jump is never
  refused.
- A move is **powered** when it exceeds the unaugmented baseline (height, lift, depth or drop). Powered moves need
  `powered_traversal` and cost energy and heat.

| Profile | Changes |
|---|---|
| Human (default) | vault 0.6-1.25 m, depth 0.9 m, drop 0.6 m; mantle to 1.45 m; grab to 2.1 m above the feet |
| Kinetic leg actuators (cybernetic, permanent) | +1 m/s run, x1.3 acceleration, x1.25 jump; vault to 1.70 m with +0.55 m lift, depth 1.2 m, drop 2.1 m; mantle to 2.2 m, grab 2.7 m, x1.4 climb; 100 energy, 20 per powered move, 35 heat (3 in a row overheat) |
| Zephyr step (magic, 25 s) | x0.65 gravity, +0.35 air control, +1 m/s air speed cap, +1 m drop, +0.3 m grab; grants `air_jump` (15 mana of 60) |
| Sprained ankle (injury) | run capped at 4 m/s, sprint x1.2, x0.8 jump, x0.7 climb; revokes `vault` |

New abilities (wall run, grapple, glide, dash ...) are new capability ids plus a move that the controller tries in
the matching row of the selection table; numbers they need become attributes. Nothing in the controller is
profile-specific.

## Animation integration

- Vault: unchanged 4.0 integration (seek by action clock, phase steering to the entry foot, support-hand IK, torso
  lean, camera follow offsets). A late vault starts on the clip's first frame without phase steering; the vault
  crossfade (Transition response) covers the foot mismatch.
- Mantle: an AnimationTree state seeked to the action's clip time. Motion warping: the authored linear root path
  is offset so the measured contacts (left hand 0.15-0.32 s, right foot 0.22-0.5 s, both on a 1.10 m top 0.75 m
  ahead at mannequin scale, `tools/audit_climb_clip.gd`) land on the real face and top by 0.15 s; after contact
  the forward travel is compressed to end where the collider ends. Floor foot IK pauses while it shows. Air grabs
  join the clip later when the feet are already close to the top.
- Air jump: the authored `DoubleJump` is seeked by time since the jump for 0.45 s, then the air loop resumes.

## Validation

Run headless from `utility/movement/flat-plane` with the harness (commands as in [4.0](MOVEMENT-LAB-4.md#reproduce-diagnostics),
filters `test_traversal`, `test_movement_capabilities`, `test_authored_playground`, `test_`).

- `tests/test_traversal_vault.gd` (16, all 4.0 assertions kept): the scripted runner now presses Space on the first
  tick a vault is offered. Lane A at 3/6/12 m/s still vaults all four walls on the authored entry foot, refuses
  1.60 m, zero aborts, zero collider overlap ticks, hand error under 10 mm; lanes B/C, depth, blocked ceiling,
  interruption, animation-independent physics, live frames and cameras all pass unchanged.
- `tests/test_traversal_intent.gd` (12): no press never vaults or mantles; a far press jumps with the normal impulse;
  early press arms; late press vaults with a shorter stride at the same ground speed; a too-close press at a thin
  wall jumps with no snap (largest tick step under 0.1 m), no overlap and no camera rotation; an infeasible wall
  jumps; a press during a vault's descent chains the 3.6 m pair; a press in the air vaults on landing; the 2.5 m
  deep block is mantled and the 1.9 m ledge is jump-and-grabbed; the 3.0 m ledge is out of a human's reach but
  reached with the cybernetic legs or the spell; the cybernetic vault of the 1.6 m wall costs energy and heat and is
  refused when overheated; the spell's air jump costs mana and a human gets none; the sprain revokes vaulting and
  caps speed; the cybernetic vault lands into a 2 m drop a human refuses; the barred wall is refused as `blocked`.
  Every trial overlap-tests the actual collider each tick (2 mm inset); ticks while a move is active: zero.
- `tests/test_movement_capabilities.gd` (6): definitions; bit-identical baselines with no modifiers; op order is
  insertion-independent; removal restores every value bit for bit and never writes the tuned parameters; timed
  expiry on the exact tick; resource gating, regeneration and the heat lockout (5.5 s to cool).
- Full utility regression: **518 passed, 0 failed** (about 191 s; 4.0 baseline in this worktree: 499/499).
- Benchmark (`benchmarks/bench_traversal_vault.gd`, headless CPU, same machine as 4.0, other lab windows closed;
  the lane A run now presses Space):

  | Measure | 4.0 | 5.0 |
  |---|---|---|
  | Whole tick, lane A with 4 vaults | p50 0.221 / p95 0.283 ms | p50 0.243 / p95 0.303 ms |
  | Physics + perception mean, open ground, traversal on / off | 0.059 / 0.049 ms | 0.075 / 0.061 ms |
  | Fresh vault plan 6 / 12 m/s | 1.312 / 1.266 ms | 1.217 / 1.154 ms |

- Native Vulkan captures (`tools/capture_traversal.gd`, side view, overlay on, the scene's own physics tick with a
  scripted input source): vault, late vault, cybernetic 1.6 m vault (hand error 0.000 m) and mantle complete with
  zero aborts; mantle and jump-and-grab frames show the hand and foot on the ledge top. Visual approval remains
  the user's.

## Limitations

- Mantle has no hand IK; contacts are aligned by the warp only. Visual approval is the user's.
- Ledge grabs use the same running-climb clip (no hanging pose or shimmy).
- Landing from a high fall (about 2 m) left the collider up to 4.7 cm in the ground for one tick, after the move had
  ended (KI-025; assumed to be the unchanged core landing, not yet isolated). Traversal tests count it separately.
- Only static box-like geometry is sensed; moving platforms and irregular tops are refused.
- The vault A/B's B side uses a scripted ideal press, not a human performance.
