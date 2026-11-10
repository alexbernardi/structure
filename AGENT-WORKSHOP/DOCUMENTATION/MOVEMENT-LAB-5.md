# Movement Lab 5.0 - unified, intentional, upgradeable traversal

Branch: `benchmark/opus-traversal`. Task: [0007](../TASKS/0007-unified-traversal.md). Builds on the
[4.0 vault](MOVEMENT-LAB-4.md) and the approved [3.0 authored locomotion](MOVEMENT-LAB-3.md); both are preserved.

## What changed

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
