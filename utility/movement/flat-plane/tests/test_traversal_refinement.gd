## Movement Lab 5.1 refinement: vault authorization (no vault from contact, held Space or stale presses), airborne
## catching and climbing over, context-driven vault variation, and the lane F test bar.
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


static func _input(press := false, hold := false, sprint := false, yaw := RUN_YAW) -> Dictionary:
	return {"move": Vector2(0, 1), "yaw": yaw, "sprint": sprint, "jump_pressed": press, "jump_held": press or hold}


## Runs `ticks` ticks of `policy.call(scene, i)`; counts moves started and records collider overlap while moving.
func _run(scene, ticks: int, policy: Callable) -> Dictionary:
	var stats := {"vaults": 0, "mantles": 0, "overs": 0, "overlap_ticks": 0, "max_step": 0.0, "max_y": -INF}
	var clearance := PhysicsShapeQueryParameters3D.new()
	var cylinder := CylinderShape3D.new()
	clearance.shape = cylinder
	clearance.exclude = [scene.body.get_rid()]
	clearance.collision_mask = scene.body.collision_mask
	var space: PhysicsDirectSpaceState3D = scene.body.get_world_3d().direct_space_state
	var v0: int = scene.vault.vaults
	var m0: int = scene.traversal.mantle.mantles
	var o0: int = scene.traversal.mantle.overs
	var previous: Vector3 = scene.body.global_position
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		scene.simulate_tick(policy.call(scene, i), DT)
		scene._process(DT)
		var position: Vector3 = scene.body.global_position
		if scene.vault.active() or scene.traversal.mantle.active():
			cylinder.radius = scene.body._shape.radius - 0.002
			cylinder.height = scene.body._shape.height - 0.004
			clearance.transform = scene.body._collider.global_transform
			if not space.intersect_shape(clearance, 1).is_empty():
				stats.overlap_ticks += 1
		stats.max_step = maxf(stats.max_step, position.distance_to(previous))
		stats.max_y = maxf(stats.max_y, position.y)
		previous = position
	stats.vaults = scene.vault.vaults - v0
	stats.mantles = scene.traversal.mantle.mantles - m0
	stats.overs = scene.traversal.mantle.overs - o0
	stats["finish"] = scene.body.global_position
	stats["choices"] = scene.traversal.choices.duplicate()
	stats["refusal"] = scene.traversal.last_refusal
	print("REFINE ", JSON.stringify({"vaults": stats.vaults, "mantles": stats.mantles, "overs": stats.overs, "overlap": stats.overlap_ticks,
		"finish": [snappedf(stats.finish.x, 0.01), snappedf(stats.finish.y, 0.01)], "choices": stats.choices, "refusal": stats.refusal}))
	return stats


static func _face(scene) -> float:
	return scene.vault.region.get("face", INF)


## Every vaultable wall of lanes A, B and D: a press after the window, Space held into the wall, and repeated presses
## while pressed against it never start a vault, a mantle or a climb over. The consequence of a missed window is the
## ordinary jump.
func test_missed_windows_held_space_and_contact_never_traverse(t) -> void:
	var scene = await _scene()
	var walls := [["vault_a", Vector3(-24.0, 0.05, -25.0)], ["vault_b", Vector3(-4.0, 0.05, -30.0)], ["lane_d", Vector3.INF]]
	for wall in walls:
		# 1. Press just after the window closed (inside the late edge), then keep holding Space into the wall.
		await _place(scene, wall[0], wall[1])
		var state := {"pressed": false}
		var stats: Dictionary = await _run(scene, 200, func(s, _i):
			if not state.pressed and s.vault.reason == "too_close":
				state.pressed = true
				return _input(true)
			return _input(false, state.pressed))
		t.ok(state.pressed, "%s: a press after the window was made" % wall[0])
		t.eq(stats.vaults + stats.mantles + stats.overs, 0, "%s: a missed window plus held Space never traverses (%s)" % [wall[0], stats.choices])
		t.eq(scene.traversal.last_choice, "jump", "%s: the missed window is an ordinary jump" % wall[0])
		t.ok(scene.traversal.last_refusal.contains("missed"), "%s: and says the window was missed (%s)" % [wall[0], scene.traversal.last_refusal])
		# 2. Pressed against the wall on the ground: repeated presses (each one a jump) and Space held throughout.
		stats = await _run(scene, 240, func(s, i): return _input(i % 20 == 0 and s.body.is_on_floor(), true))
		t.eq(stats.vaults + stats.mantles + stats.overs, 0, "%s: grounded presses against the wall never traverse (%s)" % [wall[0], stats.choices])
		t.eq(stats.vaults, 0, "%s: and never vault" % wall[0])
	# 3. A press long before the window (an early jump), held all the way: no vault when the wall arrives.
	await _place(scene, "vault_a")
	var stats: Dictionary = await _run(scene, 300, func(_s, i): return _input(i == 5, i > 5))
	t.eq(stats.vaults, 0, "a press far before the window, then held, never vaults")


## A held or early press can never be stored and fire later: presses older than the buffer are dropped.
func test_presses_expire_and_holding_is_not_a_press(t) -> void:
	var scene = await _scene()
	await _place(scene, "vault_a")
	var stats: Dictionary = await _run(scene, 400, func(s, i): return _input(false, true))
	t.eq(stats.vaults, 0, "holding Space from the start never vaults")
	await _place(scene, "vault_a", Vector3(-23.0, 0.05, -25.0))
	# In the air (a hop) with a press, landing well before the region: the press expires instead of firing later.
	var state := {"phase": 0}
	stats = await _run(scene, 300, func(s, i):
		if i == 1:
			return _input(true)
		if state.phase == 0 and not s.body.core.grounded and s.body.velocity.y < 0.0:
			state.phase = 1
			return _input(true)
		return _input())
	t.eq(stats.vaults, 0, "an airborne press before the region expires; no delayed vault")


func _climb_ready(scene, airborne: bool) -> bool:
	var d: Vector3 = scene.traversal._direction(scene.body)
	return d != Vector3.ZERO and scene.traversal.mantle.evaluate(scene.body, d, airborne).get("ok", false)


## Airborne catching: Space held never grabs; a new press in the air catches a ledge in reach (rising, at the apex,
## or falling after a failed jump), and the catch becomes a mantle onto the ledge.
func test_airborne_catch_needs_its_own_press(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_e_ledge")
	var state := {"jumped": false}
	var stats: Dictionary = await _run(scene, 240, func(s, _i):
		if not state.jumped and s.body.global_position.x > 57.6:
			state.jumped = true
			return _input(true)
		return _input(false, state.jumped))
	t.eq(stats.mantles + stats.overs, 0, "holding Space after a jump never grabs the ledge")
	# Failed jump, recovered on the way down: the second press comes while falling.
	await _place(scene, "lane_e_ledge")
	state = {"jumped": false, "caught": false}
	stats = await _run(scene, 360, func(s, _i):
		if not state.jumped and s.body.global_position.x > 57.6:
			state.jumped = true
			return _input(true)
		if state.jumped and not state.caught and s.body.velocity.y < -1.0:
			state.caught = true
			return _input(true)
		return _input())
	t.eq(stats.mantles, 1, "a press while falling catches the 1.9 m ledge (%s, %s)" % [stats.choices, stats.refusal])
	t.ok(stats.max_y > 1.89, "and climbs onto it (%.2f m)" % stats.max_y)
	t.eq(stats.overlap_ticks, 0, "no penetration while climbing")
	t.ok(stats.max_step < 0.12, "no snap into the climb (%.3f m)" % stats.max_step)


## Grip strength: a fall faster than the hands can stop is not caught by a human; the cybernetic grip holds it.
func test_grip_strength_limits_catching_a_fast_fall(t) -> void:
	var scene = await _scene()
	for profile in ["human", "cyber"]:
		scene.capabilities.clear()
		if profile == "cyber":
			scene.apply_profile("cyber")
		await _place(scene, "lane_e_ledge", Vector3(58.05, 3.6, -31.0))   # dropped 0.45 m from the 1.9 m face
		var state := {"pressed": false, "speed": 0.0}
		var stats: Dictionary = await _run(scene, 120, func(s, _i):
			if not state.pressed and s.body.global_position.y < 1.6:
				state.pressed = true
				state.speed = -s.body.velocity.y
				return _input(true)
			if not state.pressed:
				return {"move": Vector2.ZERO, "yaw": RUN_YAW}   # straight down, no drift onto the ledge
			return _input())
		if profile == "human":
			t.eq(stats.mantles, 0, "human: a %.1f m/s fall is not caught" % state.speed)
			t.ok(scene.traversal.last_refusal.contains("too_fast"), "human: because it is too fast (%s)" % scene.traversal.last_refusal)
		else:
			t.eq(stats.mantles, 1, "cyber: the stronger grip catches it (%s)" % scene.traversal.last_refusal)
	scene.capabilities.clear()


## The lane F test bar. A vault is refused (the bar blocks every arc). Human solution through the general system:
## a press at the wall jumps (missed vault window), a second press catches the wall top and climbs over it into the gap;
## then either crouch under the bar, or jump and press again to catch the bar and climb over it.
func test_the_test_bar_is_solved_by_catching_and_climbing(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_f_bar")
	var seen := {}
	var stats: Dictionary = await _run(scene, 200, func(s, _i):
		seen[s.vault.reason] = true
		return _input())
	t.eq(stats.vaults, 0, "no vault: the bar blocks the arc")
	t.ok(seen.has("blocked"), "the vault is refused as blocked (%s)" % [seen.keys()])
	for route in ["crouch", "bar"]:
		await _place(scene, "lane_f_bar")
		var plan := {"step": 0}
		stats = await _run(scene, 900, func(s, _i):
			var x: float = s.body.global_position.x
			match plan.step:
				0:
					if x > 38.9:
						plan.step = 1
						return _input(true)                # jump (the vault window is long gone)
				1:
					if not s.body.core.grounded:
						plan.step = 2
						return _input(true)                # catch the wall top
				2:
					if s.traversal.mantle.overs > 0 and s.body.is_on_floor() and not s.traversal.mantle.active():
						plan.step = 3
				3:
					if route == "crouch":
						var crouch := _input()
						crouch["crouch"] = true
						return crouch
					if s.body.is_on_floor():
						plan.step = 4
						return _input(true)                # jump under the bar
				4:
					if not s.body.core.grounded:
						plan.step = 5
						return _input(true)                # catch the bar
			return _input())
		t.ok(stats.overs >= 1, "%s: the wall top is caught and climbed over (%s, %s)" % [route, stats.choices, stats.refusal])
		t.ok(scene.body.global_position.x > 42.0, "%s: past the bar (x %.2f)" % [route, scene.body.global_position.x])
		t.eq(stats.overlap_ticks, 0, "%s: no penetration while climbing" % route)
		if route == "bar":
			t.eq(stats.overs, 2, "bar: both the wall and the bar are climbed over")


## Irregular geometry: uneven crates, a sloped top and a diagonal ledge are climbed when a climb is offered.
func test_irregular_tops_are_climbable(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_h")
	var state := {"climbs": 0}
	var stats: Dictionary = await _run(scene, 1300, func(s, _i):
		if s.body.global_position.x > 62.0:
			return {"move": Vector2.ZERO, "yaw": RUN_YAW}
		if s.body.is_on_floor() and not s.traversal.busy() and _climb_ready(s, false):
			state.climbs += 1
			return _input(true)
		return _input())
	t.eq(stats.mantles, 3, "crates, sloped block and diagonal ledge are mantled (%s, %s)" % [stats.choices, stats.refusal])
	t.eq(stats.overlap_ticks, 0, "no penetration while climbing")


## One unpaced tick including the skeleton modifiers (hand IK), as the 4.0 lane trials do.
func _full_tick(scene, input: Dictionary) -> void:
	scene.simulate_tick(input, DT)
	scene._process(DT)
	scene.authored_visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


## Runs a lane pressing Space on the first tick each vault is offered; returns one record per vault shown.
func _vault_sequence(scene, landmark: String, ticks: int, sprint := false) -> Array:
	await _place(scene, landmark)
	var records := []
	var animator = scene.authored_animation
	var current := {}
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		var offered: bool = not scene.vault.opportunity.is_empty() and scene.vault.phase == scene.vault.Phase.IDLE
		var phase_before: float = animator.gait_phase()
		_full_tick(scene, _input(offered, false, sprint))
		if scene.vault.presenting and current.is_empty():
			var mirrored: bool = animator.vault_mirrored
			var entry: float = scene.vault_profile.mirror_entry_phase if mirrored else scene.vault_profile.entry_phase
			current = {"side": scene.vault.plan.get("side", 0), "mirrored": mirrored, "turn": scene.vault.plan.get("turn", 0.0),
				"speed": scene.vault.entry_speed, "height": scene.vault.plan.height, "phase_error": absf(wrapf(phase_before - entry, -0.5, 0.5)),
				"hand_error": 0.0, "pitch": 0.0, "x": scene.body.global_position.x}
		if not current.is_empty():
			current.pitch = maxf(current.pitch, animator.vault_pitch)
			if animator._arm.active and animator._arm.influence > 0.99:
				current.hand_error = maxf(current.hand_error, animator.hand_error)
			if not scene.vault.presenting:
				records.append(current)
				current = {}
	print("VARIANTS %s %s: %s" % [landmark, "sprint" if sprint else "run", JSON.stringify(records)])
	return records


## Vaults respond to each encounter: the support hand follows the face angle (left hand for a face that comes first on
## the left, the exact mirror of the authored vault), the body turns toward the face normal, a sprint vault leans into
## it, and on square faces the stride decides the lead foot, so consecutive vaults follow the gait.
func test_vaults_respond_to_angle_speed_and_stride(t) -> void:
	var scene = await _scene()
	t.ok(scene.vault_profile.has_mirror and scene.authored_animation.has_vault_mirror, "the mirrored vault is installed")
	t.ok(absf(wrapf(scene.vault_profile.mirror_entry_phase - scene.vault_profile.entry_phase - 0.5, -0.5, 0.5)) < 0.06,
		"the mirror enters on the other foot (entry %.3f, mirror %.3f)" % [scene.vault_profile.entry_phase, scene.vault_profile.mirror_entry_phase])
	var angled: Array = await _vault_sequence(scene, "lane_h_walls", 900)
	t.ok(angled.size() >= 2, "the angled walls are vaulted (%d)" % angled.size())
	if angled.size() >= 2:
		t.eq(int(angled[0].side) * int(angled[1].side), -1, "+25 and -25 degree faces are taken on opposite hands")
		t.ok(angled[0].mirrored != angled[1].mirrored, "and shown with opposite variants")
		t.ok(signf(angled[0].turn) == -signf(angled[1].turn) and absf(angled[0].turn) > 0.1, "the body turns toward each face (%.2f, %.2f rad)" % [angled[0].turn, angled[1].turn])
	for record in angled:
		t.ok(record.hand_error < 0.01, "planted %s hand on its contact point (%.4f m)" % ["left" if record.mirrored else "right", record.hand_error])
	for sprint in [false, true]:
		var rhythm: Array = await _vault_sequence(scene, "lane_d", 900 if not sprint else 600, sprint)
		t.ok(rhythm.size() >= 5, "lane D: the rhythm walls are vaulted (%d)" % rhythm.size())
		var lefts := 0
		for record in rhythm:
			# 6 m spacing leaves a sprint little room to steer the cadence (4.0 measured 0.05 on 9 m spacing).
			var bound := 0.12 if sprint else 0.06
			t.ok(record.phase_error < bound, "%s: takeoff on the chosen variant's entry foot (error %.3f)" % ["sprint" if sprint else "run", record.phase_error])
			t.ok(record.hand_error < 0.01, "planted hand on its contact point (%.4f m)" % record.hand_error)
			lefts += 1 if record.mirrored else 0
		t.ok(lefts > 0 and lefts < rhythm.size(), "%s: consecutive square walls are not all the same variant (%d of %d left-hand)" % ["sprint" if sprint else "run", lefts, rhythm.size()])
		if sprint:
			t.ok(rhythm[0].pitch > 0.05, "a sprint vault leans into the obstacle (%.3f rad)" % rhythm[0].pitch)
		else:
			t.ok(rhythm[0].pitch < 0.06, "a 6 m/s vault stays more upright (%.3f rad)" % rhythm[0].pitch)


## Movement Lab 5.2: a jump toward a ledge needs exactly one more press to get onto it, whenever that press comes
## (before contact, at contact, or while hanging). Jump distances 0.8-2.4 m before the 1.9 m face, press at the apex.
func test_one_press_after_a_jump_gets_onto_the_ledge(t) -> void:
	var scene = await _scene()
	for gap in [0.8, 1.4, 2.0, 2.4]:
		await _place(scene, "lane_e_ledge")
		var plan := {"step": 0, "presses": 0}
		var stats: Dictionary = await _run(scene, 420, func(s, _i):
			var x: float = s.body.global_position.x
			if plan.step == 0 and x > 58.5 - gap:
				plan.step = 1
				plan.presses += 1
				return _input(true)
			if plan.step == 1 and not s.body.core.grounded and s.body.velocity.y < 0.5:
				plan.step = 2
				plan.presses += 1
				return _input(true)
			return _input())
		t.ok(stats.max_y > 1.89, "jump %.1f m before the face + one press: on top (max y %.2f, %s, %s)" % [gap, stats.max_y, stats.choices, stats.refusal])
		t.eq(plan.presses, 2, "exactly two presses in total (jump, climb)")


## Standing jumps toward a high ledge (no run-up): one press after the jump still gets on top.
func test_one_press_after_a_standing_jump(t) -> void:
	var scene = await _scene()
	for gap in [0.5, 1.0]:
		await _place(scene, "lane_e_ledge", Vector3(58.5 - 0.35 - gap, 0.05, -31.0))
		var plan := {"step": 0, "presses": 0}
		var stats: Dictionary = await _run(scene, 420, func(s, i):
			if plan.step == 0 and i == 30:
				plan.step = 1
				plan.presses += 1
				return {"move": Vector2.ZERO, "yaw": RUN_YAW, "jump_pressed": true, "jump_held": true}
			if plan.step == 0:
				return {"move": Vector2.ZERO, "yaw": RUN_YAW}
			if plan.step == 1 and not s.body.core.grounded and s.body.velocity.y < 0.5:
				plan.step = 2
				plan.presses += 1
				return _input(true)
			return _input())
		t.ok(stats.max_y > 1.89, "standing jump %.1f m from the face + one press: on top (max y %.2f, %s, %s)" % [gap, stats.max_y, stats.choices, stats.refusal])
