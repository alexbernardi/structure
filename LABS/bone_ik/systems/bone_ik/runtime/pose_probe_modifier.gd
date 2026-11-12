## A SkeletonModifier3D that changes nothing: it snapshots the local bone poses at its place in the modifier chain,
## so diagnostics can show the pose after each stage (animation -> IK -> limits -> final) separately.
extends SkeletonModifier3D

var stage := ""
var rotations: Array[Quaternion] = []
var positions: Array[Vector3] = []
var frames := 0


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var n := skeleton.get_bone_count()
	rotations.resize(n)
	positions.resize(n)
	for i in n:
		rotations[i] = skeleton.get_bone_pose_rotation(i)
		positions[i] = skeleton.get_bone_pose_position(i)
	frames += 1


func has_snapshot() -> bool:
	return frames > 0


## Model-space bone transforms of the snapshot (forward kinematics over the skeleton's hierarchy).
func globals(skeleton: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := mini(skeleton.get_bone_count(), rotations.size())
	out.resize(n)
	for i in n:
		var local := Transform3D(Basis(rotations[i]), positions[i])
		var parent := skeleton.get_bone_parent(i)
		out[i] = local if parent < 0 else out[parent] * local
	return out
