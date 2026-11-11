extends RefCounted

const ParamSet = preload("res://systems/movement_core/animation/param_set.gd")
const PATHS := {
	"walk_blend": "parameters/WalkBlend/blend_amount",
	"body_blend": "parameters/BodyAdd/add_amount",
	"playback_speed": "parameters/WalkSpeed/scale",
}


static func definitions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec in [
		["walk_blend", "Walk graph blend", "ratio", 0.0, 1.0, 1.0, 0.01],
		["body_blend", "Body additive blend", "ratio", 0.0, 1.0, 1.0, 0.01],
		["playback_speed", "Graph playback speed", "x", 0.05, 2.0, 1.0, 0.05],
	]:
		out.append({"id": spec[0], "label": spec[1], "group": "graph", "unit": spec[2],
			"min": spec[3], "max": spec[4], "default": spec[5], "step": spec[6], "affects": "visual"})
	return out


static func create():
	return ParamSet.new(definitions())
