## Test helper: plays a clip on the original imported skeleton and on the Vitruvian rig side by side and measures
## retargeting fidelity, foot contact and anatomical limit violations. Used by test_animation_retarget.gd and by
## the lab's report tool (tools/retarget_report.gd).
extends RefCounted

const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")
const Humanoid = preload("res://systems/bone_ik/rig/humanoid.gd")


static func _fk(sk: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var local := Transform3D(Basis(sk.get_bone_pose_rotation(i)), sk.get_bone_pose_position(i))
		var p := sk.get_bone_parent(i)
		out[i] = local if p < 0 else out[p] * local
	return out


static func _angle(a: Basis, b: Basis) -> float:
	var q := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return rad_to_deg(2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))


const HINGES := [["LeftUpperArm", "LeftLowerArm"], ["RightUpperArm", "RightLowerArm"],
	["LeftUpperLeg", "LeftLowerLeg"], ["RightUpperLeg", "RightLowerLeg"]]


static func _fk_with(sk: Skeleton3D, rotations: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var local := Transform3D(Basis(rotations.get(i, sk.get_bone_pose_rotation(i))), sk.get_bone_pose_position(i))
		var p := sk.get_bone_parent(i)
		out[i] = local if p < 0 else out[p] * local
	return out


## rig: a built vitruvian_rig in the tree. source_scene: the instantiated source GLB (in the tree or not).
## Violations are reported for the raw clip and after the lossless hinge alignment the rig applies before its limits.
static func measure(rig, source_scene: Node, clip: String, samples := 40) -> Dictionary:
	var src_sk: Skeleton3D = source_scene.find_children("*", "Skeleton3D", true, false)[0]
	var src_ap: AnimationPlayer = source_scene.find_children("*", "AnimationPlayer", true, false)[0]
	var def: Dictionary = rig.definition
	var sk: Skeleton3D = rig.skeleton
	var profile = rig.profile
	var scale: float = rig.animation_reports[clip].leg_scale
	rig.play(clip)
	src_ap.play(clip)
	var length: float = src_ap.get_animation(clip).length
	var out := {"clip": clip, "frames": 0, "rotation_error_deg": 0.0, "length_error_m": 0.0, "stance_toe_error_m": 0.0,
		"min_sole_m": INF, "src_min_sole_m": INF, "raw_violations": {}, "violations": {}, "worst_violation_deg": 0.0,
		"worst_bone": "", "frames_violating": 0, "max_soft_load": 0.0, "max_hinge_transfer_deg": 0.0,
		"hinge_position_change_m": 0.0}
	var pairs := []
	for b in def.bones:
		if b.helper or b.name == "Root":
			continue
		var si := src_sk.find_bone(b.name)
		if si >= 0:
			pairs.append([def.index[b.name], si])
	# Sole points (heel under the foot bone, toe tip under the toes bone) on this rig, and the equivalent points on the
	# source skeleton: same offset in the bone frame (identical orientations), scaled by the ankle-to-ball length.
	var soles := []
	for s in ["Left", "Right"]:
		var k := "l" if s == "Left" else "r"
		var foot: Dictionary = def.bones[def.index[s + "Foot"]]
		var toe: Dictionary = def.bones[def.index[s + "Toes"]]
		var src_foot := src_sk.get_bone_global_rest(src_sk.find_bone(s + "Foot"))
		var src_toe := src_sk.get_bone_global_rest(src_sk.find_bone(s + "Toes"))
		var ratio: float = src_foot.origin.distance_to(src_toe.origin) / (foot.global.origin as Vector3).distance_to(toe.global.origin)
		var heel_local: Vector3 = (foot.global as Transform3D).affine_inverse() * (def.landmarks["heel_" + k] as Vector3)
		var tip_local: Vector3 = (toe.global as Transform3D).affine_inverse() * (def.landmarks["toe_tip_" + k] as Vector3)
		soles.append([def.index[s + "Foot"], heel_local, src_sk.find_bone(s + "Foot"), heel_local * ratio])
		soles.append([def.index[s + "Toes"], tip_local, src_sk.find_bone(s + "Toes"), tip_local * ratio])
	var toes := []
	for s in ["Left", "Right"]:
		var oi: int = def.index[s + "Toes"]
		var si := src_sk.find_bone(s + "Toes")
		toes.append([oi, si, def.bones[oi].global.origin.y, src_sk.get_bone_global_rest(si).origin.y])
	for f in samples:
		var t := length * float(f) / float(maxi(1, samples - 1))
		rig.player.seek(t, true)
		src_ap.seek(t, true)
		var ours := _fk(sk)
		var theirs := _fk(src_sk)
		out.frames += 1
		for p in pairs:
			out.rotation_error_deg = maxf(out.rotation_error_deg, _angle(ours[p[0]].basis, theirs[p[1]].basis))
		for b in def.bones:
			if b.name in ["Root", "Hips"] or b.helper:
				continue
			out.length_error_m = maxf(out.length_error_m, sk.get_bone_pose_position(def.index[b.name]).distance_to(b.local.origin))
		for tt in toes:
			var src_rise: float = (theirs[tt[1]].origin.y - tt[3]) * scale
			if src_rise < 0.01:   # the source foot is planted: ours must be planted too
				out.stance_toe_error_m = maxf(out.stance_toe_error_m, absf(ours[tt[0]].origin.y - tt[2] - src_rise))
		for sp in soles:
			out.min_sole_m = minf(out.min_sole_m, (ours[sp[0]] * (sp[1] as Vector3)).y)
			out.src_min_sole_m = minf(out.src_min_sole_m, (theirs[sp[2]] * (sp[3] as Vector3)).y * scale)
		# Hinge alignment exactly as the rig's HingeAlignModifier does it, then the limit check.
		var rotations := {}
		for h in HINGES:
			var p: Dictionary = profile.joint(h[0])
			var c: Dictionary = profile.joint(h[1])
			var r := JointProfile.align_hinge(p, c, sk.get_bone_pose_rotation(p.bone_index), sk.get_bone_pose_rotation(c.bone_index))
			rotations[p.bone_index] = r.parent
			rotations[c.bone_index] = r.child
			out.max_hinge_transfer_deg = maxf(out.max_hinge_transfer_deg, absf(rad_to_deg(r.alpha)))
		var aligned := _fk_with(sk, rotations)
		for i in aligned.size():
			out.hinge_position_change_m = maxf(out.hinge_position_change_m, aligned[i].origin.distance_to(ours[i].origin))
		var frame_bad := false
		for j in profile.joints:
			var raw := JointProfile.clamp_local(j, sk.get_bone_pose_rotation(j.bone_index))
			if raw.hard > deg_to_rad(0.5):
				out.raw_violations[j.bone] = snappedf(maxf(out.raw_violations.get(j.bone, 0.0), rad_to_deg(raw.hard)), 0.1)
			var st := JointProfile.clamp_local(j, rotations.get(j.bone_index, sk.get_bone_pose_rotation(j.bone_index)))
			out.max_soft_load = maxf(out.max_soft_load, st.soft)
			if st.hard > deg_to_rad(0.5):
				frame_bad = true
				var deg := rad_to_deg(st.hard)
				out.violations[j.bone] = snappedf(maxf(out.violations.get(j.bone, 0.0), deg), 0.1)
				if deg > out.worst_violation_deg:
					out.worst_violation_deg = deg
					out.worst_bone = j.bone
		if frame_bad:
			out.frames_violating += 1
	return out
