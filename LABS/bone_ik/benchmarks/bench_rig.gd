## Performance diagnostics of the Vitruvian rig (phase 1 baseline). Run:
##   godot --headless --path LABS/bone_ik --script <abs>/TESTING/harness/run_gd_tests.gd -- --mode=bench --dir=res://benchmarks
## Measures the CPU cost of each piece of the per-frame chain in GDScript, so phase 2-5 additions can be compared and
## a cheaper rig can be chosen for distant characters (see BONE-IK-LAB.md, "Level of detail").
extends RefCounted

const Rig = preload("res://systems/bone_ik/vitruvian_rig.gd")
const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")
const RigBuilder = preload("res://systems/bone_ik/rig/rig_builder.gd")
const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")

var _tree: SceneTree
var rig


func before_each() -> void:
	_tree = Engine.get_main_loop()
	rig = Rig.new()
	_tree.root.add_child(rig)
	await _tree.process_frame
	rig.play("Jog_Fwd")


func after_each() -> void:
	rig.queue_free()
	await _tree.process_frame


func bench_limit_check_all_joints(b) -> void:
	var sk: Skeleton3D = rig.skeleton
	var n := 400
	var t0 := Time.get_ticks_usec()
	for i in n:
		for j in rig.profile.joints:
			JointProfile.clamp_local(j, sk.get_bone_pose_rotation(j.bone_index))
	b.record("joint limits, 21 joints (one rig update)", n, Time.get_ticks_usec() - t0)


func bench_axial_alignment(b) -> void:
	var sk: Skeleton3D = rig.skeleton
	var n := 200
	var t0 := Time.get_ticks_usec()
	for i in n:
		rig.profile.align_axial({}, sk.get_bone_pose_rotation)
	b.record("axial alignment, 4 hinges + 2 forearms (one rig update)", n, Time.get_ticks_usec() - t0)


func bench_full_frame(b) -> void:
	# Animation sample + every modifier, through the engine's own update (manual callback mode, synchronous).
	var sk: Skeleton3D = rig.skeleton
	var n := 200
	var length: float = rig.player.get_animation("Jog_Fwd").length
	var t0 := Time.get_ticks_usec()
	for i in n:
		rig.player.seek(fmod(i * 0.0167, length), true)
		for m in sk.get_children():
			m._process_modification_with_delta(1.0 / 60.0)
	b.record("animation sample + full modifier chain (one frame)", n, Time.get_ticks_usec() - t0)


func bench_rebuild_from_proportions(b) -> void:
	var n := 50
	var p := Proportions.new()
	var t0 := Time.get_ticks_usec()
	for i in n:
		p.set_value("height", 1.6 + 0.004 * i)
		RigBuilder.build(p)
	b.record("rig definition from proportions (data only)", n, Time.get_ticks_usec() - t0)
