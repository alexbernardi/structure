## Movement Lab 5.6: the braced hang as a climber's efficient position (arms straight and even, hips in, feet staggered
## with the toes on the face, knees turned out and clear of it) and the coordinated hanging shuffle (hands and feet in
## turn, no leg jitter, no body bob, settling when the stick is released). Lane N: the 3.0 m wall, face x 43.
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const DT := 1.0 / 120.0
const RUN_YAW := -PI / 2.0
const FACE_X := 43.0
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


func _place(scene, landmark: String, at: Vector3) -> void:
	scene.teleport_to(landmark)
	scene.body.teleport(at)
	await _tree.physics_frame


static func _input(press := false, move := Vector2(0, 1)) -> Dictionary:
	return {"move": move, "yaw": RUN_YAW, "sprint": false, "jump_pressed": press, "jump_held": press, "crouch": false}


## Ticks the scene as play does (simulation, presentation, the skeleton's modifiers); returns the largest hand-to-lip
## distance while hanging.
func _run(scene, ticks: int, policy: Callable, watch: Callable) -> Dictionary:
	var stats := {"grip_error": 0.0}
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		scene.simulate_tick(policy.call(scene, i), DT)
		scene._process(DT)
		scene.authored_visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var mantle = scene.traversal.mantle
		if mantle.hanging() and mantle._hang_time > 0.2:
			stats.grip_error = maxf(stats.grip_error, scene.authored_animation.grip_error)
		watch.call(scene)
	return stats


## Run at the wall, jump at `jump_x` (a catch), then follow `then` while hanging.
func _catch_then(jump_x: float, then: Callable) -> Callable:
	var state := {"jumped": false}
	return func(s, i):
		if not state.jumped and s.body.global_position.x > jump_x:
			state.jumped = true
			return _input(true)
		if s.traversal.mantle.hanging():
			return then.call(s, i)
		return _input()


static func _soles(scene, side: String) -> Array:
	var sk: Skeleton3D = scene.authored_visual.skeleton
	var foot: Transform3D = sk.global_transform * (scene.authored_animation.final_feet[side] as Transform3D)
	var out := []
	for point in scene.authored_visual.sole_points[side]:
		out.append(foot * point)
	return out


static func _bone(scene, name: String) -> Vector3:
	var sk: Skeleton3D = scene.authored_visual.skeleton
	return sk.global_transform * sk.get_bone_global_pose(scene.authored_visual.bone_index[name]).origin


## The drawn sole's heel and toe ends (world) after every correction.
static func _sole_ends(scene, side: String) -> Array:
	var sk: Skeleton3D = scene.authored_visual.skeleton
	var foot: Transform3D = sk.global_transform * (scene.authored_animation.final_feet[side] as Transform3D)
	var toes: Vector3 = sk.get_bone_rest(scene.authored_visual.bone_index[side + "Toes"]).origin   # bone-local
	var points: Array = scene.authored_visual.sole_points[side].duplicate()
	points.sort_custom(func(a, b): return (a as Vector3).dot(toes) < (b as Vector3).dot(toes))
	return [foot * (((points[0] as Vector3) + points[1]) * 0.5), foot * (((points[2] as Vector3) + points[3]) * 0.5)]


## World ankle after every correction (bone poses read outside the modifiers are the authored ones).
static func _ankle(scene, side: String) -> Vector3:
	var sk: Skeleton3D = scene.authored_visual.skeleton
	return sk.global_transform * (scene.authored_animation.final_feet[side] as Transform3D).origin


static func _arm_share(scene, side: String) -> float:
	var anim = scene.authored_animation
	return _bone(scene, side + "UpperArm").distance_to((anim.final_hands[side] as Transform3D).origin) / anim._arm_length()


## Hanging still on the 3.0 m wall: the climber's position, held steady.
func test_braced_hang_is_a_climbers_position(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_n", Vector3(38.0, 0.05, -85.0))
	var anim = scene.authored_animation
	var seen := {"frames": 0, "braced": 2, "hips": [INF, -INF], "toe_gap": 0.0, "into": 1.0, "stagger": INF,
		"knee_wall": INF, "turned_out": INF, "arm": [INF, -INF], "arm_diff": 0.0, "drift": 0.0, "first": {}}
	var stats: Dictionary = await _run(scene, 480, _catch_then(41.4, func(_s, _i): return _input(false, Vector2.ZERO)), func(s):
		if not s.traversal.mantle.hanging() or s.traversal.mantle._hang_time < 1.0 or anim.final_feet.is_empty():
			return
		seen.frames += 1
		seen.braced = mini(seen.braced, anim.braced_feet)
		var hips: Vector3 = (_bone(s, "LeftUpperLeg") + _bone(s, "RightUpperLeg")) * 0.5
		seen.hips = [minf(seen.hips[0], FACE_X - hips.x), maxf(seen.hips[1], FACE_X - hips.x)]
		var heights := {}
		for side in ["Left", "Right"]:
			var ends := _sole_ends(s, side)
			var toe: Vector3 = ends[1]
			seen.toe_gap = maxf(seen.toe_gap, absf(FACE_X - toe.x))
			seen.into = minf(seen.into, ((ends[1] as Vector3) - ends[0]).normalized().x)    # +x is into the wall
			heights[side] = (anim.final_feet[side] as Transform3D).origin
			var knee: Vector3 = anim.final_knees[side]
			seen.knee_wall = minf(seen.knee_wall, FACE_X - knee.x)
			var hip := _bone(s, side + "UpperLeg")
			# turned out: the knee further to its own side than its hip
			var outward := (hip - (_bone(s, "LeftUpperLeg") + _bone(s, "RightUpperLeg")) * 0.5)
			outward.y = 0.0
			seen.turned_out = minf(seen.turned_out, (knee - hip).dot(outward.normalized()))
			seen.arm = [minf(seen.arm[0], _arm_share(s, side)), maxf(seen.arm[1], _arm_share(s, side))]
			var foot: Vector3 = _ankle(s, side)
			if not seen.first.has(side):
				seen.first[side] = foot
			seen.drift = maxf(seen.drift, foot.distance_to(seen.first[side]))
		var sk: Skeleton3D = s.authored_visual.skeleton
		var left_y: float = (sk.global_transform * (heights.Left as Vector3)).y
		var right_y: float = (sk.global_transform * (heights.Right as Vector3)).y
		seen.stagger = minf(seen.stagger, left_y - right_y)
		seen.arm_diff = maxf(seen.arm_diff, absf(_arm_share(s, "Left") - _arm_share(s, "Right"))))
	print("CLIMBER ", seen)
	t.ok(seen.frames > 200 and seen.braced == 2, "both feet braced on the wall throughout (%d frames)" % seen.frames)
	t.ok(seen.hips[0] > 0.18 and seen.hips[1] < 0.40, "the hips in close to the face (%.2f .. %.2f m)" % seen.hips)
	t.ok(seen.toe_gap < 0.04, "the toes on the face (within %.3f m)" % seen.toe_gap)
	t.ok(seen.into > 0.85, "each foot points into the wall (%.2f)" % seen.into)
	t.ok(seen.stagger > 0.1, "the feet staggered: the left higher (%.2f m)" % seen.stagger)
	t.ok(seen.knee_wall > 0.06, "the knees clear the face (%.3f m)" % seen.knee_wall)
	t.ok(seen.turned_out > 0.02, "the knees turned out, each to its own side (%.3f m)" % seen.turned_out)
	t.ok(seen.arm[0] > 0.86 and seen.arm[1] < 0.99, "the arms nearly straight (%.2f .. %.2f of their length)" % seen.arm)
	t.ok(seen.arm_diff < 0.04, "both arms alike: the shoulders square to the hands (%.3f)" % seen.arm_diff)
	t.ok(seen.drift < 0.005, "the feet stay put while still (%.4f m)" % seen.drift)
	t.ok(stats.grip_error < 0.02, "hands on the lip (%.4f m)" % stats.grip_error)


## Shuffling along the wall and back: lead hand, lead foot, trail hand, trail foot; the legs never jitter back and
## forth, every foot is re-planted, the body does not bob, and everything settles when the stick is released.
func test_hanging_shuffle_is_coordinated(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_n", Vector3(38.0, 0.05, -85.0))
	var anim = scene.authored_animation
	var trace := {"prev": {}, "vel": {}, "reversals": 0, "jump": 0.0, "hips_y": [INF, -INF], "lift": 0.0, "order": [],
		"stepping": [], "moves0": {}, "spread": [INF, -INF], "hands_rest": -1.0, "feet_rest": -1.0, "arm": INF, "feet_off": 0.0, "settled": {}}
	await _run(scene, 1320, _catch_then(41.4, func(s, _i):
		var h: float = s.traversal.mantle._hang_time
		if h > 1.5 and h < 4.5:
			return _input(false, Vector2(1.0, 0.3))
		if h > 5.5 and h < 8.5:
			return _input(false, Vector2(-1.0, 0.3))
		return _input(false, Vector2.ZERO)), func(s):
		if not s.traversal.mantle.hanging() or anim.final_feet.is_empty():
			return
		var h: float = s.traversal.mantle._hang_time
		if h < 1.0:
			return
		if trace.moves0.is_empty():
			trace.moves0 = anim.foot_moves.duplicate()
		var shuffling := (h > 1.8 and h < 4.5) or (h > 5.8 and h < 8.5)
		for side in ["Left", "Right"]:
			var foot: Vector3 = _ankle(s, side)
			if trace.prev.has(side):
				var v: Vector3 = (foot - trace.prev[side]) / DT
				trace.jump = maxf(trace.jump, foot.distance_to(trace.prev[side]))
				if trace.vel.has(side) and v.length() > 0.2 and (trace.vel[side] as Vector3).length() > 0.2 and v.dot(trace.vel[side]) < 0.0:
					trace.reversals += 1
				trace.vel[side] = v
			trace.prev[side] = foot
			trace.arm = minf(trace.arm, _arm_share(s, side))
		if shuffling and anim._plants.size() == 2:
			var apart: float = (anim._plants.Left as Vector3).distance_to(anim._plants.Right)
			trace.spread = [minf(trace.spread[0], apart), maxf(trace.spread[1], apart)]
		if shuffling:
			var hips: float = ((_bone(s, "LeftUpperLeg") + _bone(s, "RightUpperLeg")) * 0.5).y
			trace.hips_y = [minf(trace.hips_y[0], hips), maxf(trace.hips_y[1], hips)]
			trace.lift = maxf(trace.lift, anim.hang_lift)
		# hand moves in the order they start
		for side in anim._step.keys():
			if not trace.stepping.has(side):
				trace.order.append(side)
		trace.stepping = anim._step.keys()
		# released at 4.5 s: the limbs settle
		if h > 4.5 and h < 5.5:
			if trace.hands_rest < 0.0 and anim._step.is_empty() and anim._foot_step.is_empty():
				trace.hands_rest = h - 4.5
			if h > 5.3:
				for side in ["Left", "Right"]:
					var hip := _bone(s, side + "UpperLeg")
					trace.feet_off = maxf(trace.feet_off, _ankle(s, side).distance_to(hip) / anim._leg_length(side)))
	var moves := {"Left": anim.foot_moves.Left - trace.moves0.Left, "Right": anim.foot_moves.Right - trace.moves0.Right}
	var repeats := 0
	for i in range(1, trace.order.size()):
		if trace.order[i] == trace.order[i - 1]:
			repeats += 1
	print("SHUFFLE ", {"reversals": trace.reversals, "jump": trace.jump, "hips_y": trace.hips_y, "lift": trace.lift,
		"hand_order": "".join(trace.order.map(func(x): return x[0])), "repeats": repeats, "moves": moves,
		"spread": trace.spread, "settle": trace.hands_rest, "feet_reach": trace.feet_off, "arm": trace.arm, "both": anim.two_hands_moving})
	t.eq(trace.reversals, 0, "no foot jitters back and forth")
	t.ok(trace.jump < 0.04, "no foot jumps (largest frame move %.3f m)" % trace.jump)
	t.ok(moves.Left >= 6 and moves.Right >= 6 and absi(moves.Left - moves.Right) <= 2, "both feet re-planted in turn (%s)" % moves)
	# a repeat is natural where the shuffle reverses (the new lead hand was the last to move) and in the settle
	t.ok(trace.order.size() >= 12 and repeats <= 4, "hands move alternately (%d moves, %d repeats)" % [trace.order.size(), repeats])
	t.eq(anim.two_hands_moving, 0, "never both hands off the ledge")
	t.ok(trace.spread[1] > 0.5, "the lead hand reaches far out (hands up to %.2f m apart)" % trace.spread[1])
	t.ok(trace.spread[0] < 0.2, "the trail hand matches up close to it (down to %.2f m apart)" % trace.spread[0])
	t.ok(trace.hips_y[1] - trace.hips_y[0] < 0.03, "the body does not bob while shuffling (%.3f m)" % (trace.hips_y[1] - trace.hips_y[0]))
	t.ok(trace.lift < 0.02, "no hand out of reach pulling the body (%.3f m)" % trace.lift)
	t.ok(trace.arm > 0.8, "arms stay long (at least %.2f of their length)" % trace.arm)
	t.ok(trace.hands_rest >= 0.0 and trace.hands_rest < 0.6, "released, every limb has settled within %.2f s" % trace.hands_rest)
	t.ok(trace.feet_off < 0.99, "no leg left stretched toward an old foothold (%.2f of its length)" % trace.feet_off)


static func _inside(scene, p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.exclude = [scene.body.get_rid()]
	return not scene.body.get_world_3d().direct_space_state.intersect_point(q, 1).is_empty()


## Round lane O's outside corner (the block's west face onto its north face) and its inside corner (the L): the braced
## feet stay on the walls - each keeps its wall until it can step to the next, a move between walls bows out round an
## outside corner, one foot at a time - so no leg flies up, jumps, or passes into the wall.
func test_braced_feet_round_corners(t) -> void:
	var scene = await _scene()
	var mantle = scene.traversal.mantle
	var anim = scene.authored_animation
	for lane in [["lane_o", Vector3(39.0, 0.05, -96.2), 42.4], ["lane_o_inside", Vector3(55.0, 0.05, -96.4), 58.4]]:
		await _place(scene, lane[0], lane[1])
		var corners0: int = mantle.corners
		var tr := {"prev": {}, "jump": 0.0, "inside": 0, "above": -INF, "braced": 2, "frames": 0, "moves0": {}, "one_foot": 0}
		await _run(scene, 900, _catch_then(lane[2], func(_s, _i):
			return _input(false, Vector2(1.0, 0.3) if mantle._hang_time > 0.5 and mantle._hang_time < 5.0 else Vector2.ZERO)), func(s):
			if not mantle.hanging() or anim.final_feet.is_empty() or mantle._hang_time < 0.6:
				return
			if tr.moves0.is_empty():
				tr.moves0 = anim.foot_moves.duplicate()
			tr.frames += 1
			tr.braced = mini(tr.braced, anim.braced_feet)
			if anim.braced_feet < 2:
				tr.one_foot += 1
			var hips: Vector3 = (_bone(s, "LeftUpperLeg") + _bone(s, "RightUpperLeg")) * 0.5
			for side in ["Left", "Right"]:
				var foot := _ankle(s, side)
				if tr.prev.has(side):
					tr.jump = maxf(tr.jump, foot.distance_to(tr.prev[side]))
				tr.prev[side] = foot
				tr.above = maxf(tr.above, foot.y - hips.y)
				if _inside(s, foot) or _inside(s, _sole_ends(s, side)[1]) or _inside(s, anim.final_knees[side]):
					tr.inside += 1)
		var moves := {"Left": anim.foot_moves.Left - tr.moves0.Left, "Right": anim.foot_moves.Right - tr.moves0.Right}
		print("CORNER FEET ", lane[0], " ", tr, " moves ", moves)
		t.eq(mantle.corners - corners0, 1, "%s: the corner is hung around" % lane[0])
		# Round an outside corner the hips swing past the end of the old wall: for a moment one foot can have no wall in
		# reach (it blends toward the dangle and steps on); never both.
		t.ok(tr.braced >= 1 and tr.one_foot < 24, "%s: braced all the way round (one foot only for %d frames)" % [lane[0], tr.one_foot])
		t.ok(tr.above < -0.4, "%s: the feet stay well below the hips - no leg flies up (%.2f m)" % [lane[0], tr.above])
		t.ok(tr.jump < 0.05, "%s: no foot jumps (largest frame move %.3f m)" % [lane[0], tr.jump])
		t.eq(tr.inside, 0, "%s: no foot, toe or knee inside the wall" % lane[0])
		t.ok(moves.Left >= 2 and moves.Right >= 2, "%s: both feet step round with the body (%s)" % [lane[0], moves])
