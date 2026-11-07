## Proportions of the humanoid rig: limb lengths, joint positions (hip and shoulder width, shoulder height) and limb thickness.
## VISUAL ONLY: the movement simulation never reads these. Lengths are metres at scale 1 and all of them (and the radii) are
## multiplied by the overall scale, so the gait model, which plans in metres on the belt, always sees the real size.
## Defaults are exactly the original rig, so nothing changes until a value is moved.
extends RefCounted

const ParamSet = preload("res://animation/param_set.gd")

const GROUPS := ["size", "legs", "torso", "arms", "thickness"]


static func _d(id: String, label: String, group: String, unit: String, lo: float, hi: float, default: float, step: float, extra := {}) -> Dictionary:
	var d := {"id": id, "label": label, "group": group, "unit": unit, "min": lo, "max": hi, "default": default, "step": step, "affects": "visual"}
	d.merge(extra, true)
	return d


static func definitions() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		_d("scale", "Overall size", "size", "x", 0.6, 1.5, 1.0, 0.01, {"curve": "log", "hint": "multiplies every length and thickness"}),
		# ---- legs
		_d("thigh_length", "Thigh length", "legs", "m", 0.30, 0.65, 0.45, 0.005, {"hint": "hip to knee"}),
		_d("shin_length", "Shin length", "legs", "m", 0.30, 0.65, 0.44, 0.005, {"hint": "knee to ankle"}),
		_d("ankle_height", "Ankle height", "legs", "m", 0.04, 0.12, 0.065, 0.0025, {"hint": "sole to ankle joint"}),
		_d("foot_length", "Foot length", "legs", "m", 0.15, 0.38, 0.25, 0.005, {"hint": "heel to toe; the ankle sits 26 % of the way along"}),
		_d("hip_width", "Hip joint offset", "legs", "m", 0.04, 0.22, 0.10, 0.005, {"hint": "each hip joint's distance from the centre line"}),
		# ---- torso
		_d("torso_length", "Lower torso length", "torso", "m", 0.14, 0.50, 0.28, 0.005, {"hint": "pelvis to chest joint"}),
		_d("chest_length", "Chest length", "torso", "m", 0.16, 0.45, 0.26, 0.005, {"hint": "chest joint to the base of the neck; the shoulders sit near the top"}),
		_d("neck_length", "Neck length", "torso", "m", 0.03, 0.20, 0.08, 0.005),
		_d("head_radius", "Head radius", "torso", "m", 0.06, 0.18, 0.105, 0.0025),
		_d("shoulder_width", "Shoulder joint offset", "torso", "m", 0.10, 0.40, 0.23, 0.005, {"hint": "each shoulder joint's distance from the centre line"}),
		_d("torso_width", "Torso width", "torso", "x", 0.5, 1.6, 1.0, 0.02, {"hint": "side-to-side size of the pelvis, spine and chest blocks"}),
		_d("torso_depth", "Torso depth", "torso", "x", 0.5, 1.8, 1.0, 0.02, {"hint": "front-to-back size of the pelvis, spine and chest blocks"}),
		# ---- arms
		_d("upper_arm_length", "Upper arm length", "arms", "m", 0.18, 0.50, 0.29, 0.005, {"hint": "shoulder to elbow"}),
		_d("forearm_length", "Forearm length", "arms", "m", 0.16, 0.45, 0.29, 0.005, {"hint": "elbow to wrist"}),
		# ---- thickness
		_d("thigh_radius", "Thigh thickness", "thickness", "m", 0.03, 0.13, 0.075, 0.0025, {"hint": "radius"}),
		_d("shin_radius", "Shin thickness", "thickness", "m", 0.025, 0.11, 0.058, 0.0025, {"hint": "radius"}),
		_d("upper_arm_radius", "Upper arm thickness", "thickness", "m", 0.025, 0.10, 0.05, 0.0025, {"hint": "radius"}),
		_d("forearm_radius", "Forearm thickness", "thickness", "m", 0.02, 0.09, 0.042, 0.0025, {"hint": "radius"}),
	]
	return out


static func create():
	return ParamSet.new(definitions())


## Real-world dimensions (metres) the rig and the gait model both use, from a rig parameter set, or the original rig for null.
static func dims(rig = null) -> Dictionary:
	var v := func(id: String) -> float:
		return float(rig.get_value(id)) if rig != null else float(_default(id))
	var k: float = v.call("scale")
	var foot: float = v.call("foot_length") * k
	var ankle: float = v.call("ankle_height") * k
	return {
		"scale": k,
		"thigh": v.call("thigh_length") * k, "shin": v.call("shin_length") * k,
		"ankle_h": ankle, "foot_len": foot, "hip_x": v.call("hip_width") * k, "hip_drop": 0.05 * k,
		"heel": Vector2(-0.26 * foot, -ankle), "toe": Vector2(0.74 * foot, -ankle),
		"torso": v.call("torso_length") * k, "chest": v.call("chest_length") * k, "neck": v.call("neck_length") * k,
		"head_r": v.call("head_radius") * k, "shoulder_x": v.call("shoulder_width") * k,
		"torso_w": v.call("torso_width"), "torso_d": v.call("torso_depth"),
		"upper_arm": v.call("upper_arm_length") * k, "forearm": v.call("forearm_length") * k,
		"thigh_r": v.call("thigh_radius") * k, "shin_r": v.call("shin_radius") * k,
		"upper_arm_r": v.call("upper_arm_radius") * k, "forearm_r": v.call("forearm_radius") * k,
	}


static func _default(id: String) -> float:
	for d in definitions():
		if d.id == id:
			return float(d.default)
	return 0.0
