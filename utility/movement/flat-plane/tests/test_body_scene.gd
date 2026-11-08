extends RefCounted

## The procedural body model inside the real scene: real physics in, a pose out; MIDI reaching the body parameters;
## and the guarantee that none of it ever changes where the body goes.

const SCENE := "res://scenes/flat_plane.tscn"
const Events = preload("res://midi/midi_events.gd")
const Behavior = preload("res://midi/control_behavior.gd")
const Visual = preload("res://character/character_visual.gd")
const DT := 1.0 / 120.0

const BIND_COPY := "user://body_scene_bindings.json"
const PRESET_COPY := "user://body_scene_presets"
const STATE := "user://body_scene_state.json"

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


func _boot(extra := {}) -> Node:
	var s: Node = load(SCENE).instantiate()
	var opts := {"no-capture": "true", "no-hardware": "true", "no-window-state": "true", "legacy-animation": "true"}
	opts.merge(extra, true)
	s.options = opts
	_tree.root.add_child(s)
	await _tree.process_frame   # _ready runs on the first frame and re-enables processing, so disable it afterwards
	s.set_physics_process(false)
	s.set_process(false)
	await _tree.physics_frame
	await _tree.physics_frame
	return s


## Boots with the tuning layer on (headless: no UI), on private copies of the shipped files.
func _boot_tuned() -> Node:
	var f := FileAccess.open(BIND_COPY, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string("res://config/tuning_bindings.json"))
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_COPY))
	_s = await _boot({"midi-config": "res://config/midi_mapping.json", "tuning-bindings": BIND_COPY, "preset-dir": PRESET_COPY, "tuning-state": STATE})
	_s.midi._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])
	return _s


## One rendered frame at 60 Hz = two physics ticks, then the real presentation update.
func _frame(s: Node, input: Dictionary) -> void:
	for i in 2:
		s.simulate_tick(input, DT)
	s._process(DT * 2.0)


func _run(s: Node, input: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / 0.01667)):
		await _tree.physics_frame
		_frame(s, input)


const RUN := {"move": Vector2(0, 1), "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": true, "crouch": false}
const STOP := {"move": Vector2.ZERO, "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}


# ------------------------------------------------------------------ physics is untouched

func _trajectory(mode: String) -> Array:
	var s: Node = await _boot({"no-tuning": "true", "no-animation": "true"} if mode == "none" else {"no-tuning": "true"})
	if mode == "off":
		s.body_params.set_value("body_dynamics", 0.0)
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	var out := []
	for i in 360:
		await _tree.physics_frame
		var sec := float(i) * DT
		var input := RUN.duplicate()
		input.yaw = clampf(sec - 1.0, 0.0, 1.0) * 1.5
		input.jump_pressed = i % 130 == 40
		input.jump_held = input.jump_pressed
		if sec > 2.5:
			input = STOP
		s.simulate_tick(input, DT)
		if mode != "none" and i % 2 == 1:
			s._process(DT * 2.0)
		out.append([s.body.global_position, s.body.velocity, s.body.core.grounded])
	s.queue_free()
	await _tree.process_frame
	return out


func test_physics_is_bit_identical_with_the_body_model_on_off_or_absent(t) -> void:
	var on: Array = await _trajectory("on")
	var off: Array = await _trajectory("off")
	var none: Array = await _trajectory("none")
	var diff_off := -1
	var diff_none := -1
	for i in on.size():
		if diff_off < 0 and on[i] != off[i]:
			diff_off = i
		if diff_none < 0 and on[i] != none[i]:
			diff_none = i
	t.eq(diff_off, -1, "model on == model off, every tick")
	t.eq(diff_none, -1, "model on == no animation at all, every tick")
	t.ok(on[on.size() - 1][0].distance_to(Vector3(120, 0.05, 120)) > 3.0, "the script actually moved the body")


# ------------------------------------------------------------------ physics in, pose out

func test_real_acceleration_leans_the_body_and_stopping_reverses_it(t) -> void:
	var s: Node = await _boot({"no-tuning": "true"})
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	await _run(s, RUN, 0.5)
	var accelerating: float = s.dynamics.pose.torso_pitch
	t.ok(accelerating > 0.03, "leans forward while accelerating: %.3f rad" % accelerating)
	await _run(s, RUN, 2.0)
	var cruising: float = s.dynamics.pose.torso_pitch
	t.ok(cruising > 0.0, "keeps a forward lean at steady speed: %.3f rad" % cruising)
	var min_pitch := 99.0
	for i in 40:
		await _tree.physics_frame
		_frame(s, STOP)
		min_pitch = minf(min_pitch, s.dynamics.pose.torso_pitch)
	t.ok(min_pitch < cruising - 0.02, "braking pitches the torso back from the cruising lean: %.3f -> %.3f rad" % [cruising, min_pitch])
	var head_z: float = s.visual.joint_position("head").z
	var pelvis_z: float = s.visual.joint_position("pelvis").z
	t.ok(is_finite(head_z) and is_finite(pelvis_z), "the skeleton stays finite")


func test_the_visual_pose_follows_the_model(t) -> void:
	var s: Node = await _boot({"no-tuning": "true"})
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	await _run(s, RUN, 2.0)
	var leaning_head: float = s.visual.joint_position("head").z - s.visual.joint_position("pelvis").z
	t.ok(leaning_head < -0.02, "the head is forward of the hips (-Z is forward) while running: %.3f m" % leaning_head)
	s.body_params.set_value("torso_lean_amp", 0.0)
	await _run(s, RUN, 1.0)
	var no_lean_head: float = s.visual.joint_position("head").z - s.visual.joint_position("pelvis").z
	t.ok(no_lean_head > leaning_head, "lean amplitude 0 removes the forward lean in the skeleton: %.3f vs %.3f m" % [no_lean_head, leaning_head])


func test_landing_compresses_through_the_knees_and_keeps_the_feet_on_the_ground(t) -> void:
	var s: Node = await _boot({"no-tuning": "true"})
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	await _run(s, STOP, 0.6)
	var rest_hip: float = s.visual.joint_height("pelvis")
	var rest_foot: float = s.visual.joint_height("foot_l")
	s._pending_impact = 12.0
	await _tree.physics_frame
	_frame(s, STOP)
	var lowest := 99.0
	var lowest_foot := 99.0
	for i in 60:
		await _tree.physics_frame
		_frame(s, STOP)
		lowest = minf(lowest, s.visual.joint_height("pelvis"))
		lowest_foot = minf(lowest_foot, s.visual.joint_height("foot_l"))
	t.ok(rest_hip - lowest > 0.03, "the hips dip on a hard landing: %.3f m" % (rest_hip - lowest))
	t.ok(lowest_foot > rest_foot - 0.02, "the feet do not sink into the ground while the hips dip: lowest %.3f vs rest %.3f m" % [lowest_foot, rest_foot])
	await _run(s, STOP, 2.0)
	t.near(s.visual.joint_height("pelvis"), rest_hip, 0.01, "and the body settles back to standing height")


func test_b_key_switches_to_the_original_pose_and_back(t) -> void:
	var s: Node = await _boot({"no-tuning": "true"})
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	await _run(s, RUN, 1.0)
	t.ok(s.dynamics.pose.active, "model active by default")
	s.toggle_body_dynamics()
	await _run(s, RUN, 0.2)
	t.ok(not s.dynamics.pose.active, "off: the pose dictionary is inactive and the legacy path runs")
	t.ok(s.visual.lean > 0.0, "the original lean variable is driving the pose again")
	s.toggle_body_dynamics()
	await _run(s, RUN, 0.2)
	t.ok(s.dynamics.pose.active, "back on")


func test_teleport_and_respawn_restart_the_model_at_rest(t) -> void:
	var s: Node = await _boot({"no-tuning": "true"})
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	await _run(s, RUN, 2.0)
	t.ok(absf(s.dynamics.pose.torso_pitch) > 0.02, "running: leaning")
	s.teleport_to_landmark(1)
	s.body.core.velocity = Vector3.ZERO
	s._process(DT * 2.0)
	t.near(s.dynamics.pose.torso_pitch, 0.0, 0.005, "no lean carried across a teleport")
	t.near(s.dynamics.pose.pelvis_drop, 0.0, 0.001, "no compression carried across a teleport")


# ------------------------------------------------------------------ MIDI reaches the body parameters

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


func test_the_body_target_is_registered_and_every_default_binding_resolves(t) -> void:
	await _boot_tuned()
	t.ok(_s.tuning.registry.has_target("body"), "body target registered")
	t.eq(_s.tuning.bindings.unresolved(_s.tuning.registry), [], "no binding points at a parameter that does not exist")
	var bound: Array = _s.tuning.bindings.referenced_keys()
	var wanted := ["torso_lean_amp", "hip_sway_amp", "rotation_lag", "landing_compression", "landing_rebound", "follow_through", "head_stabilization", "arm_swing_amp", "torso_freq", "torso_damping", "hip_freq", "hip_damping", "rotation_freq", "rotation_damping", "landing_freq", "landing_damping", "body_dynamics", "fx_torso_lean", "fx_torso_lateral", "fx_anticipation", "fx_pelvis_shift", "fx_pelvis_gait", "fx_landing", "fx_head", "fx_arms", "fx_facing_lag"]
	var missing := []
	for id in wanted:
		if not bound.has("body." + id):
			missing.append(id)
	t.eq(missing, [], "the springs, the switches and the master are all reachable from the controller")


func test_faders_and_knobs_in_the_body_banks_change_the_model_live(t) -> void:
	await _boot_tuned()
	var e = _s.tuning.engine
	e.switch_bank(3)
	t.eq(_s.tuning.bindings.bank_name(e.bank), "Body Springs", "on the body bank")
	var before: float = _s.body_params.get_value("torso_lean_amp")
	_move_fader(1, 0.5)   # picks up the parameter where it already is (soft takeover: no jump)
	t.near(_s.body_params.get_value("torso_lean_amp"), before, 0.06, "arriving at the current value does not move it")
	_move_fader(1, 0.9)
	t.near(_s.body_params.get_value("torso_lean_amp"), 1.8, 0.06, "fader 1 sets the torso lean amplitude to 90 % of 0..2")
	var f_before: float = _s.body_params.get_value("torso_freq")
	_turn(1, 3)
	t.ok(_s.body_params.get_value("torso_freq") > f_before, "knob 1 raises the torso spring frequency: %.2f -> %.2f Hz" % [f_before, _s.body_params.get_value("torso_freq")])
	e.switch_bank(4)
	_move_fader(1, 1.0)
	_move_fader(1, 0.0)
	t.ok(not _s.body_params.is_on("fx_torso_lean"), "the Body Effects fader switches the torso lean effect off")
	t.ok(_s.body_params.is_on("fx_landing"), "and leaves the others alone")


func test_a_live_change_shows_up_in_the_next_pose(t) -> void:
	await _boot_tuned()
	_s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	await _run(_s, RUN, 2.0)
	var normal: float = _s.dynamics.pose.torso_pitch
	_s.tuning.engine.set_param("body.torso_lean_amp", 2.0, "test")
	await _run(_s, RUN, 1.0)
	t.ok(_s.dynamics.pose.torso_pitch > normal * 1.3, "doubling the amplitude raises the lean without a restart: %.3f -> %.3f rad" % [normal, _s.dynamics.pose.torso_pitch])


func test_body_parameters_are_saved_and_restored_by_presets(t) -> void:
	await _boot_tuned()
	_s.tuning.engine.set_param("body.torso_freq", 5.0, "test")
	_s.tuning.engine.set_param("movement.gravity", 25.0, "test")
	t.ok(_s.tuning.save_preset_as("body_test").ok, "saved")
	_s.tuning.engine.set_param("body.torso_freq", 1.0, "test")
	_s.tuning.engine.set_param("movement.gravity", 10.0, "test")
	t.ok(_s.tuning.load_preset("body_test"), "loaded")
	t.near(_s.body_params.get_value("torso_freq"), 5.0, 0.001, "body value restored")
	t.near(_s.params.get_value("gravity"), 25.0, 0.001, "movement value restored")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/body_test.json" % PRESET_COPY))
	t.ok(doc is Dictionary and doc.targets.has("body") and doc.targets.has("movement"), "both targets are in the file")
