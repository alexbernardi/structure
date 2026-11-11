## Movement Core targets (SYSTEM-ROOMS/movement_core/room.json): one simulate() tick and one present() frame of the
## public movement character, running on flat ground in a minimal world (no laboratory scene), headless.
extends RefCounted

const MovementCharacter = preload("res://systems/movement_core/movement_character.gd")
const DT := 1.0 / 120.0
const TICKS := 600
const WARMUP := 60


func bench_movement_core(b) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var root := Node3D.new()
	tree.root.add_child(root)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(400, 1, 400)
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var character = MovementCharacter.new()
	root.add_child(character)
	await tree.process_frame
	character.spawn(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	character.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	await tree.physics_frame
	var frame := MovementCharacter.empty_frame()
	frame.move = Vector2(0.3, 1.0)
	frame.sprint = true
	var simulated := 0
	var presented := 0
	for i in TICKS + WARMUP:
		frame.yaw = 0.002 * i   # a slow curve keeps it on the floor and the gait changing
		var t0 := Time.get_ticks_usec()
		character.simulate(frame, DT)
		var t1 := Time.get_ticks_usec()
		character.present(DT)
		character.visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)   # the IK modifiers run here
		var t2 := Time.get_ticks_usec()
		if i >= WARMUP:
			simulated += t1 - t0
			presented += t2 - t1
		if i % 240 == 0:
			await tree.physics_frame
	b.record("movement_core.simulate_tick", TICKS, simulated)
	b.record("movement_core.present_frame", TICKS, presented)
	print("movement_core: simulate %.1f us/tick, present %.1f us/frame (%.1f m/s)" % [float(simulated) / TICKS,
		float(presented) / TICKS, Vector2(character.velocity().x, character.velocity().z).length()])
	root.queue_free()
	await tree.process_frame
