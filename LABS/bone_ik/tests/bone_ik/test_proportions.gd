## Proportions: metric derivation, presets, validation, asymmetry.
extends RefCounted

const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")
const RigBuilder = preload("res://systems/bone_ik/rig/rig_builder.gd")


func test_defaults_are_a_180_cm_body(t) -> void:
	var p := Proportions.new()
	var def := RigBuilder.build(p)
	t.near(def.measurements.stature, 1.80, 1e-6, "stature is exactly the requested height")
	t.near(def.measurements.arm_span, 1.80 * 1.03, 1e-6, "arm span = ratio x stature")
	t.ok(p.problems().is_empty(), "default proportions are valid: %s" % [p.problems()])
	var d := p.derive()
	# Plausibility against rounded modern adult male references at 1.80 m (see BONE-IK-PROPORTIONS.md).
	t.ok(d.left_upper_arm > 0.26 and d.left_upper_arm < 0.32, "upper arm %.3f m" % d.left_upper_arm)
	t.ok(d.left_forearm > 0.24 and d.left_forearm < 0.30, "forearm %.3f m" % d.left_forearm)
	t.ok(d.left_thigh > 0.40 and d.left_thigh < 0.47, "thigh %.3f m" % d.left_thigh)
	t.ok(d.left_shank > 0.40 and d.left_shank < 0.47, "shank %.3f m" % d.left_shank)
	t.ok(d.foot > 0.25 and d.foot < 0.30, "foot %.3f m" % d.foot)
	t.ok(d.hand > 0.17 and d.hand < 0.21, "hand %.3f m" % d.hand)
	t.ok(def.measurements.navel_height / 1.8 > 0.58 and def.measurements.navel_height / 1.8 < 0.64,
		"navel at %.3f of stature (Vitruvian circle centre)" % (def.measurements.navel_height / 1.8))


func test_height_scales_every_joint_linearly(t) -> void:
	var a := RigBuilder.build(Proportions.new())
	var b := RigBuilder.build(Proportions.new({"height": 1.50}))
	var k := 1.50 / 1.80
	var worst := 0.0
	for i in a.bones.size():
		worst = maxf(worst, (a.bones[i].global.origin * k).distance_to(b.bones[i].global.origin))
	t.ok(worst < 1e-5, "every joint scales with stature (worst %.7f m)" % worst)
	t.near(b.measurements.stature, 1.50, 1e-6, "1.50 m body is 1.50 m")


func test_vertical_weights_always_sum_to_the_stature(t) -> void:
	for overrides in [{"leg_weight": 0.62}, {"torso_weight": 0.24}, {"head_neck_weight": 0.2, "leg_weight": 0.4}]:
		var def := RigBuilder.build(Proportions.new(overrides))
		t.near(def.measurements.stature, 1.80, 1e-6, "stature exact with %s" % [overrides])


func test_arm_span_drives_arm_length(t) -> void:
	for ratio in [0.95, 1.0, 1.08]:
		var def := RigBuilder.build(Proportions.new({"arm_span_ratio": ratio}))
		t.near(def.measurements.arm_span, 1.8 * ratio, 1e-6, "span for ratio %.2f" % ratio)


func test_values_are_clamped_and_unknown_names_rejected(t) -> void:
	var p := Proportions.new()
	p.set_value("height", 9.0)
	t.eq(p.get_value("height"), 2.6, "height clamped to its maximum")
	p.set_value("hand_length_ratio", -1.0)
	t.eq(p.get_value("hand_length_ratio"), 0.085, "hand clamped to its minimum")
	t.ok(not p.set_value("tail_length", 1.0), "unknown proportion rejected")


func test_extreme_but_allowed_combinations_stay_valid(t) -> void:
	var p := Proportions.new({"arm_span_ratio": 0.90, "shoulder_width_ratio": 0.26, "hand_length_ratio": 0.13})
	var def := RigBuilder.build(p)
	var ok := true
	for bone in def.bones:
		ok = ok and bone.length > 0.0
	t.ok(ok, "every bone keeps a positive length")
	t.ok(p.problems().is_empty(), "the shortest allowed arm is still valid: %s" % [p.problems()])
	var tiny_head := Proportions.new({"head_neck_weight": 0.11, "neck_share": 0.5, "leg_weight": 0.62})
	t.ok(tiny_head.problems().size() > 0, "an implausibly small head is reported: %s" % [tiny_head.problems()])


func test_presets(t) -> void:
	var v = Proportions.from_preset("vitruvian")
	var def := RigBuilder.build(v)
	t.near(def.measurements.arm_span, def.measurements.stature, 1e-6, "Vitruvian: arm span = height")
	t.near(v.derive().foot, 1.8 / 7.0, 1e-6, "Vitruvian: foot = 1/7 of height")
	t.near(def.measurements.hip_joint_height, 0.9, 1e-6, "Vitruvian: hip line (pubis) at half height")


func test_intentional_asymmetry(t) -> void:
	var p := Proportions.new({"right_arm_scale": 1.1, "left_leg_scale": 1.05})
	t.ok(not p.is_symmetric(), "asymmetric proportions are flagged")
	var def := RigBuilder.build(p)
	var l: float = def.bones[def.index.LeftLowerArm].local.origin.length()
	var r: float = def.bones[def.index.RightLowerArm].local.origin.length()
	t.near(r / l, 1.1, 1e-5, "right upper arm 10 % longer")
	t.ok(def.landmarks.heel_l.y < def.landmarks.heel_r.y, "longer left leg reaches lower")
	t.near(def.measurements.stature, def.landmarks.vertex.y - def.landmarks.heel_l.y, 1e-6, "stature from the lowest sole")
