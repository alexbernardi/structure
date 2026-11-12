## Drives the leaf twist helper bones (deformation helpers for a future skinned body) from the anatomical twist of
## their source joint: helper rotation = share x source twist, about the helper's parent long axis.
## Runs after the limit modifier, so helpers never exceed what the limited pose implies.
extends SkeletonModifier3D

const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")

var helpers: Array = []   ## {index, source: joint, axis: Vector3 (parent-local), share, sign}


func setup(definition: Dictionary, profile) -> void:
	helpers.clear()
	for bone in definition.bones:
		if not bone.helper:
			continue
		var source: Dictionary = profile.joint(bone.twist_source)
		var parent: Dictionary = definition.bones[bone.parent_index]
		if source.is_empty():
			continue
		var d_local: Vector3 = parent.global.basis.inverse() * (parent.tip - parent.global.origin).normalized()
		# Positive anatomical twist turns about t; in the bone's own frame that is +-d_local.
		var sign := signf((source.t as Vector3).dot((source.neutral as Quaternion) * (source.d_rest as Vector3)))
		helpers.append({"index": definition.index[bone.name], "source": source, "axis": d_local.normalized(),
			"share": bone.twist_share, "sign": sign})


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for h in helpers:
		var twist: float = JointProfile.angles(h.source, skeleton.get_bone_pose_rotation(h.source.bone_index)).z
		skeleton.set_bone_pose_rotation(h.index, Quaternion(h.axis, h.sign * h.share * twist))
