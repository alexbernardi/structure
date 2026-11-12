## TwoBoneIK rotates the leg chain; retain the authored ankle orientation after that positional correction.
extends SkeletonModifier3D

var orientations := {}


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	for bone in orientations:
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * orientations[bone]).get_rotation_quaternion())
