## Collision body: reports the world to the movement core, applies the velocity it returns, and handles
## things the core must not know about (collider resizing for crouch, headroom, stair stepping, respawn).
## The collider is a flat-bottomed cylinder: after a step-up its base rests on the tread edge, which a capsule's rounded
## bottom cannot do (it slides back down onto the lower tread).
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
## Presentation-only vertical offset (<= 0 after a step-up). The body climbs a stair in one tick; the visual and the
## camera start that far below and ease back to zero, so the climb reads as a smooth rise instead of a pop.
var step_offset := 0.0

const STEP_EASE_RATE := 14.0   ## 1/s; time constant ~70 ms
const FLAT_TOLERANCE_DEG := 3.0

var _shape := CylinderShape3D.new()
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
	_shape.height = maxf(h, RADIUS * 2.0)
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
	var lift := 0.0
	if grounded and not core.just_jumped:
		lift = _try_step(dt)
	var carried := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if lift > 0.0:
		# The slide against the riser's edge bleeds speed and adds a vertical component; the step was already
		# validated as unobstructed, so keep the momentum we had.
		stepped = true
		step_offset -= lift
		velocity = carried
	core.velocity = velocity   # collisions (walls, ceilings) change the real velocity; feed it back
	step_offset = move_toward(step_offset * exp(-STEP_EASE_RATE * dt), 0.0, 0.05 * dt)
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


## Returns the height gained (0.0 = no step). Steps up onto a flat tread that is higher than the flat ground under
## the feet, within step_height, when the horizontal motion would be blocked. Requiring flat-below and flat-ahead is
## what tells stairs from ramps: a ramp's surface is slanted, so the capsule simply rides up it.
## Heights are measured with thin rays: the capsule's rounded bottom meets a stair nose at a slanted normal, so a
## capsule cast would misread a flat tread as a slope.
func _try_step(dt: float) -> float:
	var step_h: float = params.get_value("step_height")
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt
	if step_h <= 0.0 or motion.length() < 0.0005:
		return 0.0
	if not test_move(global_transform, motion, null, 0.001):
		return 0.0
	var space := get_world_3d().direct_space_state
	var flat := deg_to_rad(FLAT_TOLERANCE_DEG)
	if not is_on_floor() or get_floor_normal().angle_to(Vector3.UP) > flat:
		return 0.0   # not standing on flat ground (a ramp, or airborne)
	var ahead := global_position + motion.normalized() * (RADIUS + motion.length() + 0.02)
	var tread := _ray_down(space, ahead, step_h + 0.01, step_h + 0.01)
	if tread.is_empty() or (tread.normal as Vector3).angle_to(Vector3.UP) > flat:
		return 0.0   # nothing within step height, or the way ahead is slanted / a wall that starts higher
	var lift: float = tread.position.y - global_position.y + 0.002
	if lift < 0.02 or lift > step_h + 0.003:
		return 0.0
	if test_move(global_transform, Vector3.UP * lift):
		return 0.0   # no headroom
	var raised := global_transform
	raised.origin.y += lift
	if test_move(raised, motion, null, 0.001):
		return 0.0   # still blocked after rising: a wall, not a step
	global_position.y += lift
	return lift


## Downward ray starting `above` metres over `point`, `reach` metres long.
func _ray_down(space: PhysicsDirectSpaceState3D, point: Vector3, above: float, reach: float) -> Dictionary:
	var from := point + Vector3.UP * above
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (above + reach), collision_mask, [get_rid()]))


func respawn() -> void:
	teleport(spawn_transform.origin, spawn_transform.basis)
	respawned.emit()


## Places the body somewhere else and clears its motion. Resetting interpolation stops the renderer from drawing the
## character streaking from the old spot to the new one.
func teleport(pos: Vector3, basis := Basis.IDENTITY) -> void:
	step_offset = 0.0
	global_transform = Transform3D(basis, pos)
	velocity = Vector3.ZERO
	core.reset()
	_was_grounded = false
	reset_physics_interpolation()
