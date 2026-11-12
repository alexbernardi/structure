## Skeleton integrity: hierarchy, rest orientations, symmetry, compatibility with the imported humanoid rig.
extends RefCounted

const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")
const RigBuilder = preload("res://systems/bone_ik/rig/rig_builder.gd")
const Humanoid = preload("res://systems/bone_ik/rig/humanoid.gd")
const ClipAdapter = preload("res://systems/bone_ik/animation/humanoid_clip_adapter.gd")


func _angle(a: Basis, b: Basis) -> float:
	# 2 atan2(|v|, |w|) of the relative rotation: well conditioned near zero (acos of a dot product is not).
	var q := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return rad_to_deg(2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))


func test_hierarchy_matches_the_humanoid_profile(t) -> void:
	var def := RigBuilder.build(Proportions.new())
	var parents := Humanoid.profile_parents()
	t.eq(def.bones.size(), Humanoid.BODY.size() + Humanoid.HELPERS.size(), "23 animation bones + 6 helpers")
	var names := {}
	for i in def.bones.size():
		var b: Dictionary = def.bones[i]
		t.ok(not names.has(b.name), "unique name %s" % b.name)
		names[b.name] = true
		t.ok(b.parent_index < i, "%s comes after its parent" % b.name)
		if not b.helper:
			t.eq(b.parent, parents[b.name], "%s parent as in SkeletonProfileHumanoid" % b.name)
		else:
			t.eq(def.bones[b.parent_index].helper, false, "helper %s hangs off an animation bone" % b.name)
	for b in def.bones:
		if b.helper:
			for other in def.bones:
				if other.parent == b.name:
					t.fail("helper %s has a child %s" % [b.name, other.name])


func test_rest_orientations_are_the_profile_reference(t) -> void:
	var def := RigBuilder.build(Proportions.new({"height": 1.63, "arm_span_ratio": 1.07, "leg_weight": 0.55}))
	var bases := Humanoid.profile_bases()
	var worst := 0.0
	for b in def.bones:
		if not b.helper:
			worst = maxf(worst, _angle(b.global.basis, bases[b.name]))
	t.ok(worst < 1e-4, "global rest bases equal the profile's for any proportions (worst %.7f deg)" % worst)


func test_bilateral_symmetry(t) -> void:
	var def := RigBuilder.build(Proportions.new())
	var mirror := Basis.from_scale(Vector3(-1, 1, 1))
	for b in def.bones:
		var m: String = Humanoid.mirror_name(b.name)
		var o: Dictionary = def.bones[def.index[m]]
		var p: Vector3 = b.global.origin
		t.near(o.global.origin, Vector3(-p.x, p.y, p.z), 1e-6, "%s mirrors %s" % [m, b.name])
		t.near(o.tip, Vector3(-b.tip.x, b.tip.y, b.tip.z), 1e-6, "%s tip mirrors" % m)
		# Mirrored orientation: M * B * M (M = reflection x -> -x) is again a rotation; it must be the other side's basis.
		var mb: Basis = mirror * b.global.basis * mirror
		t.ok(_angle(mb, o.global.basis) < 1e-4, "%s orientation mirrors %s" % [m, b.name])
	t.ok(Proportions.new().is_symmetric(), "default proportions are symmetric")


func test_joint_layout_is_anatomical(t) -> void:
	var def := RigBuilder.build(Proportions.new())
	var y := func(n): return def.bones[def.index[n]].global.origin.y
	var chain := ["LeftFoot", "LeftLowerLeg", "LeftUpperLeg", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]
	for i in chain.size() - 1:
		t.ok(y.call(chain[i]) < y.call(chain[i + 1]), "%s below %s" % [chain[i], chain[i + 1]])
	t.ok(y.call("Head") < def.landmarks.vertex.y, "head pivot below the vertex")
	var x := func(n): return def.bones[def.index[n]].global.origin.x
	var arm := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"]
	for i in arm.size() - 1:
		t.ok(x.call(arm[i]) < x.call(arm[i + 1]), "%s medial to %s" % [arm[i], arm[i + 1]])
	t.ok(def.landmarks.fingertip_l.x > x.call("LeftHand"), "fingertip beyond the wrist")
	t.ok(def.landmarks.toe_tip_l.z > def.bones[def.index.LeftToes].global.origin.z, "toe tip ahead of the ball")
	t.ok(def.landmarks.heel_l.z < 0.0, "heel behind the ankle")
	t.near(def.landmarks.heel_l.y, 0.0, 1e-6, "soles on the ground")
	for b in def.bones:
		t.ok(b.length > 0.005, "%s has a length (%.3f m)" % [b.name, b.length])
		t.ok(b.global.origin.is_finite(), "%s position finite" % b.name)


func test_tips_meet_child_joints(t) -> void:
	var def := RigBuilder.build(Proportions.new())
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "LeftShoulder", "LeftUpperArm", "LeftLowerArm",
			"LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]:
		var b: Dictionary = def.bones[def.index[n]]
		var child_found := false
		for c in def.bones:
			if c.parent == n and not c.helper and c.global.origin.is_equal_approx(b.tip):
				child_found = true
		t.ok(child_found, "%s tip is its child joint" % n)


func test_proportion_edits_keep_the_hierarchy(t) -> void:
	var a := RigBuilder.build(Proportions.new())
	var b := RigBuilder.build(Proportions.new({"height": 2.1, "shoulder_width_ratio": 0.22, "upper_arm_share": 0.55,
		"thigh_share": 0.45, "foot_length_ratio": 0.17, "torso_weight": 0.38}))
	t.eq(a.bones.size(), b.bones.size(), "same bone count")
	for i in a.bones.size():
		t.eq(b.bones[i].name, a.bones[i].name, "same order")
		t.eq(b.bones[i].parent, a.bones[i].parent, "same parent for %s" % a.bones[i].name)


func test_skeleton3d_receives_the_definition(t) -> void:
	var def := RigBuilder.build(Proportions.new())
	var sk := Skeleton3D.new()
	RigBuilder.apply_to(sk, def)
	t.eq(sk.get_bone_count(), def.bones.size(), "bone count")
	var worst := 0.0
	for b in def.bones:
		var i := sk.find_bone(b.name)
		worst = maxf(worst, sk.get_bone_global_rest(i).origin.distance_to(b.global.origin))
	t.ok(worst < 1e-6, "Skeleton3D global rests equal the definition (worst %.7f m)" % worst)
	sk.free()


func test_imported_humanoid_rests_share_our_orientations(t) -> void:
	var src := ClipAdapter.load_source(ClipAdapter.SOURCES[0])
	t.ok(src.ok, "source loads: %s" % src.error)
	if not src.ok:
		return
	var def := RigBuilder.build(Proportions.new())
	var worst := 0.0
	var worst_bone := ""
	for b in def.bones:
		if b.helper or not src.rest_globals.has(b.name):
			continue
		t.eq(src.parents[b.name], b.parent, "imported parent of %s" % b.name)
		var a := _angle(b.global.basis, (src.rest_globals[b.name] as Transform3D).basis)
		if a > worst:
			worst = a
			worst_bone = b.name
	t.ok(worst < 0.01, "imported normalised rests have our orientations (worst %.4f deg at %s)" % [worst, worst_bone])
