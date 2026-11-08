## Movement Lab 4.0 traversal cost: a fresh vault plan and the silhouette clipping it is built on, and the whole tick
## (physics with perception, presentation, skeleton modifiers) on vault course lane A with traversal on, against the
## same running on open ground with traversal on (perception with nothing to see) and off.
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const Visual = preload("res://character/authored_mannequin.gd")
const Profile = preload("res://traversal/vault_profile.gd")
const Planner = preload("res://traversal/vault_planner.gd")
const DT := 1.0 / 120.0
const TICKS := 900
const WARMUP := 60


func bench_vault_planning(b) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var visual = Visual.new()
	tree.root.add_child(visual)
	await tree.process_frame
	var profile = Profile.new()
	var start := Time.get_ticks_usec()
	profile.build(visual)
	var built := Time.get_ticks_usec() - start
	b.record("vault profile build (once per clip)", 1, built, {"samples": profile.sample_count()})
	print("vault profile build: %.2f ms (%d samples)" % [built / 1000.0, profile.sample_count()])
	for speed in [6.0, 12.0]:
		var obstacle := {"distance": Planner.timing(speed).takeoff, "height": 1.1, "depth": 0.35, "slope": 0.0, "angle": 0.0, "landing": 0.0}
		var count := 40
		start = Time.get_ticks_usec()
		for i in count:
			Planner.new().plan(profile, obstacle, speed, 0.6)   # a fresh planner: no remembered plan
		var elapsed := Time.get_ticks_usec() - start
		b.record("fresh vault plan %.0f m/s" % speed, count, elapsed)
		print("fresh vault plan %.0f m/s: %.3f ms" % [speed, elapsed / 1000.0 / count])
	var timed := Planner.timing(6.0)
	var calls := 200
	start = Time.get_ticks_usec()
	for i in calls:
		profile.zones(timed.stretch, timed.takeoff, 0.35 + i * 0.001, 0.0)
	var zoned := Time.get_ticks_usec() - start
	b.record("silhouette zones", calls, zoned)
	print("silhouette zones: %.3f ms" % [zoned / 1000.0 / calls])
	visual.queue_free()
	await tree.process_frame


func bench_vault_course_ticks(b) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var scene := Scene.instantiate()
	scene.options = {"no-capture": "true", "no-hardware": "true", "no-tuning": "true", "no-window-state": "true"}
	tree.root.add_child(scene)
	await tree.process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var lane: Vector3 = scene.world.landmarks["vault_a"]
	for run in [["lane A course, traversal on", lane, true], ["open ground, traversal on", Vector3(150, 0, 150), true],
			["open ground, traversal off", Vector3(150, 0, 150), false]]:
		scene.traversal_params.set_value("traversal", 1.0 if run[2] else 0.0)
		scene.body.teleport(run[1] + Vector3(0, 0.05, 0))
		await tree.physics_frame
		var vaults_before: int = scene.vault.vaults
		var samples: Array[int] = []
		var physics := 0
		var total := 0
		for i in TICKS + WARMUP:
			if i % 240 == 0:
				await tree.physics_frame
			var start := Time.get_ticks_usec()
			scene.simulate_tick({"move": Vector2(0, 1), "yaw": -PI / 2.0}, DT)
			var simulated := Time.get_ticks_usec() - start
			scene._process(DT)
			scene.authored_visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			var elapsed := Time.get_ticks_usec() - start
			if i >= WARMUP:
				samples.append(elapsed)
				physics += simulated
				total += elapsed
		samples.sort()
		var vaults: int = scene.vault.vaults - vaults_before
		var p95 := samples[int(TICKS * 0.95)] / 1000.0
		b.record(run[0], TICKS, total, {"p95_ms": p95, "physics_mean_ms": physics / 1000.0 / TICKS, "vaults": vaults})
		print("%s: p50 %.3f ms, p95 %.3f ms, max %.3f ms, physics+perception mean %.3f ms, %d vaults" % [
			run[0], samples[TICKS / 2] / 1000.0, p95, samples[-1] / 1000.0, physics / 1000.0 / TICKS, vaults])
	scene.queue_free()
	await tree.process_frame
