## A set of tunable parameters with explicit definitions: id, label, group, unit, min, max, default, step, optional
## response curve and an `affects` tag ("physics" / "visual"). Values are clamped and snapped on every write, so
## nothing downstream ever sees an illegal value. Implements the interface TunableRegistry expects of a target.
##
## Definition keys:  id, label, group, unit, min, max, default, step            (required)
##                   type: "bool" (stored as 0.0 / 1.0)                          (optional)
##                   curve: "linear" (default) | "log" | "quad" | "sqrt"         (optional; how a 0..1 control maps)
##                   affects: "visual" | "physics"                               (optional, default "physics")
##                   hint: one line of help                                      (optional)
## Curves only change how a normalised 0..1 control position maps to the value; stored values are always real units.
##   log  : geometric between min and max (needs min > 0) - for frequencies, where each octave deserves equal travel
##   quad : finer control at the low end;  sqrt: finer control at the high end
extends RefCounted

signal changed(id: String, value: float)

var _defs: Array[Dictionary] = []
var _index: Dictionary = {}
var values: Dictionary = {}


func _init(defs: Array = []) -> void:
	for d in defs:
		_defs.append(d)
		_index[d.id] = d
		values[d.id] = float(d.default)


func definitions() -> Array[Dictionary]:
	return _defs


func ids() -> Array[String]:
	var out: Array[String] = []
	for d in _defs:
		out.append(d.id)
	return out


func def(id: String) -> Dictionary:
	return _index.get(id, {})


func affects(id: String) -> String:
	return String(def(id).get("affects", "physics"))


func get_value(id: String) -> float:
	return float(values.get(id, def(id).get("default", 0.0)))


func is_on(id: String) -> bool:
	return get_value(id) >= 0.5


func clamp_value(id: String, v: float) -> float:
	var d := def(id)
	if d.is_empty():
		return v
	if is_nan(v):
		return float(d.default)
	var x := clampf(v, float(d.min), float(d.max))
	if d.get("type", "") == "bool":
		return 1.0 if x >= 0.5 else 0.0
	return x


## Rounds to the step (measured from the minimum), clamped. Goes through a decimal string so 0.3 + 0.1 stores as 0.4.
func snap(id: String, v: float) -> float:
	var d := def(id)
	if d.is_empty():
		return v
	if is_nan(v):
		return float(d.default)
	var step := float(d.step)
	var s := v if step <= 0.0 else float(d.min) + snappedf(v - float(d.min), step)
	return clamp_value(id, float("%.6f" % s))


## Clamps into range, stores, emits `changed` only on a real change. Returns the stored value.
func set_value(id: String, v: float) -> float:
	if _index.is_empty() or not _index.has(id):
		return v
	var x := snap(id, v)
	if not is_equal_approx(float(values[id]), x):
		values[id] = x
		changed.emit(id, x)
	return x


func reset(id: String) -> void:
	if _index.has(id):
		set_value(id, float(def(id).default))


func reset_all() -> void:
	for d in _defs:
		reset(d.id)


func is_default(id: String) -> bool:
	return _index.has(id) and is_equal_approx(float(values[id]), float(def(id).default))


## Unknown ids are returned (never silently dropped); wrong types are ignored.
func apply(d: Dictionary) -> Array[String]:
	var unknown: Array[String] = []
	for id in d:
		if not _index.has(String(id)):
			unknown.append(String(id))
		elif typeof(d[id]) == TYPE_FLOAT or typeof(d[id]) == TYPE_INT:
			set_value(String(id), float(d[id]))
	return unknown


func snapshot() -> Dictionary:
	return values.duplicate()


# ------------------------------------------------------------------ control mapping

func from_normalized(id: String, t: float) -> float:
	var d := def(id)
	if d.is_empty():
		return t
	t = clampf(t, 0.0, 1.0)
	var lo := float(d.min)
	var hi := float(d.max)
	var x := lo
	match String(d.get("curve", "linear")):
		"log":
			x = lo * pow(hi / lo, t) if lo > 0.0 else lo + (hi - lo) * t
		"quad":
			x = lo + (hi - lo) * t * t
		"sqrt":
			x = lo + (hi - lo) * sqrt(t)
		_:
			x = lo + (hi - lo) * t
	return clamp_value(id, x)


func to_normalized(id: String, v: float) -> float:
	var d := def(id)
	if d.is_empty():
		return v
	var lo := float(d.min)
	var hi := float(d.max)
	if hi <= lo:
		return 0.0
	var f := clampf((v - lo) / (hi - lo), 0.0, 1.0)
	match String(d.get("curve", "linear")):
		"log":
			if lo > 0.0:
				return clampf(log(maxf(v, lo) / lo) / log(hi / lo), 0.0, 1.0)
			return f
		"quad":
			return sqrt(f)
		"sqrt":
			return f * f
	return f


## Definitions are internally consistent; used by tests.
func check_definitions() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for d in _defs:
		for k in ["id", "label", "group", "unit", "min", "max", "default", "step"]:
			if not d.has(k):
				problems.append("%s: missing '%s'" % [str(d.get("id", "?")), k])
		if problems.size() > 0 and not d.has("id"):
			continue
		if seen.has(d.id):
			problems.append("duplicate id %s" % d.id)
		seen[d.id] = true
		if d.has("min") and d.has("max") and not (d.min < d.max):
			problems.append("%s: min must be below max" % d.id)
		if d.has("default") and (d.default < d.min or d.default > d.max):
			problems.append("%s: default outside range" % d.id)
		if String(d.get("curve", "linear")) == "log" and not (d.min > 0.0):
			problems.append("%s: log curve needs min > 0" % d.id)
		if not ["linear", "log", "quad", "sqrt"].has(String(d.get("curve", "linear"))):
			problems.append("%s: unknown curve" % d.id)
		if not ["visual", "physics"].has(String(d.get("affects", "physics"))):
			problems.append("%s: affects must be visual or physics" % d.id)
		if d.get("type", "") == "bool" and (d.min != 0.0 or d.max != 1.0):
			problems.append("%s: booleans are 0..1" % d.id)
	return problems
