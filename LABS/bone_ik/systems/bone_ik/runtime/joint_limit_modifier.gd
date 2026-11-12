## Enforces the anatomical hard limits on the pose arriving at this point of the modifier chain (after animation and
## IK) and records, per joint, the angles, how far the incoming pose was beyond the hard limit and how deep it was in
## the soft (resistance) zone. With `enforce = false` it only measures.
extends SkeletonModifier3D

const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")

var profile               ## JointProfile, bound to the current rig
var enforce := true
var states := {}          ## bone -> {angles, clamped, hard (rad), soft (0..1), axis}
var violating := 0        ## joints beyond their hard limit on the last update (before clamping)
var worst_deg := 0.0      ## largest hard-limit excess on the last update, degrees
var worst_bone := ""


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or profile == null:
		return
	violating = 0
	worst_deg = 0.0
	worst_bone = ""
	for j in profile.joints:
		var state := JointProfile.clamp_local(j, skeleton.get_bone_pose_rotation(j.bone_index))
		states[j.bone] = state
		if state.hard > 1e-4:
			violating += 1
			var deg := rad_to_deg(state.hard)
			if deg > worst_deg:
				worst_deg = deg
				worst_bone = j.bone
		if enforce and state.hard > 1e-6:
			skeleton.set_bone_pose_rotation(j.bone_index, state.local)
