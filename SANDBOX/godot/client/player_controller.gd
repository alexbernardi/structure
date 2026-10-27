## First-person player body. Velocity comes from the integrated movement system (systems/movement);
## the client predicts its own movement and the server validates the reported positions.
extends CharacterBody3D

const Movement = preload("res://systems/movement/movement_model.gd")
const Palette = preload("res://client/palette.gd")

const MOUSE_SENSITIVITY := 0.0025
const EYE_HEIGHT := 1.6

var movement_params := Movement.default_params()
var camera: Camera3D
var held_item: MeshInstance3D
var look_enabled := false
var _pitch := 0.0


func _init() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	add_child(camera)
	held_item = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.28, 0.35)
	held_item.mesh = box
	held_item.position = Vector3(0.35, -0.32, -0.65)
	held_item.material_override = Palette.material(Palette.RESOURCE)
	held_item.visible = false
	camera.add_child(held_item)
	floor_snap_length = 0.3


func _ready() -> void:
	camera.make_current()


func set_carrying(carrying: bool) -> void:
	held_item.visible = carrying


func _unhandled_input(event: InputEvent) -> void:
	if look_enabled and event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	var jump := false
	if look_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		jump = Input.is_action_just_pressed("jump")
	var wish := global_basis * Vector3(input.x, 0.0, input.y)
	velocity = Movement.step(velocity, wish, is_on_floor(), jump, delta, movement_params)
	move_and_slide()
