## First modifier of the chain when no AnimationPlayer drives the rig (rest, neutral and manual modes): writes the
## rest pose plus the requested joint rotations, so every later stage (IK, limits, helpers) sees the same input path
## as with authored animation. Inactive (`active = false`) during animation playback.
extends SkeletonModifier3D

var rotations := {}   ## bone index -> local rotation (absolute, like an animation track)


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		skeleton.set_bone_pose_position(i, rest.origin)
		skeleton.set_bone_pose_rotation(i, rotations.get(i, rest.basis.get_rotation_quaternion()))
		skeleton.set_bone_pose_scale(i, Vector3.ONE)
