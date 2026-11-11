## Measures the authored UAL2 JogToFlip (in-place export) on the mannequin: hips and feet heights above the clip root,
## the lowest drawn point (toes, feet, head, hands), and the hips' pitch, to find takeoff, the airborne turn and the landing.
## The in-place export keeps the hips' own rise (the pelvis track is identical in the root-motion export), so the
## root-motion export's extra 1.2 m root arc is not used: the body's physics jump supplies the remaining height.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_flip_clip.gd
extends SceneTree

const Visual = preload("res://character/authored_mannequin.gd")
const ClipPose = preload("res://traversal/clip_pose.gd")
const CLIP := "JogToFlip"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var visual = Visual.new()
	root.add_child(visual)
	await process_frame
	if not visual.player.has_animation(CLIP):
		push_error("JogToFlip missing")
		quit(1)
		return
	var clip: Animation = visual.player.get_animation(CLIP)
	var map := ClipPose.tracks(clip)
	var index: Dictionary = visual.bone_index
	print("%s length %.4f s" % [CLIP, clip.length])
	print("t      hipsY  hipsZ  pitch   LfootY RfootY  LtoeY  RtoeY  headY  lowest")
	var prev_pitch := 0.0
	var turned := 0.0
	var lows: Array = []
	for i in int(round(clip.length * 30.0)) + 1:
		var t := minf(i / 30.0, clip.length)
		var pose := ClipPose.sample(clip, visual.skeleton, t, map)
		var hips: Transform3D = pose[index["Hips"]]
		var up := hips.basis.y
		var pitch := rad_to_deg(atan2(up.z, up.y))
		if i > 0:
			turned += wrapf(pitch - prev_pitch, -180.0, 180.0)
		prev_pitch = pitch
		var lowest := INF
		for bone in ["LeftToes", "RightToes", "LeftFoot", "RightFoot", "Head", "LeftHand", "RightHand"]:
			lowest = minf(lowest, pose[index[bone]].origin.y)
		lows.append(snappedf(lowest, 0.001))
		print("%.3f  %+.3f %+.3f %+7.1f  %+.3f %+.3f  %+.3f %+.3f  %+.3f  %+.3f  turned %+.0f" % [t, hips.origin.y,
			hips.origin.z, pitch, pose[index["LeftFoot"]].origin.y, pose[index["RightFoot"]].origin.y,
			pose[index["LeftToes"]].origin.y, pose[index["RightToes"]].origin.y, pose[index["Head"]].origin.y, lowest, turned])
	print("LOWEST ", lows)   # lowest of toes, feet, head and hands above the clip root, per 30 fps frame (FlipClip.LOWEST)
	visual.free()
	quit(0)
