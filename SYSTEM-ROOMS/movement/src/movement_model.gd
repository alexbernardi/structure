## Deterministic first-person movement model. Pure static functions: no nodes, no engine state.
## Contract: SYSTEM-ROOMS/movement/CONTRACT.md. Do not edit the sandbox copy; promote from the room.
extends RefCounted

const VERSION := "1.0.0"
## Frame-time spikes are clamped so a stalled client cannot integrate one giant step.
const MAX_DELTA := 0.1


static func default_params() -> Dictionary:
	return {
		"walk_speed": 6.0,       # m/s, horizontal speed cap
		"ground_accel": 50.0,    # m/s^2 toward the wished velocity
		"ground_decel": 40.0,    # m/s^2 braking with no input
		"air_accel": 8.0,        # m/s^2 limited air control
		"gravity": 20.0,         # m/s^2
		"jump_velocity": 7.0,    # m/s (apex ~1.22 m)
		"max_fall_speed": 40.0,  # m/s
	}


## Returns the new velocity. `wish_dir` is a world-space horizontal direction (length <= 1 honoured,
## longer vectors are normalised). `on_floor`/`jump` come from the caller's physics/input.
static func step(velocity: Vector3, wish_dir: Vector3, on_floor: bool, jump: bool, delta: float, params: Dictionary) -> Vector3:
	var dt := clampf(delta, 0.0, MAX_DELTA)
	if dt <= 0.0:
		return velocity
	var wish := Vector3(wish_dir.x, 0.0, wish_dir.z)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var walk_speed: float = params.walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float
	if on_floor:
		rate = params.ground_accel if wish.length_squared() > 0.0 else params.ground_decel
	else:
		rate = params.air_accel
	horizontal = horizontal.move_toward(wish * walk_speed, rate * dt)
	if horizontal.length() > walk_speed:
		horizontal = horizontal.normalized() * walk_speed
	var vy := velocity.y
	if on_floor and vy <= 0.0:
		vy = params.jump_velocity if jump else 0.0
	else:
		vy = maxf(vy - float(params.gravity) * dt, -float(params.max_fall_speed))
	return Vector3(horizontal.x, vy, horizontal.z)


## Upper bound of horizontal speed any sequence of step() calls can produce.
## The server uses it to validate client-reported positions.
static func max_horizontal_speed(params: Dictionary) -> float:
	return params.walk_speed


## Upper bound of vertical speed (rising or falling).
static func max_vertical_speed(params: Dictionary) -> float:
	return maxf(params.jump_velocity, params.max_fall_speed)


## Continuous-time jump apex height (m). Discrete integration lands within jump_velocity * dt of it.
static func jump_apex_height(params: Dictionary) -> float:
	return pow(params.jump_velocity, 2.0) / (2.0 * float(params.gravity))
