extends RefCounted

const Manager = preload("res://midi/midi_manager.gd")
const Events = preload("res://midi/midi_events.gd")
const Learn = preload("res://midi/midi_learn.gd")
const Replay = preload("res://tests/capture_replay.gd")

const TMP := "user://test_midi_manager.json"
const PORTS: Array[String] = ["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"]

var _m
var _changes: Array = []


func before_each() -> void:
	_changes = []
	_m = Manager.new()
	Engine.get_main_loop().root.add_child(_m)
	_m.rescan_interval = 0.0
	_m.start(TMP, false)
	_m._apply_ports(PORTS)
	_m.control_changed.connect(func(id: String, st: Dictionary) -> void: _changes.append([id, st]))


func after_each() -> void:
	_m.queue_free()
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + suffix))


func _map_capture_controls() -> void:
	_m.config.set_mapping("strip1_fader", {"sig": "pb:0:0", "behavior": "absolute", "raw_min": 0, "raw_max": 16256, "invert": false})
	_m.config.set_mapping("strip1_knob", {"sig": "cc:0:16", "behavior": "relative", "encoding": "sign_magnitude", "invert": false})
	_m.config.set_mapping("strip1_mute", {"sig": "note:0:16", "behavior": "momentary"})
	_m.config.set_mapping("global_play", {"sig": "note:0:94", "behavior": "trigger"})


func _replay(device := -1) -> void:
	for e in Replay.input_events(device):
		_m.handle_midi(e)


func test_auto_mode_accepts_one_port_per_device(t) -> void:
	t.eq(_m.accepted_ports, [0], "primary port only")
	t.ok(_m.is_port_accepted(0) and not _m.is_port_accepted(1), "duplicate port filtered")


func test_real_capture_through_both_ports_is_delivered_once(t) -> void:
	_map_capture_controls()
	var raw := []
	_m.raw_event.connect(func(ev: Dictionary, accepted: bool, _p: String) -> void: raw.append(accepted))
	_replay()
	t.eq(raw.size(), 950, "all 950 raw messages seen by the monitor")
	t.eq(raw.count(true), 475, "half are accepted")
	var faders := _changes.filter(func(c: Array) -> bool: return c[0] == "strip1_fader")
	t.eq(faders.size(), 253, "253 fader positions, each once")
	var top := 0.0
	for c in faders:
		top = maxf(top, c[1].value)
	t.near(top, 1.0, 0.0001, "full travel reaches exactly 1.0")


func test_all_ports_mode_delivers_duplicates(t) -> void:
	_map_capture_controls()
	_m.config.data.ports = "all"
	_m._compute_accepted_ports()
	_replay()
	var faders := _changes.filter(func(c: Array) -> bool: return c[0] == "strip1_fader")
	t.eq(faders.size(), 506, "both ports accepted -> every move twice")


func test_explicit_port_list(t) -> void:
	_m.config.data.ports = ["MIDIIN2 (SMC-Mixer)"]
	_m._compute_accepted_ports()
	t.eq(_m.accepted_ports, [1], "named port only")


func test_relative_knob_accumulates_steps(t) -> void:
	_map_capture_controls()
	_replay(0)
	var knob := _changes.filter(func(c: Array) -> bool: return c[0] == "strip1_knob")
	t.eq(knob.size(), 218, "every CC16 message is one step")
	var last: Dictionary = knob[knob.size() - 1][1]
	t.eq(last.accum, 135 - 83, "135 steps of +1 and 83 of -1 accumulate to the net movement")


func test_buttons_momentary_and_trigger(t) -> void:
	_map_capture_controls()
	_replay(0)
	var mute := _changes.filter(func(c: Array) -> bool: return c[0] == "strip1_mute").map(func(c: Array) -> bool: return c[1].pressed)
	t.eq(mute, [true, false], "one press and one release in the capture")
	var play := _changes.filter(func(c: Array) -> bool: return c[0] == "global_play")
	t.eq(play.size(), 1, "trigger fires on the press only; the release is ignored")
	t.ok(play[0][1].pressed, "trigger reports pressed")


func test_unmapped_events_are_reported(t) -> void:
	var seen := []
	_m.unmapped_event.connect(func(ev: Dictionary) -> void: seen.append(ev.sig))
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 55, 127))
	t.eq(seen, ["note:0:55"], "no mapping -> unmapped_event")
	t.eq(_changes.size(), 0, "no control event")


func test_learn_through_the_manager_saves_and_blocks_instant_verification(t) -> void:
	var verified := []
	_m.control_verified.connect(func(id: String) -> void: verified.append(id))
	t.ok(_m.start_learn("strip1_mute"), "learn started")
	for e in Replay.input_events(0):
		if e.pitch == 16 and e.message in [MIDI_MESSAGE_NOTE_ON, MIDI_MESSAGE_NOTE_OFF]:
			_m.handle_midi(e)
	t.ok(_m.config.is_mapped("strip1_mute"), "mapping stored")
	t.ok(FileAccess.file_exists(TMP), "saved to disk immediately")
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 127))
	t.eq(verified, [], "the tail of the learn gesture is not a verification")
	_m._verify_block_until["strip1_mute"] = 0
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 127))
	t.eq(verified, ["strip1_mute"], "a later actuation verifies it")
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 127))
	t.eq(verified.size(), 1, "only once")
	var reloaded = Manager.new()
	reloaded.start(TMP, false)
	t.ok(reloaded.config.is_verified("strip1_mute"), "verified mark persisted to disk")
	reloaded.free()


func test_learn_does_not_drive_controls(t) -> void:
	_map_capture_controls()
	_m.start_learn("strip2_mute")
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 127))
	t.eq(_changes.size(), 0, "events during learn are not routed to gameplay")


func test_relearn_to_a_taken_signature_steals_it(t) -> void:
	_map_capture_controls()
	var changed := []
	_m.mapping_changed.connect(func(id: String) -> void: changed.append(id))
	_m.start_learn("strip2_mute")
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 127))
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 0, 0, true))
	t.ok(_m.config.is_mapped("strip2_mute") and not _m.config.is_mapped("strip1_mute"), "ownership moved")
	t.ok(changed.has("strip1_mute") and changed.has("strip2_mute"), "both controls announced")


func test_hotplug_status_changes(t) -> void:
	var states := []
	_m.connection_changed.connect(func(c: bool) -> void: states.append(c))
	t.ok(_m.connected, "connected with the SMC-Mixer ports present")
	_m._apply_ports([])
	t.ok(not _m.connected, "unplugged")
	_m._apply_ports(PORTS)
	t.ok(_m.connected, "plugged back in")
	t.eq(states, [false, true], "one event per change")


func test_other_devices_do_not_count_as_connected(t) -> void:
	_m._apply_ports(["Some Keyboard"])
	t.ok(not _m.connected, "device_hint must match")


func test_events_arrive_through_the_input_pipeline(t) -> void:
	_map_capture_controls()
	Input.parse_input_event(Events.make_input_event(Events.KIND_NOTE, 0, 16, 127, 0))
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	t.eq(_changes.size(), 1, "InputEventMIDI reaches _input and is routed")


func _join_rescan(m) -> void:
	var guard := 0
	while m._rescan_thread != null and guard < 600:
		await Engine.get_main_loop().process_frame
		m._poll_rescan_thread()
		guard += 1


func test_async_rescan_runs_on_a_worker_and_applies_the_result(t) -> void:
	t.ok(_m.rescan_async(), "started on a worker thread")
	t.ok(not _m.rescan_async(), "only one at a time")
	await _join_rescan(_m)
	t.ok(_m._rescan_thread == null, "finished and joined")
	for n in _m.port_names:
		t.ok(n is String, "ports listed as strings")


func test_rescan_waits_while_a_button_is_held(t) -> void:
	_map_capture_controls()
	_m.rescan_interval = 0.01
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 127))   # strip1_mute is momentary: held
	_m._last_event_msec = -1_000_000
	_m._process(0.1)
	t.ok(_m._rescan_thread == null, "no reopen while a button is down (its release could be lost)")
	_m.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, 16, 0, 0, true))
	_m._last_event_msec = -1_000_000
	_m._process(0.1)
	t.ok(_m._rescan_thread != null, "reopens once everything is released and quiet")
	await _join_rescan(_m)
	_m.rescan_interval = 0.0


func test_rescan_waits_for_quiet_input_and_learning(t) -> void:
	_m.rescan_interval = 0.01
	_m._last_event_msec = Time.get_ticks_msec()
	_m._process(0.1)
	t.ok(_m._rescan_thread == null, "recent messages: not now")
	_m._last_event_msec = -1_000_000
	_m.start_learn("strip1_mute")
	_m._process(0.1)
	t.ok(_m._rescan_thread == null, "learning: not now")
	_m.cancel_learn()
	_m.rescan_interval = 0.0

func test_invalid_config_file_is_reported_not_overwritten(t) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{\"schema\": 7}")
	f.close()
	var m2 = Manager.new()
	m2.start(TMP, false)
	t.ok(not m2.config_errors.is_empty(), "problems reported")
	t.eq(FileAccess.get_file_as_string(TMP), "{\"schema\": 7}", "file left exactly as the user wrote it")
	t.ok(m2.config.mappings().is_empty(), "runs with an empty mapping")
	m2.free()
