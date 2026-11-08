extends RefCounted

const ParamSet = preload("res://animation/param_set.gd")


static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec in [
		["transition_duration", "Animation transition", "s", 0.06, 0.35, 0.16, 0.01],
		["cadence_multiplier", "Cadence multiplier", "x", 0.85, 1.15, 1.0, 0.01],
		["stride_scale", "Stride scale", "x", 0.9, 1.1, 1.0, 0.01],
		["lean_intensity", "Body lean intensity", "x", 0.0, 1.5, 1.0, 0.05],
		["foot_ik", "Flat-ground foot IK", "on/off", 0.0, 1.0, 1.0, 1.0],
		["legacy", "Legacy procedural baseline", "on/off", 0.0, 1.0, 0.0, 1.0],
	]:
		var definition := {"id": spec[0], "label": spec[1], "group": "locomotion", "unit": spec[2],
			"min": spec[3], "max": spec[4], "default": spec[5], "step": spec[6], "affects": "visual"}
		if spec[2] == "on/off":
			definition["type"] = "bool"
		result.append(definition)
	return result


static func create():
	return ParamSet.new(definitions())
