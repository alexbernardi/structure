## Measures the authored UAL2 ClimbUp_2m (in-place export) on the mannequin with its root motion (from UAL2_RM.glb,
## recorded in traversal/pullup_clip.gd): both hands, both feet and the hips relative to the takeoff ground, to find
## the two-handed grip on the 2 m edge and the pull-up's contacts.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_pullup_clip.gd
extends SceneTree

const Visual = preload("res://character/authored_mannequin.gd")
const ClipPose = preload("res://traversal/clip_pose.gd")
const Pullup = preload("res://traversal/pullup_clip.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var visual = Visual.new()
	root.add_child(visual)
	await process_frame
	var clip: Animation = visual.player.get_animation(Pullup.CLIP)
	var map := ClipPose.tracks(clip)
	var index: Dictionary = visual.bone_index
	print("%s length %.4f s, edge %.3f m, forward %.3f m (mannequin scale)" % [Pullup.CLIP, clip.length, Pullup.EDGE, Pullup.forward(clip.length)])
	print("t      hipsY  hipsZ   LhandY LhandZ  RhandY RhandZ  LfootY LfootZ  RfootY RfootZ  chestY")
	for i in 40:
		var t := minf(i / 30.0, clip.length)
		var pose := ClipPose.sample(clip, visual.skeleton, t, map)
		var line := "%.3f " % t
		for bone in ["Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "UpperChest"]:
			var p: Vector3 = pose[index[bone]].origin
			line += " %+.3f %+.3f " % [p.y + Pullup.rise(t), p.z + Pullup.forward(t)]
		print(line)
	visual.free()
	quit(0)
