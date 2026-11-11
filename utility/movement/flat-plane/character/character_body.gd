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
## Optional physical traversal action (traversal/vault_action.gd): filters the input, may take over whole ticks, adjusts
## the core's velocity before the move and observes the world after it. Null = plain movement.
var action = null   ## traversal/traversal_controller.gd in the lab scenes
var height_override := 0.0   ## m: a traversal move's collider height (the slide); 0 = standing / crouching as usual

const STEP_EASE_RATE := 14.0   ## 1/s; time constant ~70 ms
const FLAT_TOLERANCE_DEG := 3.0

var _shape := CylinderShape3D.new()
var _collider := CollisionShape3D.new()
var _was_grounded := false
var _prev_vy := 0.0
var _step_offset_prev := 0.0   # step_offset at the previous tick, to interpolate it like the body's transform


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
	if height_override > 0.0:
		h = height_override
	_shape.height = maxf(h, RADIUS * 2.0)
	_collider.position.y = _shape.height / 2.0


## One fixed tick. `input` is the movement input frame (see MovementCore.step).
func simulate(input: Dictionary, dt: float) -> void:
	_step_offset_prev = step_offset
	if action != null:
		input = action.filter_input(input, self, dt)
		if action.drive(self, dt):
			if action.has_method("consumed_tick"):
				action.consumed_tick(dt)
			return
	_sync_slope_settings()
	var grounded := is_on_floor()
	var ground := {"grounded": grounded, "normal": get_floor_normal() if grounded else Vector3.UP, "can_stand": _can_stand()}
	_prev_vy = velocity.y
	core.step(input, ground, dt)
	if action != null:
		action.adjust(self, dt)
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
	elif action != null:
		action.observe(self, dt)


## One kinematic traversal tick: the movement core is bypassed but the collider keeps full collision response, so a
## blocked path shows up as tracking error instead of tunnelling. The crouch collider stands in for the tucked body,
## and floor snapping is off because the path leaves the ground on purpose.
func drive_to(target: Vector3, dt: float) -> void:
	core.crouching = true
	_apply_shape(true)
	floor_snap_length = 0.0
	stepped = false
	velocity = (target - global_position) / dt
	move_and_slide()
	core.velocity = velocity
	core.grounded = false
	step_offset = move_toward(step_offset * exp(-STEP_EASE_RATE * dt), 0.0, 0.05 * dt)


## Ends a traversal action and hands `v` to the movement core. A landing re-attaches the floor at once, so the next
## tick is ground movement rather than a fall followed by a landing.
func release(v: Vector3, landed: bool) -> void:
	_sync_slope_settings()
	velocity = v
	if landed:
		apply_floor_snap()
	core.velocity = v
	core.grounded = landed and is_on_floor()
	core.coyote_left = 0.0
	_was_grounded = core.grounded
	_prev_vy = 0.0


## Where the presentation (visual and camera) sits relative to the body: the eased stair-step offset plus any
## traversal offset (the authored vault's body path differs from the collider's hump).
func presentation_offset() -> Vector3:
	var fraction := Engine.get_physics_interpolation_fraction()
	var offset := Vector3.UP * step_offset_at(fraction)
	if action != null:
		offset += action.offset(fraction)
	return offset


## Where the cameras follow relative to the body: the presentation offset without a traversal action's pose fitting
## (see VaultAction.follow_offset).
func follow_offset() -> Vector3:
	var fraction := Engine.get_physics_interpolation_fraction()
	var offset := Vector3.UP * step_offset_at(fraction)
	if action != null:
		offset += action.follow_offset(fraction)
	return offset


## The step offset between the last two ticks, interpolated like the body's transform: at a step-up the body is drawn
## part-way up the riser, so the full offset would put the character below the tread for a frame.
func step_offset_at(fraction: float) -> float:
	return lerpf(_step_offset_prev, step_offset, fraction)


## True when the collider can grow from its current height to `height` without hitting anything above.
func can_rise_to(height: float) -> bool:
	var extra := height - _shape.height
	return extra <= 0.0 or not test_move(global_transform, Vector3.UP * (extra + 0.02))


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
	_step_offset_prev = 0.0
	height_override = 0.0
	if action != null:
		action.cancel()
	global_transform = Transform3D(basis, pos)
	velocity = Vector3.ZERO
	core.reset()
	_was_grounded = false
	reset_physics_interpolation()
