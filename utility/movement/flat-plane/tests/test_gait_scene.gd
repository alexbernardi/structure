extends RefCounted

const SCENE := "res://scenes/gait_treadmill.tscn"
const Events = preload("res://midi/midi_events.gd")
const Behavior = preload("res://midi/control_behavior.gd")
const GaitParams = preload("res://animation/gait_params.gd")

const BIND_COPY := "user://gait_scene_bindings.json"
const PRESET_COPY := "user://gait_scene_presets"
const STATE := "user://gait_scene_state.json"
const DT := 1.0 / 60.0

var _tree: SceneTree
var _s


func before_each() -> void:
	_tree = Engine.get_main_loop()


func after_each() -> void:
	if _s != null and is_instance_valid(_s):
		_s.queue_free()
		await _tree.process_frame
	_s = null
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BIND_COPY + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE))
	var d := DirAccess.open(PRESET_COPY)
	if d:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PRESET_COPY))


func _boot(extra := {}, tuned := false) -> Node:
	var s: Node = load(SCENE).instantiate()
	var opts := {"no-hardware": "true", "no-window-state": "true"}
	if not tuned:
		opts["no-tuning"] = "true"
	opts.merge(extra, true)
	s.options = opts
	_tree.root.add_child(s)
	await _tree.process_frame   # _ready runs on the first frame and re-enables processing, so disable it afterwards
	s.set_process(false)
	_s = s
	return s


func _boot_tuned() -> Node:
	var f := FileAccess.open(BIND_COPY, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string("res://config/gait_bindings.json"))
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_COPY))
	for name in ["default", "stroll", "brisk", "stiff_robot", "shuffle"]:
		var g := FileAccess.open("%s/%s.json" % [PRESET_COPY, name], FileAccess.WRITE)
		g.store_string(FileAccess.get_file_as_string("res://presets_gait/%s.json" % name))
		g.close()
	var s: Node = await _boot({"midi-config": "res://config/midi_mapping.json", "tuning-bindings": BIND_COPY, "preset-dir": PRESET_COPY, "tuning-state": STATE}, true)
	s.midi._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])
	return s


func _run(s: Node, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		s.advance(DT)
		s._measure_slip(DT)


# ------------------------------------------------------------------ the scene

func test_it_loads_and_walks(t) -> void:
	var s := await _boot()
	await _run(s, 2.0)
	t.ok(s.model.pose.active, "the gait model is running")
	t.near(s.speed, s.gait_params.def("walk_speed").default, 1e-9, "at the default belt speed")
	t.ok(s.visual.gait_weight > 0.99, "and drives the skeleton")
	t.ok(s.model.phase > 0.0, "the cycle advanced")
	t.ok(s.cam.current and s.cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "side camera is orthographic by default")
	t.near(s.cam.global_position.x, 5.0, 1e-6, "looking at the character from the side")
	t.ok(is_zero_approx(s.visual.global_position.length()), "the character stays in place on the belt")


func test_the_belt_moves_at_the_walking_speed_and_stops_when_frozen(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("walk_speed", 1.6)
	s.advance(DT)
	var before: float = s.belt_offset
	await _run(s, 1.0)
	t.near(s.belt_offset - before, 1.6, 1.6 * DT * 2.0, "one second moves the belt by the walking speed in metres")
	s.gait_params.set_value("freeze", 1.0)
	var held: float = s.belt_offset
	await _run(s, 0.5)
	t.eq(s.belt_offset, held, "frozen: the belt stands still")
	s.gait_params.set_value("freeze", 0.0)
	s.gait_params.set_value("time_scale", 0.5)
	var slow_start: float = s.belt_offset
	await _run(s, 1.0)
	t.near(s.belt_offset - slow_start, 0.8, 0.05, "half-speed playback: half the belt travel")


func test_the_belt_follows_speed_changes_without_a_jump(t) -> void:
	var s := await _boot()
	await _run(s, 0.5)
	s.gait_params.set_value("walk_speed", 2.4)
	var last: float = s.speed
	var worst := 0.0
	for i in 60:
		s.advance(DT)
		worst = maxf(worst, s.speed - last)
		last = s.speed
	t.ok(worst <= 3.0 * DT + 1e-9, "the belt speed changes by at most its acceleration limit per frame: %s m/s" % worst)
	t.near(s.speed, 2.4, 1e-9, "and arrives")


func test_planted_feet_do_not_slip_on_the_belt_as_posed_on_the_skeleton(t) -> void:
	var s := await _boot()
	for speed in [0.8, 1.2, 1.8]:
		s.gait_params.set_value("walk_speed", speed)
		await _run(s, 1.5)   # lets the speed settle and fills one measuring window
		await _run(s, 1.2)
		t.ok(s.slip_l < 0.003 and s.slip_r < 0.003, "%.1f m/s: worst slip of a planted sole over the last second is L %.1f R %.1f mm/s" % [speed, 1000.0 * s.slip_l, 1000.0 * s.slip_r])


func test_slip_is_actually_measured(t) -> void:
	var s := await _boot()
	await _run(s, 2.2)
	t.ok(s._sole_valid.has(true), "a heel or toe is being tracked while it is planted")
	# a belt that disagrees with the gait must show up as slip: measure as if time ran twice as fast as the feet were told,
	# so the belt looks like it runs at half the planned speed (0.6 m/s against 1.2)
	var seen := 0.0
	for i in 40:
		s.advance(DT)
		s.gait_params.set_value("time_scale", 2.0)
		s._measure_slip(DT)
		s.gait_params.set_value("time_scale", 1.0)
		seen = maxf(seen, maxf(s._slip_peak[0], s._slip_peak[1]))
	t.near(seen, 0.5 * s.speed, 0.05, "the measured slip is the mismatch (half the belt speed here): %.2f m/s" % seen)

func test_keys_and_views(t) -> void:
	var s := await _boot()
	s.set_view("front")
	t.near(s.cam.global_position.z, -5.0, 1e-6, "front view looks at the face of the character (it walks toward -Z)")
	s.set_view("three-quarter")
	t.ok(s.cam.global_position.x > 1.0 and s.cam.global_position.z < -1.0, "three-quarter view")
	s.set_view("nonsense")
	t.eq(s.view, "three-quarter", "an unknown view is ignored")
	s.gait_params.set_value("view_ortho", 0.0)
	s._apply_camera()
	t.eq(s.cam.projection, Camera3D.PROJECTION_PERSPECTIVE, "the projection switch works")
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	s._unhandled_input(ev)
	t.ok(s.gait_params.is_on("freeze"), "space freezes")
	s._step_scrub(1.0 / 48.0)
	t.near(s.gait_params.get_value("scrub"), 1.0 / 48.0, 0.003, "stepping while frozen moves the scrub position")
	s._unhandled_input(ev)
	t.ok(not s.gait_params.is_on("freeze"), "space resumes")


func test_freeze_and_scrub_show_a_chosen_pose(t) -> void:
	var s := await _boot({"gait.freeze": "1", "gait.scrub": "0.25"})
	await _run(s, 0.5)
	t.near(s.model.phase, 0.25, 1e-9, "the command line can pose the walk (frozen at 0.25)")
	var a: Vector3 = s.visual.joint_position("foot_l")
	await _run(s, 0.5)
	t.eq(s.visual.joint_position("foot_l"), a, "and it holds exactly")


func test_turning_the_gait_model_off_shows_the_original_walk(t) -> void:
	var s := await _boot()
	await _run(s, 1.0)
	t.ok(s.visual.gait_weight > 0.99, "model on")
	s.gait_params.set_value("gait_model", 0.0)
	await _run(s, 0.5)
	t.ok(not s.model.pose.active, "the model is inactive")
	t.eq(s.visual.gait_weight, 0.0, "and the original pose is back")


# ------------------------------------------------------------------ the controller

func _mapping(control_id: String) -> Dictionary:
	return _s.midi.config.mapping_of(control_id)


func _send(kind: String, channel: int, number: int, value: int, off := false) -> void:
	_s.midi.handle_midi(Events.make_input_event(kind, channel, number, value, 0, off))


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


func test_the_registry_holds_the_gait_and_body_targets_and_every_binding_resolves(t) -> void:
	var s := await _boot_tuned()
	var reg = s.tuning.registry
	t.ok(reg.has_target("gait") and reg.has_target("rig") and reg.has_target("body") and not reg.has_target("movement"), "gait, proportions and body targets only")
	t.eq(s.tuning.bindings.unresolved(reg), [], "no binding points at a missing parameter")
	t.eq(s.tuning.bindings.bank_count(), 8, "the original gait banks plus the animation graph")
	var bound: Array = s.tuning.bindings.referenced_keys()
	var missing := []
	for key in reg.keys():
		if (String(key).begins_with("gait.") or String(key).begins_with("rig.")) and not bound.has(key):
			missing.append(key)
	t.eq(missing, [], "every gait and proportion parameter is on the controller")


func test_faders_knobs_and_switches_change_the_walk_live(t) -> void:
	var s := await _boot_tuned()
	var e = s.tuning.engine
	t.eq(s.tuning.bindings.bank_name(e.bank), "Walk Cycle", "starts on the walk cycle bank")
	_move_fader(1, 0.4)   # the walk speed's current position: picks it up
	_move_fader(1, 0.75)
	t.near(s.gait_params.get_value("walk_speed"), 2.25, 0.07, "fader 1 sets the walk speed (75 % of 0..3)")
	var step: float = s.gait_params.get_value("step_length")
	_turn(2, 4)
	t.ok(s.gait_params.get_value("step_length") > step, "knob 2 lengthens the step: %.2f -> %.2f m" % [step, s.gait_params.get_value("step_length")])
	e.switch_bank(3)
	t.eq(s.tuning.bindings.bank_name(e.bank), "Toggles", "the toggles bank")
	_move_fader(3, 1.0)
	_move_fader(3, 0.0)
	t.ok(not s.gait_params.is_on("foot_roll"), "fader 3 switches foot roll off")
	_move_fader(1, 1.0)
	_move_fader(1, 0.0)
	t.ok(not s.gait_params.is_on("gait_model"), "fader 1 switches the gait model off")
	s.advance(DT)
	t.ok(not s.model.pose.active, "and the next frame shows the original walk")
	_turn(4, 1)
	t.ok(s.gait_params.is_on("freeze"), "knob 4 on the toggles bank freezes the cycle")


func test_the_shipped_presets_load_and_apply(t) -> void:
	var s := await _boot_tuned()
	t.ok(s.tuning.load_preset("stiff_robot"), "loads")
	t.ok(not s.gait_params.is_on("foot_roll") and not s.gait_params.is_on("fx_pelvis_bob"), "no foot roll, no bob")
	t.ok(s.tuning.load_preset("brisk"), "brisk loads")
	t.near(s.gait_params.get_value("walk_speed"), 1.8, 1e-9, "brisk walk speed")
	t.ok(s.tuning.load_preset("default"), "default loads")
	t.near(s.gait_params.get_value("walk_speed"), s.gait_params.def("walk_speed").default, 1e-9, "and restores the defaults")
	t.ok(s.gait_params.is_on("foot_roll"), "including the switches")


func test_gait_values_survive_a_saved_preset(t) -> void:
	var s := await _boot_tuned()
	s.tuning.engine.set_param("gait.heel_strike_angle", 24.0, "test")
	s.tuning.engine.set_param("body.torso_freq", 4.0, "test")
	t.ok(s.tuning.save_preset_as("gait_test").ok, "saved")
	s.tuning.engine.set_param("gait.heel_strike_angle", 5.0, "test")
	s.tuning.engine.set_param("body.torso_freq", 1.0, "test")
	t.ok(s.tuning.load_preset("gait_test"), "loaded")
	t.near(s.gait_params.get_value("heel_strike_angle"), 24.0, 1e-9, "gait value restored")
	t.near(s.body_params.get_value("torso_freq"), 4.0, 1e-9, "body value restored")


func test_the_respawn_button_restarts_the_cycle(t) -> void:
	var s := await _boot_tuned()
	await _run(s, 1.0)
	t.ok(s.model.phase > 0.0, "walking")
	s._on_tuning_action("respawn", {})
	t.eq(s.model.phase, 0.0, "the cycle restarts at the left heel strike")
	s._on_tuning_action("teleport_next", {})
	t.eq(s.view, "side-left", "the teleport buttons step through the camera views")


func test_the_overlay_draws_without_errors(t) -> void:
	var s := await _boot()
	s.set_process(true)
	for i in 6:
		await _tree.process_frame
	t.ok(s.overlay.is_inside_tree(), "overlay is alive after drawing frames")
	s.gait_params.set_value("gait_model", 0.0)
	for i in 3:
		await _tree.process_frame
	s.gait_params.set_value("gait_model", 1.0)
	s.gait_params.set_value("freeze", 1.0)
	for i in 3:
		await _tree.process_frame
	t.ok(true, "drawn in every mode (model off, frozen) without an engine error")


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func test_the_keyboard_shortcuts_of_the_tuning_layer_work_in_the_lab(t) -> void:
	var s := await _boot_tuned()
	t.eq(s.tuning.engine.bank, 0, "starts on the first bank")
	s.tuning._unhandled_input(_key(KEY_PAGEDOWN))
	t.eq(s.tuning.engine.bank, 1, "PgDn: next bank")
	s.tuning._unhandled_input(_key(KEY_PAGEUP))
	t.eq(s.tuning.engine.bank, 0, "PgUp: previous bank")
	s.gait_params.set_value("step_length", 0.5)
	s.tuning._unhandled_input(_key(KEY_HOME))
	t.near(s.gait_params.get_value("step_length"), s.gait_params.def("step_length").default, 1e-9, "Home: reset every parameter")
	s.gait_params.set_value("arm_swing", 40.0)
	s.tuning._unhandled_input(_key(KEY_F5))
	var saved := []
	var dir := DirAccess.open(PRESET_COPY)
	for f in dir.get_files():
		if f.begins_with("tuned_"):
			saved.append(f)
	t.eq(saved.size(), 1, "F5: saved the current values as a preset (%s)" % str(saved))
	if not saved.is_empty():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [PRESET_COPY, saved[0]]))
		t.near(doc.targets.gait.arm_swing, 40.0, 1e-9, "with the values as they were")
		t.ok(doc.targets.has("rig") and doc.targets.has("body"), "for the gait, proportion and body targets")
