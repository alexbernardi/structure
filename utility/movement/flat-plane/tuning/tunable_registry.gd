## Everything the controller can tune, addressed as "target.id" (e.g. "movement.max_ground_speed").
## A target is any object that provides: definitions(), def(id), get_value(id), set_value(id, v) -> stored,
## reset(id), is_default(id), from_normalized(id, t), to_normalized(id, v), snap(id, v).
## Movement parameters are the first target; other systems register theirs and reuse the same banks and presets.
extends RefCounted

signal targets_changed

var _targets: Dictionary = {}   # name -> {label, source}


static func make_key(target: String, id: String) -> String:
	return "%s.%s" % [target, id]


static func is_valid_key(key: String) -> bool:
	var parts := key.split(".")
	if parts.size() != 2 or parts[0] == "" or parts[1] == "":
		return false
	var re := RegEx.create_from_string("^[a-z0-9_]+$")
	return re.search(parts[0]) != null and re.search(parts[1]) != null


static func target_of(key: String) -> String:
	return key.get_slice(".", 0)


static func id_of(key: String) -> String:
	return key.get_slice(".", 1)


func register(target: String, label: String, source: Object) -> void:
	_targets[target] = {"label": label, "source": source}
	targets_changed.emit()


func unregister(target: String) -> void:
	if _targets.erase(target):
		targets_changed.emit()


func target_names() -> Array:
	return _targets.keys()


func has_target(target: String) -> bool:
	return _targets.has(target)


func source_of(target: String) -> Object:
	return _targets[target].source if _targets.has(target) else null


## True when the key's target is registered and the parameter exists.
func has_key(key: String) -> bool:
	var t := target_of(key)
	return _targets.has(t) and not _targets[t].source.def(id_of(key)).is_empty()


func keys() -> Array[String]:
	var out: Array[String] = []
	for t in _targets:
		for d in _targets[t].source.definitions():
			out.append(make_key(t, d.id))
	return out


func def_of(key: String) -> Dictionary:
	return _targets[target_of(key)].source.def(id_of(key)) if has_key(key) else {}


func label_of(key: String) -> String:
	var d := def_of(key)
	return String(d.get("label", key))


func unit_of(key: String) -> String:
	return String(def_of(key).get("unit", ""))


func target_label(key: String) -> String:
	var t := target_of(key)
	return String(_targets[t].label) if _targets.has(t) else t


func value(key: String) -> float:
	return float(_targets[target_of(key)].source.get_value(id_of(key))) if has_key(key) else 0.0


## Clamps and snaps; returns the stored value.
func set_value(key: String, v: float) -> float:
	if not has_key(key):
		return v
	var src: Object = _targets[target_of(key)].source
	return float(src.set_value(id_of(key), src.snap(id_of(key), v)))


func default_of(key: String) -> float:
	return float(def_of(key).get("default", 0.0))


func is_default(key: String) -> bool:
	return has_key(key) and _targets[target_of(key)].source.is_default(id_of(key))


func norm(key: String) -> float:
	return float(_targets[target_of(key)].source.to_normalized(id_of(key), value(key))) if has_key(key) else 0.0


func from_norm(key: String, t: float) -> float:
	return float(_targets[target_of(key)].source.from_normalized(id_of(key), t)) if has_key(key) else 0.0


func is_bool(key: String) -> bool:
	return def_of(key).get("type", "") == "bool"


func step_of(key: String) -> float:
	return float(def_of(key).get("step", 0.0))


func reset(key: String) -> void:
	if has_key(key):
		_targets[target_of(key)].source.reset(id_of(key))


## {target: {id: value}} for every registered target.
func capture() -> Dictionary:
	var out := {}
	for t in _targets:
		var vals := {}
		for d in _targets[t].source.definitions():
			vals[d.id] = float(_targets[t].source.get_value(d.id))
		out[t] = vals
	return out


func format_value(key: String, v: float) -> String:
	var d := def_of(key)
	if d.get("type", "") == "bool":
		return "ON" if v >= 0.5 else "off"
	var step := float(d.get("step", 0.1))
	var decimals := 0 if step >= 1.0 else (1 if step >= 0.1 else 2)
	var unit := String(d.get("unit", ""))
	if unit.begins_with("0.."):
		unit = ""   # a plain 0..1 ratio needs no unit label
	return (("%." + str(decimals) + "f %s") % [v, unit]).strip_edges()
