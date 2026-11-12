## Lossless hinge alignment for elbows and knees (see JointProfile.align_hinge): moves rotation about the upper
## arm / thigh axis out of the hinge into the parent's axial roll. Runs before the limit modifier so authored poses
## are judged anatomically (a hinge cannot bend sideways) without moving any joint.
extends SkeletonModifier3D

const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")
const HINGES := ["LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg"]

var profile
var transferred := {}   ## hinge bone -> radians moved to the parent on the last update


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or profile == null:
		return
	for bone in HINGES:
		var c: Dictionary = profile.joint(bone)
		var p: Dictionary = profile.joint(c.parent) if not c.is_empty() else {}
		if p.is_empty():
			continue
		var r := JointProfile.align_hinge(p, c, skeleton.get_bone_pose_rotation(p.bone_index),
			skeleton.get_bone_pose_rotation(c.bone_index))
		transferred[bone] = r.alpha
		if r.alpha != 0.0:
			skeleton.set_bone_pose_rotation(p.bone_index, r.parent)
			skeleton.set_bone_pose_rotation(c.bone_index, r.child)
