extends RefCounted

const SCENE := "res://scenes/flat_plane.tscn"
const Events = preload("res://midi/midi_events.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")
const Behavior = preload("res://midi/control_behavior.gd")
const DT := 1.0 / 120.0

const BIND_COPY := "user://scene_test_bindings.json"
const PRESET_COPY := "user://scene_test_presets"
const STATE := "user://scene_test_state.json"

var _s
var _tree: SceneTree


func _copy(src: String, dst: String) -> void:
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src))
	f.close()


func _prepare_files() -> void:
	_copy("res://config/tuning_bindings.json", BIND_COPY)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_COPY))
	for n in ["default", "floaty", "slippery", "snappy", "strafe_lab"]:
		_copy("res://presets/%s.json" % n, "%s/%s.json" % [PRESET_COPY, n])


func _cleanup_files() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BIND_COPY + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE))
	var d := DirAccess.open(PRESET_COPY)
	if d:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PRESET_COPY))


func _boot(extra := {}) -> void:
	_s = load(SCENE).instantiate()
	var opts := {"no-capture": "true", "no-hardware": "true", "tuning-ui": "true", "midi-config": "res://config/midi_mapping.json",
		"tuning-bindings": BIND_COPY, "preset-dir": PRESET_COPY, "tuning-state": STATE}
	opts.merge(extra, true)
	_s.options = opts
	_tree.root.add_child(_s)
	await _tree.process_frame   # let _ready run first: it re-enables the scene's own processing
	_s.set_physics_process(false)
	_s.set_process(false)
	if _s.midi != null:
		_s.midi._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])
	await _tree.physics_frame
	await _tree.physics_frame


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_cleanup_files()
	_prepare_files()
	await _boot()


func after_each() -> void:
	if _s != null and is_instance_valid(_s):
		_s.queue_free()
		await _tree.process_frame
	_cleanup_files()


# ------------------------------------------------------------------ synthetic hardware, built from the learned mapping

func _mapping(control_id: String) -> Dictionary:
	return _s.midi.config.mapping_of(control_id)


func _send(sig_kind: String, channel: int, number: int, value: int, off := false) -> void:
	_s.midi.handle_midi(Events.make_input_event(sig_kind, channel, number, value, 0, off))


func _move_fader(strip: int, v: float) -> void:
	var m := _mapping("strip%d_fader" % strip)
	var parts: PackedStringArray = String(m.sig).split(":")
	_send(parts[0], int(parts[1]), int(parts[2]), int(round(lerpf(float(m.raw_min), float(m.raw_max), v))))


func _turn(strip: int, steps: int) -> void:
	var m := _mapping("strip%d_knob" % strip)
	var parts: PackedStringArray = String(m.sig).split(":")
	var raw := -1
	for candidate in [1, 65, 127, 63]:
		if signi(Behavior.decode_relative(candidate, m)) == signi(steps):
			raw = candidate
			break
	for i in absi(steps):
		_send(parts[0], int(parts[1]), int(parts[2]), raw)


func _tap(control_id: String) -> void:
	var parts: PackedStringArray = String(_mapping(control_id).sig).split(":")
	_send(parts[0], int(parts[1]), int(parts[2]), 127)
	_send(parts[0], int(parts[1]), int(parts[2]), 0, true)


func _run(frame: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		await _tree.physics_frame
		_s.body.simulate(frame, DT)


func _walk() -> Dictionary:
	return {"move": Vector2(0, 1), "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}


# ------------------------------------------------------------------ tests

func test_scene_wires_midi_and_tuning_together(t) -> void:
	t.ok(_s.midi != null and _s.tuning != null and _s.tuning.engine != null, "manager, tuning system and engine exist")
	t.ok(_s.midi.config.mappings().size() >= 59, "the learned mapping is loaded (%d controls)" % _s.midi.config.mappings().size())
	t.ok(_s.midi.config.unmapped_ids().is_empty(), "every required control is mapped")
	t.ok(_s.tuning.hud != null and _s.tuning.editor != null, "HUD and editor were built")
	t.eq(_s.tuning.load_errors, [], "shipped bindings are accepted")
	t.ok(_s.tuning.registry.has_key("movement.max_ground_speed"), "movement parameters are registered")


func test_a_fader_changes_gameplay_through_the_real_mapping(t) -> void:
	_move_fader(1, 0.9)       # park high, away from the value (4.5 m/s = 0.25)
	_move_fader(1, 0.1)       # cross the value: pickup engages
	_move_fader(1, 0.5)
	t.near(_s.params.get_value("max_ground_speed"), 8.0, 0.15, "strip 1 fader = max ground speed: %.2f" % _s.params.get_value("max_ground_speed"))
	_s.body.teleport(Vector3(150, 0.05, 150))   # open ground: nothing to slow the run
	await _run(_walk(), 2.0)
	var v: Vector3 = _s.body.velocity
	t.near(Vector2(v.x, v.z).length(), _s.params.get_value("max_ground_speed"), 0.15, "and the character really runs at that speed (%.2f m/s)" % Vector2(v.x, v.z).length())
	_move_fader(1, 0.2)
	await _run(_walk(), 1.5)
	v = _s.body.velocity
	t.ok(Vector2(v.x, v.z).length() < 5.0, "moving the fader down slows the running character live: %.2f m/s" % Vector2(v.x, v.z).length())


func test_a_knob_fine_tunes_and_the_fader_must_pick_up_again(t) -> void:
	_turn(1, 3)
	t.eq(_s.params.get_value("max_ground_speed"), 4.8, "three clicks clockwise = +0.3 m/s")
	_turn(1, -1)
	t.eq(_s.params.get_value("max_ground_speed"), 4.7, "one click back")
	_move_fader(1, 0.9)
	t.eq(_s.params.get_value("max_ground_speed"), 4.7, "a fader far from the value does not take over")


func test_bank_switch_never_jumps_a_parameter(t) -> void:
	for strip in range(1, 9):
		_move_fader(strip, 0.95)
	var before: Dictionary = _s.tuning.registry.capture().movement.duplicate()
	_tap("global_bank_next")
	t.eq(_s.tuning.engine.bank, 1, "bank 2 is active")
	for strip in range(1, 9):
		_move_fader(strip, 0.93)
	t.eq(_s.tuning.registry.capture().movement, before, "parked faders nudged after the switch changed nothing")
	_move_fader(2, 0.0)     # drag strip 2 (gravity) down through its value
	t.ok(_s.params.get_value("gravity") <= 19.6 + 0.01, "after crossing, the fader owns the value")
	t.ok(absf(_s.params.get_value("gravity") - 19.6) < 20.0, "and it never leapt to the old fader position first")


func test_buttons_reset_lock_and_select(t) -> void:
	_turn(1, 20)
	t.ok(_s.params.get_value("max_ground_speed") > 6.0, "tuned up")
	_tap("strip1_mute")
	t.eq(_s.params.get_value("max_ground_speed"), 4.5, "M resets to default")
	_tap("strip1_solo")
	_turn(1, 20)
	t.eq(_s.params.get_value("max_ground_speed"), 4.5, "S locked it: the knob does nothing")
	t.ok(_s.tuning.engine.locked.has("movement.max_ground_speed"), "lock state visible to the HUD")
	_tap("strip1_select")
	t.eq(_s.tuning.engine.selected_key, "movement.max_ground_speed", "Select shows details")


func test_global_buttons_respawn_and_teleport(t) -> void:
	_s.body.teleport(Vector3(30, 0.05, 30))
	_tap("global_play")
	t.near(_s.body.global_position.distance_to(_s.world.spawn_transform.origin), 0.0, 0.1, "Play respawns")
	_tap("global_nav_right")
	var names: Array = _s.landmark_names()
	t.near(_s.body.global_position.distance_to(_s.world.landmarks[names[1]] + Vector3(0, 0.05, 0)), 0.0, 0.1, "Right teleports to the next landmark: %s" % names[1])
	_tap("global_nav_left")
	_tap("global_nav_left")
	t.near(_s.body.global_position.distance_to(_s.world.landmarks[names[names.size() - 1]] + Vector3(0, 0.05, 0)), 0.0, 0.1, "Left wraps around to the last: %s" % names[names.size() - 1])
	t.eq(_s.body.velocity, Vector3.ZERO, "motion cleared on teleport")


func test_presets_cycle_with_the_transport_buttons(t) -> void:
	_tap("global_forward")
	t.eq(_s.tuning.engine.preset_name, "default", "forward loads the first preset")
	_tap("global_forward")
	t.eq(_s.tuning.engine.preset_name, "floaty", "and the next")
	t.eq(_s.params.get_value("gravity"), 9.8, "floaty has low gravity")
	_tap("global_rewind")
	t.eq(_s.tuning.engine.preset_name, "default", "rewind goes back")
	t.eq(_s.params.get_value("gravity"), 19.6, "default values restored")


func test_loading_a_preset_does_not_let_parked_faders_yank_values(t) -> void:
	for strip in range(1, 9):
		_move_fader(strip, 0.9)
	_s.tuning.load_preset("snappy")
	var snappy_speed: float = _s.params.get_value("max_ground_speed")
	_move_fader(1, 0.88)
	t.eq(_s.params.get_value("max_ground_speed"), snappy_speed, "the fader at 0.9 cannot overwrite the preset value")
	_move_fader(1, 0.1)
	_move_fader(1, 0.3)
	t.near(_s.params.get_value("max_ground_speed"), 1.0 + 0.3 * 14.0, 0.15, "after crossing it is live again")


func test_save_preset_roundtrip_through_the_scene(t) -> void:
	_turn(1, 15)
	_turn(2, -8)
	var tuned: Dictionary = _s.tuning.registry.capture().movement.duplicate()
	var r: Dictionary = _s.tuning.save_preset_as("My Tuned Setup")
	t.ok(r.ok and r.name == "my_tuned_setup", "saved: %s" % str(r))
	t.eq(_s.tuning.engine.preset_name, "my_tuned_setup", "becomes the current preset")
	t.ok(not _s.tuning.engine.is_modified(), "and is not 'modified'")
	_tap("global_stop")
	t.ok(_s.params.is_default("max_ground_speed"), "Stop resets everything")
	t.ok(_s.tuning.load_preset("my_tuned_setup"), "reload")
	t.eq(_s.tuning.registry.capture().movement, tuned, "every value came back exactly")


func test_default_preset_is_protected(t) -> void:
	_tap("global_forward")   # default
	_turn(1, 5)
	_tap("global_nav_up")    # save current
	t.ok(_s.tuning.engine.preset_name != "default" and _s.tuning.engine.preset_name.begins_with("tuned_"), "saved under a new name instead: %s" % _s.tuning.engine.preset_name)
	t.ok(not _s.tuning.save_preset_as("default").ok, "explicit overwrite refused")
	t.ok(not _s.tuning.delete_preset("default"), "delete refused")
	t.eq(_s.tuning.presets.load_preset("default").targets.movement.max_ground_speed, 4.5, "file untouched")


func test_remembers_preset_and_bank_between_sessions(t) -> void:
	_tap("global_forward")
	_tap("global_forward")   # floaty
	_tap("global_bank_next")
	_s.tuning.save_state()
	_s.queue_free()
	await _tree.process_frame
	await _boot()
	t.eq(_s.tuning.engine.preset_name, "floaty", "preset restored")
	t.eq(_s.params.get_value("gravity"), 9.8, "with its values")
	t.eq(_s.tuning.engine.bank, 1, "and the bank")


func test_unplugging_is_shown_and_does_not_break_tuning(t) -> void:
	_s.midi._apply_ports([])
	t.ok(not _s.midi.connected, "disconnected")
	_s.midi._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])
	_turn(1, 2)
	t.eq(_s.params.get_value("max_ground_speed"), 4.7, "works again right after reconnecting")


func test_hud_modes_and_notifications(t) -> void:
	var hud = _s.tuning.hud
	t.eq(hud.mode, 0, "starts in full mode")
	_tap("global_nav_down")
	t.eq(hud.mode, 1, "Down cycles to compact")
	_tap("global_nav_down")
	t.eq(hud.mode, 2, "then hidden")
	t.ok(not hud.visible or hud._toasts.size() > 0, "hidden unless a notification is showing")
	_tap("global_nav_down")
	t.eq(hud.mode, 0, "and back to full")
	_s.tuning.load_preset("floaty")
	t.ok(hud._toasts.any(func(x: Dictionary) -> bool: return String(x.text).contains("floaty")), "loading a preset posts a notification")
	await _tree.process_frame


func test_editor_pauses_movement_and_edits_bindings(t) -> void:
	var ed = _s.tuning.editor
	_s.tuning.toggle_editor()
	t.ok(ed.visible, "editor opens")
	t.ok(not _s.live.enabled, "keyboard movement is paused while it is open")
	t.eq(ed._fader_opts[0].selected, _s.tuning.registry.keys().find("movement.max_ground_speed") + 1, "strip 1 fader shows its parameter")
	ed._on_slot_selected(_s.tuning.registry.keys().find("movement.gravity") + 1, 8, "fader")
	t.eq(_s.tuning.bindings.slot_key(0, 8, "fader"), "movement.gravity", "choosing in the list edits the binding")
	ed._on_slot_selected(0, 8, "fader")
	t.eq(_s.tuning.bindings.slot_key(0, 8, "fader"), "", "(none) clears it")
	ed._on_strip_action(ed._strip_action_opts.mute.item_count - 1, "mute")
	t.ok(_s.tuning.bindings.strip_action("mute") != "reset_param", "button actions are editable")
	_s.tuning.toggle_editor()
	t.ok(_s.live.enabled, "movement resumes when it closes")


func test_binding_a_parameter_by_moving_a_control_via_the_editor(t) -> void:
	_s.tuning.editor._learn_param.select(_s.tuning.registry.keys().find("movement.air_control"))
	t.ok(_s.tuning.engine.begin_learn("movement.air_control"), "armed")
	_move_fader(8, 0.5)
	t.eq(_s.tuning.bindings.slot_key(0, 8, "fader"), "movement.air_control", "strip 8's fader now drives air steering")
	_move_fader(8, 0.0)
	_move_fader(8, 1.0)
	_move_fader(8, 0.5)
	t.near(_s.params.get_value("air_control"), 0.5, 0.02, "and it works immediately")


func test_save_bindings_persists_edits_and_a_bad_file_is_reported(t) -> void:
	_s.tuning.bindings.assign(0, 8, "fader", "movement.gravity")
	t.ok(_s.tuning.save_bindings().ok, "saved")
	_s.queue_free()
	await _tree.process_frame
	await _boot()
	t.eq(_s.tuning.bindings.slot_key(0, 8, "fader"), "movement.gravity", "edit survived a restart")
	_s.queue_free()
	await _tree.process_frame
	var f := FileAccess.open(BIND_COPY, FileAccess.WRITE)
	f.store_string("{\"schema\": 4}")
	f.close()
	await _boot()
	t.ok(not _s.tuning.load_errors.is_empty(), "a rejected file is reported")
	t.eq(_s.tuning.bindings.bank_count(), Bindings.default_data().banks.size(), "defaults are used meanwhile")
	t.eq(FileAccess.get_file_as_string(BIND_COPY), "{\"schema\": 4}", "the bad file is not overwritten on startup")


func test_keyboard_shortcuts_mirror_the_buttons(t) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_PAGEDOWN
	key.keycode = KEY_PAGEDOWN
	_s.tuning._unhandled_input(key)
	t.eq(_s.tuning.engine.bank, 1, "PageDown = next bank")
	key.physical_keycode = KEY_HOME
	key.keycode = KEY_HOME
	_s.tuning.engine.bank = 0
	_s.params.set_value("max_ground_speed", 9.0)
	_s.tuning._unhandled_input(key)
	t.ok(_s.params.is_default("max_ground_speed"), "Home = reset all")


func test_no_tuning_option_leaves_a_plain_sandbox(t) -> void:
	_s.queue_free()
	await _tree.process_frame
	await _boot({"no-tuning": "true"})
	t.ok(_s.tuning == null and _s.midi == null, "no MIDI, no tuning")
	await _run(_walk(), 0.5)
	t.ok(_s.body.velocity.length() > 1.0, "the character still moves")
