## Forward kinematics of an authored clip on a skeleton's rest hierarchy, without playing it. Used to measure the clip
## once (clearance silhouette, hand path, phase matching) without disturbing the live AnimationTree.
extends RefCounted


## Bone name -> {track type: track index} for one animation.
static func tracks(animation: Animation) -> Dictionary:
	var result := {}
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() != 1:
			continue
		var bone := String(path.get_subname(0))
		var entry: Dictionary = result.get(bone, {})
		entry[animation.track_get_type(track)] = track
		result[bone] = entry
	return result


## Skeleton-space transforms of every bone of `skeleton` posed by `animation` at `time`. Parents precede children in
## the mannequin's bone order, so one pass suffices. Position keys are scaled by the skeleton's motion scale, as the
## mixer does for humanoid-normalized clips.
static func sample(animation: Animation, skeleton: Skeleton3D, time: float, track_map := {}) -> Array[Transform3D]:
	if track_map.is_empty():
		track_map = tracks(animation)
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		var position := rest.origin
		var rotation := rest.basis.get_rotation_quaternion()
		var entry: Dictionary = track_map.get(skeleton.get_bone_name(bone), {})
		if entry.has(Animation.TYPE_POSITION_3D):
			position = animation.position_track_interpolate(entry[Animation.TYPE_POSITION_3D], time) * skeleton.motion_scale
		if entry.has(Animation.TYPE_ROTATION_3D):
			rotation = animation.rotation_track_interpolate(entry[Animation.TYPE_ROTATION_3D], time)
		var local := Transform3D(Basis(rotation), position)
		var parent := skeleton.get_bone_parent(bone)
		result.append(result[parent] * local if parent >= 0 else local)
	return result
