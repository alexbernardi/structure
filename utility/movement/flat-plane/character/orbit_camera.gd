## Third-person follow / orbit camera. Owns only the view: yaw and pitch (driven by the mouse), distance (wheel),
## smoothed follow of a target, and a collision-aware spring arm. `yaw` is what movement input is relative to.
extends Node3D

const MIN_PITCH := deg_to_rad(-75.0)
const MAX_PITCH := deg_to_rad(60.0)
const MIN_DISTANCE := 1.2
const MAX_DISTANCE := 12.0

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var distance := 4.2
var sensitivity := 0.0025
var follow_height := 1.45
var follow_smoothing := 18.0
var mouse_look_enabled := true   ## false while a UI wants the cursor

var arm := SpringArm3D.new()
var camera := Camera3D.new()
var _focus := Vector3.ZERO


func _ready() -> void:
	top_level = true
	# Moved every rendered frame from the target's interpolated transform, so it must not be interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arm.collision_mask = 1
	arm.shape = SphereShape3D.new()
	(arm.shape as SphereShape3D).radius = 0.25
	arm.margin = 0.1
	add_child(arm)
	camera.fov = 75.0
	camera.current = true
	arm.add_child(camera)
	arm.spring_length = distance
	if target:
		_focus = _target_position()
	_apply()


func look(relative: Vector2) -> void:
	yaw -= relative.x * sensitivity
	pitch = clampf(pitch - relative.y * sensitivity, MIN_PITCH, MAX_PITCH)


func zoom(step: float) -> void:
	distance = clampf(distance + step, MIN_DISTANCE, MAX_DISTANCE)


func _unhandled_input(event: InputEvent) -> void:
	if not mouse_look_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		look(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-0.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(0.4)


func _target_position() -> Vector3:
	if target == null:
		return Vector3.ZERO
	return target.get_global_transform_interpolated().origin + Vector3.UP * follow_height


func _process(delta: float) -> void:
	if target:
		_focus = _focus.lerp(_target_position(), 1.0 - exp(-follow_smoothing * delta))
	_apply()


func _apply() -> void:
	global_position = _focus
	global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	arm.spring_length = distance


## Snap to the target without smoothing (after a respawn).
func snap() -> void:
	if target:
		_focus = _target_position()
	_apply()
