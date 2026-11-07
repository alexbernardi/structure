## Turns logical control events into parameter changes and actions. Pure logic (no nodes): the tuning system
## feeds it control events and listens to its signals, tests drive it directly.
##  - faders (absolute) set the bound parameter, but only after soft takeover has engaged;
##  - knobs (relative) fine-adjust by whole parameter steps and never jump;
##  - buttons run actions (reset / lock / revert / select a parameter, switch banks, presets, respawn ...);
##  - banks swap which parameters the strips address; every switch re-arms takeover so nothing jumps.
extends RefCounted

const Catalog = preload("res://midi/control_catalog.gd")
const Takeover = preload("res://tuning/soft_takeover.gd")
const Registry = preload("res://tuning/tunable_registry.gd")

signal param_changed(key: String, value: float, source: String)
signal bank_changed(index: int)
## Actions the engine cannot perform itself (respawn, presets, teleport, hud, recording).
signal action_requested(action: String, context: Dictionary)
signal state_changed
signal learn_finished(bank: int, strip: int, kind: String, key: String)

const ENGINE_ACTIONS := ["reset_param", "lock_param", "revert_param", "select_param", "toggle_param", "reset_all", "bank_prev", "bank_next"]

var registry
var bindings
var bank := 0
var locked: Dictionary = {}          ## key -> true: frozen against controllers, presets and resets
var baseline: Dictionary = {}        ## key -> value to revert to (the loaded preset, else defaults)
var selected_key := ""
var preset_name := ""
var last_change: Dictionary = {}     ## {key, value, source, msec} of the most recent change
var pending_learn := ""              ## parameter key waiting to be bound by moving a fader/knob

var _slots: Dictionary = {}          ## "bank:strip" -> takeover state of that strip's fader
var _phys: Dictionary = {}           ## control id -> last physical fader position (0..1)


func _init(reg, bind) -> void:
	registry = reg
	bindings = bind
	capture_baseline()
	rearm_all()


# ------------------------------------------------------------------ control events

## `st` is the manager's control state: faders {value}, knobs {delta}, buttons {pressed}.
func on_control(control_id: String, st: Dictionary) -> void:
	var c := Catalog.get_control(control_id)
	if c.is_empty():
		return
	if c.kind == Catalog.BUTTON:
		if st.get("pressed", false):
			_on_button(control_id, c)
		return
	if pending_learn != "" and (c.kind == Catalog.FADER or c.kind == Catalog.KNOB):
		_finish_learn(int(c.strip), "fader" if c.kind == Catalog.FADER else "knob")
		return
	if c.kind == Catalog.FADER:
		_on_fader(control_id, int(c.strip), float(st.get("value", 0.0)))
	elif c.kind == Catalog.KNOB:
		_on_knob(int(c.strip), int(st.get("delta", 0)))


func _on_fader(control_id: String, strip: int, v: float) -> void:
	_phys[control_id] = v
	var key: String = bindings.slot_key(bank, strip, "fader")
	if key == "" or not registry.has_key(key):
		return
	var slot := _slot_id(bank, strip)
	var state: Dictionary = _slots.get(slot, Takeover.arm(-1.0, registry.norm(key)))
	var was_engaged: bool = state.engaged
	state = Takeover.update(state, v, registry.norm(key))
	_slots[slot] = state
	if state.engaged != was_engaged:
		state_changed.emit()
	if state.engaged and not locked.has(key):
		set_param(key, registry.from_norm(key, v), "fader", slot)


func _on_knob(strip: int, delta: int) -> void:
	var key: String = bindings.slot_key(bank, strip, "knob")
	if delta == 0 or key == "" or not registry.has_key(key) or locked.has(key):
		return
	if registry.is_bool(key):
		set_param(key, 1.0 if delta > 0 else 0.0, "knob")
		return
	set_param(key, registry.value(key) + float(delta) * registry.step_of(key) * bindings.knob_scale(), "knob")


func _on_button(control_id: String, c: Dictionary) -> void:
	var action := ""
	var ctx := {"control": control_id, "strip": int(c.strip)}
	if c.strip > 0:
		var part := control_id.get_slice("_", 1)
		action = bindings.strip_action(part)
		ctx["key"] = strip_key(int(c.strip))
	else:
		action = bindings.global_action(control_id)
	run_action(action, ctx)


## The parameter a strip's buttons act on: its fader's parameter, else its knob's.
func strip_key(strip: int) -> String:
	var k: String = bindings.slot_key(bank, strip, "fader")
	if k == "":
		k = bindings.slot_key(bank, strip, "knob")
	return k if registry.has_key(k) else ""


func run_action(action: String, ctx := {}) -> void:
	if action == "" or action == "none":
		return
	var key: String = ctx.get("key", selected_key)
	match action:
		"reset_param":
			reset_param(key)
		"revert_param":
			revert_param(key)
		"lock_param":
			toggle_lock(key)
		"select_param":
			select(key)
		"toggle_param":
			if registry.has_key(key) and registry.is_bool(key):
				set_param(key, 0.0 if registry.value(key) >= 0.5 else 1.0, "button")
		"reset_all":
			reset_all()
		"bank_next":
			switch_bank((bank + 1) % bindings.bank_count())
		"bank_prev":
			switch_bank((bank - 1 + bindings.bank_count()) % bindings.bank_count())
		_:
			action_requested.emit(action, ctx)


# ------------------------------------------------------------------ parameters

## Sets a parameter from any source. Locked parameters refuse everything except source "force".
## Faders bound to the key (other than the one that caused the change) must be picked up again.
func set_param(key: String, v: float, source: String, origin_slot := "") -> bool:
	if not registry.has_key(key) or (locked.has(key) and source != "force"):
		return false
	var before: float = registry.value(key)
	var after: float = registry.set_value(key, v)
	if is_equal_approx(before, after):
		return false
	last_change = {"key": key, "value": after, "source": source, "msec": Time.get_ticks_msec()}
	param_changed.emit(key, after, source)
	rearm_key(key, origin_slot)
	return true


func reset_param(key: String) -> void:
	if registry.has_key(key):
		set_param(key, registry.default_of(key), "reset")


func revert_param(key: String) -> void:
	if registry.has_key(key):
		set_param(key, float(baseline.get(key, registry.default_of(key))), "revert")


func reset_all() -> void:
	for key in registry.keys():
		set_param(key, registry.default_of(key), "reset")
	preset_name = ""
	capture_baseline_defaults()
	state_changed.emit()


func toggle_lock(key: String) -> void:
	if not registry.has_key(key):
		return
	if locked.has(key):
		locked.erase(key)
	else:
		locked[key] = true
	state_changed.emit()


func select(key: String) -> void:
	selected_key = key if registry.has_key(key) else ""
	state_changed.emit()


# ------------------------------------------------------------------ presets (values live in the preset store)

func capture_baseline() -> void:
	baseline = {}
	var cap: Dictionary = registry.capture()
	for t in cap:
		for id in cap[t]:
			baseline[Registry.make_key(t, id)] = float(cap[t][id])


func capture_baseline_defaults() -> void:
	baseline = {}
	for key in registry.keys():
		baseline[key] = registry.default_of(key)


## Applies {target: {id: value}}. Locked parameters are skipped. Returns {applied, skipped_locked, unknown}.
func apply_values(targets: Dictionary, name: String, source := "preset") -> Dictionary:
	var out := {"applied": 0, "skipped_locked": [], "unknown": []}
	for t in targets:
		for id in targets[t]:
			var key := Registry.make_key(String(t), String(id))
			if not registry.has_key(key):
				out.unknown.append(key)
			elif locked.has(key):
				out.skipped_locked.append(key)
				baseline[key] = float(targets[t][id])
			else:
				set_param(key, float(targets[t][id]), source)
				baseline[key] = float(targets[t][id])
				out.applied += 1
	preset_name = name
	rearm_all()
	state_changed.emit()
	return out


func mark_saved(name: String) -> void:
	preset_name = name
	capture_baseline()
	state_changed.emit()


func modified_keys() -> Array[String]:
	var out: Array[String] = []
	for key in registry.keys():
		if not is_equal_approx(registry.value(key), float(baseline.get(key, registry.default_of(key)))):
			out.append(key)
	return out


func is_modified() -> bool:
	return not modified_keys().is_empty()


# ------------------------------------------------------------------ banks and soft takeover

func _slot_id(b: int, strip: int) -> String:
	return "%d:%d" % [b, strip]


func fader_id(strip: int) -> String:
	return "strip%d_fader" % strip


func switch_bank(i: int) -> void:
	if i < 0 or i >= bindings.bank_count():
		return
	bank = i
	rearm_all()
	bank_changed.emit(bank)
	state_changed.emit()


## Re-evaluates every fader slot against the last physical position seen on that fader.
func rearm_all() -> void:
	for b in bindings.bank_count():
		for strip in range(1, Catalog.STRIPS + 1):
			_rearm_slot(b, strip)


## A parameter changed from `origin_slot` (or from elsewhere if ""): every other fader bound to it needs pickup.
func rearm_key(key: String, origin_slot := "") -> void:
	for b in bindings.bank_count():
		for strip in range(1, Catalog.STRIPS + 1):
			if bindings.slot_key(b, strip, "fader") == key and _slot_id(b, strip) != origin_slot:
				_rearm_slot(b, strip)
	state_changed.emit()


func _rearm_slot(b: int, strip: int) -> void:
	var key: String = bindings.slot_key(b, strip, "fader")
	if key == "" or not registry.has_key(key):
		_slots.erase(_slot_id(b, strip))
		return
	_slots[_slot_id(b, strip)] = Takeover.arm(float(_phys.get(fader_id(strip), -1.0)), registry.norm(key))


## Slot state for the HUD: {key, engaged, physical (-1 unknown), target (0..1)}.
func fader_info(strip: int) -> Dictionary:
	var key: String = bindings.slot_key(bank, strip, "fader")
	if key == "" or not registry.has_key(key):
		return {}
	var st: Dictionary = _slots.get(_slot_id(bank, strip), Takeover.arm(-1.0, registry.norm(key)))
	return {"key": key, "engaged": st.engaged, "physical": float(_phys.get(fader_id(strip), -1.0)), "target": registry.norm(key)}


# ------------------------------------------------------------------ binding by moving a control

func begin_learn(key: String) -> bool:
	if not registry.has_key(key):
		return false
	pending_learn = key
	state_changed.emit()
	return true


func cancel_learn() -> void:
	pending_learn = ""
	state_changed.emit()


func _finish_learn(strip: int, kind: String) -> void:
	var key := pending_learn
	pending_learn = ""
	bindings.assign(bank, strip, kind, key)
	rearm_all()
	learn_finished.emit(bank, strip, kind, key)
	state_changed.emit()
