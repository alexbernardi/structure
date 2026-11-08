## Measures the authored SafetyVault on the original rig at primitive-mannequin scale: root travel and hand/foot paths.
## Contacts are where an end effector is (nearly) still in world space, so the root-motion export is used here only.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_vault_clip.gd
extends SceneTree

const RootMotion = preload("res://assets/quaternius/UAL2_Traversal_RM.glb")
const BONES := ["Root", "Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftToes", "RightToes"]
const RATE := 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source: Node = RootMotion.instantiate()
	var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	var scale := 1.01 / skeleton.get_bone_global_rest(skeleton.find_bone("Hips")).origin.y
	var animation := player.get_animation("SafetyVault")
	root.add_child(source)
	await process_frame
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("SafetyVault")
	print("SafetyVault length %.4f s, proportion scale %.4f, motion scale %.4f" % [animation.length, scale, skeleton.motion_scale])
	var header := "t      "
	for bone in BONES:
		header += "%-26s" % bone
	print(header)
	var previous := {}
	var count := int(round(animation.length * RATE))
	for i in count + 1:
		var time := minf(i / RATE, animation.length)
		player.seek(time, true)
		var line := "%.3f  " % time
		for bone in BONES:
			var p := skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin * scale
			var speed: float = 0.0 if not previous.has(bone) else (p - previous[bone]).length() * RATE
			previous[bone] = p
			line += "%+.2f %+.2f %+.2f %4.1f   " % [p.x, p.y, p.z, speed]
		print(line)
	source.free()
	quit(0)
