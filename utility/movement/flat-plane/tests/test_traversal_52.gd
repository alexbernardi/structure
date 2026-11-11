## Movement Lab 5.2: catch on contact and hang, one press to pull up (two-handed ClimbUp_2m), letting go, refusals,
## fences at sharp angles, the momentum crouch slide, and a combined course. Unpaced fixed-tick trials; the collider
## is overlap-tested every tick a move drives it (2 mm inset).
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const DT := 1.0 / 120.0
const RUN_YAW := -PI / 2.0
var _tree: SceneTree
var _nodes: Array[Node] = []


func before_each() -> void:
	_tree = Engine.get_main_loop()


func after_each() -> void:
	for node in _nodes:
		node.queue_free()
	_nodes.clear()
	await _tree.process_frame


func _scene(extra := {}):
	var scene = Scene.instantiate()
	var options := {"no-capture": "true", "no-hardware": "true", "no-window-state": "true", "tuning-state": ""}
	options.merge(extra, true)
	scene.options = options
	_tree.root.add_child(scene)
	_nodes.append(scene)
	await _tree.process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return scene


func _place(scene, landmark: String, at := Vector3.INF) -> void:
	scene.teleport_to(landmark)
	if at != Vector3.INF:
		scene.body.teleport(at)
	await _tree.physics_frame


static func _input(press := false, extra := {}) -> Dictionary:
	var input := {"move": Vector2(0, 1), "yaw": RUN_YAW, "sprint": false, "jump_pressed": press, "jump_held": press}
	input.merge(extra, true)
	return input


func _run(scene, ticks: int, policy: Callable) -> Dictionary:
	var stats := {"overlap_ticks": 0, "max_y": -INF, "max_step": 0.0, "presses": 0, "hang_ticks": 0, "grip_error": 0.0,
		"min_speed": INF, "speeds": []}
	var clearance := PhysicsShapeQueryParameters3D.new()
	var cylinder := CylinderShape3D.new()
	clearance.shape = cylinder
	clearance.exclude = [scene.body.get_rid()]
	clearance.collision_mask = scene.body.collision_mask
	var space: PhysicsDirectSpaceState3D = scene.body.get_world_3d().direct_space_state
	var counts0 := {"vaults": scene.vault.vaults, "mantles": scene.traversal.mantle.mantles, "overs": scene.traversal.mantle.overs,
		"hangs": scene.traversal.mantle.hangs, "slides": scene.traversal.slides}
	var previous: Vector3 = scene.body.global_position
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		var input: Dictionary = policy.call(scene, i)
		if input.get("jump_pressed", false):
			stats.presses += 1
		scene.simulate_tick(input, DT)
		scene._process(DT)
		scene.authored_visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var position: Vector3 = scene.body.global_position
		var moving: bool = scene.vault.active() or scene.traversal.mantle.active() or scene.traversal.mantle.hanging() or scene.traversal.sliding
		if moving:
			cylinder.radius = scene.body._shape.radius - 0.002
			cylinder.height = scene.body._shape.height - 0.004
			clearance.transform = scene.body._collider.global_transform
			if not space.intersect_shape(clearance, 1).is_empty():
				stats.overlap_ticks += 1
		if scene.traversal.mantle.hanging():
			stats.hang_ticks += 1
			if scene.traversal.mantle._hang_time > 0.2:
				stats.grip_error = maxf(stats.grip_error, scene.authored_animation.grip_error)
		if scene.traversal.sliding:
			stats.speeds.append(scene.traversal.slide_velocity.length())
		stats.max_step = maxf(stats.max_step, position.distance_to(previous))
		stats.max_y = maxf(stats.max_y, position.y)
		previous = position
	for key in counts0:
		var now: int = {"vaults": scene.vault.vaults, "mantles": scene.traversal.mantle.mantles, "overs": scene.traversal.mantle.overs,
			"hangs": scene.traversal.mantle.hangs, "slides": scene.traversal.slides}[key]
		stats[key] = now - int(counts0[key])
	stats["finish"] = scene.body.global_position
	stats["choices"] = scene.traversal.choices.duplicate()
	stats["refusal"] = scene.traversal.last_refusal
	print("T52 ", JSON.stringify({"finish": [snappedf(stats.finish.x, 0.01), snappedf(stats.finish.y, 0.01), snappedf(stats.finish.z, 0.01)],
		"vaults": stats.vaults, "mantles": stats.mantles, "overs": stats.overs, "hangs": stats.hangs, "slides": stats.slides,
		"overlap": stats.overlap_ticks, "presses": stats.presses, "choices": stats.choices, "refusal": stats.refusal}))
	return stats


## Jump at a 2.2 m wall with no further press: the body catches the edge on contact and hangs with both hands on it.
## Holding Space does nothing; one new press pulls up and over onto the top. Exactly two presses in all.
func test_catch_on_contact_hangs_and_one_press_pulls_up(t) -> void:
	var scene = await _scene()
	for wall in [["2.2 m", 40.0, 2.2], ["2.6 m", 50.0, 2.6]]:
		await _place(scene, "lane_j", Vector3(float(wall[1]) - 5.0, 0.05, -61.0))
		var plan := {"step": 0, "held": 0}
		var stats: Dictionary = await _run(scene, 600, func(s, _i):
			var x: float = s.body.global_position.x
			match plan.step:
				0:
					if x > float(wall[1]) - 1.6:
						plan.step = 1
						return _input(true)             # the jump
				1:
					if s.traversal.mantle.hanging() and s.traversal.mantle._hang_time > 0.3:
						plan.step = 2
				2:
					plan.held += 1
					if plan.held < 60:
						return _input(false, {"jump_held": true})   # holding Space while hanging: nothing
					plan.step = 3
					return _input(true)                 # the one press
			return _input())
		t.eq(stats.hangs, 1, "%s: the edge is caught on contact (%s)" % [wall[0], stats.choices])
		t.ok(stats.hang_ticks >= 90, "%s: and held while Space is only held (%d hang ticks)" % [wall[0], stats.hang_ticks])
		t.eq(stats.presses, 2, "%s: two presses in all (jump, pull up)" % wall[0])
		t.ok(int(stats.choices.get("pullup", 0)) >= 1, "%s: the press pulls up" % wall[0])
		t.ok(stats.max_y > float(wall[2]) - 0.01, "%s: on top (%.2f m)" % [wall[0], stats.max_y])
		t.eq(stats.overlap_ticks, 0, "%s: no penetration while hanging or climbing" % wall[0])
		t.ok(stats.max_step < 0.15, "%s: no snap into or out of the hang (%.3f m)" % [wall[0], stats.max_step])
		t.ok(stats.grip_error < 0.03, "%s: both hands on the edge while hanging (%.4f m)" % [wall[0], stats.grip_error])
		t.ok(scene.body.core.grounded and not scene.traversal.busy(), "%s: back in normal locomotion on top" % wall[0])


## A press already made in the air as the body reaches the edge is not lost: it pulls up at once (no hang, no repeat).
## Crouch while hanging lets go. A wall without room on top cannot be caught and the press says why.
func test_early_press_drop_and_refusal(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_j", Vector3(45.0, 0.05, -61.0))
	var plan := {"step": 0}
	var stats: Dictionary = await _run(scene, 500, func(s, _i):
		if plan.step == 0 and s.body.global_position.x > 48.4:
			plan.step = 1
			return _input(true)
		if plan.step == 1 and not s.body.core.grounded and s.body.velocity.y < 1.5:
			plan.step = 2
			return _input(true)
		return _input())
	t.eq(stats.hangs, 0, "a timely second press does not stop in a hang")
	t.eq(stats.mantles, 1, "it climbs the 2.6 m wall directly (%s)" % [stats.choices])
	t.ok(stats.max_y > 2.59, "onto the top (%.2f m)" % stats.max_y)
	# Hang, then let go with crouch.
	await _place(scene, "lane_j", Vector3(35.0, 0.05, -61.0))
	plan = {"step": 0}
	stats = await _run(scene, 400, func(s, _i):
		if plan.step == 0 and s.body.global_position.x > 38.4:
			plan.step = 1
			return _input(true)
		if plan.step == 1 and s.traversal.mantle.hanging() and s.traversal.mantle._hang_time > 0.3:
			plan.step = 2
			return _input(false, {"crouch": true})
		return {"move": Vector2.ZERO, "yaw": RUN_YAW} if plan.step == 2 else _input())
	t.eq(stats.hangs, 1, "caught the 2.2 m edge")
	t.ok(int(stats.choices.get("let_go", 0)) >= 1, "crouch lets go")
	t.eq(stats.mantles, 0, "and nothing climbs")
	t.ok(scene.body.global_position.y < 0.1, "back on the ground")
	# No room on top (a slab just above the 2.6 m top): no catch; a press says why.
	await _place(scene, "lane_j_covered")
	plan = {"step": 0}
	stats = await _run(scene, 300, func(s, _i):
		if plan.step == 0 and s.body.global_position.x > 66.4:
			plan.step = 1
			return _input(true)
		if plan.step == 1 and not s.body.core.grounded and s.body.velocity.y < 0.5:
			plan.step = 2
			return _input(true)
		return _input())
	t.eq(stats.hangs + stats.mantles + stats.overs, 0, "no catch or climb under the slab")
	t.ok(stats.refusal.contains("headroom"), "the press is refused for headroom (%s)" % stats.refusal)


## The thin 2.4 m wall: catch, hang, one press pulls up and over and drops to the far side. The 3.0 m wall is out of a
## human's reach and caught with the cybernetic legs.
func test_pull_up_over_and_upgrade_reach(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_j_thin")
	var plan := {"step": 0}
	var stats: Dictionary = await _run(scene, 600, func(s, _i):
		if plan.step == 0 and s.body.global_position.x > 58.2:
			plan.step = 1
			return _input(true)
		if plan.step == 1 and s.traversal.mantle.hanging() and s.traversal.mantle._hang_time > 0.2:
			plan.step = 2
			return _input(true)
		return _input())
	t.eq(stats.hangs, 1, "the thin wall's top is caught")
	t.eq(stats.overs, 1, "one press climbs over it (%s, %s)" % [stats.choices, stats.refusal])
	t.ok(scene.body.global_position.x > 60.2, "landing beyond it (x %.2f)" % scene.body.global_position.x)
	t.eq(stats.overlap_ticks, 0, "no penetration")
	for profile in ["human", "cyber"]:
		scene.capabilities.clear()
		if profile == "cyber":
			scene.apply_profile("cyber")
		await _place(scene, "lane_j", Vector3(73.0, 0.05, -61.0))
		plan = {"step": 0}
		stats = await _run(scene, 500, func(s, _i):
			if plan.step == 0 and s.body.global_position.x > 76.6:
				plan.step = 1
				return _input(true)
			if plan.step == 1 and s.traversal.mantle.hanging() and s.traversal.mantle._hang_time > 0.2:
				plan.step = 2
				return _input(true)
			return _input())
		if profile == "human":
			t.eq(stats.hangs + stats.mantles, 0, "human: the 3.0 m edge is out of reach")
		else:
			t.eq(stats.hangs, 1, "cyber: the 3.0 m edge is caught (%s)" % [stats.choices])
			t.ok(stats.max_y > 2.99, "cyber: and pulled up onto (%.2f m)" % stats.max_y)
	scene.capabilities.clear()


## Fences at 30-75 degrees: a press near the fence gets over it - square to the fence - and keeps the sideways
## momentum along it; from the air, a catch does the same. No fence-specific code: the fan of probes finds the face.
func test_fences_at_sharp_angles(t) -> void:
	var scene = await _scene()
	for i in 4:
		var angle: float = [30.0, 45.0, 60.0, 75.0][i]
		var cx := 40.0 + i * 9.0
		var normal := Vector3(-1, 0, 0).rotated(Vector3.UP, deg_to_rad(angle))   # the fence's near face, toward the runner
		await _place(scene, "lane_i", Vector3(cx - 6.0, 0.05, -55.0))
		var side_before := signf((scene.body.global_position - Vector3(cx, 0, -55)).dot(normal))
		var plan := {"step": 0, "exit": 0.0}
		var stats: Dictionary = await _run(scene, 420, func(s, _i):
			var gap: float = absf((s.body.global_position - Vector3(cx, 0, -55)).dot(normal))
			var along: float = absf((s.body.global_position - Vector3(cx, 0, -55)).dot(normal.cross(Vector3.UP)))
			if plan.step == 0 and (not s.vault.opportunity.is_empty() or (gap < 0.9 and along < 2.0)):
				plan.step = 1
				return _input(true)
			if plan.step == 1 and not s.traversal.busy() and (s.vault.vaults > 0 or s.traversal.mantle.overs > 0):
				plan.step = 2
				plan.exit = Vector2(s.body.velocity.x, s.body.velocity.z).length()
			return _input())
		var side_after := signf((scene.body.global_position - Vector3(cx, 0, -55)).dot(normal))
		t.ok(side_after != side_before, "%d deg fence: crossed (%s, %s)" % [int(angle), stats.choices, stats.refusal])
		t.ok(stats.vaults + stats.overs >= 1, "%d deg fence: by a vault or a climb over, not around its end" % int(angle))
		t.eq(stats.overlap_ticks, 0, "%d deg fence: no penetration" % int(angle))
		t.ok(stats.max_step < 0.15, "%d deg fence: no snap (%.3f m)" % [int(angle), stats.max_step])
		if angle > 35.0:
			t.ok(plan.exit > 1.0, "%d deg fence: momentum along the fence survives (%.2f m/s)" % [int(angle), plan.exit])
	# From the air at 60 degrees: jump toward it, press again near it.
	var cx2 := 58.0
	var n2 := Vector3(-1, 0, 0).rotated(Vector3.UP, deg_to_rad(60.0))
	await _place(scene, "lane_i", Vector3(cx2 - 6.0, 0.05, -55.0))
	var before := signf((scene.body.global_position - Vector3(cx2, 0, -55)).dot(n2))
	var step := {"n": 0}
	var stats2: Dictionary = await _run(scene, 420, func(s, _i):
		var gap: float = absf((s.body.global_position - Vector3(cx2, 0, -55)).dot(n2))
		if step.n == 0 and gap < 1.6:
			step.n = 1
			return _input(true)
		if step.n == 1 and not s.body.core.grounded and gap < 0.9:
			step.n = 2
			return _input(true)
		return _input())
	t.ok(signf((scene.body.global_position - Vector3(cx2, 0, -55)).dot(n2)) != before, "60 deg fence from the air: crossed (%s)" % [stats2.choices])
	t.ok(stats2.overs >= 1, "60 deg fence from the air: by a catch and climb over (%s, %s)" % [stats2.choices, stats2.refusal])


## The crouch slide: starts only at speed, runs on momentum (no fixed distance), slows smoothly, steers within its
## limit, fits under 1.0 m bars that a crouch cannot pass, and stands back up only where there is room.
func test_crouch_slide_momentum_and_clearance(t) -> void:
	var scene = await _scene()
	# Too slow: crouch is the ordinary crouch.
	await _place(scene, "lane_k")
	var stats: Dictionary = await _run(scene, 120, func(_s, i): return _input(false, {"crouch": i > 5, "move": Vector2(0, 0.4)}))
	t.eq(stats.slides, 0, "a crouch at walking speed is not a slide")
	# Sprint into a slide under both bars.
	await _place(scene, "lane_k")
	var plan := {"crouch": false}
	stats = await _run(scene, 360, func(s, _i):
		if not plan.crouch and s.body.global_position.x > 44.0:
			plan.crouch = true
		return _input(false, {"sprint": true, "crouch": plan.crouch}))
	t.eq(stats.slides, 1, "crouch at a sprint slides (%s)" % [stats.choices])
	t.ok(scene.body.global_position.x > 58.5, "under both 1.0 m bars (x %.2f)" % scene.body.global_position.x)
	t.eq(stats.overlap_ticks, 0, "the low collider never penetrates the bars")
	var speeds: Array = stats.speeds
	t.ok(speeds.size() > 90, "the slide lasts on its momentum (%.2f s)" % (speeds.size() * DT))
	var rises := 0
	for k in range(1, speeds.size()):
		if speeds[k] > speeds[k - 1] + 1e-4:
			rises += 1
	t.eq(rises, 0, "on flat ground it only ever slows (no fixed-speed travel)")
	t.ok(speeds[0] > 11.0, "it starts from the sprint speed plus the boost (%.2f m/s)" % speeds[0])
	# A crouch-walk cannot pass under the bars.
	await _place(scene, "lane_k", Vector3(46.0, 0.05, -67.0))
	stats = await _run(scene, 300, func(_s, _i): return _input(false, {"crouch": true}))
	t.ok(scene.body.global_position.x < 49.85, "crouch-walking is stopped by the 1.0 m bar (x %.2f)" % scene.body.global_position.x)
	# Releasing crouch under a bar: no standing up into it; the slide scoots out first.
	await _place(scene, "lane_k")
	plan = {"crouch": false, "released": false, "under": false}
	stats = await _run(scene, 300, func(s, _i):
		var x: float = s.body.global_position.x
		if not plan.crouch and x > 46.0:
			plan.crouch = true
		if plan.crouch and absf(x - 50.0) < 0.1:
			plan.released = true
			plan.under = s.traversal.sliding
		return _input(false, {"sprint": true, "crouch": plan.crouch and not plan.released}))
	t.ok(plan.under, "still sliding when crouch is released under the bar")
	t.eq(stats.overlap_ticks, 0, "never stands up into the bar")
	t.ok(scene.body.global_position.x > 50.4, "carries on past it (x %.2f)" % scene.body.global_position.x)
	# Steering is limited.
	await _place(scene, "lane_k", Vector3(20.0, 0.05, -67.0))
	plan = {"t": 0, "worst": 0.0, "last": Vector3.ZERO}
	stats = await _run(scene, 200, func(s, i):
		var crouch: bool = i > 60
		var turn: bool = i > 80
		if s.traversal.sliding:
			var v: Vector3 = s.traversal.slide_velocity
			if plan.last != Vector3.ZERO and v.length() > 0.5:
				plan.worst = maxf(plan.worst, absf(plan.last.signed_angle_to(v, Vector3.UP)))
			plan.last = v
		return {"move": Vector2(1, 0) if turn else Vector2(0, 1), "yaw": RUN_YAW, "sprint": true, "crouch": crouch, "jump_pressed": false})
	var limit: float = scene.capabilities.get_value("slide_steer") * DT
	t.ok(plan.worst <= limit + 1e-4, "steering turns at most slide_steer per tick (%.4f <= %.4f rad)" % [plan.worst, limit])
	t.ok(plan.worst > limit * 0.5, "and does turn toward the stick (%.4f rad)" % plan.worst)


## Slopes: uphill a slide dies sooner than on the flat, downhill it speeds up. A slide jump keeps the slide's speed.
func test_slide_slopes_and_slide_jump(t) -> void:
	var scene = await _scene()
	var flat_ticks := 0
	var uphill_ticks := 0
	for run in ["flat", "uphill"]:
		await _place(scene, "lane_k", Vector3(64.0 if run == "uphill" else 20.0, 0.05, -67.0))
		var plan := {"crouch": false}
		var stats: Dictionary = await _run(scene, 360, func(s, i):
			if not plan.crouch and i > 60:
				plan.crouch = true
			return _input(false, {"sprint": true, "crouch": plan.crouch}))
		if run == "flat":
			flat_ticks = stats.speeds.size()
		else:
			uphill_ticks = stats.speeds.size()
	t.ok(uphill_ticks < flat_ticks, "uphill the slide is shorter (%d vs %d ticks)" % [uphill_ticks, flat_ticks])
	await _place(scene, "lane_k_plateau")
	var plan2 := {"crouch": false}
	var down: Dictionary = await _run(scene, 240, func(s, i):
		if not plan2.crouch and s.body.global_position.x > 87.0:
			plan2.crouch = true
		return _input(false, {"crouch": plan2.crouch}))   # a 6 m/s run: gravity along 12 degrees outweighs the drag
	var speeds: Array = down.speeds
	t.ok(speeds.size() > 10 and speeds.max() > speeds[0] + 0.5, "downhill the slide speeds up (%.2f -> %.2f m/s)" % [speeds[0] if speeds.size() > 0 else 0.0, speeds.max() if speeds.size() > 0 else 0.0])
	# Slide jump.
	await _place(scene, "lane_k", Vector3(20.0, 0.05, -67.0))
	var state := {"jumped": false, "speed": 0.0, "air": 0.0}
	await _run(scene, 160, func(s, i):
		if s.traversal.sliding and s.traversal.slide_time > 0.3 and not state.jumped:
			state.jumped = true
			state.speed = s.traversal.slide_velocity.length()
			return _input(true, {"sprint": true, "crouch": true})
		if state.jumped and not s.body.core.grounded:
			state.air = maxf(state.air, Vector2(s.body.velocity.x, s.body.velocity.z).length())
		return _input(false, {"sprint": true, "crouch": i > 60}))
	t.ok(state.jumped and state.air > state.speed - 0.5, "a slide jump keeps the slide's speed (%.2f -> %.2f m/s)" % [state.speed, state.air])


## Lane L in one run: vault, mantle, catch and pull up a 2.4 m wall, slide under a 1.0 m bar.
func test_combined_course(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_l")
	var plan := {"crouch": false, "pressed_block": false, "jumped_high": false, "pulled": false}
	var stats: Dictionary = await _run(scene, 1500, func(s, _i):
		var x: float = s.body.global_position.x
		if not s.vault.opportunity.is_empty() and s.vault.phase == s.vault.Phase.IDLE:
			return _input(true)
		if not plan.pressed_block and x > 46.0 and x < 46.8 and s.body.is_on_floor():
			plan.pressed_block = true
			return _input(true)
		if not plan.jumped_high and x > 55.2 and s.body.is_on_floor():
			plan.jumped_high = true
			return _input(true)
		if s.traversal.mantle.hanging() and s.traversal.mantle._hang_time > 0.2 and not plan.pulled:
			plan.pulled = true
			return _input(true)
		if x > 62.0:
			plan.crouch = true
		return _input(false, {"sprint": x > 60.0, "crouch": plan.crouch}))
	t.eq(stats.vaults, 1, "the wall is vaulted (%s, %s)" % [stats.choices, stats.refusal])
	t.ok(stats.mantles >= 2, "the block is mantled and the high wall pulled up (%d)" % stats.mantles)
	t.eq(stats.hangs, 1, "the high wall is caught on contact")
	t.eq(stats.slides, 1, "the bar is slid under")
	t.ok(scene.body.global_position.x > 66.5, "past the bar (x %.2f)" % scene.body.global_position.x)
	t.eq(stats.overlap_ticks, 0, "no penetration in any move")
