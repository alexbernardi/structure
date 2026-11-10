## The character's effective movement capability: tuned baselines + profile attributes + modifiers -> the numbers the
## movement core and the traversal planner read, plus the set of capabilities (moves) the character has.
##
## Baselines are never written: movement parameters stay whatever the MIDI tuning says, the traversal controls stay
## in traversal_params, the profile holds the character's own attributes. Modifiers are kept as a list and every
## effective value is recomputed from its baseline whenever anything changes, so adding and removing modifiers in
## any order always returns exactly to the baseline. With no modifiers, every effective value is bit-identical to its
## baseline (no arithmetic is applied), so the 3.0/4.0 physics is unchanged.
##
## Deterministic: timed modifiers count down on the fixed physics tick (tick()), never on wall time.
extends RefCounted

const Attributes = preload("res://capability/movement_attributes.gd")
const Params = preload("res://movement/movement_params.gd")

signal changed

## Attributes whose baseline is an existing tuned control (MIDI bank 5), so tuning and upgrades compose.
const TUNED := {"momentum_conservation": "momentum_continuity", "vault_window": "anticipation"}

var params                        ## movement/movement_params.gd (baseline of the movement core ids)
var traversal_params              ## traversal/traversal_params.gd (baseline of the TUNED ids)
var profile := Attributes.defaults()
var base_capabilities: Array[String] = []
var modifiers: Array = []         ## MovementModifier, in insertion order (order never changes a result)
var core := {}                    ## effective movement core parameters; the same Dictionary object for the body's life
var values := {}                  ## effective traversal attributes
var capabilities := {}            ## capability id -> true
var revision := 0                 ## bumps on every change (cheap cache key for planners)


func _init() -> void:
	for c in Attributes.BASE_CAPABILITIES:
		base_capabilities.append(String(c))


func setup(movement_params, traversal_parameters = null) -> void:
	params = movement_params
	traversal_params = traversal_parameters
	params.changed.connect(func(_id: String, _v: float) -> void: refresh())
	if traversal_params != null:
		traversal_params.changed.connect(func(id: String, _v: float) -> void:
			if TUNED.values().has(id):
				refresh())
	refresh()


## Baseline (unmodified) value of a movement parameter or traversal attribute.
func base_value(id: String) -> float:
	if params != null and not Params.def(id).is_empty():
		return params.get_value(id)
	if TUNED.has(id) and traversal_params != null:
		return traversal_params.get_value(TUNED[id])
	return float(profile.get(id, Attributes.def(id).get("default", 0.0)))


## Effective value: the baseline with every modifier applied (see movement_modifier.gd for the op order).
func resolve(id: String) -> float:
	var value := base_value(id)
	var adds := 0.0
	var muls := 1.0
	var touched := false
	var setter = null
	var cap := INF
	var floor_value := -INF
	for m in modifiers:
		for e in m.effects:
			if e.stat != id:
				continue
			touched = true
			match e.op:
				"add":
					adds += e.value
				"mul":
					muls *= e.value
				"set":
					if setter == null or m.priority > setter[0] or (m.priority == setter[0] and m.id > setter[1]):
						setter = [m.priority, m.id, e.value]
				"cap":
					cap = minf(cap, e.value)
				"floor":
					floor_value = maxf(floor_value, e.value)
	if not touched:
		return value
	value = (value + adds) * muls
	if setter != null:
		value = setter[2]
	value = clampf(value, floor_value, cap) if floor_value <= cap else cap
	var d := Params.def(id) if not Params.def(id).is_empty() else Attributes.def(id)
	if not d.is_empty():
		value = clampf(value, float(d.min), float(d.max))
	return value


func get_value(id: String) -> float:
	if values.has(id):
		return values[id]
	if core.has(id):
		return core[id]
	return resolve(id)


## True when the effective value differs from the baseline (an upgraded or impaired attribute).
func modified(id: String) -> bool:
	return get_value(id) != base_value(id)


func can(capability: String) -> bool:
	return capabilities.has(capability)


## Adds a modifier, replacing (and so refreshing the duration of) one with the same id. False if it is invalid.
func add(modifier) -> bool:
	if not modifier.check().is_empty():
		push_warning("Rejected movement modifier: %s" % ", ".join(modifier.check()))
		return false
	remove(modifier.id, false)
	modifier.remaining = modifier.duration
	modifiers.append(modifier)
	refresh()
	return true


func remove(modifier_id: String, notify := true) -> bool:
	for i in modifiers.size():
		if modifiers[i].id == modifier_id:
			modifiers.remove_at(i)
			if notify:
				refresh()
			return true
	return false


func remove_source(source: String) -> int:
	var before := modifiers.size()
	modifiers = modifiers.filter(func(m) -> bool: return m.source != source)
	if modifiers.size() != before:
		refresh()
	return before - modifiers.size()


func clear() -> void:
	if not modifiers.is_empty():
		modifiers.clear()
		refresh()


func has(modifier_id: String) -> bool:
	for m in modifiers:
		if m.id == modifier_id:
			return true
	return false


func find(modifier_id: String):
	for m in modifiers:
		if m.id == modifier_id:
			return m
	return null


## One fixed tick: timed modifiers count down and expire.
func tick(dt: float) -> void:
	var expired := false
	for m in modifiers:
		if m.timed():
			m.remaining -= dt
			expired = expired or m.remaining <= 1e-6   # the tick that reaches the duration, despite float accumulation
	if expired:
		modifiers = modifiers.filter(func(m) -> bool: return not m.timed() or m.remaining > 1e-6)
		refresh()


func refresh() -> void:
	if params != null:
		for d in Params.definitions():
			core[d.id] = resolve(d.id)
	for d in Attributes.DEFS:
		values[d.id] = resolve(d.id)
	capabilities.clear()
	for c in base_capabilities:
		capabilities[c] = true
	for m in modifiers:
		for g in m.grants:
			capabilities[g] = true
	for m in modifiers:
		for r in m.revokes:
			capabilities.erase(r)
	revision += 1
	changed.emit()


func summary() -> String:
	if modifiers.is_empty():
		return "baseline human"
	var parts: Array[String] = []
	for m in modifiers:
		parts.append(m.label if m.label != "" else m.id)
	return " + ".join(parts)
