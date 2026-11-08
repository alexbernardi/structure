## The four traversal controls (Movement Lab 4.0), plus the traversal and debug switches. Everything else is derived
## from the approach speed, the measured obstacle and the authored clip.
extends RefCounted

const ParamSet = preload("res://animation/param_set.gd")


static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec in [
		["anticipation", "Anticipation", "s", 0.15, 0.6, 0.35, 0.01, "physics"],
		["transition_response", "Transition response", "s", 0.06, 0.3, 0.12, 0.01, "visual"],
		["contact_correction", "Contact correction", "x", 0.0, 1.0, 1.0, 0.05, "visual"],
		["momentum_continuity", "Momentum continuity", "x", 0.0, 1.0, 0.6, 0.05, "physics"],
		["traversal", "Traversal (vault)", "on/off", 0.0, 1.0, 1.0, 1.0, "physics"],
		["debug_overlay", "Traversal debug overlay", "on/off", 0.0, 1.0, 0.0, 1.0, "visual"],
	]:
		var definition := {"id": spec[0], "label": spec[1], "group": "traversal", "unit": spec[2],
			"min": spec[3], "max": spec[4], "default": spec[5], "step": spec[6], "affects": spec[7]}
		if spec[2] == "on/off":
			definition["type"] = "bool"
		result.append(definition)
	return result


static func create():
	return ParamSet.new(definitions())
