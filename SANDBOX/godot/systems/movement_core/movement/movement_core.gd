## Fixed-timestep, momentum-preserving movement simulation. Pure logic: no nodes, no physics server.
## The caller (character body) reports what the world says (grounded, floor normal, headroom) and applies the
## returned velocity; this class decides only how velocity changes. Same inputs -> same trajectory.
##
## Model (Source/Quake family, tuned to be human-scale by default):
##  - ground: friction (proportional drag + braking) then accelerate toward the wished velocity; speed above the cap
##    is bled off by friction only, never clipped, so momentum survives landings and direction changes;
##  - air: no friction; acceleration only builds speed along the wished direction up to `air_speed_cap`, so
##    strafing across the velocity can still add speed (air strafing / bunny hopping emerge from the rules);
##  - jump: coyote time and jump buffering; a buffered jump on the landing tick skips friction (bunny hop).
extends RefCounted

const Params = preload("res://systems/movement_core/movement/movement_params.gd")

var p: Dictionary = Params.defaults()  ## live parameter values; assign `params.values` for live tuning

var velocity := Vector3.ZERO
var grounded := false
var crouching := false
var floor_normal := Vector3.UP
var coyote_left := 0.0
var jump_buffer_left := 0.0
var just_jumped := false
var just_landed := false
var acceleration := Vector3.ZERO       ## measured horizontal acceleration of the last step (m/s^2)
var wish_speed := 0.0                  ## the speed cap that applied on the last step (m/s)
var ticks := 0


func reset(v := Vector3.ZERO) -> void:
	velocity = v
	grounded = false
	crouching = false
	floor_normal = Vector3.UP
	coyote_left = 0.0
	jump_buffer_left = 0.0
	just_jumped = false
	just_landed = false
	acceleration = Vector3.ZERO
	ticks = 0


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## input: {move: Vector2 (x right, y forward, <= 1), yaw: float (rad, camera/view), jump_pressed, jump_held, sprint, crouch}
## ground: {grounded: bool, normal: Vector3, can_stand: bool}. Returns the new velocity.
func step(input: Dictionary, ground: Dictionary, dt: float) -> Vector3:
	ticks += 1
	var old_h := Vector3(velocity.x, 0.0, velocity.z)
	var was_grounded := grounded
	var normal: Vector3 = ground.get("normal", Vector3.UP)
	var slope_angle := normal.angle_to(Vector3.UP)
	grounded = bool(ground.get("grounded", false)) and slope_angle <= deg_to_rad(p.max_walkable_slope)
	floor_normal = normal if grounded else Vector3.UP
	just_landed = grounded and not was_grounded
	just_jumped = false

	if grounded:
		coyote_left = p.coyote_time
	elif was_grounded and not just_jumped:
		coyote_left = p.coyote_time

	var wants_crouch: bool = input.get("crouch", false)
	if wants_crouch:
		crouching = true
	elif crouching and ground.get("can_stand", true):
		crouching = false

	if input.get("jump_pressed", false):
		jump_buffer_left = maxf(p.jump_buffer_time, dt)
	var auto: bool = p.auto_jump >= 0.5 and input.get("jump_held", false)
	if (jump_buffer_left > 0.0 or auto) and (grounded or coyote_left > 0.0):
		velocity.y = p.jump_impulse
		grounded = false
		floor_normal = Vector3.UP
		coyote_left = 0.0
		jump_buffer_left = 0.0
		just_jumped = true

	var move: Vector2 = input.get("move", Vector2.ZERO)
	if move.length_squared() > 1.0:
		move = move.normalized()
	var wish := Basis(Vector3.UP, float(input.get("yaw", 0.0))) * Vector3(move.x, 0.0, -move.y)
	var wish_dir := wish.normalized() if wish.length_squared() > 0.000001 else Vector3.ZERO
	var cap: float = p.crouch_speed if crouching else p.max_ground_speed * (p.sprint_multiplier if input.get("sprint", false) else 1.0)
	wish_speed = wish.length() * cap

	if grounded:
		_ground_move(wish_dir, wish_speed, dt, slope_angle)
	else:
		_air_move(wish_dir, wish_speed, dt)

	if velocity.y < -p.max_fall_speed:
		velocity.y = -p.max_fall_speed
	jump_buffer_left = maxf(0.0, jump_buffer_left - dt)
	if not grounded:
		coyote_left = maxf(0.0, coyote_left - dt)
	acceleration = (Vector3(velocity.x, 0.0, velocity.z) - old_h) / dt
	return velocity


func _ground_move(wish_dir: Vector3, speed_cap: float, dt: float, slope_angle: float) -> void:
	var n := floor_normal
	velocity -= n * velocity.dot(n)  # landing absorbs the vertical part; horizontal momentum stays
	var dir := wish_dir
	if dir != Vector3.ZERO:
		dir = (dir - n * dir.dot(n)).normalized()
		# Climbing is slower: scale the wished speed by how directly we face uphill and how steep it is.
		var uphill := Vector3.UP - n * n.y
		if uphill.length_squared() > 0.000001:
			var facing := maxf(0.0, dir.dot(uphill.normalized()))
			var steepness := slope_angle / deg_to_rad(p.max_walkable_slope)
			speed_cap *= 1.0 - p.slope_speed_penalty * facing * steepness
	if dir == Vector3.ZERO:
		var speed := velocity.length()
		if speed > 0.0001:
			var drop: float = _friction_drop(speed, dt) + p.braking * dt
			velocity *= maxf(speed - drop, 0.0) / speed
	else:
		# Friction acts on sideways sliding, on speed above the cap and on opposing motion, but not on speed
		# below the cap along the wished direction: otherwise the real top speed would sit under max_ground_speed.
		var along := velocity.dot(dir)
		var sideways := velocity - dir * along
		var side_speed := sideways.length()
		if side_speed > 0.0001:
			sideways *= maxf(side_speed - _friction_drop(side_speed, dt), 0.0) / side_speed
		if along > speed_cap:
			along = maxf(along - _friction_drop(along, dt), speed_cap)
		elif along < 0.0:
			along = minf(along + _friction_drop(-along, dt) + p.braking * dt, 0.0)
		velocity = sideways + dir * along
		_accelerate(dir, speed_cap, p.ground_accel, dt)
	velocity -= n * velocity.dot(n)


func _friction_drop(speed: float, dt: float) -> float:
	return maxf(speed, p.stop_speed) * p.ground_friction * dt


func _air_move(wish_dir: Vector3, speed_cap: float, dt: float) -> void:
	if wish_dir != Vector3.ZERO:
		_accelerate(wish_dir, minf(speed_cap, p.air_speed_cap), p.air_accel, dt)
		var h := Vector3(velocity.x, 0.0, velocity.z)
		var spd := h.length()
		if p.air_control > 0.0 and spd > 0.1:
			h = (h + wish_dir * (p.air_control * p.air_accel * dt)).normalized() * spd
			velocity.x = h.x
			velocity.z = h.z
	velocity.y -= p.gravity * dt


## Adds speed along `dir` only while the projection of the velocity on it is below `speed_cap`.
func _accelerate(dir: Vector3, speed_cap: float, accel: float, dt: float) -> void:
	var add := speed_cap - velocity.dot(dir)
	if add <= 0.0:
		return
	velocity += dir * minf(accel * dt, add)
