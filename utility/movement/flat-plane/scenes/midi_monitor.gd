## MIDI Monitor and MIDI Learn: device status, live event log, guided mapping of every control, verification.
## Launch: godot --path utility/movement/flat-plane            (this is the project's main scene)
## Options after `--`: --config=<path>  --no-hardware  --demo  --screenshot=<abs.png>  --quit-after=<seconds>
extends Control

const Manager = preload("res://midi/midi_manager.gd")
const ControllerPanel = preload("res://scenes/controller_panel.gd")
const Catalog = preload("res://midi/control_catalog.gd")
const Learn = preload("res://midi/midi_learn.gd")
const Events = preload("res://midi/midi_events.gd")
const Replay = preload("res://tests/capture_replay.gd")

const MAX_LOG_LINES := 400

var mgr
var panel
var _status: Label
var _ports: Label
var _banner: Label
var _prompt: Label
var _result: Label
var _progress: Label
var _detail: Label
var _log: RichTextLabel
var _mode: OptionButton
var _confirm: ConfirmationDialog
var _invert_btn: Button

var _log_lines: Array[String] = []
var _log_dirty := false
var _log_clock := 0.0
var _queue: Array[String] = []
var _wizard := false
var _advance_in := -1.0
var _selected := ""
var _args := {}
var _frames := 0
var options := {}  ## overrides command-line options (used by tests)
var _demo_events: Array[InputEventMIDI] = []
var _demo_index := 0


func _ready() -> void:
	_parse_args()
	_build_ui()
	mgr = Manager.new()
	add_child(mgr)
	var demo := _args.has("demo")
	var path: String = _args.get("config", "user://demo_midi.json" if demo else Manager.Config.DEFAULT_PATH)
	mgr.autosave = not demo
	mgr.start(path, not _args.has("no-hardware") and not demo)
	panel.bind(mgr)
	mgr.raw_event.connect(_on_raw_event)
	mgr.unmapped_event.connect(_on_unmapped)
	mgr.ports_changed.connect(func(_n: Array) -> void: _refresh_status())
	mgr.connection_changed.connect(_on_connection_changed)
	mgr.learn_status.connect(_on_learn_status)
	mgr.learn.finished.connect(_on_learn_finished)
	mgr.mapping_changed.connect(func(_id: String) -> void: _refresh_progress())
	mgr.control_verified.connect(_on_verified)
	if demo:
		_setup_demo()
	_refresh_status()
	_refresh_progress()
	_log_line("[color=#9aa]Monitor started. Config: %s  profile: %s[/color]" % [path, mgr.config.active_profile_name()])


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--"):
			var p := a.substr(2).split("=", true, 1)
			_args[p[0]] = p[1] if p.size() > 1 else "true"
	_args.merge(options, true)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.14, 0.17)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	top.add_child(_status)
	_ports = Label.new()
	_ports.modulate = Color(0.75, 0.78, 0.85)
	_ports.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_ports)
	_mode = OptionButton.new()
	_mode.add_item("Ports: auto (one per device)", 0)
	_mode.add_item("Ports: all (shows duplicates)", 1)
	_mode.item_selected.connect(_on_port_mode)
	top.add_child(_mode)
	top.add_child(_button("Rescan", func() -> void: mgr.rescan(true); _refresh_status()))
	top.add_child(_button("Reload config", func() -> void: _reload()))

	_banner = Label.new()
	_banner.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.visible = false
	root.add_child(_banner)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	panel = ControllerPanel.new()
	panel.control_clicked.connect(_on_panel_click)
	left.add_child(panel)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(930, 60)
	left.add_child(_prompt)
	_result = Label.new()
	_result.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
	left.add_child(_result)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 16)
	left.add_child(_progress)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	left.add_child(row)
	row.add_child(_button("Learn all unmapped", _start_wizard))
	row.add_child(_button("Skip", _skip))
	row.add_child(_button("Cancel (Esc)", _cancel))
	row.add_child(_button("Save now", func() -> void: _save()))
	row.add_child(_button("Clear ALL mappings...", func() -> void: _confirm.popup_centered()))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var title := Label.new()
	title.text = "Selected control"
	right.add_child(title)
	_detail = Label.new()
	_detail.custom_minimum_size = Vector2(0, 110)
	_detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_detail.modulate = Color(0.8, 0.85, 0.95)
	right.add_child(_detail)
	var drow := HBoxContainer.new()
	right.add_child(drow)
	drow.add_child(_button("Learn this", func() -> void: _learn_single(_selected)))
	_invert_btn = _button("Invert direction", _toggle_invert)
	drow.add_child(_invert_btn)
	drow.add_child(_button("Clear this", func() -> void: _clear_selected()))
	var ltitle := Label.new()
	ltitle.text = "Live MIDI (grey = duplicate port, ignored)"
	right.add_child(ltitle)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(380, 200)
	right.add_child(_log)

	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Remove every mapping in this profile? (a .bak copy of the file is kept on the next save)"
	_confirm.confirmed.connect(func() -> void: _clear_all())
	add_child(_confirm)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


# ------------------------------------------------------------------ status

func _refresh_status() -> void:
	if mgr == null:
		return
	if mgr.connected:
		_status.text = "● %s connected" % mgr.config.data.get("device_hint", "MIDI device")
		_status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	else:
		_status.text = "○ %s not found - plug in the USB cable" % mgr.config.data.get("device_hint", "MIDI device")
		_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	var parts: Array[String] = []
	for i in mgr.port_names.size():
		var role := "ACTIVE" if mgr.is_port_accepted(i) else "ignored duplicate"
		parts.append("[%d] %s (%s) x%d" % [i, mgr.port_names[i], role, int(mgr.port_counts.get(i, 0))])
	_ports.text = "   ".join(parts) if not parts.is_empty() else "no MIDI inputs"
	_banner.visible = not mgr.config_errors.is_empty()
	if _banner.visible:
		_banner.text = "Config file rejected (left untouched on disk): %s" % "; ".join(mgr.config_errors.slice(0, 3))
	var all_mode: bool = mgr.config.data.get("ports", "auto") == "all"
	_mode.select(1 if all_mode else 0)


func _refresh_progress() -> void:
	var req := Catalog.required_ids()
	var mapped := 0
	var verified := 0
	for id in req:
		if mgr.config.is_mapped(id):
			mapped += 1
			if mgr.config.is_verified(id):
				verified += 1
	_progress.text = "Mapped %d / %d     Verified %d / %d     Profile: %s" % [mapped, req.size(), verified, req.size(), mgr.config.active_profile_name()]
	if mapped == req.size() and verified < req.size() and not mgr.learn.is_active():
		_prompt.text = "All controls mapped. Now VERIFY: move / press every control once - a green tick appears on each."
	elif verified == req.size():
		_prompt.text = "All %d controls verified on the hardware." % req.size()
	_show_detail()


func _on_connection_changed(c: bool) -> void:
	_refresh_status()
	_log_line("[color=%s]%s[/color]" % ["#6e6" if c else "#f77", "Device connected" if c else "Device DISCONNECTED"])


func _process(delta: float) -> void:
	_frames += 1
	_log_clock += delta
	if _log_dirty and _log_clock > 0.08:
		_log_clock = 0.0
		_log_dirty = false
		_log.text = "\n".join(_log_lines)
	if _frames % 15 == 0:
		_refresh_status()
	if _advance_in >= 0.0:
		_advance_in -= delta
		if _advance_in < 0.0:
			_next_in_queue()
	if _demo_index < _demo_events.size():
		for i in 4:
			if _demo_index < _demo_events.size():
				mgr.handle_midi(_demo_events[_demo_index])
				_demo_index += 1
	if _args.has("screenshot") and _frames == 100:
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(_args.screenshot))
		get_tree().quit()
	if _args.has("quit-after") and Time.get_ticks_msec() / 1000.0 > float(_args["quit-after"]):
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel()


# ------------------------------------------------------------------ log

func _log_line(bbcode: String) -> void:
	_log_lines.append(bbcode)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG_LINES)
	_log_dirty = true


func _on_raw_event(ev: Dictionary, accepted: bool, port: String) -> void:
	var text := "%8.2f [%d] %s" % [Time.get_ticks_msec() / 1000.0, ev.device, Events.describe(ev)]
	if not accepted:
		_log_line("[color=#667]%s  (dup, ignored)[/color]" % text)
		return
	var id: String = mgr.config.find_by_sig(ev.sig)
	if id != "":
		text += "  -> %s" % Catalog.get_control(id).label
	_log_line("[color=#dde]%s[/color]" % text)


func _on_unmapped(ev: Dictionary) -> void:
	if not mgr.learn.is_active():
		_log_line("[color=#fb4]  unmapped: %s[/color]" % ev.sig)


# ------------------------------------------------------------------ learning

func _start_wizard() -> void:
	_queue = mgr.config.unmapped_ids()
	_wizard = true
	if _queue.is_empty():
		_wizard = false
		_prompt.text = "Nothing left to map. Use a control's Learn button to re-learn one."
		return
	_next_in_queue()


func _next_in_queue() -> void:
	_advance_in = -1.0
	while not _queue.is_empty() and mgr.config.is_mapped(_queue[0]):
		_queue.pop_front()
	if _queue.is_empty():
		_wizard = false
		panel.learning = ""
		_result.text += "   (wizard finished)"
		_refresh_progress()
		return
	_begin_learn(_queue[0])


func _begin_learn(id: String) -> void:
	_select(id)
	panel.learning = id
	mgr.start_learn(id)


func _learn_single(id: String) -> void:
	if id == "":
		return
	_wizard = false
	_queue = []
	_begin_learn(id)


func _skip() -> void:
	if _wizard and not _queue.is_empty():
		mgr.cancel_learn()
		_queue.pop_front()
		_next_in_queue()


func _cancel() -> void:
	_wizard = false
	_queue = []
	_advance_in = -1.0
	mgr.cancel_learn()
	panel.learning = ""


func _on_learn_status(s: Dictionary) -> void:
	_prompt.text = s.prompt
	if s.state == "IDLE":
		panel.learning = ""


func _on_learn_finished(id: String, mapping: Dictionary) -> void:
	_result.text = "OK  %s  ->  %s" % [Catalog.get_control(id).label, Learn.describe_mapping(mapping)]
	panel.learning = ""
	if _wizard and not _queue.is_empty() and _queue[0] == id:
		_queue.pop_front()
		_advance_in = 0.7
	_refresh_progress()


func _on_verified(id: String) -> void:
	_log_line("[color=#6e6]  verified: %s[/color]" % Catalog.get_control(id).label)
	_refresh_progress()


# ------------------------------------------------------------------ selection and editing

func _on_panel_click(id: String) -> void:
	_select(id)


func _select(id: String) -> void:
	_selected = id
	panel.selected = id
	_show_detail()


func _show_detail() -> void:
	if _selected == "":
		_detail.text = "Click a control on the panel."
		return
	var c := Catalog.get_control(_selected)
	var m: Dictionary = mgr.config.mapping_of(_selected)
	if m.is_empty():
		_detail.text = "%s  (%s)\nnot mapped" % [c.label, c.kind]
	else:
		_detail.text = "%s  (%s)\n%s\nverified: %s" % [c.label, c.kind, JSON.stringify(m), mgr.config.profile().verified.get(_selected, "no")]
	_invert_btn.disabled = m.is_empty() or m.behavior == "momentary" or m.behavior == "trigger"


func _toggle_invert() -> void:
	var m: Dictionary = mgr.config.mapping_of(_selected)
	if m.is_empty():
		return
	m["invert"] = not m.get("invert", false)
	_save()
	_show_detail()


func _clear_selected() -> void:
	if _selected != "":
		mgr.clear_mapping(_selected)
		_result.text = "Cleared %s" % Catalog.get_control(_selected).label


func _clear_all() -> void:
	mgr.config.clear_all()
	_save()
	for id in Catalog.ids():
		mgr.mapping_changed.emit(id)
	_result.text = "All mappings cleared"


func _save() -> void:
	var r: Dictionary = mgr.save_config()
	_result.text = "Saved %s" % mgr.config_path if r.ok else "SAVE FAILED: %s" % r.error
	_refresh_progress()


func _reload() -> void:
	var r: Dictionary = mgr.reload_config()
	_result.text = "Reloaded %s" % mgr.config_path if r.ok else "Reload failed: %s" % str(r.errors[0])
	_refresh_status()
	_refresh_progress()


func _on_port_mode(index: int) -> void:
	mgr.config.data.ports = "all" if index == 1 else "auto"
	mgr._compute_accepted_ports()
	_refresh_status()
	_save()


# ------------------------------------------------------------------ demo (screenshots only)

func _setup_demo() -> void:
	mgr._apply_ports(["SMC-Mixer", "MIDIIN2 (SMC-Mixer)"])
	mgr.config.set_mapping("strip1_fader", {"sig": "pb:0:0", "behavior": "absolute", "raw_min": 0, "raw_max": 16256, "invert": false})
	mgr.config.set_mapping("strip1_knob", {"sig": "cc:0:16", "behavior": "relative", "encoding": "sign_magnitude", "invert": false})
	mgr.config.set_mapping("strip1_mute", {"sig": "note:0:16", "behavior": "momentary"})
	mgr.config.set_mapping("global_play", {"sig": "note:0:94", "behavior": "momentary"})
	mgr.config.set_mapping("strip2_fader", {"sig": "pb:1:0", "behavior": "absolute", "raw_min": 0, "raw_max": 16256, "invert": false})
	mgr.config.mark_verified("strip1_fader")
	mgr.config.mark_verified("global_play")
	_demo_events = Replay.input_events()
	_select("strip1_knob")
	panel.learning = "strip3_fader"  # visual only: a real learn would swallow the replayed events
