# SPEC: movement

## Responsibilities and scope

Computes a first-person character's next velocity from its current velocity, a wished horizontal direction,
grounded state, jump input and frame time. Also exposes the speed bounds every valid trajectory respects.

Out of scope: collision response (Godot's `CharacterBody3D.move_and_slide()` in the consumer), input mapping,
camera control, animation, networking.

## Behaviour

| Rule | Value (defaults) |
|---|---|
| Horizontal speed approaches `wish * walk_speed` | `walk_speed` 6 m/s, hard cap |
| Ground acceleration with input / braking without input | 50 / 40 m/s² |
| Air control | 8 m/s² toward the wished velocity |
| Wish vectors longer than 1 | normalised (diagonals are not faster) |
| Jump | only when grounded and not rising: `vy = jump_velocity` (7 m/s, apex ≈ 1.22 m) |
| Gravity / terminal fall | 20 m/s² / 40 m/s |
| Frame time | clamped to `[0, MAX_DELTA = 0.1]`; `<= 0` returns the velocity unchanged |

Determinism: pure function of its inputs (no randomness, no engine state); `Vector3` uses float32.
The golden trajectory is bit-identical at float32 precision on Windows (Godot 4.7.2 official build).
