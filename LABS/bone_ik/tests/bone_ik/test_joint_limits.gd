## Joint profile: data validity, angle round trips, clamping, and anatomical bending directions.
extends RefCounted

const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")
const RigBuilder = preload("res://systems/bone_ik/rig/rig_builder.gd")
const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")
const JointMath = preload("res://systems/bone_ik/rig/joint_math.gd")
const Fk = preload("res://tests/bone_ik/rig_fk.gd")

var def: Dictionary
var profile


func before_each() -> void:
	def = RigBuilder.build(Proportions.new())
	profile = JointProfile.new(def)


func _tip(g: Dictionary, bone: String) -> Vector3:
	return Fk.tip(def, g, bone)


func _origin(g: Dictionary, bone: String) -> Vector3:
	return (g[bone] as Transform3D).origin


func _pose(degrees: Dictionary, clamp := false) -> Dictionary:
	return Fk.globals(def, Fk.pose(profile, degrees, clamp))


func test_data_is_complete_and_consistent(t) -> void:
	t.eq(profile.joints.size(), 21, "5 spinal + 8 per side (left defined, right mirrored)")
	for j in profile.joints:
		for k in JointProfile.AXES:
			var l: Dictionary = j.limits_deg[k]
			t.ok(l.hard.x <= l.soft.x and l.soft.x <= l.soft.y and l.soft.y <= l.hard.y, "%s %s: soft inside hard" % [j.bone, k])
			t.ok(l.soft.x <= 0.0 and l.soft.y >= 0.0, "%s %s: neutral is inside the soft range" % [j.bone, k])
			t.ok(l.hard.y - l.hard.x < 359.0, "%s %s: a bounded range" % [j.bone, k])
		t.ok(not j.sources.is_empty(), "%s cites sources" % j.bone)
		for s in j.sources:
			t.ok(profile.spec.sources.has(s), "%s source %s is defined" % [j.bone, s])
		t.near(j.t.length(), 1.0, 1e-6, "%s twist axis unit" % j.bone)
		t.ok(absf(j.t.dot(j.f)) < 1e-6 and absf(j.t.dot(j.a)) < 1e-6 and absf(j.f.dot(j.a)) < 1e-6, "%s frame orthogonal" % j.bone)
		t.ok(j.f.dot(j.given_f) > 0.85, "%s flex axis close to the documented one (%.2f)" % [j.bone, j.f.dot(j.given_f)])
		t.ok(j.a.dot(j.given_a) > 0.85, "%s abd axis close to the documented one (%.2f)" % [j.bone, j.a.dot(j.given_a)])


func test_right_side_mirrors_the_left(t) -> void:
	for j in profile.joints:
		if not j.bone.begins_with("Left"):
			continue
		var r: Dictionary = profile.joint("Right" + j.bone.substr(4))
		t.ok(r.limits_deg.flex.hard == j.limits_deg.flex.hard and r.limits_deg.twist.soft == j.limits_deg.twist.soft, "%s ranges mirrored" % r.bone)
		t.near(r.f, Vector3(j.f.x, -j.f.y, -j.f.z), 1e-5, "%s flex axis mirrored" % r.bone)
		t.near(r.t, Vector3(j.t.x, -j.t.y, -j.t.z), 1e-5, "%s twist axis mirrored" % r.bone)


func test_rest_pose_angles(t) -> void:
	for j in profile.joints:
		var ang: Vector3 = JointProfile.angles(j, j.rest_local) * (180.0 / PI)
		if j.bone.ends_with("UpperArm"):
			t.near(ang, Vector3(0, 90, 0), 1e-3, "%s: the T-pose is 90 degrees of abduction from the hanging arm" % j.bone)
		else:
			t.near(ang, Vector3.ZERO, 1e-3, "%s rest is anatomical zero" % j.bone)


func test_angles_round_trip(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1505
	var worst := 0.0
	for j in profile.joints:
		for _i in 60:
			var ang := Vector3(rng.randf_range(j.limits.flex.hard.x, j.limits.flex.hard.y),
				rng.randf_range(j.limits.abd.hard.x, j.limits.abd.hard.y),
				rng.randf_range(j.limits.twist.hard.x, j.limits.twist.hard.y))
			ang = JointMath.clamp_angles(ang, j.limits)
			if Vector2(ang.x, ang.y).length() > deg_to_rad(170.0):
				continue   # within 10 degrees of the swing singularity (arm straight overhead) twist is ill-conditioned
			var back := JointProfile.angles(j, JointProfile.local_from_angles(j, ang))
			worst = maxf(worst, (back - ang).length())
	t.ok(worst < 1e-4, "angles -> local rotation -> angles is exact (worst %.7f rad)" % worst)


func test_clamping_keeps_every_joint_inside_its_hard_limits(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var worst := 0.0
	var moved_inside := 0
	for j in profile.joints:
		for _i in 80:
			var q: Quaternion = Quaternion(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
				rng.randf_range(0.0, PI)) * j.rest_local
			var s := JointProfile.clamp_local(j, q)
			var after := JointProfile.angles(j, s.local)
			worst = maxf(worst, JointMath.limit_state(after, j.limits).hard)
			if s.hard <= 1e-6 and not s.local.is_equal_approx(q):
				moved_inside += 1
	t.ok(worst < 1e-4, "clamped poses are within the hard limits (worst %.7f rad)" % worst)
	t.eq(moved_inside, 0, "poses already inside the limits are not changed")


func test_soft_load_grows_from_soft_to_hard(t) -> void:
	var j: Dictionary = profile.joint("LeftLowerLeg")
	var lim: Dictionary = j.limits
	t.near(JointMath.limit_state(Vector3(lim.flex.soft.y, 0, 0), lim).soft, 0.0, 1e-6, "no load at the soft limit")
	var mid: float = (lim.flex.soft.y + lim.flex.hard.y) * 0.5
	t.near(JointMath.limit_state(Vector3(mid, 0, 0), lim).soft, 0.5, 1e-6, "half load midway")
	t.near(JointMath.limit_state(Vector3(lim.flex.hard.y, 0, 0), lim).soft, 1.0, 1e-6, "full load at the hard limit")
	t.eq(JointMath.limit_state(Vector3(lim.flex.hard.y, 0, 0), lim).hard, 0.0, "the hard limit itself is allowed")


func test_knee_bends_backward_and_cannot_hyperextend(t) -> void:
	for side in ["Left", "Right"]:
		var g := _pose({side + "LowerLeg": Vector3(70, 0, 0)})
		t.ok(_origin(g, side + "Foot").z < _origin(g, side + "LowerLeg").z - 0.2, "%s knee flexion moves the ankle behind the knee" % side)
		var bad := _pose({side + "LowerLeg": Vector3(-40, 0, 0)}, true)
		var ang: Vector3 = JointProfile.angles(profile.joint(side + "LowerLeg"), Fk.pose(profile, {side + "LowerLeg": Vector3(-40, 0, 0)}, true)[side + "LowerLeg"]) * (180.0 / PI)
		t.near(ang.x, -6.0, 1e-3, "%s knee hyperextension stops at the hard limit" % side)
		t.ok(_origin(bad, side + "Foot").z > _origin(bad, side + "LowerLeg").z, "%s clamped knee does not bend backwards" % side)
		var side_bend := Fk.pose(profile, {side + "LowerLeg": Vector3(0, 30, 0)}, true)
		var a2: Vector3 = JointProfile.angles(profile.joint(side + "LowerLeg"), side_bend[side + "LowerLeg"]) * (180.0 / PI)
		t.near(a2.y, 5.0, 1e-3, "%s knee sideways bending stops at 5 degrees" % side)


func test_elbow_bends_forward_in_t_pose(t) -> void:
	for side in ["Left", "Right"]:
		var g := _pose({side + "LowerArm": Vector3(80, 0, 0)})
		t.ok(_origin(g, side + "Hand").z > _origin(g, side + "LowerArm").z + 0.2, "%s elbow flexion brings the hand forward" % side)
		var clamped := Fk.pose(profile, {side + "LowerArm": Vector3(-45, 0, 0)}, true)
		var ang: Vector3 = JointProfile.angles(profile.joint(side + "LowerArm"), clamped[side + "LowerArm"]) * (180.0 / PI)
		t.near(ang.x, -8.0, 1e-3, "%s elbow hyperextension stops at the hard limit" % side)


func test_hip_and_shoulder_directions(t) -> void:
	for side in ["Left", "Right"]:
		var out := 1.0 if side == "Left" else -1.0
		var g := _pose({side + "UpperLeg": Vector3(60, 0, 0)})
		t.ok(_origin(g, side + "LowerLeg").z > 0.3, "%s hip flexion moves the knee forward" % side)
		g = _pose({side + "UpperLeg": Vector3(0, 40, 0)})
		t.ok(_origin(g, side + "LowerLeg").x * out > def.bones[def.index[side + "UpperLeg"]].global.origin.x * out + 0.2, "%s hip abduction moves the knee outward" % side)
		# Hip internal rotation with the knee at 90 degrees swings the foot outward (clinical test position).
		g = _pose({side + "UpperLeg": Vector3(90, 0, 30), side + "LowerLeg": Vector3(90, 0, 0)})
		var g0 := _pose({side + "UpperLeg": Vector3(90, 0, 0), side + "LowerLeg": Vector3(90, 0, 0)})
		t.ok(_origin(g, side + "Foot").x * out > _origin(g0, side + "Foot").x * out + 0.1, "%s hip internal rotation swings the foot laterally" % side)
		# Shoulder angles are measured from the hanging arm.
		g = _pose({side + "UpperArm": Vector3.ZERO})
		t.ok(_origin(g, side + "LowerArm").y < _origin(g, side + "UpperArm").y - 0.25, "%s shoulder neutral = arm hanging" % side)
		g = _pose({side + "UpperArm": Vector3(90, 0, 0)})
		t.ok(_origin(g, side + "LowerArm").z > 0.2, "%s shoulder flexion raises the arm forward" % side)
		g = _pose({side + "UpperArm": Vector3(0, 90, 0)})
		t.ok(_origin(g, side + "LowerArm").x * out > _origin(g, side + "UpperArm").x * out + 0.25, "%s shoulder abduction raises the arm sideways" % side)
		g = _pose({side + "UpperArm": Vector3(175, 0, 0)})
		t.ok(_origin(g, side + "Hand").y > _origin(g, side + "UpperArm").y + 0.45, "%s arm reaches overhead (hanging)" % side)
		# Internal rotation with the elbow at 90 degrees moves the forearm across the body.
		g = _pose({side + "UpperArm": Vector3(0, 0, 45), side + "LowerArm": Vector3(90, 0, 0)})
		t.ok(_origin(g, side + "Hand").x * out < _origin(g, side + "LowerArm").x * out - 0.1, "%s shoulder internal rotation turns the forearm medially" % side)


func test_distal_joint_directions(t) -> void:
	for side in ["Left", "Right"]:
		var base := Fk.globals(def)
		var g := _pose({side + "Foot": Vector3(15, 0, 0)})
		t.ok(_tip(g, side + "Toes").y > _tip(base, side + "Toes").y + 0.02, "%s dorsiflexion lifts the toes" % side)
		g = _pose({side + "Toes": Vector3(40, 0, 0)})
		t.ok(_tip(g, side + "Toes").y > _tip(base, side + "Toes").y + 0.03, "%s toe extension lifts the toe tip" % side)
		g = _pose({side + "Hand": Vector3(45, 0, 0)})
		t.ok(_tip(g, side + "Hand").y < _tip(base, side + "Hand").y - 0.08, "%s wrist flexion bends the palm side (down in T-pose)" % side)
		g = _pose({side + "Hand": Vector3(0, 20, 0)})
		t.ok(_tip(g, side + "Hand").z > _tip(base, side + "Hand").z + 0.04, "%s radial deviation turns the hand toward the thumb (forward)" % side)
		g = _pose({side + "Shoulder": Vector3(25, 0, 0)})
		t.ok(_origin(g, side + "UpperArm").y > _origin(base, side + "UpperArm").y + 0.02, "%s girdle elevation lifts the shoulder" % side)
		g = _pose({side + "Shoulder": Vector3(0, 20, 0)})
		t.ok(_origin(g, side + "UpperArm").z > _origin(base, side + "UpperArm").z + 0.02, "%s protraction moves the shoulder forward" % side)
		g = _pose({side + "Foot": Vector3(0, 0, 25)})
		var out := 1.0 if side == "Left" else -1.0
		var sole_normal: Vector3 = (g[side + "Foot"] as Transform3D).basis * ((def.bones[def.index[side + "Foot"]].global as Transform3D).basis.inverse() * Vector3.DOWN)
		t.ok(sole_normal.x * out < -0.2, "%s inversion turns the sole medially" % side)


func test_spine_directions(t) -> void:
	var base := Fk.globals(def)
	var g := _pose({"Spine": Vector3(30, 0, 0)})
	t.ok(_origin(g, "Neck").z > _origin(base, "Neck").z + 0.1, "trunk flexion bends forward")
	g = _pose({"Spine": Vector3(0, 20, 0)})
	t.ok(_origin(g, "Neck").x > 0.05, "positive lateral flexion bends to the left")
	g = _pose({"UpperChest": Vector3(0, 0, 25)})
	t.ok(_origin(g, "LeftUpperArm").z < _origin(base, "LeftUpperArm").z - 0.03, "rotation to the left turns the left shoulder back")
	g = _pose({"Head": Vector3(15, 0, 0)})
	t.ok(_tip(g, "Head").z > _tip(base, "Head").z + 0.02, "head flexion (nod) moves the vertex forward")
	g = _pose({"Neck": Vector3(0, 0, 40)})
	var face: Vector3 = (g.Head as Transform3D).basis * ((def.bones[def.index.Head].global as Transform3D).basis.inverse() * Vector3.FORWARD * -1.0)
	t.ok(face.x > 0.5, "neck rotation to the left turns the face to the left")
