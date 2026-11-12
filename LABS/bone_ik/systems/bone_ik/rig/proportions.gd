## Editable body proportions of the Vitruvian rig, and their conversion to metric segment lengths.
##
## Every value except `height` and `body_mass` is a ratio, so one set of proportions describes a body at any
## stature. Vertical layout uses three weights (legs, torso, head and neck) that are normalised to sum to 1, so
## any edit keeps the stature exact and the hierarchy valid. Arm span drives the total arm length; the
## upper-arm share and hand length split it. Sources and the reasoning behind each default:
## AGENT-WORKSHOP/DOCUMENTATION/BONE-IK-PROPORTIONS.md.
extends RefCounted

## name -> [default, minimum, maximum, label]
const SPEC := {
	"height": [1.80, 1.0, 2.6, "stature (m)"],
	"arm_span_ratio": [1.03, 0.90, 1.15, "arm span / stature"],
	"leg_weight": [0.522, 0.40, 0.62, "legs: hip joint height (weight)"],
	"torso_weight": [0.328, 0.24, 0.42, "torso: hip joint to C7/T1 (weight)"],
	"head_neck_weight": [0.150, 0.11, 0.20, "head + neck: C7/T1 to vertex (weight)"],
	"neck_share": [0.37, 0.25, 0.50, "neck share of head + neck"],
	"thigh_share": [0.493, 0.42, 0.56, "thigh share of hip-to-ankle"],
	"ankle_height_ratio": [0.039, 0.025, 0.06, "ankle joint height / stature"],
	"shoulder_width_ratio": [0.18, 0.13, 0.26, "shoulder joint centres / stature"],
	"pelvis_width_ratio": [0.095, 0.07, 0.14, "hip joint centres / stature"],
	"upper_arm_share": [0.512, 0.44, 0.58, "upper-arm share of shoulder-to-wrist"],
	"hand_length_ratio": [0.108, 0.085, 0.13, "hand, wrist to fingertip / stature"],
	"hand_width_ratio": [0.05, 0.035, 0.07, "hand breadth / stature"],
	"foot_length_ratio": [0.152, 0.12, 0.18, "foot, heel to toe tip / stature"],
	"foot_width_ratio": [0.055, 0.04, 0.075, "foot breadth / stature"],
	"head_width_ratio": [0.085, 0.07, 0.11, "head breadth / stature"],
	"left_arm_scale": [1.0, 0.8, 1.2, "left arm length factor (asymmetry)"],
	"right_arm_scale": [1.0, 0.8, 1.2, "right arm length factor (asymmetry)"],
	"left_leg_scale": [1.0, 0.8, 1.2, "left leg length factor (asymmetry)"],
	"right_leg_scale": [1.0, 0.8, 1.2, "right leg length factor (asymmetry)"],
	"body_mass": [75.0, 30.0, 250.0, "body mass (kg), for the physics body plan"],
}

## Fractions of the torso between the hip-joint line and C7/T1: pelvis (to L5/S1), lumbar (to T12/L1),
## lower thoracic (to ~T6/T7), upper thoracic (to C7/T1). Fixed in phase 1; documented with the proportions.
const TORSO_SPLIT := [0.17, 0.22, 0.25, 0.36]
## Navel height above the hip-joint line as a share of the torso (de Leva's LPT / trunk, about 0.24).
const NAVEL_SHARE := 0.24

## Conceptual presets. "modern" is the default (rounded modern adult anthropometry); "vitruvian" follows the
## ratios written on Leonardo's drawing (arm span = height, foot = 1/7, hand = 1/10, the pubis at half height).
const PRESETS := {
	"modern": {},
	"vitruvian": {"arm_span_ratio": 1.0, "leg_weight": 0.50, "torso_weight": 0.35, "head_neck_weight": 0.15,
		"foot_length_ratio": 1.0 / 7.0, "hand_length_ratio": 0.10, "shoulder_width_ratio": 0.19},
}

var values := {}


func _init(overrides := {}) -> void:
	reset()
	for key in overrides:
		set_value(key, overrides[key])


func reset() -> void:
	values.clear()
	for key in SPEC:
		values[key] = float(SPEC[key][0])


static func from_preset(name: String):
	var Self = load("res://systems/bone_ik/rig/proportions.gd")
	return Self.new(PRESETS.get(name, {}))


func duplicate():
	var copy = get_script().new()
	copy.values = values.duplicate()
	return copy


## Sets one parameter, clamped to its documented range. Returns false for an unknown name.
func set_value(key: String, value: float) -> bool:
	if not SPEC.has(key):
		push_warning("unknown proportion %s" % key)
		return false
	values[key] = clampf(float(value), SPEC[key][1], SPEC[key][2])
	return true


func get_value(key: String) -> float:
	return values[key]


func is_symmetric() -> bool:
	return is_equal_approx(values.left_arm_scale, values.right_arm_scale) \
		and is_equal_approx(values.left_leg_scale, values.right_leg_scale)


## Problems that clamping alone cannot fix (combinations). Empty = valid.
func problems() -> Array[String]:
	var out: Array[String] = []
	var d := derive()
	for side in ["left", "right"]:
		if d[side + "_upper_arm"] < 0.06 * d.height or d[side + "_forearm"] < 0.06 * d.height:
			out.append("%s arm too short for its shoulder width and hand length" % side)
		if d[side + "_thigh"] < 0.12 * d.height or d[side + "_shank"] < 0.12 * d.height:
			out.append("%s leg too short" % side)
	if d.neck < 0.02 * d.height or d.head < 0.06 * d.height:
		out.append("head / neck too short")
	return out


## Metric segment lengths and joint heights (metres). Side-specific limb values carry the asymmetry factors.
func derive() -> Dictionary:
	var h: float = values.height
	var total: float = values.leg_weight + values.torso_weight + values.head_neck_weight
	var legs: float = values.leg_weight / total
	var torso_n: float = values.torso_weight / total
	var head_neck_n: float = values.head_neck_weight / total
	var d := {"height": h}
	d.hip_joint_height = legs * h
	d.ankle_height = values.ankle_height_ratio * h
	d.torso = torso_n * h
	d.head_neck = head_neck_n * h
	d.neck = d.head_neck * values.neck_share
	d.head = d.head_neck - d.neck
	d.neck_base_height = d.hip_joint_height + d.torso       # C7/T1
	d.head_pivot_height = d.neck_base_height + d.neck       # atlanto-occipital
	d.navel_height = d.hip_joint_height + NAVEL_SHARE * d.torso
	d.shoulder_width = values.shoulder_width_ratio * h
	d.pelvis_width = values.pelvis_width_ratio * h
	d.hand = values.hand_length_ratio * h
	d.hand_width = values.hand_width_ratio * h
	d.foot = values.foot_length_ratio * h
	d.foot_width = values.foot_width_ratio * h
	d.head_width = values.head_width_ratio * h
	var arm: float = (values.arm_span_ratio * h - d.shoulder_width) * 0.5   # shoulder joint centre to fingertip
	var reach: float = arm - d.hand
	var leg: float = d.hip_joint_height - d.ankle_height                    # hip joint to ankle joint
	for side in ["left", "right"]:
		var arm_k: float = values[side + "_arm_scale"]
		var leg_k: float = values[side + "_leg_scale"]
		d[side + "_upper_arm"] = reach * values.upper_arm_share * arm_k
		d[side + "_forearm"] = reach * (1.0 - values.upper_arm_share) * arm_k
		d[side + "_hand"] = d.hand * arm_k
		d[side + "_thigh"] = leg * values.thigh_share * leg_k
		d[side + "_shank"] = leg * (1.0 - values.thigh_share) * leg_k
	d.body_mass = values.body_mass
	return d
