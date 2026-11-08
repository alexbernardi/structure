extends RefCounted

const SCENE = preload("res://scenes/flat_plane.tscn")
const DT := 1.0 / 60.0
const FRAMES := 360


func bench_gait_turning(b) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var scene := SCENE.instantiate()
	scene.options = {"no-capture": "true", "no-hardware": "true", "no-tuning": "true", "no-window-state": "true", "legacy-animation": "true"}
	tree.root.add_child(scene)
	await tree.process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.gait_params.set_value("run_mode", 1.0)
	scene.params.set_value("max_ground_speed", 6.0)
	scene.params.set_value("sprint_multiplier", 2.0)
	var ground := {"grounded": true, "normal": Vector3.UP, "can_stand": true}
	for case in [["straight", 0.0, false], ["circles", 1.5, false], ["varying circles", 3.0, false], ["sprint circles", 1.5, true]]:
		scene.body.core.reset()
		var samples: Array[int] = []
		var generation: int = scene.visual.walk_animation.generation
		var baking := 0
		var speed_min := INF
		var speed_max := 0.0
		for i in FRAMES + 60:
			var yaw: float = i * DT * case[1]
			if case[0] == "varying circles":
				yaw += 0.35 * sin(i * DT * 2.0)
			var input := {"move": Vector2(0, 1), "yaw": yaw, "sprint": case[2]}
			var before: int = scene.visual.walk_animation.generation
			var start := Time.get_ticks_usec()
			scene.body.core.step(input, ground, DT)
			scene._process(DT)
			var elapsed := Time.get_ticks_usec() - start
			if i < 60:
				generation = scene.visual.walk_animation.generation
				await tree.process_frame
				continue
			samples.append(elapsed)
			if scene.visual.walk_animation.generation != before:
				baking += scene.visual.walk_animation.bake_usec
			speed_min = minf(speed_min, scene.body.core.horizontal_speed())
			speed_max = maxf(speed_max, scene.body.core.horizontal_speed())
			await tree.process_frame
		var total := 0
		for sample in samples:
			total += sample
		samples.sort()
		var label: String = case[0]
		b.record("running " + label, FRAMES, total)
		print("%s: p50 %.3f ms, p95 %.3f ms, max %.3f ms; %d bakes / %d frames, bake %.1f ms; speed %.6f..%.6f" % [
			label, samples[FRAMES / 2] / 1000.0, samples[int(FRAMES * 0.95)] / 1000.0, samples[-1] / 1000.0,
			scene.visual.walk_animation.generation - generation, FRAMES, baking / 1000.0, speed_min, speed_max])
	scene.queue_free()
	await tree.process_frame
