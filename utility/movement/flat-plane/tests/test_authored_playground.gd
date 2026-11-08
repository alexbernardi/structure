extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const Comparison = preload("res://scenes/locomotion_comparison.tscn")
const Events = preload("res://midi/midi_events.gd")
const DT := 1.0 / 120.0
var _tree: SceneTree
var _scene


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_scene = Scene.instantiate()
	_scene.options = {"no-capture": "true", "no-hardware": "true", "no-window-state": "true", "tuning-state": ""}
	_tree.root.add_child(_scene)
	await _tree.process_frame
	_scene.set_process(false)
	_scene.set_physics_process(false)
	_scene.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_scene.body.teleport(Vector3(150, 0.05, 150))
	await _tree.physics_frame
	await _tree.physics_frame


func after_each() -> void:
	_scene.queue_free()
	await _tree.process_frame


func test_default_ownership_live_switch_and_frozen_visual(t) -> void:
	t.ok(_scene.authored_visual.visible and _scene.authored_animation.tree.active, "authored is the default visible writer")
	t.ok(not _scene.authored_visual.player.active, "AnimationPlayer supplies clips but never competes with AnimationTree")
	t.ok(not _scene.visual.visible and not _scene.visual.walk_animation.tree.active, "legacy graph is disabled")
	var generation: int = _scene.visual.walk_animation.generation
	for i in 30:
		_scene._process(DT)
	t.eq(_scene.visual.walk_animation.generation, generation, "inactive procedural clips never regenerate")
	var position: Vector3 = _scene.body.position
	var velocity: Vector3 = _scene.body.velocity
	var height: float = _scene.body.current_height()
	for legacy in [true, false, true, false]:
		_scene.locomotion_params.set_value("legacy", 1.0 if legacy else 0.0)
		t.eq(_scene.visual.walk_animation.tree.active, legacy, "only selected graph active")
		t.eq(_scene.authored_animation.tree.active, not legacy, "only selected graph active")
		t.eq(_scene.body.position, position, "toggle cannot teleport physics")
		t.eq(_scene.body.velocity, velocity, "toggle cannot change velocity")
		t.eq(_scene.body.current_height(), height, "toggle cannot resize collider")
	_scene.animation_enabled = false
	_scene.body.position += Vector3(3, 0, 0)
	_scene._process(DT)
	t.near(_scene.authored_visual.global_position, _scene.body.global_position + Vector3.UP * _scene.body.step_offset, 0.001, "frozen animation still follows the moving body")


func test_real_displacement_drives_cadence_and_teleports_do_not(t) -> void:
	for sprint in [false, true]:
		for i in 180:
			await _tree.physics_frame
			_scene.simulate_tick({"move": Vector2(0, 1), "sprint": sprint}, DT)
			_scene._process(DT)
		t.near(_scene.body.core.horizontal_speed(), 12.0 if sprint else 6.0, 0.05, "existing physical defaults unchanged")
		t.near(_scene.authored_animation.measured_speed, _scene.body.core.horizontal_speed(), 0.01, "measured real movement, not an input wish")
		t.eq(_scene.authored_animation.model.state, "Run", "normal and sprint both use authored running")
	_scene.teleport_to_landmark(1)
	_scene._process(DT)
	t.eq(_scene.authored_animation.measured_speed, 0.0, "respawn/teleport distance excluded")


func _fader(strip: int, value: int) -> void:
	var mapping: Dictionary = _scene.midi.config.mapping_of("strip%d_fader" % strip)
	var signature: PackedStringArray = mapping.sig.split(":")
	var raw := int(round(lerpf(float(mapping.raw_min), float(mapping.raw_max), value / 127.0)))
	_scene.midi.handle_midi(Events.make_input_event(signature[0], int(signature[1]), int(signature[2]), raw, 0, false))


func test_simplified_bank_uses_verified_midi_mapping_and_preserves_legacy(t) -> void:
	_scene.midi.rescan_interval = 0.0
	_scene.midi._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])
	t.eq(_scene.tuning.bindings.bank_count(), 4, "three physical banks and one animation bank")
	t.eq(_scene.tuning.load_errors, [], "new shipped binding file loads")
	t.eq(_scene.tuning.bindings.unresolved(_scene.tuning.registry), [], "all keys resolve")
	_scene.tuning.engine.switch_bank(3)
	for strip in range(1, 5):
		var key: String = _scene.tuning.bindings.slot_key(3, strip, "fader")
		t.ok(key.begins_with("locomotion."), "new animation controls, not old procedural knobs")
		_fader(strip, 127)
		_fader(strip, 0)
		_fader(strip, 64)
		var id := key.trim_prefix("locomotion.")
		var definition: Dictionary = _scene.locomotion_params.def(id)
		t.near(_scene.locomotion_params.get_value(id), lerpf(definition.min, definition.max, 64.0 / 127.0), definition.step, "real mapped fader changes " + key)
	_fader(6, 0)
	_fader(6, 127)
	t.ok(_scene.locomotion_params.is_on("legacy") and _scene.visual.visible, "mapped legacy switch changes the live writer")
	_fader(6, 0)
	t.ok(not _scene.locomotion_params.is_on("legacy"), "can return without restarting")
	t.ok(_scene.tuning.load_preset("default"), "existing preset still loads")
	t.ok(_scene.tuning.registry.has_key("body.body_dynamics"), "legacy parameters remain addressable")
	t.near(_scene.params.get_value("max_ground_speed"), 6.0, 0.001, "legacy preset keeps physical defaults")
	var Store = preload("res://tuning/preset_store.gd")
	_scene.tuning.presets = Store.new("user://authored_preset_test")
	var saved: Dictionary = _scene.tuning.save_preset_as("authored_test")
	t.ok(saved.ok, "new and legacy parameters save together")
	var before: float = _scene.locomotion_params.get_value("transition_duration")
	_scene.locomotion_params.set_value("transition_duration", 0.35)
	t.ok(_scene.tuning.load_preset("authored_test"), "authored preset reloads")
	t.eq(_scene.locomotion_params.get_value("transition_duration"), before, "authored value round trips")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://authored_preset_test/authored_test.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://authored_preset_test"))


func test_recorded_comparison_has_identical_physics_with_and_without_animation(t) -> void:
	_scene.queue_free()
	await _tree.process_frame
	_scene = Comparison.instantiate()
	_tree.root.add_child(_scene)
	await _tree.process_frame
	_scene.set_physics_process(false)
	_scene.set_process(false)
	_scene.restart()
	var maximum_error := 0.0
	var states := {}
	var speeds := {}
	for i in _scene.frames.size():
		await _tree.physics_frame
		_scene._physics_process(DT)
		_scene.left._process(DT)
		_scene.right._process(DT)
		maximum_error = maxf(maximum_error, _scene.left.body.position.distance_to(_scene.right.body.position))
		t.eq(_scene.left.body.velocity, _scene.right.body.velocity, "animation never changes physical velocity")
		states[_scene.right.authored_animation.model.state] = true
		if i % 360 == 359 and i < 2160:
			speeds[i / 360] = _scene.right.body.core.horizontal_speed()
		if i == 2100:
			_scene.left.animation_enabled = false
	t.eq(maximum_error, 0.0, "entire recorded physical trajectory is bit-identical in separate worlds")
	for i in 6:
		t.near(speeds[i], [0.0, 1.0, 2.0, 4.0, 6.0, 8.0][i], 0.02, "actual requested physical speed trial")
	for state in ["Idle", "Run", "Jump", "Fall", "Land", "Crouch"]:
		t.ok(states.has(state), "recording exercises " + state)
	_scene.right.tuning.scene_action.emit("record_toggle", {})
	t.ok(_scene.get_node("Controls/Toolbar/Playground") is Button, "comparison exposes a route back to live movement")
