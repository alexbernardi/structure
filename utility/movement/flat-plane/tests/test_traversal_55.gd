## Movement Lab 5.5: the skeleton view, foot IK on real ground (a step, a slope, stairs, uneven pads), the braced hang
## (feet on the wall; dangling under a shelf), and hanging around corners (outside, inside, refused).
## Lanes N (3.0 m wall, face x 43), O (block west face x 44 z -99..-95; inside corner at x 60 z -95; thin wall west
## face x 71.875 ends at z -95; shelf lip face x 80.8), P (pads, a 0.2 m step edge at x 49, stairs, a 15 degree slope).
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const MantleAction = preload("res://traversal/mantle_action.gd")
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


func _scene():
	var scene = Scene.instantiate()
	scene.options = {"no-capture": "true", "no-hardware": "true", "no-window-state": "true", "tuning-state": ""}
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


static func _input(press := false, move := Vector2(0, 1), yaw := RUN_YAW) -> Dictionary:
	return {"move": move, "yaw": yaw, "sprint": false, "jump_pressed": press, "jump_held": press, "crouch": false}


func _run(scene, ticks: int, policy: Callable, watch := Callable()) -> Dictionary:
	var stats := {"overlap_ticks": 0, "max_y": -INF, "grip_error": 0.0}
	var clearance := PhysicsShapeQueryParameters3D.new()
	var cylinder := CylinderShape3D.new()
	clearance.shape = cylinder
	clearance.exclude = [scene.body.get_rid()]
	clearance.collision_mask = scene.body.collision_mask
	var space: PhysicsDirectSpaceState3D = scene.body.get_world_3d().direct_space_state
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		scene.simulate_tick(policy.call(scene, i), DT)
		scene._process(DT)
		scene.authored_visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var mantle = scene.traversal.mantle
		if mantle.active() or mantle.hanging():
			cylinder.radius = scene.body._shape.radius - 0.002
			cylinder.height = scene.body._shape.height - 0.004
			clearance.transform = scene.body._collider.global_transform
			if not space.intersect_shape(clearance, 1).is_empty():
				stats.overlap_ticks += 1
		if mantle.hanging() and mantle._hang_time > 0.2:
			stats.grip_error = maxf(stats.grip_error, scene.authored_animation.grip_error)
		stats.max_y = maxf(stats.max_y, scene.body.global_position.y)
		if watch.is_valid():
			watch.call(scene)
	stats["choices"] = scene.traversal.choices.duplicate()
	print("T55 ", JSON.stringify({"finish": [snappedf(scene.body.global_position.x, 0.01), snappedf(scene.body.global_position.y, 0.01),
		snappedf(scene.body.global_position.z, 0.01)], "choices": stats.choices, "grip": snappedf(stats.grip_error, 0.0001),
		"overlap": stats.overlap_ticks, "block": scene.traversal.mantle.shimmy_block, "corners": scene.traversal.mantle.corners}))
	return stats


func _catch_then(jump_x: float, then: Callable) -> Callable:
	var state := {"jumped": false}
	return func(s, i):
		if not state.jumped and s.body.global_position.x > jump_x:
			state.jumped = true
			return _input(true)
		if s.traversal.mantle.hanging():
			return then.call(s, i)
		return _input()


## World positions of a foot's sole corners after every correction.
static func _soles(scene, side: String) -> Array:
	var sk: Skeleton3D = scene.authored_visual.skeleton
	var foot: Transform3D = sk.global_transform * (scene.authored_animation.final_feet[side] as Transform3D)
	var out := []
	for point in scene.authored_visual.sole_points[side]:
		out.append(foot * point)
	return out


static func _ground_at(scene, p: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = scene.body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.8)
	q.exclude = [scene.body.get_rid()]
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else -INF


## K: the skeleton view draws the real final skeleton (the same pose the IK left the mesh in) through the body at 40 %.
func test_skeleton_view_draws_the_real_pose(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_n", Vector3(38.0, 0.05, -85.0))
	scene.toggle_skeleton_view()
	var seen := {"frames": 0, "worst": 0.0}
	await _run(scene, 240, _catch_then(41.4, func(_s, _i): return _input(false, Vector2.ZERO)), func(s):
		if s.traversal.mantle.hanging() and s.traversal.mantle._hang_time > 0.4 and not s.authored_animation.final_hands.is_empty():
			seen.frames += 1
			for side in ["Left", "Right"]:
				var drawn: Vector3 = s.skeleton_overlay.joint_world.get(side + "Hand", Vector3.INF)
				seen.worst = maxf(seen.worst, drawn.distance_to((s.authored_animation.final_hands[side] as Transform3D).origin)))
	t.ok(scene.skeleton_overlay != null and scene.skeleton_overlay.visible and scene.skeleton_overlay.updates > 100, "the skeleton view is drawn every update")
	t.ok(seen.frames > 50 and seen.worst < 1e-3, "it shows the hands where the IK put them (worst %.5f m over %d frames)" % [seen.worst, seen.frames])
	var faded := true
	for material in scene.authored_visual.body_materials:
		faded = faded and is_equal_approx(material.albedo_color.a, 0.4) and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	t.ok(faded and scene.authored_visual.body_materials.size() > 20, "every body part at 40 %% opacity (%d parts)" % scene.authored_visual.body_materials.size())
	scene.toggle_skeleton_view()
	t.ok(not scene.skeleton_overlay.visible and is_equal_approx(scene.authored_visual.body_materials[0].albedo_color.a, 1.0), "K again: solid body, no skeleton")


## Standing across a 0.2 m step: each foot on its own ground (the pelvis drops for the lower one); on a 15 degree slope
## the planted feet tilt to it; on flat ground nothing changes.
func test_feet_stand_on_the_real_ground(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_p_step")
	await _run(scene, 150, func(_s, _i): return _input(false, Vector2.ZERO, 0.0))
	var gaps := []
	for side in ["Left", "Right"]:
		var lowest := INF
		var ground := -INF
		for p in _soles(scene, side):
			if p.y < lowest:
				lowest = p.y
				ground = _ground_at(scene, p)
		gaps.append([side, snappedf(ground, 0.001), snappedf(lowest - ground, 0.001)])
	print("STEP ", gaps, " pelvis ", scene.authored_animation._pelvis)
	t.ok(absf(gaps[0][1] - gaps[1][1]) > 0.15, "the feet stand on different levels (%.2f and %.2f m)" % [gaps[0][1], gaps[1][1]])
	t.ok(absf(gaps[0][2]) < 0.03 and absf(gaps[1][2]) < 0.03, "each sole on its own ground (%.3f, %.3f m)" % [gaps[0][2], gaps[1][2]])
	t.ok(scene.authored_animation._pelvis < -0.1, "the pelvis drops to let the lower foot reach (%.3f m)" % scene.authored_animation._pelvis)
	# Flat ground: the baseline sole angle; on the slope the planted feet follow its normal.
	var angle := func(s, side: String, normal: Vector3) -> float:
		var sk: Skeleton3D = s.authored_visual.skeleton
		var rest := sk.get_bone_global_rest(s.authored_visual.bone_index[side + "Foot"]).basis
		var up_local := rest.inverse() * Vector3.UP
		var now: Basis = sk.global_transform.basis * (s.authored_animation.final_feet[side] as Transform3D).basis
		return rad_to_deg((now * up_local).normalized().angle_to(normal))
	await _place(scene, "lane_p", Vector3(36.0, 0.05, -105.0))
	await _run(scene, 120, func(_s, _i): return _input(false, Vector2.ZERO, 0.0))
	var flat: float = maxf(angle.call(scene, "Left", Vector3.UP), angle.call(scene, "Right", Vector3.UP))
	t.ok(scene.authored_animation.terrain_correction < 0.005, "flat ground: no terrain offset (%.4f m)" % scene.authored_animation.terrain_correction)
	await _place(scene, "lane_p", Vector3(65.0, 0.7, -105.0))
	await _run(scene, 150, func(_s, _i): return _input(false, Vector2.ZERO, 0.0))
	var slope_n := Vector3(-sin(deg_to_rad(15.0)), cos(deg_to_rad(15.0)), 0.0)
	var tilted: float = maxf(angle.call(scene, "Left", slope_n), angle.call(scene, "Right", slope_n))
	print("SLOPE flat %.2f deg, slope %.2f deg" % [flat, tilted])
	t.ok(tilted < flat + 5.0, "on the 15 degree slope the feet lie on it (%.1f deg from its normal; flat baseline %.1f)" % [tilted, flat])


## Walking up 0.15 m stairs and across uneven pads: no sole sinks into a tread or a pad.
func test_feet_do_not_sink_on_stairs_or_uneven_ground(t) -> void:
	var scene = await _scene()
	var worst := {"stairs": 0.0, "pads": 0.0}
	for course in [["stairs", Vector3(52.0, 0.05, -105.0), 260], ["pads", Vector3(40.5, 0.05, -105.0), 200]]:
		await _place(scene, "lane_p", course[1])
		await _run(scene, course[2], func(_s, i): return _input(false, Vector2(0, 0.45) if i > 20 else Vector2.ZERO), func(s):
			if not s.body.core.grounded or s.authored_animation.final_feet.is_empty():
				return
			for side in ["Left", "Right"]:
				for p in _soles(s, side):
					var g := _ground_at(s, p)
					if g > -INF:
						worst[course[0]] = maxf(worst[course[0]], g - p.y))
	print("SINK ", worst)
	t.ok(worst.stairs < 0.04, "up the stairs no sole corner sinks more than %.3f m into a tread" % worst.stairs)
	t.ok(worst.pads < 0.04, "across the pads no sole corner sinks more than %.3f m" % worst.pads)


## Hanging on a wall the feet come up onto it like a climber's (both braced, the hips held out from the wall); under a
## shelf with nothing for the feet within reach the body dangles.
func test_braced_hang_and_dangling_under_a_shelf(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_n", Vector3(38.0, 0.05, -85.0))
	var anim = scene.authored_animation
	var seen := {"frames": 0, "feet_out": [INF, -INF], "hips_out": INF, "braced": 99, "knee_wall": INF, "knee_up": INF}
	var stats: Dictionary = await _run(scene, 300, _catch_then(41.4, func(_s, _i): return _input(false, Vector2.ZERO)), func(s):
		if not s.traversal.mantle.hanging() or s.traversal.mantle._hang_time < 0.7 or anim.final_feet.is_empty():
			return
		seen.frames += 1
		var sk: Skeleton3D = s.authored_visual.skeleton
		for side in ["Left", "Right"]:
			var foot: Vector3 = sk.global_transform * (anim.final_feet[side] as Transform3D).origin
			seen.feet_out = [minf(seen.feet_out[0], 43.0 - foot.x), maxf(seen.feet_out[1], 43.0 - foot.x)]
			var knee: Vector3 = anim.final_knees[side]
			seen.knee_wall = minf(seen.knee_wall, 43.0 - knee.x)
			seen.knee_up = minf(seen.knee_up, knee.y - foot.y)
		var hips: Vector3 = sk.global_transform * sk.get_bone_global_pose(s.authored_visual.bone_index.Hips).origin
		seen.hips_out = minf(seen.hips_out, 43.0 - hips.x)
		seen.braced = mini(seen.braced, anim.braced_feet))
	print("BRACE ", seen, " brace ", anim._brace)
	t.ok(seen.frames > 100 and seen.braced == 2 and anim._brace > 0.95, "both feet braced on the wall (%d, brace %.2f)" % [seen.braced, anim._brace])
	t.ok(seen.feet_out[0] > 0.03 and seen.feet_out[1] < 0.15, "ankles just off the wall: the feet press on it (%.3f .. %.3f m)" % seen.feet_out)
	t.ok(seen.hips_out > 0.2, "the hips held out from the wall (%.2f m)" % seen.hips_out)
	t.ok(seen.knee_up > 0.25, "knees up above the braced feet, a climber's brace (at least %.2f m)" % seen.knee_up)
	t.ok(seen.knee_wall > 0.05, "the knees clear the wall (%.3f m)" % seen.knee_wall)
	t.ok(stats.grip_error < 0.02, "hands on the lip (%.4f m)" % stats.grip_error)
	await _place(scene, "lane_o_shelf", Vector3(76.0, 0.05, -97.0))
	var shelf := {"hung": false, "braced": 0}
	await _run(scene, 300, _catch_then(79.2, func(s, _i):
		if s.traversal.mantle._hang_time > 0.7:
			shelf.hung = true
			shelf.braced = maxi(shelf.braced, anim.braced_feet)
		return _input(false, Vector2.ZERO)))
	t.ok(shelf.hung, "the shelf lip is caught")
	t.ok(shelf.braced == 0 and anim._brace < 0.05, "nothing for the feet within reach under it: the body dangles (%d braced)" % shelf.braced)


## Hanging around corners: on the block's west face, shimmying right reaches its corner and goes round it onto the
## north face (an arc, the body turning, the hands on two walls for a moment), then on along it; one press pulls up.
## In the L the shimmy turns the inside corner; at the thin wall's end the corner is refused and the hang stays.
func test_hanging_around_corners(t) -> void:
	var scene = await _scene()
	var mantle = scene.traversal.mantle
	var anim = scene.authored_animation
	# Outside corner.
	await _place(scene, "lane_o", Vector3(39.0, 0.05, -96.2))
	var seen := {"split": 0.0, "max_step": 0.0, "last": Vector3.INF, "pressed": false, "after": Vector3.INF}
	var stats: Dictionary = await _run(scene, 1100, _catch_then(42.4, func(s, _i):
		var h: float = mantle._hang_time
		if mantle.corners == 1 and seen.after == Vector3.INF and absf(mantle.shimmy_velocity) > 0.0 and mantle.corner.is_empty():
			seen.after = s.body.global_position
		if h > 0.5 and h < 5.5:
			return _input(false, Vector2(1.0, 0.3))
		if h > 6.0 and not seen.pressed:
			seen.pressed = true
			return _input(true, Vector2(0, 1))
		return _input(false, Vector2(0, 1) if seen.pressed else Vector2.ZERO)), func(s):
		if mantle.hanging():
			var p: Vector3 = s.body.global_position
			if seen.last != Vector3.INF:
				seen.max_step = maxf(seen.max_step, p.distance_to(seen.last))
			seen.last = p
			var c: Dictionary = anim.debug_contacts
			if c.has("hands") and c.hands.size() == 2:
				seen.split = maxf(seen.split, rad_to_deg((c.hands[0][1] as Vector3).angle_to(c.hands[1][1]))))
	print("OUTSIDE ", seen, " dir ", mantle.plan.direction)
	t.eq(mantle.corners, 1, "the outside corner is hung around (%s)" % [stats.choices])
	t.ok(seen.after != Vector3.INF and seen.after.z > -95.0 + 0.3 and seen.after.x > 44.0, "and the shimmy goes on along the north face (%s)" % seen.after)
	t.ok(seen.split > 60.0, "the hands are on two walls at the corner (%.0f degrees apart)" % seen.split)
	t.ok(seen.max_step < 0.05, "an arc, not a jump (largest step %.3f m)" % seen.max_step)
	t.ok(stats.grip_error < 0.03, "hands on the lip all the way round (%.4f m)" % stats.grip_error)
	t.eq(stats.overlap_ticks, 0, "the collider clears the corner")
	t.ok(stats.max_y > 2.99, "one press pulls up from the north face (%.2f m)" % stats.max_y)
	# Inside corner.
	await _place(scene, "lane_o_inside", Vector3(55.0, 0.05, -96.4))
	var corners0: int = mantle.corners
	stats = await _run(scene, 800, _catch_then(58.4, func(_s, _i):
		return _input(false, Vector2(1.0, 0.3) if mantle._hang_time > 0.5 else Vector2.ZERO)))
	print("INSIDE dir ", mantle.plan.direction, " at ", scene.body.global_position)
	t.eq(mantle.corners - corners0, 1, "the inside corner is hung around")
	t.ok(mantle.plan.direction.dot(Vector3(0, 0, 1)) > 0.99, "now facing the second wall (%s)" % mantle.plan.direction)
	t.ok(scene.body.global_position.x < 59.5, "and moving along it (x %.2f)" % scene.body.global_position.x)
	t.ok(stats.grip_error < 0.03, "hands on the lip (%.4f m)" % stats.grip_error)
	t.eq(stats.overlap_ticks, 0, "no penetration in the inside corner")
	# Refused: the thin wall's end face is too narrow to hang on.
	await _place(scene, "lane_o_thin", Vector3(68.0, 0.05, -96.2))
	corners0 = mantle.corners
	stats = await _run(scene, 600, _catch_then(70.6, func(_s, _i):
		return _input(false, Vector2(1.0, 0.3) if mantle._hang_time > 0.5 else Vector2.ZERO)))
	t.eq(mantle.corners - corners0, 0, "the thin wall's corner is refused")
	t.ok(mantle.hanging() and mantle.shimmy_block.begins_with("corner"), "the hang holds and says why (%s)" % mantle.shimmy_block)


## The quick mantle onto lane L's 1.2 m block: its left hand plants on the top - palm on the real surface, held where it
## landed along the ledge while the body rises past it (the authored wrist rise as the arm pushes is kept).
func test_mantle_hand_is_planted_on_the_top(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_l", Vector3(42.5, 0.05, -73.0))
	var anim = scene.authored_animation
	var seen := {"pressed": false, "frames": 0, "drift": 0.0, "start": Vector3.INF, "palm": INF}
	var stats: Dictionary = await _run(scene, 300, func(s, _i):
		var x: float = s.body.global_position.x
		if not seen.pressed and x > 46.0 and s.body.is_on_floor():
			seen.pressed = true
			return _input(true)
		return _input(), func(s):
			if anim._mantle_plant.is_empty() or not anim._arm_left.active or anim._arm_left.influence < 0.99:
				return
			var wrist: Vector3 = (anim.final_hands["Left"] as Transform3D).origin
			if seen.start == Vector3.INF:
				seen.start = wrist
				seen.palm = wrist.y - float(anim._mantle_plant.top)
			seen.frames += 1
			seen.drift = maxf(seen.drift, Vector2(wrist.x - seen.start.x, wrist.z - seen.start.z).length()))
	print("MANTLEHAND ", seen, " err ", anim.mantle_hand_error, " mantles ", scene.traversal.mantle.mantles)
	t.ok(scene.traversal.mantle.mantles >= 1, "the block is mantled (%s)" % [stats.choices])
	t.ok(seen.frames > 10, "the left hand is planted for the authored contact (%d frames)" % seen.frames)
	t.ok(seen.palm > 0.0 and seen.palm < 0.06, "the palm on the real top (wrist %.3f m above it)" % seen.palm)
	t.ok(seen.drift < 0.02, "held where it landed along the ledge (drift %.4f m)" % seen.drift)
	t.ok(anim.mantle_hand_error < 0.02, "on its contact after correction while planted (%.4f m; it lets go as the arm straightens)" % anim.mantle_hand_error)
	t.eq(stats.overlap_ticks, 0, "no penetration")
