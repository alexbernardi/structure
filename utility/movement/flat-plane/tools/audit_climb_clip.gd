## Measures the authored UAL2 ClimbUp_1m (in-place export) on the primitive mannequin: hands, feet and hips relative to
## the clip root, plus the authored linear root motion (1.0 m up, 1.676 m forward over the clip, source units, from the
## root-motion export). Prints the numbers traversal/mantle_clip.gd records.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_climb_clip.gd
extends SceneTree

const Visual = preload("res://character/authored_mannequin.gd")
const ClipPose = preload("res://traversal/clip_pose.gd")
const RISE := 1.0
const FORWARD := 1.676
const RATE := 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var visual = Visual.new()
	root.add_child(visual)
	await process_frame
	for clip_name in ["ClimbUp_1m", "DoubleJump"]:
		var clip: Animation = visual.player.get_animation(clip_name)
		var map := ClipPose.tracks(clip)
		var index: Dictionary = visual.bone_index
		var scale: float = visual.proportion_scale
		print("%s length %.4f s, proportion %.4f, root rise %.4f m, forward %.4f m (mannequin scale)" % [clip_name, clip.length, scale, RISE * scale, FORWARD * scale])
		print("t      hipsY  hipsZ   LhandY LhandZ  RhandY RhandZ  LfootY LfootZ  RfootY RfootZ   (root at t added for climb)")
		var count := int(round(clip.length * RATE))
		for i in count + 1:
			var t := minf(i / RATE, clip.length)
			var pose := ClipPose.sample(clip, visual.skeleton, t, map)
			var lift := 0.0
			var ahead := 0.0
			if clip_name == "ClimbUp_1m":
				lift = RISE * scale * t / clip.length
				ahead = FORWARD * scale * t / clip.length
			var line := "%.3f " % t
			for bone in ["Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				var p: Vector3 = pose[index[bone]].origin
				line += " %+.3f %+.3f " % [p.y + lift, p.z + ahead]
			print(line)
	visual.free()
	quit(0)
