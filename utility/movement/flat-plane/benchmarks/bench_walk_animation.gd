extends RefCounted

const SCENE = preload("res://scenes/gait_treadmill.tscn")


func _boot() -> Node:
	var tree: SceneTree = Engine.get_main_loop()
	var scene := SCENE.instantiate()
	scene.options = {"no-tuning": "true", "no-window-state": "true"}
	tree.root.add_child(scene)
	await tree.process_frame
	scene.set_process(false)
	scene.advance(0.0)
	return scene


func bench_tree_steady_frame(b) -> void:
	var scene := await _boot()
	var n := 1000
	var start := Time.get_ticks_usec()
	for i in n:
		scene.advance(1.0 / 120.0)
	b.record("Treadmill.advance with AnimationTree (steady speed, springs + planner + tree)", n, Time.get_ticks_usec() - start)
	scene.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func bench_tree_regenerate(b) -> void:
	var scene := await _boot()
	var n := 100
	var start := Time.get_ticks_usec()
	for i in n:
		scene.model.cycle = scene.model.cycle_for(0.8 + float(i) * 0.01)
		scene.visual.walk_animation.regenerate()
	b.record("Walk clip regeneration (96 samples x 16 tracks)", n, Time.get_ticks_usec() - start)
	scene.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
