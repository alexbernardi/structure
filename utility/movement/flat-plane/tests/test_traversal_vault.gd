## Movement Lab 4.0 authored vault. Pure planning and measurement are checked against independent brute-force
## references; whole-scene trials run the vault course (lanes A/B/C) unpaced (the physics is identical, the engine just
## does not wait in real time; skeleton modifiers are forced every tick), and one trial is paced by the engine so the
## per-frame contact IK is measured exactly as it is presented live.
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const Visual = preload("res://character/authored_mannequin.gd")
const Profile = preload("res://traversal/vault_profile.gd")
const Planner = preload("res://traversal/vault_planner.gd")
const Clip = preload("res://traversal/vault_clip.gd")
const DT := 1.0 / 120.0
const RUN_YAW := -PI / 2.0   ## the vault lanes run toward +X
var _tree: SceneTree
var _nodes: Array[Node] = []


func before_each() -> void:
	_tree = Engine.get_main_loop()


func after_each() -> void:
	for node in _nodes:
		node.queue_free()
	_nodes.clear()
	await _tree.process_frame


func _profile():
	var visual = Visual.new()
	_tree.root.add_child(visual)
	_nodes.append(visual)
	await _tree.process_frame
	var profile = Profile.new()
	profile.build(visual)
	return profile


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


func _place(scene, lane: String, x := NAN) -> void:
	scene.teleport_to("vault_" + lane)
	if not is_nan(x):
		var at: Vector3 = scene.body.global_position
		scene.body.teleport(Vector3(x, at.y, at.z))
	await _tree.physics_frame


## Scenes share the root world's physics space: one must be gone before the next is built.
func _free(scene) -> void:
	_nodes.erase(scene)
	scene.queue_free()
	await _tree.process_frame


func _run_input(sprint := false) -> Dictionary:
	return {"move": Vector2(0, 1), "yaw": RUN_YAW, "sprint": sprint}


## One unpaced tick: physics, the presented frame, and the skeleton modifiers (deferred to the next idle otherwise).
func _tick(scene, input: Dictionary) -> void:
	scene.simulate_tick(input, DT)
	scene._process(DT)
	scene.authored_visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


func _trial(scene, lane: String, ticks: int, sprint := false, start_x := NAN) -> Dictionary:
	await _place(scene, lane, start_x)
	var stats := {"takeoffs": [], "hand_error": 0.0, "max_step": 0.0, "reasons": {}, "states": {}, "crouch": 0,
		"lane": lane, "sprint": sprint, "run_speed": scene.params.get_value("max_ground_speed"),
		"start_x": scene.body.position.x, "ticks": ticks, "overlap_ticks": 0, "contacts": {}}
	var clearance := PhysicsShapeQueryParameters3D.new()
	var cylinder := CylinderShape3D.new()
	clearance.shape = cylinder
	clearance.exclude = [scene.body.get_rid()]
	clearance.collision_mask = scene.body.collision_mask
	var space: PhysicsDirectSpaceState3D = scene.body.get_world_3d().direct_space_state
	var vaults_before: int = scene.vault.vaults
	var aborts_before: int = scene.vault.aborts
	var previous: Vector3 = scene.body.global_position
	var was_active := false
	var animator = scene.authored_animation
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		_tick(scene, _run_input(sprint))
		if i == 0:
			stats["teleport_speed"] = animator.measured_speed
		var position: Vector3 = scene.body.global_position
		# Ignore contact tolerance, not penetrations: test the actual collider with a 2 mm inset.
		cylinder.radius = scene.body._shape.radius - 0.002
		cylinder.height = scene.body._shape.height - 0.004
		clearance.transform = scene.body._collider.global_transform
		if not space.intersect_shape(clearance, 1).is_empty():
			stats.overlap_ticks += 1
		for contact in scene.body.get_slide_collision_count():
			var collider: Object = scene.body.get_slide_collision(contact).get_collider()
			if collider is Node:
				var name: String = collider.name
				stats.contacts[name] = stats.contacts.get(name, 0) + 1
		stats.max_step = maxf(stats.max_step, position.distance_to(previous))
		previous = position
		if scene.vault.active() and not was_active:
			stats.takeoffs.append(animator.gait_phase())
		was_active = scene.vault.active()
		stats.reasons[scene.vault.reason] = true
		stats.states[animator.model.state] = true
		if animator.model.state == "Crouch":
			stats.crouch += 1
		if scene.vault.presenting and animator._arm.active and animator._arm.influence > 0.99:
			stats.hand_error = maxf(stats.hand_error, animator.hand_error)
	stats["vaults"] = scene.vault.vaults - vaults_before
	stats["aborts"] = scene.vault.aborts - aborts_before
	var finish: Vector3 = scene.body.global_position
	stats["finish"] = [finish.x, finish.y, finish.z]
	stats["exit_speed"] = scene.body.core.horizontal_speed()
	print("VAULT_LANE_RESULT ", JSON.stringify(stats))
	return stats


## Lowest body surface per sample in front of, over and beyond a slab, by dense sampling of every capsule (a sphere
## swept along its axis) with the same rounded-corner overhang rule as zones().
static func _sampled_zones(profile, stretch: float, face: float, depth: float, slope: float, steps: int) -> Array:
	var lo := face - 0.03
	var hi := face + depth + 0.03
	var skew := sqrt(1.0 + slope * slope)
	var result := [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for i in profile.sample_count():
		var time: float = profile.times[i]
		var travel := Clip.travel(time, stretch)
		var skip: int = Profile.SUPPORT_SEGMENT if time > Profile.SUPPORT_WINDOW[0] and time < Profile.SUPPORT_WINDOW[1] else -1
		var low := [INF, INF, INF]
		var ends: PackedVector3Array = profile.segments[i]
		for s in profile.radii.size():
			if s == skip:
				continue
			var r: float = profile.radii[s]
			for k in steps + 1:
				var p: Vector3 = ends[s * 2].lerp(ends[s * 2 + 1], float(k) / steps)
				var g := p.z + travel - slope * p.x
				if g <= lo:
					low[0] = minf(low[0], p.y - r)
				if g >= hi:
					low[2] = minf(low[2], p.y - r)
				var outside := maxf(maxf(lo - g, g - hi), 0.0) / skew
				if outside <= r:
					low[1] = minf(low[1], p.y - sqrt(maxf(r * r - outside * outside, 0.0)))
		for p in profile.points[i]:
			var g: float = p.z + travel - slope * p.x
			if g <= lo:
				low[0] = minf(low[0], p.y)
			if g >= hi:
				low[2] = minf(low[2], p.y)
			if g >= lo and g <= hi:
				low[1] = minf(low[1], p.y)
		for zone in 3:
			result[zone].append(low[zone])
	return result


static func _obstacle(speed: float, height: float, depth: float, angle: float, landing := 0.0) -> Dictionary:
	return {"distance": Planner.timing(speed).takeoff, "height": height, "depth": depth, "slope": tan(angle), "angle": angle, "landing": landing}


func test_vault_timing_follows_the_approach_with_bounded_rate_and_stretch(t) -> void:
	var previous := {}
	for step in 49:
		var speed := 2.0 + step * 0.25
		var timed := Planner.timing(speed)
		t.ok(timed.rate >= Planner.MIN_RATE - 1e-6 and timed.rate <= Planner.MAX_RATE + 1e-6, "bounded playback rate at %.2f m/s" % speed)
		t.ok(timed.stretch >= Planner.MIN_STRETCH - 1e-6 and timed.stretch <= Planner.MAX_STRETCH + 1e-6, "bounded stride stretch at %.2f m/s" % speed)
		t.near(timed.travel_speed, clampf(speed, Planner.MIN_TRAVEL, Planner.MAX_TRAVEL), 0.001, "vault ground speed is the approach speed within range")
		t.near(timed.duration, Clip.LENGTH / timed.rate, 1e-6, "duration is the clip at its rate")
		t.near(timed.takeoff, Clip.face_distance(timed.stretch), 1e-6, "takeoff distance follows the stretch")
		if not previous.is_empty():
			t.ok(timed.takeoff >= previous.takeoff - 1e-6, "takeoff distance never shrinks with speed")
			t.ok(absf(timed.rate - previous.rate) < 0.06 and absf(timed.stretch - previous.stretch) < 0.06, "no jump in rate or stretch at %.2f m/s" % speed)
		previous = timed


func test_screen_applies_each_geometric_limit(t) -> void:
	var base := _obstacle(6.0, 1.0, 0.4, 0.0)
	t.eq(Planner.screen(base), "", "an in-range wall passes")
	for limit in [["height", 0.6, ""], ["height", 1.25, ""], ["height", 0.59, "too_low"], ["height", 1.26, "too_high"],
			["angle", deg_to_rad(34.0), ""], ["angle", deg_to_rad(-36.0), "too_angled"], ["depth", 0.9, ""], ["depth", 0.91, "too_deep"],
			["landing", -0.6, ""], ["landing", -0.61, "bad_landing"], ["landing", 0.31, "bad_landing"]]:
		var obstacle := base.duplicate()
		obstacle[limit[0]] = limit[1]
		t.eq(Planner.screen(obstacle), limit[2], "%s %.3f" % [limit[0], limit[1]])


func test_zones_match_dense_capsule_sampling(t) -> void:
	var profile = await _profile()
	t.ok(profile.valid, "the authored vault clip is installed and measured")
	t.eq(profile.sample_count(), int(round(Clip.LENGTH / Profile.STEP)) + 1, "a sample every 120 Hz tick of the clip")
	for config in [[1.0, 1.2, 0.3, 0.0], [0.85, 1.1, 0.6, 0.0], [1.3, 1.5, 0.9, 0.0], [1.0, 1.25, 0.3, 0.364], [1.15, 1.3, 0.2, -0.364], [1.3, 1.45, 0.6, 0.7]]:
		var zones: Array = profile.zones(config[0], config[1], config[2], config[3])
		var sampled: Array = _sampled_zones(profile, config[0], config[1], config[2], config[3], 96)
		var lower := 0.0
		var higher := 0.0
		var mismatched := 0
		for zone in 3:
			for i in profile.sample_count():
				var exact: float = zones[zone][i]
				var dense: float = sampled[zone][i]
				if is_finite(exact) != is_finite(dense):
					mismatched += 1
				elif is_finite(exact):
					lower = maxf(lower, dense - exact)
					higher = maxf(higher, exact - dense)
		t.eq(mismatched, 0, "the same samples have surfaces in each zone %s" % [config])
		t.ok(lower < 0.003, "exact clipping only finds lower points between dense samples %s: %.4f m" % [config, lower])
		t.ok(higher < 0.004, "the rounded-corner overhang is within 4 mm of dense sampling %s: %.4f m" % [config, higher])


func test_plans_keep_the_whole_warped_body_clear_and_the_hand_in_reach(t) -> void:
	var profile = await _profile()
	var reach: float = profile.arm_length * Planner.REACH
	var planned := 0
	var rejected := {}
	for speed in [3.0, 6.0, 12.0]:
		for height in [0.6, 1.0, 1.25]:
			for depth in [0.2, 0.6]:
				for angle in [0.0, deg_to_rad(20.0), deg_to_rad(-20.0)]:
					var obstacle := _obstacle(speed, height, depth, angle)
					var plan: Dictionary = Planner.new().plan(profile, obstacle, speed, 0.6)
					if not plan.ok:
						rejected[plan.reason] = rejected.get(plan.reason, 0) + 1
						continue
					planned += 1
					var label := "%.0f m/s %.2f m high %.1f m deep %.0f deg" % [speed, height, depth, rad_to_deg(angle)]
					t.ok(plan.warp >= Planner.WARP_RANGE[0] and plan.warp <= Planner.WARP_RANGE[1], "bounded body warp " + label)
					t.ok(plan.dip >= 0.0 and plan.dip <= Planner.MAX_DIP + 1e-6, "bounded support dip " + label)
					t.ok(plan.lean >= 0.0 and plan.lean <= Planner.MAX_LEAN + 1e-6, "bounded torso lean " + label)
					t.ok(plan.hand_gap < 0.01, "the support hand reaches the top " + label + ": gap %.4f m" % plan.hand_gap)
					t.ok(plan.hand_off - plan.hand_on >= Planner.MIN_HOLD - 1e-5, "a real plant, not a tap " + label + ": %.3f s" % (plan.hand_off - plan.hand_on))
					t.near(plan.crest, height + Planner.CREST, 1e-6, "collider crests the top " + label)
					var point: Vector3 = plan.hand_point
					var near: float = plan.face + point.x * plan.slope
					t.near(point.y, height + Clip.PALM, 1e-5, "hand contact on the top " + label)
					t.ok(point.z >= near + Planner.HAND_INSET - 1e-5 and point.z <= near + depth - Planner.HAND_INSET + 1e-5, "hand inside the top's edges " + label)
					var sampled: Array = _sampled_zones(profile, plan.stretch, plan.face, depth, plan.slope, 32)
					var worst := INF
					var worst_reach := 0.0
					for i in profile.sample_count():
						var time: float = profile.times[i]
						var lift := Planner.visual_height(plan, time)
						for need in [[sampled[0][i], -Planner.GROUND_TOLERANCE], [sampled[1][i], height + Planner.CLEARANCE], [sampled[2][i], -Planner.GROUND_TOLERANCE]]:
							if is_finite(need[0]):
								worst = minf(worst, need[0] + lift - need[1])
						if Planner.hand_weight(plan, time) >= 0.999:
							var shoulder: Vector3 = profile.leaned_shoulder(i, plan.lean) + Vector3(0, lift, Planner.travel(plan, time))
							worst_reach = maxf(worst_reach, shoulder.distance_to(point) - reach - maxf(plan.hand_gap, 0.0))
					t.ok(worst > -0.01, "every limb clears the top and the ground through the whole clip " + label + ": %.4f m" % worst)
					t.ok(worst_reach < 0.002, "the planted hand is within the arm's reach " + label + ": %.4f m" % worst_reach)
	t.ok(planned >= 40, "the vaultable range plans (%d of 54; rejected %s)" % [planned, rejected])
	for reason in rejected:
		t.ok(reason in ["too_high", "too_deep"], "only clearance limits reject in-range walls: " + reason)


func test_planner_rejections_and_the_remembered_plan(t) -> void:
	var profile = await _profile()
	var planner := Planner.new()
	t.eq(planner.plan(Profile.new(), _obstacle(6.0, 1.0, 0.3, 0.0), 6.0, 0.6).reason, "no_clip", "an unmeasured clip never plans")
	t.eq(planner.plan(profile, _obstacle(6.0, 1.0, 0.3, 0.0), Planner.MIN_ENTRY_SPEED - 0.01, 0.6).reason, "too_slow", "slow approaches never vault")
	var early := _obstacle(6.0, 1.0, 0.3, 0.0)
	early.distance += Planner.TAKEOFF_TOLERANCE + 0.05
	t.eq(planner.plan(profile, early, 6.0, 0.6).reason, "off_takeoff", "the face must be at the takeoff distance")
	t.eq(planner.plan(profile, _obstacle(6.0, 1.4, 0.3, 0.0), 6.0, 0.6).reason, "too_high", "screened before planning")
	var far: Dictionary = planner.plan(profile, _obstacle(12.0, 1.0, 0.2, deg_to_rad(-34.0)), 12.0, 0.6)
	t.eq(far.reason, "out_of_reach", "a top the support hand cannot touch is refused rather than vaulted with a hovering hand")
	t.ok(far.get("hand_gap", 0.0) > Planner.MAX_HAND_GAP, "the refusal reports the unmet reach")
	var obstacle := _obstacle(6.0, 0.95, 0.3, deg_to_rad(10.0))
	var first: Dictionary = planner.plan(profile, obstacle, 6.0, 0.6)
	t.ok(first.ok, "a lane A wall plans")
	first.warp = 99.0
	var again: Dictionary = planner.plan(profile, obstacle, 6.0, 0.6)
	t.ok(again.warp != 99.0, "the remembered plan is handed out as a copy")
	t.eq(again, Planner.new().plan(profile, obstacle, 6.0, 0.6), "the remembered plan equals a fresh one")
	for change in [["height", 1.1], ["depth", 0.5], ["slope", 0.0], ["landing", -0.2]]:
		var other := obstacle.duplicate()
		other[change[0]] = change[1]
		t.eq(planner.plan(profile, other, 6.0, 0.6), Planner.new().plan(profile, other, 6.0, 0.6), "a changed %s is planned afresh" % change[0])
	var faster: Dictionary = planner.plan(profile, _obstacle(8.0, 0.95, 0.3, 0.0), 8.0, 0.6)
	t.eq(faster, Planner.new().plan(profile, _obstacle(8.0, 0.95, 0.3, 0.0), 8.0, 0.6), "a changed approach speed is planned afresh")
	t.near(planner.plan(profile, obstacle, 6.0, 1.0).exit_speed, 6.0, 1e-4, "full momentum continuity keeps the approach speed")


func test_lane_a_vaults_every_vaultable_wall_on_the_authored_foot(t) -> void:
	var scene = await _scene()
	t.ok(scene.vault.enabled() and scene.authored_animation.has_vault, "traversal on with the authored vault installed")
	var entry: float = scene.vault_profile.entry_phase
	var spine: int = scene.authored_visual.bone_index.Spine
	for trial in [["6 m/s", 1080, false, 0.0], ["sprint 12 m/s", 840, true, 0.0], ["3 m/s", 2160, false, 3.0]]:
		if trial[3] > 0.0:
			scene.body.params.set_value("max_ground_speed", trial[3])
		var stats: Dictionary = await _trial(scene, "a", trial[1], trial[2])
		t.eq(stats.vaults, 4, trial[0] + ": the 0.80, 0.95, 1.10 and 1.25 m walls are vaulted")
		t.eq(stats.aborts, 0, trial[0] + ": no vault aborted")
		t.eq(stats.teleport_speed, 0.0, trial[0] + ": landmark teleport distance never becomes measured running speed")
		t.eq(stats.overlap_ticks, 0, trial[0] + ": the actual collider never penetrates course geometry by 2 mm")
		t.ok(stats.reasons.has("too_high"), trial[0] + ": the 1.60 m wall is rejected")
		t.ok(stats.finish[0] > 17.4 and stats.finish[0] < 17.48, trial[0] + ": stopped against, not through, the tall wall")
		t.near(stats.exit_speed, 0.0, 0.01, trial[0] + ": the run has actually stopped by the end of the trial")
		t.eq(stats.takeoffs.size(), 4, trial[0] + ": four takeoffs")
		for k in stats.takeoffs.size():
			var phase: float = stats.takeoffs[k]
			t.ok(absf(wrapf(phase - entry, -0.5, 0.5)) < 0.05, trial[0] + ": takeoff %d on the vault's entry foot (run phase %.3f, entry %.3f)" % [k, phase, entry])
		t.ok(stats.hand_error < 0.01, trial[0] + ": planted hand on its contact point (%.4f m)" % stats.hand_error)
		t.ok(stats.max_step < 0.16, trial[0] + ": no collider jump (largest tick step %.3f m)" % stats.max_step)
		t.eq(stats.crouch, 0, trial[0] + ": the collider's clearance crouch is never shown")
		var residue: float = scene.authored_visual.skeleton.get_bone_pose_rotation(spine).angle_to(scene.authored_animation._spine_base)
		t.ok(residue < 0.001, trial[0] + ": the support lean leaves no Spine residue (%.5f rad)" % residue)
		print("Lane A %s: takeoff phases %s, hand error %.4f m, largest step %.3f m" % [trial[0], stats.takeoffs, stats.hand_error, stats.max_step])


func test_lanes_b_and_c_vault_the_angled_and_deck_walls_only(t) -> void:
	var scene = await _scene()
	var stats: Dictionary = await _trial(scene, "b", 600)
	t.eq(stats.vaults, 1, "lane B: the 20 degree wall is vaulted")
	t.ok(stats.reasons.has("too_angled"), "lane B: the 40 degree wall is refused")
	t.eq(stats.aborts, 0, "lane B: no abort")
	t.eq(stats.overlap_ticks, 0, "lane B: no collider penetration")
	t.ok(stats.contacts.has("VaultB40"), "lane B: the rejected angled wall still collides with the body")
	t.ok(stats.finish[2] > -29.0, "lane B: ordinary collision slides the runner off-line, not through the angled wall")
	t.ok(stats.hand_error < 0.01, "lane B: planted hand on its contact point (%.4f m)" % stats.hand_error)
	stats = await _trial(scene, "c", 900)
	t.eq(stats.vaults, 2, "lane C: both deck walls are vaulted")
	t.eq(stats.aborts, 0, "lane C: no abort")
	t.eq(stats.overlap_ticks, 0, "lane C: no collider penetration on the raised/stepped landing")
	t.near(stats.exit_speed, 6.0, 0.01, "lane C: running continues after landing")
	t.ok(stats.hand_error < 0.01, "lane C: planted hand on its contact point (%.4f m)" % stats.hand_error)
	t.ok(stats.max_step < 0.25, "lane C: no collider jump beyond the deck step-up (%.3f m)" % stats.max_step)


func test_lane_b_depth_walls_are_measured_and_the_thick_wall_stops_the_runner(t) -> void:
	var scene = await _scene()
	var stats := await _trial(scene, "b", 600, false, -5.0)
	t.eq(stats.vaults, 1, "the 0.6 m depth wall is vaulted")
	t.eq(stats.aborts, 0, "the accepted vault completes")
	t.ok(stats.reasons.has("too_deep"), "the 1.4 m depth wall is refused")
	t.eq(stats.overlap_ticks, 0, "no collider penetration in either wall")
	t.ok(stats.finish[0] > 7.9 and stats.finish[0] < 7.96, "the thick wall stops the runner on its near side")
	t.near(stats.exit_speed, 0.0, 0.01, "the refused wall actually stops movement")


func test_blocked_vault_clearance_is_refused_before_takeoff(t) -> void:
	var scene = await _scene()
	scene.world._box(Vector3(-18, 1.9, -25), Vector3(5, 0.2, 3), Vector3.ZERO, null, "VaultCeiling")
	await _tree.physics_frame
	var stats := await _trial(scene, "a", 480)
	t.eq(stats.vaults, 0, "the low ceiling prevents committing to a blocked vault path")
	t.ok(stats.reasons.has("blocked"), "clearance rejection is explicit")
	t.eq(stats.overlap_ticks, 0, "the body stays out of the wall and ceiling")
	t.ok(stats.finish[0] < -18.5, "the obstacle blocks movement rather than teleporting the body")
	t.near(stats.exit_speed, 0.0, 0.01, "the runner stops safely")


func _arm(scene) -> bool:
	await _place(scene, "a")
	for i in 240:
		_tick(scene, _run_input())
		if scene.vault.armed():
			return true
	return false


func test_interrupted_approaches_disarm_and_a_jump_cannot_break_the_vault(t) -> void:
	var scene = await _scene()
	t.ok(await _arm(scene), "running at the first wall arms the vault")
	for i in 150:
		_tick(scene, {"move": Vector2.ZERO, "yaw": RUN_YAW})
	t.ok(not scene.vault.armed() and not scene.vault.active(), "releasing the stick disarms")
	t.eq(scene.vault.vaults, 0, "no vault without the wish to go on")
	t.ok(await _arm(scene), "re-armed")
	for i in 3:
		_tick(scene, {"move": Vector2(0, 1), "yaw": 0.0})
	t.ok(not scene.vault.armed(), "turning away disarms")
	for i in 120:
		_tick(scene, {"move": Vector2.ZERO, "yaw": 0.0})
	t.eq(scene.vault.vaults, 0, "no vault after turning away")
	t.ok(await _arm(scene), "re-armed")
	var input := _run_input()
	input.merge({"jump_pressed": true, "jump_held": true}, true)
	_tick(scene, input)
	_tick(scene, _run_input())
	t.ok(scene.body.core.grounded or scene.vault.active(), "a jump press while committed does not leave the ground on its own")
	t.ok(scene.body.velocity.y < 0.5 or scene.vault.active(), "no jump impulse while committed")
	for i in 120:
		_tick(scene, _run_input())
	t.eq(scene.vault.vaults, 1, "the committed vault still happens")
	t.eq(scene.vault.aborts, 0, "and completes")


func test_missing_clip_or_traversal_off_falls_back_to_running(t) -> void:
	var scene = await _scene({"no-traversal-clip": "true"})
	t.ok(not scene.vault_profile.valid and not scene.authored_animation.has_vault, "no vault clip measured or in the graph")
	t.ok(not scene.vault.enabled(), "traversal unavailable")
	t.ok("unavailable" in scene.traversal_status(), "the readout says why: " + scene.traversal_status())
	var stats: Dictionary = await _trial(scene, "a", 300)
	t.eq(stats.vaults, 0, "never vaults without the clip")
	t.ok(stats.states.has("Run"), "authored running still works (states %s)" % [stats.states.keys()])
	t.ok(scene.body.global_position.x < -18.0, "the first wall stops the run (x %.2f)" % scene.body.global_position.x)
	await _free(scene)
	var off = await _scene({"no-traversal": "true"})
	t.ok(off.vault_profile.valid and not off.vault.enabled(), "the switch turns an installed vault off")
	t.ok("off" in off.traversal_status(), "the readout says traversal is off: " + off.traversal_status())


## Playtest shortcuts: --landmark starts on a vault lane, T / Shift+T step through the landmarks.
func test_landmark_option_and_keys_reach_the_vault_lanes(t) -> void:
	var scene = await _scene({"landmark": "vault_b"})
	var at := func(landmark: String) -> bool:   # horizontally: the body may have settled for a tick
		var target: Vector3 = scene.world.landmarks[landmark]
		var p: Vector3 = scene.body.global_position
		return Vector2(p.x - target.x, p.z - target.z).length() < 1e-4
	t.ok(at.call("vault_b"), "starts on lane B (%s)" % scene.body.global_position)
	t.near(scene.cam.yaw, RUN_YAW, 1e-6, "the camera faces down the lane")
	var names: Array[String] = scene.landmark_names()
	var index := names.find("vault_b")
	var key := InputEventKey.new()
	key.keycode = KEY_T
	key.pressed = true
	scene._unhandled_input(key)
	var after: String = names[(index + 1) % names.size()]
	t.ok(at.call(after), "T moves to the next landmark (%s)" % after)
	key.shift_pressed = true
	scene._unhandled_input(key)
	t.ok(at.call("vault_b"), "Shift+T moves back")
	t.ok(not scene.teleport_to("nowhere"), "an unknown landmark is refused")
	t.ok(at.call("vault_b"), "and the body stays put")


func test_traversal_never_changes_physics_without_a_vault(t) -> void:
	var paths := []
	var seen := {}
	for options in [{}, {"no-traversal": "true"}]:
		var scene = await _scene(options)
		await _place(scene, "a", 11.0)   # the 1.60 m wall ahead is refused (run into it), then weave off over open ground
		var path := []
		for i in 600:
			if i % 240 == 0:
				await _tree.physics_frame
			var input := _run_input(i > 300)
			if i >= 240:
				input.yaw = PI + 0.5 + 0.3 * sin((i - 240) * 0.03)   # toward +Z and +X, clear of the course and the ledge
			input.jump_pressed = i == 420
			scene.simulate_tick(input, DT)
			path.append([scene.body.global_position, scene.body.velocity])
			seen[scene.vault.reason] = true
		paths.append(path)
		t.eq(scene.vault.vaults, 0, "no vault in this run")
		await _free(scene)
	t.ok(seen.has("too_high"), "perception saw and refused the tall wall")
	var differences := 0
	for i in paths[0].size():
		if paths[0][i][0] != paths[1][i][0] or paths[0][i][1] != paths[1][i][1]:
			differences += 1
	t.eq(differences, 0, "bit-identical trajectories with traversal on and off when nothing is vaulted")


func test_active_vault_physics_does_not_depend_on_rendered_animation(t) -> void:
	var paths := []
	for animated in [true, false]:
		var scene = await _scene()
		scene.animation_enabled = animated
		await _place(scene, "a")
		var path := []
		for i in 480:
			if i % 240 == 0:
				await _tree.physics_frame
			_tick(scene, _run_input(true))
			path.append([scene.body.global_position, scene.body.velocity, scene.vault.phase, scene.vault.time])
		t.ok(scene.vault.vaults >= 3, "the equivalence trial includes multiple active vaults")
		t.eq(scene.vault.aborts, 0, "the physical vault completes with animation on or off")
		paths.append(path)
		await _free(scene)
	t.eq(paths[0], paths[1], "the full vault trajectory and action clock are bit-identical without rendering")


## The live order: the engine runs the scene's own _process every rendered frame (with physics interpolation, as in the
## game), physics ticks arrive from physics_frame, and the final pose is read as the last modifier finishes.
func test_live_frames_plant_feet_and_hand_on_their_targets(t) -> void:
	var scene = await _scene()
	scene.set_process(true)
	scene.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	var animator = scene.authored_animation
	var errors := {"feet": 0.0, "feet_samples": 0, "hand": 0.0, "hand_samples": 0}
	var measure := func() -> void:
		for index in 2:
			if animator._feet[index].active:
				var side := "Left" if index == 0 else "Right"
				errors.feet = maxf(errors.feet, animator.final_feet[side].origin.distance_to(animator._feet[index].target))
				errors.feet_samples += 1
		if animator._arm.active and animator._arm.influence > 0.99:
			errors.hand = maxf(errors.hand, animator.hand_error)
			errors.hand_samples += 1
	animator._orientation.modification_processed.connect(measure)
	await _place(scene, "a")
	for i in 260:
		await _tree.physics_frame
		scene.simulate_tick(_run_input(), DT)
	animator._orientation.modification_processed.disconnect(measure)
	t.eq(scene.vault.vaults, 1, "the first wall is vaulted")
	t.ok(errors.feet_samples > 20 and errors.hand_samples > 3, "both contacts were presented (%d foot, %d hand frames)" % [errors.feet_samples, errors.hand_samples])
	t.ok(errors.feet < 0.005, "planted feet reach their targets in the frame they are set (%.4f m)" % errors.feet)
	t.ok(errors.hand < 0.01, "the support hand stays on its contact point while the body travels (%.4f m)" % errors.hand)


## Cameras follow the character's travel over the wall: neither the collider's hump nor the dip that fits the authored
## hand to a lower wall. The view stays level over a flat vault and rises onto a deck without ducking first. Live
## frames (as in the game), so each camera pairs the interpolated body with the offset at the same fraction.
func test_cameras_follow_the_vault_travel_without_hump_or_dip(t) -> void:
	var scene = await _scene()
	scene.set_process(true)
	scene.body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	scene.toggle_side_view()
	t.eq(scene._side_cam.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"a render-driven side camera does not interpolate an already-interpolated target again")
	for lane in ["a", "c"]:
		await _place(scene, lane)
		scene.cam.snap()
		scene._update_side_view(0.0)
		t.near(scene._side_cam.fov, 60.0 if lane == "c" else 40.0, 0.001,
			"the closer lane C view widens to keep the raised vault arm in frame")
		t.ok(scene._side_offset.normalized().dot(Vector3.FORWARD if lane == "c" else Vector3.BACK) > 0.99,
			"the side view uses the outside of lane " + lane + ", without foreground lane walls")
		var sight := PhysicsRayQueryParameters3D.create(scene._side_cam.global_position, scene.side_focus(0.0),
			1, [scene.body.get_rid()])
		t.ok(scene.body.get_world_3d().direct_space_state.intersect_ray(sight).is_empty(),
			"the side camera can see the character, not the back of the course wall")
		var before: int = scene.vault.vaults
		var ground := NAN
		var orbit_start := NAN
		var side_start := NAN
		var side_prev := NAN
		var s := {"dip": 0.0, "low": INF, "high": -INF, "apart": 0.0, "orbit_low": INF, "orbit_high": -INF,
			"side_low": INF, "side_high": -INF, "side_step": 0.0, "hump": 0.0}
		for i in 720:
			await _tree.physics_frame
			scene.simulate_tick(_run_input(), DT)
			var side_y: float = scene._side_cam.global_position.y
			if not scene.vault.presenting:
				if scene.vault.vaults > before:
					break
				ground = scene.body.global_position.y
				orbit_start = scene.cam._focus.y
				side_start = side_y
				side_prev = side_y
				continue
			var body: Vector3 = scene.body.global_position
			var drawn: Vector3 = body + scene.vault.offset(1.0)
			var follow: Vector3 = body + scene.vault.follow_offset(1.0)
			s.hump = maxf(s.hump, body.y - ground)
			s.dip = maxf(s.dip, ground - drawn.y)
			s.low = minf(s.low, follow.y - ground)
			s.high = maxf(s.high, follow.y - ground)
			s.apart = maxf(s.apart, Vector2(drawn.x - follow.x, drawn.z - follow.z).length())
			s.orbit_low = minf(s.orbit_low, scene.cam._focus.y - orbit_start)
			s.orbit_high = maxf(s.orbit_high, scene.cam._focus.y - orbit_start)
			s.side_low = minf(s.side_low, side_y - side_start)
			s.side_high = maxf(s.side_high, side_y - side_start)
			s.side_step = maxf(s.side_step, absf(side_y - side_prev))
			side_prev = side_y
		var landing: float = scene.vault.plan.landing
		print("Camera follow lane %s: hump %.3f dip %.3f follow %+.4f..%+.4f orbit %+.4f..%+.4f side %+.4f..%+.4f step %.4f landing %+.3f" % [
			lane, s.hump, s.dip, s.low, s.high, s.orbit_low, s.orbit_high, s.side_low, s.side_high, s.side_step, landing])
		t.eq(scene.vault.vaults - before, 1, "lane %s: one vault" % lane)
		t.ok(s.hump > 0.5, "lane %s: the collider humps over the wall (%.2f m)" % [lane, s.hump])
		t.ok(s.apart < 1e-4, "lane %s: the follow point travels with the drawn character (%.6f m apart)" % [lane, s.apart])
		t.ok(s.low > minf(landing, 0.0) - 0.005 and s.high < maxf(landing, 0.0) + 0.005,
			"lane %s: the follow point stays between takeoff and landing ground (%.3f..%.3f, landing %+.2f)" % [lane, s.low, s.high, landing])
		t.ok(s.orbit_low > -0.005 and s.orbit_high < maxf(landing, 0.0) + 0.005,
			"lane %s: the orbit camera neither ducks nor rides the hump (%+.3f..%+.3f m)" % [lane, s.orbit_low, s.orbit_high])
		t.ok(s.side_low > -0.005 and s.side_high < maxf(landing, 0.0) + 0.005,
			"lane %s: the side view neither ducks nor rides the hump (%+.3f..%+.3f m)" % [lane, s.side_low, s.side_high])
		t.ok(s.side_step < 0.012, "lane %s: the side view's height eases (largest tick step %.4f m)" % [lane, s.side_step])
		if lane == "a":
			t.ok(s.dip > 0.1, "lane A: the drawn root dips to fit the hand to the low wall (%.3f m), which the cameras ignore" % s.dip)
