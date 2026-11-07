## Phase 0 performance baseline of the original controller and presentation, measured headless.
##   godot --headless --path utility/movement/flat-plane --script ../../../TESTING/harness/run_gd_tests.gd -- \
##         --mode=bench --dir=res://benchmarks --report=<abs.json>
## Numbers are per call, on whatever machine runs them: record them next to the hardware, never compare across machines.
## Later phases add their own benchmarks and must report the cost they ADD to these.
extends RefCounted

const Core = preload("res://movement/movement_core.gd")
const SCENE := "res://scenes/flat_plane.tscn"
const DT := 1.0 / 120.0

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


func _frame(move := Vector2(0, 1), extra := {}) -> Dictionary:
	var d := {"move": move, "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}
	d.merge(extra, true)
	return d


func bench_core_step_ground(b) -> void:
	var core: Core = Core.new()
	core.grounded = true
	var inp := _frame()
	var ground := {"grounded": true, "normal": Vector3.UP, "can_stand": true}
	var n := 200000
	var t0 := Time.get_ticks_usec()
	for i in n:
		core.step(inp, ground, DT)
	b.record("core.step (ground, running)", n, Time.get_ticks_usec() - t0)


func bench_core_step_air(b) -> void:
	var core: Core = Core.new()
	core.velocity = Vector3(0, 0, -5)
	var inp := _frame()
	var ground := {"grounded": false, "normal": Vector3.UP, "can_stand": true}
	var n := 200000
	var t0 := Time.get_ticks_usec()
	for i in n:
		core.step(inp, ground, DT)
		core.velocity.y = 0.0
	b.record("core.step (air, strafing)", n, Time.get_ticks_usec() - t0)


func bench_body_simulate_open_ground(b) -> void:
	await _boot()
	_s.body.teleport(Vector3(200, 0.05, 200))
	await Engine.get_main_loop().physics_frame
	var inp := _frame(Vector2(1, 0))
	var n := 20000
	var t0 := Time.get_ticks_usec()
	for i in n:
		_s.body.simulate(inp, DT)
		if i % 500 == 499:
			_s.body.teleport(Vector3(200, 0.05, 200))   # keep running on the 400 m plane
	b.record("body.simulate (open ground, running)", n, Time.get_ticks_usec() - t0)
	await _free()


func bench_body_simulate_stairs(b) -> void:
	await _boot()
	var inp := _frame(Vector2(1, 0))
	var n := 6000
	var t0 := Time.get_ticks_usec()
	for i in n:
		if i % 150 == 0:
			_s.body.teleport(_s.world.landmarks["stairs_0.18"] + Vector3(-1.5, 0.05, 0))
		_s.body.simulate(inp, DT)
	b.record("body.simulate (stairs: step-up rays + test_move)", n, Time.get_ticks_usec() - t0)
	await _free()


func bench_visual_update_pose(b) -> void:
	await _boot()
	var state := {"speed": 5.0, "vy": 0.0, "grounded": true, "crouching": false, "accel_forward": 0.0, "heading": 0.3}
	var n := 20000
	var t0 := Time.get_ticks_usec()
	for i in n:
		state.speed = 3.0 + float(i % 100) / 25.0
		_s.visual.update_pose(state, 1.0 / 144.0)
	b.record("visual.update_pose (15 bones)", n, Time.get_ticks_usec() - t0)
	await _free()


func bench_scene_process_frame(b) -> void:
	await _boot()
	_s.set_process(false)
	var n := 5000
	var t0 := Time.get_ticks_usec()
	for i in n:
		_s._process(1.0 / 144.0)
	b.record("scene._process (follow + pose + readout text)", n, Time.get_ticks_usec() - t0)
	await _free()
