## Native MIDI I/O for the lab: device discovery, hot-plug, port de-duplication, MIDI Learn and routing of
## physical controls to logical control events. Add one instance to the scene tree and call start().
## Gameplay code only ever sees `control_changed(control_id, state)`; it never sees MIDI numbers.
extends Node

const Config = preload("res://midi/midi_config.gd")
const Learn = preload("res://midi/midi_learn.gd")
const Events = preload("res://midi/midi_events.gd")
const Behavior = preload("res://midi/control_behavior.gd")
const Catalog = preload("res://midi/control_catalog.gd")
const Pattern = preload("res://midi/midi_pattern.gd")

## Every received message with the port it came from; `accepted` is false for filtered duplicates.
signal raw_event(ev: Dictionary, accepted: bool, port_name: String)
## A mapped control changed. state: {kind, value (absolute 0..1), delta + accum (relative), pressed (button), raw}.
signal control_changed(control_id: String, state: Dictionary)
signal unmapped_event(ev: Dictionary)
signal ports_changed(port_names: Array)
signal connection_changed(connected: bool)
signal learn_status(status: Dictionary)
signal mapping_changed(control_id: String)
## First physical actuation of a mapped control after it was learned (the control is "verified").
signal control_verified(control_id: String)

const VERIFY_SETTLE_MSEC := 1500
const RESCAN_IDLE_MSEC := 1000

var config = Config.new()
var learn = Learn.new()
var config_path := Config.DEFAULT_PATH
var config_errors: Array[String] = []
var rescan_interval := 2.0  ## seconds between hot-plug checks (each costs ~40 ms); 0 disables polling
var autosave := true

var port_names: Array[String] = []
var accepted_ports: Array[int] = []
var port_counts: Dictionary = {}  ## device index -> messages seen
var connected := false
var control_state: Dictionary = {}

var _started := false
var _since_rescan := 0.0
var _last_event_msec := -1_000_000
var _verify_block_until: Dictionary = {}


func start(path := Config.DEFAULT_PATH, open_hardware := true) -> void:
	config_path = path
	config_errors = []
	var r: Dictionary = config.load_file(path)
	if not r.ok and not r.get("missing", false):
		config_errors = r.errors  # keep the invalid file untouched on disk; run with an empty mapping
	learn.changed.connect(func(s: Dictionary) -> void: learn_status.emit(s))
	learn.finished.connect(_on_learn_finished)
	_started = true
	if open_hardware:
		OS.open_midi_inputs()
		rescan(false)


func stop() -> void:
	_started = false
	OS.close_midi_inputs()


## Re-enumerates inputs. Godot only lists devices when the inputs are opened, so a rescan closes and reopens them
## (skipped while messages are arriving or a learn gesture is in progress, to avoid losing events).
func rescan(reopen := true) -> void:
	if reopen:
		OS.close_midi_inputs()
		OS.open_midi_inputs()
	var names: Array[String] = []
	for n in OS.get_connected_midi_inputs():
		names.append(String(n))
	_apply_ports(names)


func _apply_ports(names: Array) -> void:
	var list: Array[String] = []
	for n in names:
		list.append(String(n))
	var changed := list != port_names
	port_names = list
	_compute_accepted_ports()
	if changed:
		port_counts = {}
		ports_changed.emit(port_names)
	var hint := String(config.data.get("device_hint", "")).to_lower()
	var now_connected := false
	for n in port_names:
		if hint == "" or n.to_lower().contains(hint):
			now_connected = true
	if now_connected != connected or changed:
		var was := connected
		connected = now_connected
		if was != connected:
			connection_changed.emit(connected)


## "auto": a controller exposes the same messages on several ports (`SMC-Mixer`, `MIDIIN2 (SMC-Mixer)`);
## keep one port per device so each physical action is delivered once.
func _compute_accepted_ports() -> void:
	accepted_ports = []
	var mode: Variant = config.data.get("ports", "auto")
	if mode is Array:
		for i in port_names.size():
			if (mode as Array).has(port_names[i]):
				accepted_ports.append(i)
		return
	if mode == "all":
		for i in port_names.size():
			accepted_ports.append(i)
		return
	var re := RegEx.create_from_string("^MIDIIN\\d+ \\((.*)\\)$")
	var chosen := {}  # base name -> port index
	for i in port_names.size():
		var m := re.search(port_names[i])
		var base := m.get_string(1) if m else port_names[i]
		var exact := not m
		if not chosen.has(base) or exact:
			chosen[base] = i
	for i in chosen.values():
		accepted_ports.append(i)
	accepted_ports.sort()


func is_port_accepted(device: int) -> bool:
	return accepted_ports.has(device)


func _process(delta: float) -> void:
	if not _started:
		return
	learn.tick(delta)
	if rescan_interval > 0.0:
		_since_rescan += delta
		if _since_rescan >= rescan_interval:
			_since_rescan = 0.0
			var quiet := Time.get_ticks_msec() - _last_event_msec > RESCAN_IDLE_MSEC
			if quiet and not learn.is_active():
				rescan(true)


func _input(event: InputEvent) -> void:
	if event is InputEventMIDI:
		handle_midi(event)


## Entry point for hardware events (via _input) and for tests/replay (synthetic events).
func handle_midi(e: InputEventMIDI) -> void:
	var ev := Events.from_input_event(e)
	if ev.is_empty():
		return
	port_counts[ev.device] = int(port_counts.get(ev.device, 0)) + 1
	var accepted := is_port_accepted(ev.device)
	var pname := port_names[ev.device] if ev.device >= 0 and ev.device < port_names.size() else "port %d" % ev.device
	raw_event.emit(ev, accepted, pname)
	if not accepted:
		return
	_last_event_msec = Time.get_ticks_msec()
	if learn.is_active():
		learn.feed(ev)
		return
	_route(ev)


func _route(ev: Dictionary) -> void:
	var id: String = config.find_by_sig(ev.sig)
	if id == "":
		unmapped_event.emit(ev)
		return
	var m: Dictionary = config.mapping_of(id)
	var st := {"kind": Catalog.kind_of(id), "raw": ev.value, "usec": ev.usec}
	match m.behavior:
		Behavior.ABSOLUTE:
			st["value"] = Behavior.normalize_absolute(int(ev.value), m)
		Behavior.RELATIVE:
			var steps := Behavior.decode_relative(int(ev.value), m)
			if steps == 0:
				return
			st["delta"] = steps
			var prev: Dictionary = control_state.get(id, {})
			st["accum"] = int(prev.get("accum", 0)) + steps
		"momentary":
			if not (ev.pressed or ev.released):
				return
			st["pressed"] = ev.pressed
		"trigger":
			if not ev.pressed:
				return
			st["pressed"] = true
	control_state[id] = st
	control_changed.emit(id, st)
	_try_verify(id)


func _try_verify(id: String) -> void:
	if config.is_verified(id) or Time.get_ticks_msec() < int(_verify_block_until.get(id, 0)):
		return
	config.mark_verified(id)
	if autosave:
		save_config()
	control_verified.emit(id)


func start_learn(id: String) -> bool:
	return learn.start(id)


func cancel_learn() -> void:
	learn.cancel()


func _on_learn_finished(id: String, mapping: Dictionary) -> void:
	var replaced: String = config.set_mapping(id, mapping)
	_verify_block_until[id] = Time.get_ticks_msec() + VERIFY_SETTLE_MSEC
	control_state.erase(id)
	if autosave:
		save_config()
	if replaced != "":
		mapping_changed.emit(replaced)
	mapping_changed.emit(id)


## Fills in strips that follow the pattern of the mapped ones. They stay "inferred" until actuated on the hardware.
func infer_strips() -> Array:
	var proposals := Pattern.propose(config)
	Pattern.apply(config, proposals)
	if autosave and not proposals.is_empty():
		save_config()
	for p in proposals:
		mapping_changed.emit(p.control_id)
	return proposals


func clear_mapping(id: String) -> void:
	config.clear_mapping(id)
	control_state.erase(id)
	if autosave:
		save_config()
	mapping_changed.emit(id)


func save_config() -> Dictionary:
	return config.save_file(config_path)


func reload_config() -> Dictionary:
	var r: Dictionary = config.load_file(config_path)
	config_errors = [] if r.ok else r.errors
	_compute_accepted_ports()
	for id in Catalog.ids():
		mapping_changed.emit(id)
	return r


func get_value(id: String, default := 0.0) -> float:
	return float(control_state.get(id, {}).get("value", default))
