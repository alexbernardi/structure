## Cost of the procedural body model (Movement Lab 2.0 phase 2). Compare with bench_baseline.gd: these are what it ADDS.
extends RefCounted

const BodyParams = preload("res://animation/body_params.gd")
const BodyDynamics = preload("res://animation/body_dynamics.gd")
const SCENE := "res://scenes/flat_plane.tscn"

var _s


func _boot() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_s = load(SCENE).instantiate()
	_s.options = {"no-capture": "true", "no-hardware": "true", "no-tuning": "true", "no-window-state": "true"}
	tree.root.add_child(_s)
	await tree.process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	await tree.physics_frame
	await tree.physics_frame


func _free() -> void:
	_s.queue_free()
	await Engine.get_main_loop().process_frame


func _kinematics(i: int) -> Dictionary:
	var a := sin(float(i) * 0.05)
	return {"velocity": Vector3(-3.0 * a, 0.0, -4.0 - 2.0 * a), "accel": Vector3(2.0 * a, 0.0, -6.0 * a), "heading": 0.3 * a,
		"grounded": i % 90 > 10, "gait_phase": fmod(float(i) * 0.2, TAU), "gait_amount": 0.7, "landed_impact": 6.0 if i % 90 == 11 else 0.0}


func bench_body_dynamics_update(b) -> void:
	var dyn := BodyDynamics.new(BodyParams.create())
	var n := 100000
	var t0 := Time.get_ticks_usec()
	for i in n:
		dyn.update(1.0 / 144.0, _kinematics(i))
	b.record("BodyDynamics.update (all effects, includes building the input)", n, Time.get_ticks_usec() - t0)


func bench_kinematics_input_only(b) -> void:
	var n := 100000
	var t0 := Time.get_ticks_usec()
	for i in n:
		_kinematics(i)
	b.record("building the input dictionary alone (subtract from the line above)", n, Time.get_ticks_usec() - t0)


func bench_body_dynamics_master_off(b) -> void:
	var p = BodyParams.create()
	p.set_value("body_dynamics", 0.0)
	var dyn := BodyDynamics.new(p)
	var n := 100000
	var t0 := Time.get_ticks_usec()
	for i in n:
		dyn.update(1.0 / 144.0, {"heading": 0.0})
	b.record("BodyDynamics.update with the master switch off", n, Time.get_ticks_usec() - t0)


func bench_visual_pose_with_dynamics(b) -> void:
	await _boot()
	var dyn := BodyDynamics.new(BodyParams.create())
	var state := {"speed": 5.0, "vy": 0.0, "grounded": true, "crouching": false, "accel_forward": 0.0, "heading": 0.3}
	var n := 20000
	var t0 := Time.get_ticks_usec()
	for i in n:
		state.dyn = dyn.update(1.0 / 144.0, _kinematics(i))
		_s.visual.update_pose(state, 1.0 / 144.0)
	b.record("dynamics.update + visual.update_pose (dyn path)", n, Time.get_ticks_usec() - t0)
	state.erase("dyn")
	t0 = Time.get_ticks_usec()
	for i in n:
		_s.visual.update_pose(state, 1.0 / 144.0)
	b.record("visual.update_pose (original path)", n, Time.get_ticks_usec() - t0)
	await _free()


func bench_scene_process_frame_with_dynamics(b) -> void:
	await _boot()
	var n := 5000
	var t0 := Time.get_ticks_usec()
	for i in n:
		_s._process(1.0 / 144.0)
	b.record("scene._process with the body model on", n, Time.get_ticks_usec() - t0)
	_s.body_params.set_value("body_dynamics", 0.0)
	t0 = Time.get_ticks_usec()
	for i in n:
		_s._process(1.0 / 144.0)
	b.record("scene._process with the body model off", n, Time.get_ticks_usec() - t0)
	await _free()
