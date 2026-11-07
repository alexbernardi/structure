## Collision body: reports the world to the movement core, applies the velocity it returns, and handles
## things the core must not know about (collider resizing for crouch, headroom, stair stepping, respawn).
## Driven explicitly through simulate(), once per physics tick, so ordering and replay are deterministic.
extends CharacterBody3D

const Core = preload("res://movement/movement_core.gd")
const Params = preload("res://movement/movement_params.gd")

signal respawned
signal landed(impact_speed: float)

const RADIUS := 0.35
const KILL_HEIGHT := -40.0
const LAYER_CHARACTER := 2

var params: Params
var core: Core = Core.new()
var spawn_transform := Transform3D.IDENTITY
var stepped := false          ## true on ticks where a stair step was taken (telemetry)
var last_impact := 0.0

var _shape := CapsuleShape3D.new()
var _collider := CollisionShape3D.new()
var _was_grounded := false
var _prev_vy := 0.0


func setup(p: Params) -> void:
	params = p
	core.p = p.values
	_shape.radius = RADIUS
	_collider.shape = _shape
	add_child(_collider)
	collision_layer = 1 << (LAYER_CHARACTER - 1)
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_stop_on_slope = true
	floor_block_on_wall = true
	max_slides = 6
	_apply_shape(false)
	_sync_slope_settings()


func current_height() -> float:
	return params.get_value("crouch_height") if core.crouching else params.get_value("stand_height")


func _sync_slope_settings() -> void:
	floor_max_angle = deg_to_rad(params.get_value("max_walkable_slope"))
	floor_snap_length = maxf(0.1, params.get_value("step_height") + 0.05)


func _apply_shape(crouched: bool) -> void:
	var h: float = params.get_value("crouch_height") if crouched else params.get_value("stand_height")
	_shape.height = maxf(h, RADIUS * 2.0 + 0.01)
	_collider.position.y = _shape.height / 2.0


## One fixed tick. `input` is the movement input frame (see MovementCore.step).
func simulate(input: Dictionary, dt: float) -> void:
	_sync_slope_settings()
	var grounded := is_on_floor()
	var ground := {"grounded": grounded, "normal": get_floor_normal() if grounded else Vector3.UP, "can_stand": _can_stand()}
	_prev_vy = velocity.y
	core.step(input, ground, dt)
	_apply_shape(core.crouching)
	velocity = core.velocity
	stepped = false
	if grounded and not core.just_jumped and _try_step(dt):
		stepped = true
	move_and_slide()
	core.velocity = velocity   # collisions (walls, ceilings) change the real velocity; feed it back
	var now_grounded := is_on_floor()
	if now_grounded and not _was_grounded:
		last_impact = maxf(0.0, -_prev_vy)
		landed.emit(last_impact)
	_was_grounded = now_grounded
	if global_position.y < KILL_HEIGHT:
		respawn()


func _can_stand() -> bool:
	if not core.crouching:
		return true
	var extra: float = params.get_value("stand_height") - params.get_value("crouch_height")
	return not test_move(global_transform, Vector3.UP * (extra + 0.02))


## Lifts the body onto a ledge up to step_height when the horizontal motion is blocked by a wall-like surface.
## The tread height is measured with a thin ray just ahead of the capsule: its rounded bottom touches a stair
## edge at a slanted normal, so a capsule cast would misjudge the flat top as a steep slope.
func _try_step(dt: float) -> bool:
	var step_h: float = params.get_value("step_height")
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt
	if step_h <= 0.0 or motion.length() < 0.0005:
		return false
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit, 0.001):
		return false
	if hit.get_normal().angle_to(Vector3.UP) < floor_max_angle:
		return false   # a walkable slope or tiny bump: the capsule rides over it by itself
	var origin := global_position + motion.normalized() * (RADIUS + 0.02) + Vector3.UP * (step_h + 0.01)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * (step_h + 0.01), collision_mask, [get_rid()])
	var tread := get_world_3d().direct_space_state.intersect_ray(query)
	if tread.is_empty():
		return false   # nothing within step height ahead (a taller wall starts above the ray origin)
	var lift: float = tread.position.y - global_position.y + 0.002
	if lift < 0.01 or lift > step_h + 0.003:
		return false
	if (tread.normal as Vector3).angle_to(Vector3.UP) > floor_max_angle:
		return false
	if test_move(global_transform, Vector3.UP * lift):
		return false   # no headroom
	var raised := global_transform
	raised.origin.y += lift
	if test_move(raised, motion, null, 0.001):
		return false   # still blocked after rising: not a step
	global_position.y += lift
	return true


func respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	core.reset()
	_was_grounded = false
	respawned.emit()
