## Left-right mirror of an authored humanoid clip across the character's sagittal (YZ) plane. The mannequin's rest
## skeleton is mirror-symmetric (tools/audit_mirror.gd, re-checked by tests), so mirroring every bone-local key and
## swapping Left/Right tracks gives the exact mirror image of the authored motion: no keyframe is invented or edited
## beyond the reflection. Used for the left-hand SafetyVault (Movement Lab 5.1).
extends RefCounted


static func mirror_name(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.substr(4)
	if bone.begins_with("Right"):
		return "Left" + bone.substr(5)
	return bone


## M * t * M with M = diag(-1, 1, 1).
static func mirror_transform(t: Transform3D) -> Transform3D:
	var m := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return Transform3D(m * t.basis * m, Vector3(-t.origin.x, t.origin.y, t.origin.z))


static func mirror_rotation(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


## A new animation: each bone track moved to the mirrored bone, positions reflected in x, rotations reflected.
static func mirror_animation(source: Animation) -> Animation:
	var clip := Animation.new()
	clip.length = source.length
	clip.loop_mode = source.loop_mode
	for track in source.get_track_count():
		var path := source.track_get_path(track)
		var kind := source.track_get_type(track)
		var bone := String(path.get_subname(0)) if path.get_subname_count() == 1 else ""
		var target := clip.add_track(kind)
		clip.track_set_path(target, NodePath(String(path.get_concatenated_names()) + ":" + mirror_name(bone)) if bone != "" else path)
		clip.track_set_interpolation_type(target, source.track_get_interpolation_type(track))
		for key in source.track_get_key_count(track):
			var time := source.track_get_key_time(track, key)
			var value = source.track_get_key_value(track, key)
			match kind:
				Animation.TYPE_POSITION_3D:
					value = Vector3(-value.x, value.y, value.z)
				Animation.TYPE_ROTATION_3D:
					value = mirror_rotation(value)
			clip.track_insert_key(target, time, value, source.track_get_key_transition(track, key))
	return clip
