## {{LAB_NAME}} laboratory smoke test: the scene builds, and with movement_core installed the approved character stands
## on the floor and runs. Add the laboratory's own tests next to this file (`structure.py lab validate`).
extends RefCounted

const Scene = preload("res://scenes/lab.tscn")
var _tree: SceneTree
var _scene


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_scene = Scene.instantiate()
	_tree.root.add_child(_scene)
	await _tree.process_frame


func after_each() -> void:
	_scene.queue_free()
	await _tree.process_frame


func test_scene_builds(t) -> void:
	t.ok(_scene.get_child_count() > 0, "the test ground is built")


func test_movement_character_runs_when_installed(t) -> void:
	if _scene.character == null:
		t.ok(true, "movement_core is not installed in this laboratory")
		return
	var character = _scene.character
	character.drive_self = false
	_scene.set_physics_process(false)
	await _tree.physics_frame
	var frame: Dictionary = character.empty_frame()
	frame.move = Vector2(0, 1)
	for _i in 180:
		character.simulate(frame, 1.0 / character.TICK_RATE)
		character.present(1.0 / character.TICK_RATE)
	t.ok(character.grounded(), "on the floor (%s)" % character.state)
	t.ok(Vector2(character.velocity().x, character.velocity().z).length() > 5.0, "running (%.2f m/s)" % character.velocity().length())
