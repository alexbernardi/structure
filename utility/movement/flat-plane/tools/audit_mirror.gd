## Checks that the mannequin's rest skeleton is mirror-symmetric across its sagittal (YZ) plane, which makes a
## bone-local mirror of an authored clip exact (traversal/clip_mirror.gd).
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_mirror.gd
extends SceneTree

const Visual = preload("res://systems/movement_core/character/authored_mannequin.gd")
const Mirror = preload("res://systems/movement_core/traversal/clip_mirror.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var visual = Visual.new()
	root.add_child(visual)
	await process_frame
	var skeleton: Skeleton3D = visual.skeleton
	var worst := 0.0
	for bone in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(bone)
		var other := skeleton.find_bone(Mirror.mirror_name(name))
		var a := skeleton.get_bone_rest(bone)
		var b := Mirror.mirror_transform(skeleton.get_bone_rest(other))
		var error := a.origin.distance_to(b.origin) + a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
		worst = maxf(worst, error)
		if error > 1e-3:
			print("asymmetric rest: %s vs %s (%.5f)" % [name, Mirror.mirror_name(name), error])
	print("MIRROR worst rest asymmetry %.6f" % worst)
	visual.free()
	quit(0)
