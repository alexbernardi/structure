# Movement Core 1.0 - architecture and use

The approved movement character as a reusable package. Interface: [CONTRACT.md](../../SYSTEM-ROOMS/movement_core/CONTRACT.md)
(the only part other systems may rely on). Version and changelog: [room README](../../SYSTEM-ROOMS/movement_core/README.md).
How it was built and measured: [Movement Lab 3.0](MOVEMENT-LAB-3.md), [4.0](MOVEMENT-LAB-4.md), [5.x](MOVEMENT-LAB-5.md).

Source (the workbench): `utility/movement/flat-plane/systems/movement_core/`. Installed copies (read-only):
`SANDBOX/godot/systems/movement_core/`, `LABS/<lab>/systems/movement_core/`.

## Layers

| Layer | Files (under the package) | Role |
|---|---|---|
| Public entry | `movement_character.gd` | assembles everything below; ticks, presents, signals, modifiers, impulses |
| Movement core | `movement/movement_core.gd`, `movement/movement_params.gd` | velocity integration: ground / air acceleration, friction, sprint, crouch, slopes, gravity, coyote time, jump buffer (pure, no nodes) |
| Collision body | `character/character_body.gd` | `CharacterBody3D` flat-bottomed cylinder: feeds the core the floor, applies its velocity, crouch collider and headroom, stair steps, respawn, `landed` |
| Traversal | `traversal/traversal_controller.gd` and the moves | one physical action per tick: jump / vault / mantle / climb-over / ledge catch / hang / shimmy / corners / pull-up / slide / flip / air jump; refusals with reasons |
| Perception and planning | `traversal/obstacle_probe.gd`, `vault_planner.gd`, `vault_profile.gd` | rays and shape casts find walls, tops and landings; the vault is planned from the authored clip's measured silhouette |
| Moves | `traversal/vault_action.gd`, `mantle_action.gd` (mantle, catch, hang, shimmy, corners, pull-up) | kinematic drive of the body along authored or planned paths with full collision response |
| Capabilities | `capability/movement_attributes.gd`, `movement_capabilities.gd`, `movement_modifier.gd`, `movement_resources.gd`, `movement_profiles.gd` | attribute registry, modifiers (add / mul / set / cap / floor, grants, revokes, timed), stamina / energy / heat / mana |
| Presentation | `character/authored_mannequin.gd`, `animation/authored_animation.gd`, `animation/locomotion_model.gd` | Quaternius mannequin, AnimationTree state machine seeked by the moves' clocks, run phase sync |
| IK | `animation/two_bone_correction.gd`, `foot_orientation.gd` (+ logic in `authored_animation.gd`) | analytic two-bone IK for hands and feet; terrain feet (heel / toe / lookahead rays, pelvis drop, slope tilt, no sinking); hang hands on the lip, braced climber feet, quick-mantle hand |
| Debug | `animation/skeleton_overlay.gd`, `traversal/vault_debug.gd` | skeleton view (real final pose, body at 40 %); interaction regions, contacts, ledge paths, refusals |
| Clips | `traversal/*_clip.gd`, `clip_pose.gd`, `clip_mirror.gd`, `assets/quaternius/` | timing tables measured from the authored clips (audited by the workbench tools), mirroring, the GLBs |

Presentation never feeds back into physics (tested: with presentation off the body moves identically). The vault
profile is measured once from the mannequin when the character is built.

## Movement states

`state` is one of `grounded`, `crouching`, `airborne`, `sliding`, `flipping`, `vaulting`, `mantling`, `hanging`
(the last five are traversal states: `traversal_started` / `traversal_finished` fire on entering / leaving them).
Order of precedence: vault > hang > mantle (incl. climb-over and pull-up) > flip > slide > ground / air.

Decisions on a press of Space (fresh presses only; held Space or stale presses never trigger a move): on the ground
vault (inside the visible window, early presses arm the approach, late presses fit a shorter stride) > mantle /
climb-over > jump; in the air ledge catch (or climb-over) > air jump > buffered press. Jumping into a wall too high to
climb catches and hangs without a press; Space then pulls up, Ctrl or stick-back lets go, stick left / right shimmies
(hand over hand, reach and match, round outside and inside corners). Crouch at speed slides; Space while crouched or
sliding flips.

## Parameters and modifiers

- Movement parameters (`movement/movement_params.gd`): `max_ground_speed` 6 m/s, `sprint_multiplier`, `jump_impulse`,
  `gravity`, `coyote_time`, `step_height`, `stand_height`, ... (ids, units, ranges, defaults in the file).
- Traversal attributes (`capability/movement_attributes.gd`): reach and grip (`grip_reach`, `catch_distance`,
  `grip_strength`), limits (`vault_max_height`, `mantle_max_height`), `shimmy_speed` 0.6 m/s, slide and flip tuning,
  resources (stamina, energy, heat, mana) and their costs.
- Base capabilities: `jump`, `vault`, `mantle`, `slide`, `flip`; modifiers grant others (`air_jump`, `powered_traversal`) or revoke any.
- Example modifiers (`capability/movement_profiles.gd`): cybernetic legs (more speed, jump, reach, powered climbs,
  energy and heat), zephyr step (a timed spell: lighter, mana air jump), sprained ankle (capped speed, no vault / flip).

```gdscript
const Modifier = preload("res://systems/movement_core/capability/movement_modifier.gd")
var rocket_boots = Modifier.make("rocket_boots", "Rocket boots", "equipment",
	[["air_jumps", "add", 2], ["air_jump_impulse", "mul", 1.6], ["max_fall_speed", "cap", 30.0]], ["air_jump"])
character.add_modifier(rocket_boots)       # capabilities_changed fires; character.attribute("air_jumps") == 3
character.remove_modifier("rocket_boots")
```

New kinds of traversal (wall running, grappling, rocket boots with their own physics) are added inside the package as
new moves in the traversal controller, new attributes and capability ids - a minor version - so consumers that use
the contract keep working.

## Using it in a project

```gdscript
const MovementCharacter = preload("res://systems/movement_core/movement_character.gd")

func _ready() -> void:
	MovementCharacter.register_input_actions()
	var character = MovementCharacter.new()
	add_child(character)
	character.spawn(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	character.drive_self = true                # or call simulate(frame, 1.0 / 120.0) and present(delta) yourself
	character.traversal_started.connect(func(move): print("started ", move))
```

Requirements (CONTRACT "Dependencies"): physics at 120 Hz for `drive_self`, world geometry on collision layer 1,
Godot 4.7. Worked examples: `LABS/_TEMPLATE/scenes/lab.gd` (a playable test ground) and
`SANDBOX/godot/tests/unit/test_movement_core.gd` (headless: input, run, jump, mantle, events, modifiers).

## Inputs and controls

Actions (registered at runtime if missing): `move_forward` W/Up, `move_back` S/Down, `move_left` A/Left,
`move_right` D/Right, `jump` Space, `sprint` Shift, `crouch` Ctrl/C. The camera yaw comes from the caller. The
workbench adds its own keys (K skeleton view, F10 traversal debug, T landmarks, 1-4 example modifiers, MIDI tuning):
[Movement Lab 5](MOVEMENT-LAB-5.md).

## Performance

Measured headless on the development machine (`room bench movement_core`): `simulate` tick 64 us, `present` frame
174 us (targets 250 / 700 us in `room.json`). The traversal course tick (physics + perception + presentation) was
0.18-0.27 ms p50-p95 ([MOVEMENT-LAB-4.md](MOVEMENT-LAB-4.md)). Compare numbers only on the same machine.

## Multiplayer considerations

Deterministic per tick for a fixed `dt` and input sequence; no randomness, and the only clock read times the vault
planner for telemetry.
Not yet wired into the authoritative server, which still validates movement with the `movement` room's speed bounds
(a traversal move would exceed them). Networking it means: input frames as client requests, the server running the
same `simulate`, `snapshot()` replicated, client prediction and reconciliation, traversal moves validated as moves
rather than speeds - a protocol version bump and its own laboratory.

## Known limitations

From the laboratory records (KI-024): feel of 5.x traversal awaits more playtesting; corners are one committed arc at
the hang's height; the 23-bone mannequin has rigid hands; the braced stagger is fixed (left foot high); a foot can kink
once mid-step round a corner; the orbit camera is a convenience, not part of the contract.
