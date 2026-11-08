extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const DT := 1.0 / 60.0
const FRAMES := 360


func bench_authored_vs_legacy(b) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var scene := Scene.instantiate()
	scene.options = {"no-capture": "true", "no-hardware": "true", "no-tuning": "true", "no-window-state": "true"}
	tree.root.add_child(scene)
	await tree.process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for legacy in [true, false]:
		scene.locomotion_params.set_value("legacy", 1.0 if legacy else 0.0)
		for speed in [4.0, 6.0, 8.0, 12.0]:
			var samples: Array[int] = []
			for i in FRAMES + 60:
				var heading := i * DT * 1.5
				var velocity: Vector3 = Vector3(-sin(heading), 0.0, -cos(heading)) * speed
				scene.body.core.acceleration = (velocity - scene.body.core.velocity) / DT
				scene.body.core.velocity = velocity
				scene.body.core.grounded = true
				scene.body.position += velocity * DT
				var start := Time.get_ticks_usec()
				scene._process(DT)
				var elapsed := Time.get_ticks_usec() - start
				if i >= 60:
					samples.append(elapsed)
				await tree.process_frame
			var total := 0
			for sample in samples:
				total += sample
			samples.sort()
			var label := "%s %.0f m/s circles" % ["legacy" if legacy else "authored", speed]
			var p95 := samples[int(FRAMES * 0.95)] / 1000.0
			b.record(label, FRAMES, total, {"p95_ms": p95})
			print("%s: p50 %.3f ms, p95 %.3f ms, max %.3f ms" % [
				label, samples[FRAMES / 2] / 1000.0, p95, samples[-1] / 1000.0])
	scene.queue_free()
	await tree.process_frame
