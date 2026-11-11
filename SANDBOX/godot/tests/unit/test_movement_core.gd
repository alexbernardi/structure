## The installed Movement Core used from the main game project with no laboratory code (SYSTEM-ROOMS/movement_core):
## a character is built in a minimal world (a floor and one block), driven by player input, runs, jumps, mantles the
## block, reports its state and events to another system, and takes and loses a movement modifier.
extends RefCounted

const MovementCharacter = preload("res://systems/movement_core/movement_character.gd")
const Profiles = preload("res://systems/movement_core/capability/movement_profiles.gd")
const Modifier = preload("res://systems/movement_core/capability/movement_modifier.gd")
const DT := 1.0 / MovementCharacter.TICK_RATE
const BLOCK_FACE_Z := -6.0
const BLOCK_HEIGHT := 1.4

var _tree: SceneTree
var _root: Node3D


## Stands in for another system (combat, UI, audio): it only listens to the character's public signals.
class Listener:
	extends RefCounted
	var states: Array[String] = []
	var started: Array[String] = []
	var finished: Array[String] = []
	var landings := 0
	var capability_changes := 0

	func attach(character) -> void:
		character.state_changed.connect(func(_previous: String, current: String) -> void: states.append(current))
		character.traversal_started.connect(func(move: String) -> void: started.append(move))
		character.traversal_finished.connect(func(move: String) -> void: finished.append(move))
		character.landed.connect(func(_impact: float) -> void: landings += 1)
		character.capabilities_changed.connect(func() -> void: capability_changes += 1)


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_root = Node3D.new()
	_tree.root.add_child(_root)
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))                                                   # the floor
	_box(Vector3(0, BLOCK_HEIGHT / 2.0, BLOCK_FACE_Z - 1.0), Vector3(3, BLOCK_HEIGHT, 2))             # a block to climb


func after_each() -> void:
	_root.queue_free()
	await _tree.process_frame


func _box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()   # world geometry on collision layer 1 (the contract)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	body.position = at
	_root.add_child(body)


func _character():
	var character = MovementCharacter.new()
	_root.add_child(character)   # builds itself in _ready
	await _tree.process_frame
	character.spawn(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	character.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	await _tree.physics_frame
	return character


func _tick(character, frame: Dictionary) -> void:
	character.simulate(frame, DT)
	character.present(DT)


func test_builds_from_the_installed_package_alone(t) -> void:
	var character = await _character()
	t.eq(character.VERSION, "1.0.0", "Movement Core version")
	t.ok(character.body is CharacterBody3D and character.visual != null and character.animation != null, "body, mannequin and animation built")
	t.ok(character.vault_profile.valid, "the authored traversal clips resolved (vault profile measured on the mannequin)")
	t.eq(character.body.collision_layer, 2, "the character is on collision layer 2")
	t.eq(character.body.collision_mask, 1, "and collides with world layer 1")
	for _i in 60:
		_tick(character, MovementCharacter.empty_frame())
	t.eq(character.state, "grounded", "standing on the floor")
	t.near(character.body.global_position.y, 0.0, 0.05, "on the ground")


func test_player_input_runs_jumps_and_mantles_while_another_system_listens(t) -> void:
	var character = await _character()
	var listener := Listener.new()
	listener.attach(character)
	MovementCharacter.register_input_actions()
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "crouch"]:
		t.ok(InputMap.has_action(action), "input action %s registered" % action)
	# Player input: the keyboard actions, read through the character's own input source.
	Input.action_press("move_forward")
	var top_speed := 0.0
	for _i in 120:
		var frame: Dictionary = character.live.sample(0.0)
		_tick(character, frame)
		top_speed = maxf(top_speed, Vector2(character.velocity().x, character.velocity().z).length())
	Input.action_release("move_forward")
	t.ok(top_speed > 5.0, "runs from the move action (%.2f m/s)" % top_speed)
	# A jump in place.
	for _i in 120:
		_tick(character, MovementCharacter.empty_frame())
	var frame := MovementCharacter.empty_frame()
	frame.jump_pressed = true
	frame.jump_held = true
	_tick(character, frame)
	var peak := 0.0
	for _i in 120:
		_tick(character, MovementCharacter.empty_frame())
		peak = maxf(peak, character.body.global_position.y)
	t.ok(peak > 0.5, "jumps (apex %.2f m)" % peak)
	t.ok(listener.states.has("airborne") and listener.landings >= 1, "the listener saw the jump and the landing (%s)" % [listener.states])
	# Run at the block and press Space close to it: a mantle onto its top.
	character.teleport(Vector3(0, 0.05, -1.0))
	var pressed := false
	var top := -INF
	for _i in 600:
		var f := MovementCharacter.empty_frame()
		f.move = Vector2(0, 1)
		if not pressed and character.body.global_position.z < BLOCK_FACE_Z + 1.2:
			pressed = true
			f.jump_pressed = true
			f.jump_held = true
		_tick(character, f)
		top = maxf(top, character.body.global_position.y)
		if pressed and not character.traversing() and character.grounded() and character.body.global_position.y > BLOCK_HEIGHT - 0.1:
			break
	print("MOVEMENT_CORE choices ", character.traversal.choices, " states ", listener.states, " started ", listener.started)
	t.ok(listener.started.has("mantling"), "a traversal started and the listener was told (%s)" % [listener.started])
	t.ok(listener.finished.has("mantling"), "and finished (%s)" % [listener.finished])
	t.ok(top > BLOCK_HEIGHT - 0.1 and character.grounded(), "standing on the block's top (%.2f m)" % character.body.global_position.y)
	var snap: Dictionary = character.snapshot()
	t.eq(snap.state, character.state, "the snapshot carries the state for other systems")
	t.ok(snap.position is Vector3 and snap.velocity is Vector3, "and position and velocity")


func test_a_modifier_changes_movement_and_its_removal_restores_it(t) -> void:
	var character = await _character()
	var listener := Listener.new()
	listener.attach(character)
	var base_speed: float = character.attribute("max_ground_speed")
	var base_air_jumps: float = character.attribute("air_jumps")
	var boots = Modifier.make("test_boots", "Test boots", "equipment", [["max_ground_speed", "mul", 1.5], ["air_jumps", "add", 1]], [], INF, ["slide"])
	t.eq(boots.check().size(), 0, "the modifier definition is valid")
	t.ok(character.add_modifier(boots), "added")
	t.near(character.attribute("max_ground_speed"), base_speed * 1.5, 0.001, "run speed x1.5 (%.2f -> %.2f)" % [base_speed, character.attribute("max_ground_speed")])
	t.near(character.attribute("air_jumps"), base_air_jumps + 1.0, 0.001, "one more air jump")
	t.ok(not character.can("slide"), "the slide capability revoked")
	t.ok(character.remove_modifier("test_boots"), "removed")
	t.near(character.attribute("max_ground_speed"), base_speed, 0.001, "run speed restored")
	t.ok(character.can("slide"), "slide granted again")
	t.ok(listener.capability_changes >= 2, "the listener heard both changes (%d)" % listener.capability_changes)
	# The shipped example: cybernetic legs raise the vault and mantle limits.
	var cyber = Profiles.cybernetic_legs()
	var base_mantle: float = character.attribute("mantle_max_height")
	character.add_modifier(cyber)
	t.ok(character.attribute("mantle_max_height") > base_mantle, "cybernetic legs raise the mantle height")
	character.remove_modifier(cyber.id)
	t.near(character.attribute("mantle_max_height"), base_mantle, 0.001, "and removing them restores it")
	t.ok(character.apply_impulse(Vector3(0, 0, 3)), "a knockback impulse is accepted while not traversing")
