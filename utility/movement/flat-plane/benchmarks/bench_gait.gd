## Cost of the procedural gait (treadmill lab). Compare with bench_baseline.gd and bench_body.gd.
extends RefCounted

const GaitParams = preload("res://animation/gait_params.gd")
const GaitModel = preload("res://animation/gait_model.gd")
const RigParams = preload("res://animation/rig_params.gd")


func bench_gait_cycle_constants_cache_miss(b) -> void:
	# a different speed on every call: what a frame costs while the belt speed or a setting is changing
	var m := GaitModel.new(GaitParams.create(), RigParams.create())
	var n := 300
	var t0 := Time.get_ticks_usec()
	for i in n:
		m.cycle_for(0.5 + float(i) * 0.003)
	b.record("GaitModel.cycle_for (cache miss: foot planner constants + hip lowering sweep)", n, Time.get_ticks_usec() - t0)


func bench_gait_update_steady_speed(b) -> void:
	var m := GaitModel.new(GaitParams.create(), RigParams.create())
	var n := 5000
	var t0 := Time.get_ticks_usec()
	for i in n:
		m.update(1.0 / 120.0, 1.2)
	b.record("GaitModel.update at a steady speed (cache hit + pose)", n, Time.get_ticks_usec() - t0)


func bench_gait_pose_at(b) -> void:
	var m := GaitModel.new(GaitParams.create(), RigParams.create())
	m.cycle = m.cycle_for(1.2)
	var n := 2000
	var t0 := Time.get_ticks_usec()
	for i in n:
		m.pose_at(float(i % 100) / 100.0)
	b.record("GaitModel.pose_at (two ankles, hips, two legs by IK, arms)", n, Time.get_ticks_usec() - t0)


func bench_visual_apply_rig(b) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var v = load("res://character/character_visual.gd").new()
	tree.root.add_child(v)
	await tree.process_frame
	var rig = RigParams.create()
	var n := 500
	var t0 := Time.get_ticks_usec()
	for i in n:
		rig.set_value("thigh_length", 0.40 + 0.005 * float(i % 20))
		v.apply_rig(rig)
	b.record("Visual.apply_rig (re-proportion 15 bones and rebuild 15 meshes)", n, Time.get_ticks_usec() - t0)
	v.queue_free()
	await tree.process_frame
