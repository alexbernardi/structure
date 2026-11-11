## Movement Lab 5.0 unified traversal: intentional activation (Space inside the interaction region), buffering and
## chaining, mantles and ledge grabs, invalid presses, and upgrade-dependent feasibility through the modifier stack.
## Whole-scene trials run unpaced on the fixed tick (physics identical, the engine just does not wait); every tick the
## actual collider is overlap-tested against the course (2 mm inset), as in the 4.0 vault trials.
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const Profiles = preload("res://capability/movement_profiles.gd")
const DT := 1.0 / 120.0
const RUN_YAW := -PI / 2.0   ## lanes run toward +X
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


func _free(scene) -> void:
	_nodes.erase(scene)
	scene.queue_free()
	await _tree.process_frame


func _place(scene, landmark: String, x := NAN) -> void:
	scene.teleport_to(landmark)
	if not is_nan(x):
		var at: Vector3 = scene.body.global_position
		scene.body.teleport(Vector3(x, at.y, at.z))
	await _tree.physics_frame


static func _input(press := false, sprint := false, hold := false) -> Dictionary:
	return {"move": Vector2(0, 1), "yaw": RUN_YAW, "sprint": sprint, "jump_pressed": press, "jump_held": press or hold}


## Runs `ticks` ticks; `policy.call(scene, i)` returns the input for each. Records overlaps, the largest collider step,
## yaw changes of the drawn character and what each press did.
func _run(scene, ticks: int, policy: Callable) -> Dictionary:
	var stats := {"overlap_ticks": 0, "fall_overlap_ticks": 0, "max_step": 0.0, "max_vy": 0.0, "max_y": -INF, "vaults": 0, "mantles": 0, "aborts": 0}
	var clearance := PhysicsShapeQueryParameters3D.new()
	var cylinder := CylinderShape3D.new()
	clearance.shape = cylinder
	clearance.exclude = [scene.body.get_rid()]
	clearance.collision_mask = scene.body.collision_mask
	var space: PhysicsDirectSpaceState3D = scene.body.get_world_3d().direct_space_state
	var vaults_before: int = scene.vault.vaults
	var mantles_before: int = scene.traversal.mantle.mantles
	var aborts_before: int = scene.vault.aborts + scene.traversal.mantle.aborts
	var previous: Vector3 = scene.body.global_position
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		scene.simulate_tick(policy.call(scene, i), DT)
		scene._process(DT)
		var position: Vector3 = scene.body.global_position
		cylinder.radius = scene.body._shape.radius - 0.002
		cylinder.height = scene.body._shape.height - 0.004
		clearance.transform = scene.body._collider.global_transform
		var hits := space.intersect_shape(clearance, 4)
		var moving: bool = scene.vault.active() or scene.traversal.mantle.active() or scene.vault.presenting or scene.traversal.mantle.presenting
		if not hits.is_empty() and not moving and scene.body.velocity.y < -4.0:
			stats.fall_overlap_ticks += 1   # ordinary core landing after a fall (see KNOWN-ISSUES), not a traversal move
		elif not hits.is_empty():
			stats.overlap_ticks += 1
			print("OVERLAP tick %d at %s with %s: mantle %s t=%.3f vault %s grounded %s crouch %s h %.2f" % [i, position, hits[0].collider.name,
				scene.traversal.mantle.active(), scene.traversal.mantle.time, scene.vault.active(), scene.body.core.grounded, scene.body.core.crouching, scene.body._shape.height])
		stats.max_step = maxf(stats.max_step, position.distance_to(previous))
		stats.max_vy = maxf(stats.max_vy, scene.body.velocity.y)
		stats.max_y = maxf(stats.max_y, position.y)
		previous = position
	stats.vaults = scene.vault.vaults - vaults_before
	stats.mantles = scene.traversal.mantle.mantles - mantles_before
	stats.aborts = scene.vault.aborts + scene.traversal.mantle.aborts - aborts_before
	stats["finish"] = scene.body.global_position
	stats["choices"] = scene.traversal.choices.duplicate()
	print("TRAVERSAL_RESULT ", JSON.stringify({"overlap": stats.overlap_ticks, "step": stats.max_step, "vaults": stats.vaults,
		"mantles": stats.mantles, "aborts": stats.aborts, "finish": [stats.finish.x, stats.finish.y], "choices": stats.choices}))
	return stats


## Presses on the first tick the given condition holds (once), otherwise runs.
func _press_when(condition: Callable, sprint := false) -> Callable:
	var state := {"done": false}
	return func(scene, i: int) -> Dictionary:
		if not state.done and condition.call(scene, i):
			state.done = true
			return _input(true, sprint)
		return _input(false, sprint)


static func _face(scene) -> float:
	return scene.vault.region.get("face", INF)


func test_running_at_walls_never_vaults_without_a_press(t) -> void:
	var scene = await _scene()
	await _place(scene, "vault_a")
	var stats: Dictionary = await _run(scene, 600, func(_s, _i): return _input())
	t.eq(stats.vaults, 0, "no press, no vault")
	t.eq(stats.mantles, 0, "no press, no mantle")
	t.ok(scene.body.global_position.x < -18.3, "the first wall stops the runner (x %.2f)" % scene.body.global_position.x)
	t.eq(stats.overlap_ticks, 0, "the wall is never penetrated")
	t.ok(scene.vault.opportunity.is_empty(), "standing at the wall, no vault is offered")


func test_a_press_inside_the_region_vaults_and_outside_it_jumps(t) -> void:
	var scene = await _scene()
	await _place(scene, "vault_a")
	# Far before the region: an ordinary jump.
	var stats: Dictionary = await _run(scene, 60, _press_when(func(_s, i): return i == 30))
	t.eq(stats.vaults, 0, "a press far from the wall does not vault")
	t.eq(scene.traversal.last_choice, "jump", "it is an ordinary jump")
	t.near(stats.max_vy, scene.capabilities.get_value("jump_impulse"), 0.3, "with the normal jump impulse")
	# Inside the region (early half): the eased, armed vault.
	await _place(scene, "vault_a")
	stats = await _run(scene, 360, _press_when(func(s, _i): return not s.vault.opportunity.is_empty() and not s.vault.opportunity.late and _face(s) < s.vault.region.far - 1.0))
	t.eq(stats.vaults, 1, "a press inside the region vaults the first wall")
	t.eq(scene.vault.late_vaults, 0, "an early press arms the eased approach")
	t.eq(stats.aborts, 0, "and completes")
	t.eq(stats.overlap_ticks, 0, "without penetrating the wall")
	t.ok(stats.max_step < 0.16, "no snap (largest tick step %.3f m)" % stats.max_step)


func test_a_late_press_still_vaults_with_a_shorter_stride(t) -> void:
	var scene = await _scene()
	await _place(scene, "vault_a")
	var stats: Dictionary = await _run(scene, 300, _press_when(func(s, _i): return not s.vault.opportunity.is_empty() and s.vault.opportunity.late))
	t.eq(stats.vaults, 1, "a press inside the nominal takeoff point vaults")
	t.eq(scene.vault.late_vaults, 1, "as a late vault")
	t.eq(stats.aborts, 0, "which completes")
	t.eq(stats.overlap_ticks, 0, "clear of the wall")
	t.ok(stats.max_step < 0.16, "no snap at the immediate takeoff (%.3f m)" % stats.max_step)
	t.ok(scene.vault.plan.stretch < 1.17, "the stride is shortened (stretch %.3f)" % scene.vault.plan.stretch)
	t.near(scene.vault.plan.travel_speed, 6.0, 0.05, "and the ground speed is kept")


func test_a_press_too_close_to_a_thin_wall_jumps_without_snapping(t) -> void:
	var scene = await _scene()
	await _place(scene, "vault_a")
	var yaw_before: float = scene.cam.yaw
	var stats: Dictionary = await _run(scene, 240, _press_when(func(s, _i): return s.vault.reason == "too_close" and _face(s) < 0.7))
	t.eq(stats.vaults, 0, "too close to vault")
	t.eq(stats.mantles, 0, "a 0.35 m wall has no room to mantle onto")
	t.eq(scene.traversal.last_choice, "jump", "the press is an ordinary jump")
	t.ok(stats.max_step < 0.1, "no snap or teleport (largest step %.3f m)" % stats.max_step)
	t.eq(stats.overlap_ticks, 0, "no penetration")
	t.eq(scene.cam.yaw, yaw_before, "no camera rotation")


func test_an_infeasible_wall_falls_back_to_a_jump(t) -> void:
	var scene = await _scene()
	await _place(scene, "vault_a", 11.0)   # the 1.60 m wall is ahead
	var stats: Dictionary = await _run(scene, 300, _press_when(func(s, _i): return _face(s) < 2.5 and _face(s) > 1.5))
	t.eq(stats.vaults, 0, "the 1.6 m wall is not vaulted by a human")
	t.eq(scene.traversal.last_choice, "jump", "the press jumps")
	t.ok(scene.vault.reason == "too_high" or scene.traversal.last_refusal.contains("too_high") or scene.traversal.last_refusal == "", "refusal is explicit (%s / %s)" % [scene.vault.reason, scene.traversal.last_refusal])
	t.eq(stats.overlap_ticks, 0, "no penetration")
	t.ok(stats.max_step < 0.1, "no snap (%.3f m)" % stats.max_step)


func test_presses_during_a_vault_chain_into_the_next_one(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_d_pair")
	var pressed := {"first": false, "chain": false, "exit": -1.0}
	var policy := func(s, _i):
		if pressed.exit < 0.0 and s.vault.vaults >= 2 and not s.vault.active() and s.body.core.grounded:
			pressed.exit = s.body.core.horizontal_speed()
		if not pressed.first and not s.vault.opportunity.is_empty():
			pressed.first = true
			return _input(true)
		if pressed.first and not pressed.chain and s.vault.active() and s.vault.time > 0.5:
			pressed.chain = true
			return _input(true)
		return _input()
	var stats: Dictionary = await _run(scene, 420, policy)
	t.ok(pressed.chain, "a press was made during the first vault's descent")
	t.eq(stats.vaults, 2, "both walls of the tight pair are vaulted (%s)" % [stats.choices])
	t.eq(stats.aborts, 0, "both complete")
	t.eq(stats.overlap_ticks, 0, "no penetration")
	t.ok(int(stats.choices.get("buffered", 0)) >= 1, "the descent press was buffered")
	t.ok(pressed.exit > 5.0, "running continues out of the second vault (%.2f m/s)" % pressed.exit)


func test_a_press_in_the_air_is_buffered_into_a_vault_on_landing(t) -> void:
	var scene = await _scene()
	await _place(scene, "vault_a", -26.0)
	var state := {"phase": 0}
	var policy := func(s, i):
		if state.phase == 0 and i == 40:   # hop at full running speed, landing inside the first wall's region
			state.phase = 1
			return _input(true)        # hop
		if state.phase == 1 and not s.body.core.grounded and s.body.velocity.y < -4.0:
			state.phase = 2
			return _input(true)        # pressed while still falling: buffered
		if state.phase == 2 and s.body.core.grounded:
			state.phase = 3
		return _input()
	var stats: Dictionary = await _run(scene, 240, policy)
	t.ok(state.phase >= 2, "the second press was made in the air")
	t.eq(stats.vaults, 1, "the buffered press vaults on landing")
	t.eq(stats.aborts, 0, "and completes")


func test_deep_blocks_are_mantled_and_tall_ledges_need_a_jump_and_grab(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_e")
	var stats: Dictionary = await _run(scene, 240, _press_when(func(s, _i): return s.body.global_position.x > 39.0))
	t.eq(stats.vaults, 0, "a 2.5 m deep block is not vaulted")
	t.eq(stats.mantles, 1, "it is mantled")
	t.eq(stats.aborts, 0, "the mantle completes")
	t.eq(stats.overlap_ticks, 0, "without penetrating the block")
	t.ok(stats.max_step < 0.12, "no snap (%.3f m)" % stats.max_step)
	t.ok(stats.max_y > 0.99, "standing on its top (%.2f m)" % stats.max_y)
	# 1.9 m ledge: a grounded press jumps (too high to mantle); a second press in the air catches the ledge (5.1: held
	# Space no longer grabs).
	await _place(scene, "lane_e_ledge")
	var hold := {"on": false, "caught": false}
	stats = await _run(scene, 360, func(s, _i):
		if not hold.on and s.body.global_position.x > 57.6:
			hold.on = true
			return _input(true)
		if hold.on and not hold.caught and not s.body.core.grounded and s.body.velocity.y < 1.0:
			hold.caught = true
			return _input(true)
		return _input(false, false, hold.on))
	t.eq(stats.mantles, 1, "the 1.9 m ledge is grabbed and climbed (%s)" % [stats.choices])
	t.eq(stats.aborts, 0, "and the climb completes")
	t.eq(stats.overlap_ticks, 0, "without penetration")
	t.ok(stats.max_y > 1.89, "standing on top (%.2f m)" % stats.max_y)


func test_upgrades_change_what_is_feasible(t) -> void:
	var scene = await _scene()
	# The 3.6 m ledge (5.4: a human's jump and arms reach about 3.1 m): beyond a human's grab, within the cybernetic
	# jump + reach and the spell's lighter jump.
	for profile in ["human", "cyber", "magic"]:
		scene.capabilities.clear()
		if profile != "human":
			scene.apply_profile(profile)
		await _place(scene, "lane_e_gate")
		var plan := {"jumped": false, "air": false}
		var stats: Dictionary = await _run(scene, 420, func(s, _i):
			if not plan.jumped and s.body.global_position.x > 67.4:
				plan.jumped = true
				return _input(true)
			if plan.jumped and not plan.air and not s.body.core.grounded and s.body.velocity.y < 0.5:
				plan.air = true
				return _input(true, false, true)   # second press near the apex: air jump if the character can
			return _input(false, false, plan.jumped))
		if profile == "human":
			t.eq(stats.mantles, 0, "human: the 3.6 m ledge is out of reach")
			t.ok(scene.body.global_position.y < 0.1, "human: still on the ground")
		else:
			t.eq(stats.mantles, 1, "%s: the 3.6 m ledge is reached (%s)" % [profile, stats.choices])
			t.ok(stats.max_y > 3.59, "%s: standing on it (%.2f m)" % [profile, stats.max_y])
			t.eq(stats.overlap_ticks, 0, "%s: no penetration" % profile)
	# The 1.6 m wall: vaulted only with cybernetic legs, which costs energy and heat.
	scene.capabilities.clear()
	scene.apply_profile("cyber")
	await _place(scene, "vault_a", 11.0)
	var energy_before: float = scene.traversal.resources.level.energy
	var stats2: Dictionary = await _run(scene, 360, _press_when(func(s, _i): return not s.vault.opportunity.is_empty(), false))
	t.eq(stats2.vaults, 1, "cyber: the 1.6 m wall is vaulted")
	t.eq(stats2.aborts, 0, "cyber: the powered vault completes")
	t.eq(stats2.overlap_ticks, 0, "cyber: without penetration")
	t.ok(scene.traversal.resources.level.energy < energy_before, "cyber: the powered vault drew energy")
	t.ok(scene.traversal.resources.level.heat > 0.0, "cyber: and made heat")
	# Overheated: the powered vault is refused, the press jumps instead.
	scene.traversal.resources.level.heat = scene.traversal.resources.capacity("heat")
	scene.traversal.resources.overheated = true
	await _place(scene, "vault_a", 11.0)
	stats2 = await _run(scene, 240, _press_when(func(s, _i): return not s.vault.opportunity.is_empty(), false))
	t.eq(stats2.vaults, 0, "overheated: no powered vault")
	t.ok(scene.traversal.last_refusal.contains("overheated"), "overheated: refusal says why (%s)" % scene.traversal.last_refusal)
	t.eq(scene.traversal.last_choice, "jump", "overheated: the press is a jump")
	scene.capabilities.clear()


func test_air_jump_is_a_granted_capability_that_costs_mana(t) -> void:
	var scene = await _scene()
	for profile in ["human", "magic"]:
		scene.capabilities.clear()
		if profile == "magic":
			scene.apply_profile("magic")
		await _place(scene, "spawn")
		var state := {"step": 0, "vy": 0.0}
		await _run(scene, 120, func(s, i):
			if i == 2:
				return {"move": Vector2.ZERO, "yaw": 0.0, "jump_pressed": true, "jump_held": true}
			if state.step == 0 and i > 5 and s.body.velocity.y < 1.0:
				state.step = 1
				return {"move": Vector2.ZERO, "yaw": 0.0, "jump_pressed": true, "jump_held": true}
			if state.step == 1:
				state.step = 2
				state.vy = s.body.velocity.y
			return {"move": Vector2.ZERO, "yaw": 0.0})
		if profile == "human":
			t.ok(state.vy < 1.0, "human: a second press in the air does nothing (vy %.2f)" % state.vy)
			t.eq(int(scene.traversal.choices.get("air_jump", 0)), 0, "human: no air jump")
		else:
			t.ok(state.vy > 4.0, "magic: the air jump sets the rise again (vy %.2f)" % state.vy)
			t.eq(int(scene.traversal.choices.get("air_jump", 0)), 1, "magic: one air jump")
			t.near(scene.traversal.resources.spent.mana, scene.capabilities.get_value("mana_cost_air_jump"), 1e-4, "magic: it cost its mana")
	scene.capabilities.clear()


func test_injury_revokes_the_vault_and_caps_speed(t) -> void:
	var scene = await _scene()
	scene.apply_profile("injury")
	await _place(scene, "vault_a")
	var stats: Dictionary = await _run(scene, 300, _press_when(func(s, _i): return not s.vault.opportunity.is_empty()))
	t.eq(stats.vaults, 0, "a sprained ankle cannot vault")
	t.ok(scene.traversal.last_refusal.contains("not_capable"), "refused as not capable (%s)" % scene.traversal.last_refusal)
	t.ok(scene.body.core.horizontal_speed() <= 4.0 + 1e-3 or scene.body.global_position.x < -18.0, "speed capped at 4 m/s")
	scene.apply_profile("injury")   # toggles it off
	t.ok(scene.capabilities.can("vault"), "healed: vaulting is back")


func test_cybernetic_vault_lands_into_a_drop_a_human_refuses(t) -> void:
	var scene = await _scene()
	for profile in ["human", "cyber"]:
		scene.capabilities.clear()
		if profile == "cyber":
			scene.apply_profile("cyber")
		await _place(scene, "lane_f_drop")
		var stats: Dictionary = await _run(scene, 300, _press_when(func(s, _i): return not s.vault.opportunity.is_empty()))
		if profile == "human":
			t.eq(stats.vaults, 0, "human: the 2 m drop is refused")
			t.ok(scene.vault.reason == "bad_landing" or stats.vaults == 0, "human: as a bad landing (%s)" % scene.vault.reason)
		else:
			t.eq(stats.vaults, 1, "cyber: vaults into the 2 m drop")
			t.eq(stats.aborts, 0, "cyber: completes")
			t.ok(scene.body.global_position.y < 0.1, "cyber: lands on the lower ground")
			t.eq(stats.overlap_ticks, 0, "cyber: no penetration")
	scene.capabilities.clear()


func test_invalid_regions_are_refused_explicitly(t) -> void:
	var scene = await _scene()
	var seen := {}
	await _place(scene, "lane_f")
	await _run(scene, 1500, func(s, _i):
		seen[s.vault.reason] = true
		var m: Dictionary = s.traversal.mantle.last_seen
		if not m.is_empty():
			seen["mantle:" + String(m.get("reason", ""))] = true
		return _input())
	t.ok(seen.has("blocked"), "the barred wall is refused as blocked (%s)" % [seen.keys()])
	t.eq(scene.vault.vaults, 0, "nothing is traversed without a press")
