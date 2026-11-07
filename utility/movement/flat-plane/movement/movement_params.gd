## Explicit definitions of every tunable movement parameter: id, unit, minimum, maximum, default, step.
## Values live in a plain Dictionary so the simulation can read them with no overhead, and every write is clamped.
## Metres, seconds, degrees only where stated in `unit`.
extends RefCounted

signal changed(id: String, value: float)

const GROUPS := ["ground", "jump", "air", "slope", "body"]

## type "bool" is stored as 0.0 / 1.0. `fine` is the step used by fine-adjustment controls (knobs).
const DEFS: Array[Dictionary] = [
	{"id": "max_ground_speed", "label": "Max ground speed", "group": "ground", "unit": "m/s", "min": 1.0, "max": 15.0, "default": 4.5, "step": 0.1},
	{"id": "ground_accel", "label": "Ground acceleration", "group": "ground", "unit": "m/s^2", "min": 1.0, "max": 120.0, "default": 45.0, "step": 1.0},
	{"id": "ground_friction", "label": "Ground friction", "group": "ground", "unit": "1/s", "min": 0.0, "max": 20.0, "default": 7.0, "step": 0.1},
	{"id": "braking", "label": "Braking (no/opposing input)", "group": "ground", "unit": "m/s^2", "min": 0.0, "max": 100.0, "default": 20.0, "step": 1.0},
	{"id": "stop_speed", "label": "Friction stop speed", "group": "ground", "unit": "m/s", "min": 0.1, "max": 5.0, "default": 1.0, "step": 0.05},
	{"id": "sprint_multiplier", "label": "Sprint multiplier", "group": "ground", "unit": "x", "min": 1.0, "max": 3.0, "default": 1.6, "step": 0.05},
	{"id": "crouch_speed", "label": "Crouch speed", "group": "ground", "unit": "m/s", "min": 0.5, "max": 6.0, "default": 2.0, "step": 0.1},
	{"id": "jump_impulse", "label": "Jump impulse", "group": "jump", "unit": "m/s", "min": 1.0, "max": 15.0, "default": 5.5, "step": 0.1},
	{"id": "gravity", "label": "Gravity", "group": "jump", "unit": "m/s^2", "min": 1.0, "max": 60.0, "default": 19.6, "step": 0.2},
	{"id": "max_fall_speed", "label": "Terminal fall speed", "group": "jump", "unit": "m/s", "min": 5.0, "max": 100.0, "default": 50.0, "step": 1.0},
	{"id": "coyote_time", "label": "Coyote time", "group": "jump", "unit": "s", "min": 0.0, "max": 0.5, "default": 0.1, "step": 0.01},
	{"id": "jump_buffer_time", "label": "Jump buffer", "group": "jump", "unit": "s", "min": 0.0, "max": 0.5, "default": 0.1, "step": 0.01},
	{"id": "auto_jump", "label": "Auto-jump while held", "group": "jump", "unit": "on/off", "min": 0.0, "max": 1.0, "default": 0.0, "step": 1.0, "type": "bool"},
	{"id": "air_accel", "label": "Air acceleration", "group": "air", "unit": "m/s^2", "min": 0.0, "max": 200.0, "default": 30.0, "step": 1.0},
	{"id": "air_speed_cap", "label": "Air speed cap (wish speed)", "group": "air", "unit": "m/s", "min": 0.0, "max": 10.0, "default": 1.2, "step": 0.05},
	{"id": "air_control", "label": "Air steering", "group": "air", "unit": "0..1", "min": 0.0, "max": 1.0, "default": 0.35, "step": 0.01},
	{"id": "max_walkable_slope", "label": "Max walkable slope", "group": "slope", "unit": "deg", "min": 5.0, "max": 85.0, "default": 46.0, "step": 1.0},
	{"id": "slope_speed_penalty", "label": "Uphill speed penalty", "group": "slope", "unit": "0..1", "min": 0.0, "max": 1.0, "default": 0.4, "step": 0.01},
	{"id": "step_height", "label": "Step-up height", "group": "slope", "unit": "m", "min": 0.0, "max": 0.6, "default": 0.35, "step": 0.01},
	{"id": "stand_height", "label": "Standing height", "group": "body", "unit": "m", "min": 1.4, "max": 2.2, "default": 1.8, "step": 0.01},
	{"id": "crouch_height", "label": "Crouching height", "group": "body", "unit": "m", "min": 0.8, "max": 1.4, "default": 1.1, "step": 0.01},
]

static var _index: Dictionary = {}

var values: Dictionary = defaults()


static func definitions() -> Array[Dictionary]:
	return DEFS


static func ids() -> Array[String]:
	var out: Array[String] = []
	for d in DEFS:
		out.append(d.id)
	return out


static func def(id: String) -> Dictionary:
	if _index.is_empty():
		for d in DEFS:
			_index[d.id] = d
	return _index.get(id, {})


static func defaults() -> Dictionary:
	var out := {}
	for d in DEFS:
		out[d.id] = float(d.default)
	return out


static func clamp_value(id: String, v: float) -> float:
	var d := def(id)
	if d.is_empty():
		return v
	var x := clampf(v, float(d.min), float(d.max))
	if d.get("type", "") == "bool":
		return 1.0 if x >= 0.5 else 0.0
	return x


## Maps a normalised 0..1 control position to the parameter range.
static func from_normalized(id: String, t: float) -> float:
	var d := def(id)
	return clamp_value(id, lerpf(float(d.min), float(d.max), clampf(t, 0.0, 1.0)))


## Rounds to the parameter's step (measured from its minimum) so controller-set values are clean numbers.
static func snap(id: String, v: float) -> float:
	var d := def(id)
	if d.is_empty():
		return v
	var step := float(d.step)
	var snapped := v if step <= 0.0 else float(d.min) + snappedf(v - float(d.min), step)
	# Round-trip through a decimal string: the nearest double to the decimal value, so 4.5 + 0.1 stores as 4.6, not 4.6000000000000005.
	return clamp_value(id, float("%.6f" % snapped))


static func to_normalized(id: String, v: float) -> float:
	var d := def(id)
	return clampf((v - float(d.min)) / (float(d.max) - float(d.min)), 0.0, 1.0)


func get_value(id: String) -> float:
	return float(values.get(id, def(id).get("default", 0.0)))


## Clamps into the legal range. Returns the stored value; emits `changed` only when it actually changed.
func set_value(id: String, v: float) -> float:
	if def(id).is_empty():
		return v
	var x := clamp_value(id, v)
	if not is_equal_approx(float(values[id]), x):
		values[id] = x
		changed.emit(id, x)
	return x


func reset(id: String) -> void:
	set_value(id, float(def(id).get("default", 0.0)))


func reset_all() -> void:
	for d in DEFS:
		reset(d.id)


func is_default(id: String) -> bool:
	return is_equal_approx(float(values[id]), float(def(id).default))


## Applies a dictionary of values (e.g. from a preset). Unknown ids are returned, never silently dropped.
func apply(d: Dictionary) -> Array[String]:
	var unknown: Array[String] = []
	for id in d:
		if def(String(id)).is_empty():
			unknown.append(String(id))
		elif typeof(d[id]) == TYPE_FLOAT or typeof(d[id]) == TYPE_INT:
			set_value(String(id), float(d[id]))
	return unknown


func snapshot() -> Dictionary:
	return values.duplicate()


## Definitions are internally consistent. Returns problems (empty = fine); used by tests.
static func check_definitions() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for d in DEFS:
		if seen.has(d.id):
			problems.append("duplicate id %s" % d.id)
		seen[d.id] = true
		if not (d.min < d.max):
			problems.append("%s: min must be below max" % d.id)
		if d.default < d.min or d.default > d.max:
			problems.append("%s: default outside range" % d.id)
		if String(d.unit) == "" or String(d.label) == "":
			problems.append("%s: unit and label are required" % d.id)
		if not GROUPS.has(d.group):
			problems.append("%s: unknown group %s" % [d.id, d.group])
	return problems
