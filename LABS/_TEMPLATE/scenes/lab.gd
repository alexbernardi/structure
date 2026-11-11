## {{LAB_NAME}} laboratory: a minimal test ground (floor, a few blocks, light) with the approved movement character
## when movement_core is installed (res://systems/movement_core/). Build the laboratory's own system next to it;
## reach the character only through its public interface (SYSTEM-ROOMS/movement_core/CONTRACT.md).
##   WASD run, mouse look, Space jump / vault / climb, Shift sprint, Ctrl crouch / slide, Esc frees the mouse.
extends Node3D

const MOVEMENT_CHARACTER := "res://systems/movement_core/movement_character.gd"
const ORBIT_CAMERA := "res://systems/movement_core/character/orbit_camera.gd"

var character    ## movement_character.gd, or null without movement_core
var camera


func _ready() -> void:
	_build_world()
	if ResourceLoader.exists(MOVEMENT_CHARACTER):
		var MovementCharacter = load(MOVEMENT_CHARACTER)
		MovementCharacter.register_input_actions()
		character = MovementCharacter.new()
		character.name = "MovementCharacter"
		add_child(character)
		character.spawn(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 4)))
		camera = load(ORBIT_CAMERA).new()
		camera.target = character.body
		add_child(camera)
		character.drive_self = true   # samples the keyboard every tick and presents every frame
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_dt: float) -> void:
	if character != null:
		character.input_yaw = camera.yaw


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## World geometry goes on collision layer 1 (the movement contract).
func _build_world() -> void:
	_block(Vector3(0, -0.5, 0), Vector3(60, 1, 60), Color(0.55, 0.6, 0.65))
	_block(Vector3(-3, 0.5, -6), Vector3(2, 1.0, 0.4), Color(0.8, 0.5, 0.3))    # vaultable wall
	_block(Vector3(3, 0.7, -7), Vector3(2.5, 1.4, 2.0), Color(0.4, 0.6, 0.8))   # mantle block
	_block(Vector3(0, 1.5, -14), Vector3(6, 3.0, 1.0), Color(0.5, 0.5, 0.75))   # 3.0 m wall: jump, catch, hang, shimmy
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	add_child(env)


func _block(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	body.position = at
	add_child(body)
