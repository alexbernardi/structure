## MIDI Learn: turns the messages a user produces into a mapping for one catalog control.
## Event-driven state machine; time only advances through tick(), so tests are deterministic.
## Buttons: first press locks the signature, a release decides momentary vs trigger.
## Knobs/faders: first CC/pitch-bend/pressure message locks the signature; the stream is analysed to decide
## absolute vs relative; relative controls then need the opposite direction to work out the encoding.
extends RefCounted

const Catalog = preload("res://midi/control_catalog.gd")
const Behavior = preload("res://midi/control_behavior.gd")
const Events = preload("res://midi/midi_events.gd")

enum State { IDLE, LISTEN, COLLECT, NEED_REVERSE, COLLECT_REVERSE, WAIT_RELEASE, DONE, FAILED }

const IDLE_FINALIZE_SEC := 0.6
const RELEASE_WAIT_SEC := 0.8
const MAX_SAMPLES := 80
const FORCE_DECISION_SAMPLES := 16
const MIN_SWEEP_FRACTION := 0.8
const REARM_SEC := 0.4

signal changed(status: Dictionary)
signal finished(control_id: String, mapping: Dictionary)

var state: State = State.IDLE
var control_id := ""
var kind := ""
var sig := ""
var prompt := ""
var message_kind := ""
var _values: Array[int] = []
var _first_values: Array[int] = []
var _first_analysis: Dictionary = {}
var _idle := 0.0
var _mapping: Dictionary = {}
var _armed := false


func is_active() -> bool:
	return state != State.IDLE and state != State.DONE and state != State.FAILED


func start(id: String) -> bool:
	if not Catalog.has(id):
		return false
	control_id = id
	kind = Catalog.kind_of(id)
	sig = ""
	message_kind = ""
	_values = []
	_first_values = []
	_first_analysis = {}
	_idle = 0.0
	_mapping = {}
	state = State.LISTEN
	var c := Catalog.get_control(id)
	match kind:
		Catalog.BUTTON:
			prompt = "%s: press and release it once" % c.label
		Catalog.FADER:
			prompt = "%s: move it through its FULL travel, up and down, then stop" % c.label
		_:
			prompt = "%s: turn it clockwise (a few seconds), then stop" % c.label
	_emit()
	return true


func cancel() -> void:
	if is_active():
		state = State.IDLE
		prompt = "Learn cancelled"
		_emit()


func status() -> Dictionary:
	return {"state": State.keys()[state], "control": control_id, "kind": kind, "prompt": prompt, "sig": sig,
		"samples": _values.size(), "done": state == State.DONE, "failed": state == State.FAILED, "mapping": _mapping}


func feed(ev: Dictionary) -> void:
	if ev.is_empty() or not is_active():
		return
	match state:
		State.LISTEN:
			_on_listen(ev)
		State.COLLECT, State.COLLECT_REVERSE:
			if ev.sig == sig:
				_values.append(int(ev.value))
				_idle = 0.0
				if _values.size() >= MAX_SAMPLES:
					_finalize(false)
				else:
					_emit()
		State.NEED_REVERSE:
			if ev.sig == sig:
				if _armed:
					_values = [int(ev.value)]
					state = State.COLLECT_REVERSE
					_emit()
				_idle = 0.0
		State.WAIT_RELEASE:
			if ev.sig == sig and ev.released:
				_complete({"sig": sig, "behavior": "momentary"})


func tick(dt: float) -> void:
	if not is_active():
		return
	_idle += dt
	match state:
		State.NEED_REVERSE:
			# Messages still arriving from the first gesture must not count as the opposite direction.
			if _idle >= REARM_SEC:
				_armed = true
		State.COLLECT, State.COLLECT_REVERSE:
			if _idle >= IDLE_FINALIZE_SEC and _values.size() > 0:
				_finalize(true)
		State.WAIT_RELEASE:
			if _idle >= RELEASE_WAIT_SEC:
				_complete({"sig": sig, "behavior": "trigger"})


func _on_listen(ev: Dictionary) -> void:
	if kind == Catalog.BUTTON:
		if (ev.kind == Events.KIND_NOTE or ev.kind == Events.KIND_CC) and ev.pressed:
			sig = ev.sig
			message_kind = ev.kind
			_idle = 0.0
			state = State.WAIT_RELEASE
			prompt = "Got %s - release it" % sig
			_emit()
		return
	if ev.kind == Events.KIND_CC or ev.kind == Events.KIND_PITCH_BEND or ev.kind == Events.KIND_PRESSURE:
		sig = ev.sig
		message_kind = ev.kind
		_values = [int(ev.value)]
		_idle = 0.0
		state = State.COLLECT
		prompt = "Locked %s - keep moving, then stop" % sig
		_emit()


func _domain_max() -> int:
	return int(Events.DOMAIN_MAX[message_kind])


## `from_idle`: the user has already stopped moving (so the opposite-direction stage can start at once);
## false when the sample cap ended the gesture while the user may still be turning.
func _finalize(from_idle: bool) -> void:
	if state == State.COLLECT_REVERSE:
		var r := Behavior.infer_relative(_first_values, _values)
		if not r.ok:
			_values = []
			_armed = from_idle
			_idle = 0.0
			state = State.NEED_REVERSE
			prompt = "%s. Turn it counter-clockwise again" % r.reason
			_emit()
			return
		var m := {"sig": sig, "behavior": Behavior.RELATIVE, "encoding": r.encoding, "invert": r.invert}
		if r.encoding == Behavior.ENC_FIXED:
			m["cw_values"] = r.cw_values
			m["ccw_values"] = r.ccw_values
		_complete(m)
		return
	var a := Behavior.analyze(_values, _domain_max())
	var decision: String = a.behavior
	if decision == Behavior.UNKNOWN and _values.size() >= FORCE_DECISION_SAMPLES:
		decision = Behavior.force_decision(a)
	if decision == Behavior.UNKNOWN:
		prompt = "Only %d messages (need %d) - keep moving" % [_values.size(), Behavior.MIN_SAMPLES]
		_emit()
		return
	if decision == Behavior.ABSOLUTE:
		_complete(_absolute_mapping(a))
		return
	_first_values = _values.duplicate()
	_first_analysis = a
	_values = []
	_armed = from_idle
	_idle = 0.0
	state = State.NEED_REVERSE
	var up := "counter-clockwise" if kind == Catalog.KNOB else "DOWN"
	prompt = "Detected a RELATIVE control (%s). Now turn it %s, then stop" % [sig, up]
	_emit()


func _absolute_mapping(a: Dictionary) -> Dictionary:
	var domain := _domain_max()
	var effective_max := domain
	# A 7-bit control sent as 14-bit pitch bend (SMC-Mixer: low byte always 0) never reaches 16383.
	# Only trust a quantisation seen in >= 8 samples, capped at 7 bits so a sparse sweep cannot shrink the range.
	if message_kind == Events.KIND_PITCH_BEND and _values.size() >= 8 and _trailing_zero_bits(_values) >= 4:
		var q := 1 << mini(_trailing_zero_bits(_values), 7)
		effective_max = domain - (domain % q)
	var lo := 0
	var hi := effective_max
	if float(a["max"] - a["min"]) >= MIN_SWEEP_FRACTION * float(effective_max):
		lo = a["min"]
		hi = a["max"]
	return {"sig": sig, "behavior": Behavior.ABSOLUTE, "raw_min": lo, "raw_max": hi, "invert": false}


static func _trailing_zero_bits(values: Array) -> int:
	var bits := 14
	for v in values:
		var x := int(v)
		var b := 0
		while b < 14 and (x & (1 << b)) == 0:
			b += 1
		bits = mini(bits, b)
	return bits


func _complete(mapping: Dictionary) -> void:
	_mapping = mapping
	state = State.DONE
	prompt = "Mapped %s -> %s" % [Catalog.get_control(control_id).label, describe_mapping(mapping)]
	_emit()
	finished.emit(control_id, mapping)


func _emit() -> void:
	changed.emit(status())


static func describe_mapping(m: Dictionary) -> String:
	var s := "%s (%s" % [m.sig, m.behavior]
	if m.behavior == Behavior.RELATIVE:
		s += ", %s%s" % [m.encoding, ", inverted" if m.get("invert", false) else ""]
	elif m.behavior == Behavior.ABSOLUTE:
		s += ", %d..%d" % [m.raw_min, m.raw_max]
	return s + ")"
