extends RefCounted

const Events = preload("res://midi/midi_events.gd")
const SCENE := "res://scenes/midi_monitor.tscn"
const CFG := "user://test_scene_midi.json"

var _scene


func before_each() -> void:
	_scene = load(SCENE).instantiate()
	_scene.options = {"no-hardware": "true", "config": CFG}
	Engine.get_main_loop().root.add_child(_scene)


func after_each() -> void:
	_scene.queue_free()
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG + suffix))


func _frames(n := 2) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _press(note: int, device := 0) -> void:
	_scene.mgr.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, note, 127, device))
	_scene.mgr.handle_midi(Events.make_input_event(Events.KIND_NOTE, 0, note, 0, device, true))


## The scene runs without hardware in tests, so it knows no ports until we say which exist.
func _connect() -> void:
	_scene.mgr._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])


func test_scene_loads_and_shows_state(t) -> void:
	await _frames()
	t.ok(_scene.mgr != null and _scene.panel != null, "monitor built its manager and panel")
	t.ok(_scene._status.text.contains("not found"), "no hardware opened: reported as not found")
	t.ok(_scene._progress.text.contains("Mapped 0 / 59"), "progress starts at 0 of 59: %s" % _scene._progress.text)


func test_wizard_walks_controls_in_order_and_saves(t) -> void:
	await _frames()
	_connect()
	_scene._start_wizard()
	t.eq(_scene.panel.learning, "strip1_knob", "first prompt is strip 1 knob")
	t.ok(_scene._prompt.text.contains("Strip 1 knob"), "prompt names the control: %s" % _scene._prompt.text)
	# Strip 1 knob: relative, two directions
	for i in 6:
		_scene.mgr.handle_midi(Events.make_input_event(Events.KIND_CC, 0, 16, 1))
	_scene.mgr.learn.tick(1.0)
	for i in 6:
		_scene.mgr.handle_midi(Events.make_input_event(Events.KIND_CC, 0, 16, 65))
	_scene.mgr.learn.tick(1.0)
	t.ok(_scene.mgr.config.is_mapped("strip1_knob"), "knob mapped")
	t.ok(_scene._result.text.begins_with("OK"), "result line shown: %s" % _scene._result.text)
	t.ok(_scene._progress.text.contains("Mapped 1 / 59"), "progress updated")
	_scene._advance_in = 0.0
	_scene._process(0.1)
	t.eq(_scene.panel.learning, "strip1_fader", "wizard advanced to the next control")
	t.ok(FileAccess.file_exists(CFG), "config written to disk")


func test_clicking_a_control_selects_and_learns_it(t) -> void:
	await _frames()
	_connect()
	_scene.panel.control_clicked.emit("global_play")
	t.eq(_scene._selected, "global_play", "selected")
	t.ok(_scene._detail.text.contains("not mapped"), "detail says not mapped")
	_scene._learn_single("global_play")
	_press(94)
	t.ok(_scene.mgr.config.is_mapped("global_play"), "learned from the press and release")
	t.eq(_scene.mgr.config.mapping_of("global_play").sig, "note:0:94", "signature")


func test_duplicate_port_events_are_logged_as_ignored(t) -> void:
	await _frames()
	_scene.mgr._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])
	_press(16, 0)
	_press(16, 1)
	await _frames(8)
	_scene._process(0.2)   # the log refreshes on a timer; frames run faster than that headless
	t.ok(_scene._log.text.contains("dup, ignored"), "the second port's copy is marked in the log")


func test_clear_and_invert_edit_the_config(t) -> void:
	await _frames()
	_scene.mgr.config.set_mapping("strip1_knob", {"sig": "cc:0:16", "behavior": "relative", "encoding": "sign_magnitude", "invert": false})
	_scene._select("strip1_knob")
	_scene._toggle_invert()
	t.ok(_scene.mgr.config.mapping_of("strip1_knob").invert, "inverted and saved")
	_scene._clear_selected()
	t.ok(not _scene.mgr.config.is_mapped("strip1_knob"), "cleared")


func test_invalid_config_shows_a_banner(t) -> void:
	_scene.queue_free()
	var f := FileAccess.open(CFG, FileAccess.WRITE)
	f.store_string("{\"schema\": 5}")
	f.close()
	_scene = load(SCENE).instantiate()
	_scene.options = {"no-hardware": "true", "config": CFG}
	Engine.get_main_loop().root.add_child(_scene)
	await _frames()
	t.ok(_scene._banner.visible, "banner shown")
	t.ok(_scene._banner.text.contains("rejected"), "explains: %s" % _scene._banner.text)
