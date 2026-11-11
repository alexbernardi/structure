## Movement Lab 5.4: reach from the body and the jump, the hands on the lip, the dangling hang (swing and legs), and
## the shimmy. Lane N: a 3.0 m wall 8 m long (face x 43, z -89 .. -81), a 0.6 m gap, a 2.6 m wall (face x 55).
## Unpaced fixed-tick trials; the collider is overlap-tested every tick a move drives it.
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const MantleAction = preload("res://systems/movement_core/traversal/mantle_action.gd")
const Profiles = preload("res://systems/movement_core/capability/movement_profiles.gd")
const DT := 1.0 / 120.0
const RUN_YAW := -PI / 2.0
const FACE_X := 43.0
const TOP := 3.0
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


func _place(scene, at: Vector3) -> void:
	scene.teleport_to("lane_n")
	scene.body.teleport(at)
	await _tree.physics_frame


static func _input(press := false, move := Vector2(0, 1)) -> Dictionary:
	return {"move": move, "yaw": RUN_YAW, "sprint": false, "jump_pressed": press, "jump_held": press, "crouch": false}


## Runs the policy (scene, tick, stats) -> input; `watch` (scene, stats) runs after each presented frame.
func _run(scene, ticks: int, policy: Callable, watch := Callable()) -> Dictionary:
	var stats := {"overlap_ticks": 0, "max_y": -INF, "grip_error": 0.0, "hang_ticks": 0}
	var clearance := PhysicsShapeQueryParameters3D.new()
	var cylinder := CylinderShape3D.new()
	clearance.shape = cylinder
	clearance.exclude = [scene.body.get_rid()]
	clearance.collision_mask = scene.body.collision_mask
	var space: PhysicsDirectSpaceState3D = scene.body.get_world_3d().direct_space_state
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		scene.simulate_tick(policy.call(scene, i, stats), DT)
		scene._process(DT)
		scene.authored_visual.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var mantle = scene.traversal.mantle
		if mantle.active() or mantle.hanging():
			cylinder.radius = scene.body._shape.radius - 0.002
			cylinder.height = scene.body._shape.height - 0.004
			clearance.transform = scene.body._collider.global_transform
			if not space.intersect_shape(clearance, 1).is_empty():
				stats.overlap_ticks += 1
		if mantle.hanging():
			stats.hang_ticks += 1
			if mantle._hang_time > 0.2:
				stats.grip_error = maxf(stats.grip_error, scene.authored_animation.grip_error)
		stats.max_y = maxf(stats.max_y, scene.body.global_position.y)
		if watch.is_valid():
			watch.call(scene, stats)
	stats["choices"] = scene.traversal.choices.duplicate()
	stats["refusal"] = scene.traversal.last_refusal
	print("HANG ", JSON.stringify({"finish": [snappedf(scene.body.global_position.x, 0.01), snappedf(scene.body.global_position.y, 0.01),
		snappedf(scene.body.global_position.z, 0.01)], "choices": stats.choices, "refusal": stats.refusal, "grip": snappedf(stats.grip_error, 0.0001),
		"overlap": stats.overlap_ticks, "block": scene.traversal.mantle.shimmy_block}))
	return stats


## Run at the wall, jump once (x > jump_x), then `then` decides the input while hanging.
func _catch_policy(jump_x: float, then := Callable()) -> Callable:
	var state := {"jumped": false}
	return func(s, i, stats):
		if not state.jumped and s.body.global_position.x > jump_x:
			state.jumped = true
			return _input(true)
		if s.traversal.mantle.hanging() and then.is_valid():
			return then.call(s, i, stats)
		return _input()


## The catch limit is the body's own reach (its height) above wherever the jump has put the feet: a human catches a
## 3.0 m top, a weaker jump (the sprained ankle) does not, and a shorter body reaches less.
func test_reach_follows_the_body_and_the_jump(t) -> void:
	var scene = await _scene()
	var sk: Skeleton3D = scene.authored_visual.skeleton
	var b: Dictionary = scene.authored_visual.bone_index
	var shoulder := sk.get_bone_global_rest(b.LeftUpperArm).origin
	var elbow := sk.get_bone_global_rest(b.LeftLowerArm).origin
	var wrist := sk.get_bone_global_rest(b.LeftHand).origin
	var overhead: float = shoulder.y + shoulder.distance_to(elbow) + elbow.distance_to(wrist)
	var stand: float = scene.body.params.get_value("stand_height")
	var reach: float = scene.traversal.mantle.hand_reach(scene.body)
	t.ok(absf(overhead + 0.16 - reach) < 0.03, "the reach model matches the mannequin: wrist overhead %.3f m + 0.16 vs %.3f m" % [overhead, reach])
	scene.body.params.set_value("stand_height", stand - 0.2)
	var shorter: float = scene.traversal.mantle.hand_reach(scene.body)
	scene.body.params.set_value("stand_height", stand)
	t.ok(absf(reach - shorter - 0.2 * MantleAction.REACH_RATIO) < 1e-4, "a body 0.2 m shorter reaches %.3f m less" % (reach - shorter))
	await _place(scene, Vector3(38.0, 0.05, -85.0))
	var stats: Dictionary = await _run(scene, 240, _catch_policy(41.4))
	t.ok(stats.hang_ticks > 0, "a human jump catches the 3.0 m top (%s, %s)" % [stats.choices, stats.refusal])
	scene.capabilities.add(Profiles.sprained_ankle())
	await _place(scene, Vector3(39.0, 0.05, -85.0))
	stats = await _run(scene, 240, _catch_policy(41.6))
	scene.capabilities.remove_source(Profiles.INJURY)
	t.eq(stats.hang_ticks, 0, "with the weaker jump (x0.8 impulse) the same top is out of reach (%s)" % stats.refusal)


## Hanging: each wrist on its grip point (just out from the face, just above the top), fingers over the top into the
## wall, palm down; arms nearly straight; the head and chest off the wall; the dangling feet off the wall and the ground.
func test_hands_are_placed_on_the_lip(t) -> void:
	var scene = await _scene()
	await _place(scene, Vector3(38.0, 0.05, -85.0))
	var seen := {"frames": 0, "wrist_up": [INF, -INF], "wrist_out": [INF, -INF], "fingers": INF, "palm": INF, "arm": INF, "head": -INF,
		"feet_into": -INF, "feet_low": INF}
	var anim = scene.authored_animation
	var arm: float = anim._arm_length()
	var stats: Dictionary = await _run(scene, 360, _catch_policy(41.4, func(_s, _i, _st): return _input(false, Vector2.ZERO)),
		func(s, _st):
			if not s.traversal.mantle.hanging() or s.traversal.mantle._hang_time < 0.4 or anim.final_hands.is_empty():
				return
			seen.frames += 1
			var sk: Skeleton3D = s.authored_visual.skeleton
			var b: Dictionary = s.authored_visual.bone_index
			for side in ["Left", "Right"]:
				var hand: Transform3D = anim.final_hands[side]
				seen.wrist_up = [minf(seen.wrist_up[0], hand.origin.y - TOP), maxf(seen.wrist_up[1], hand.origin.y - TOP)]
				seen.wrist_out = [minf(seen.wrist_out[0], FACE_X - hand.origin.x), maxf(seen.wrist_out[1], FACE_X - hand.origin.x)]
				seen.fingers = minf(seen.fingers, hand.basis.y.normalized().dot(Vector3.RIGHT))
				seen.palm = minf(seen.palm, hand.basis.z.normalized().dot(Vector3.DOWN))
				var shoulder: Vector3 = sk.global_transform * sk.get_bone_global_pose(b[side + "UpperArm"]).origin
				seen.arm = minf(seen.arm, shoulder.distance_to(hand.origin) / arm)
				var foot: Vector3 = sk.global_transform * (anim.final_feet[side] as Transform3D).origin
				seen.feet_into = maxf(seen.feet_into, foot.x - FACE_X)
				seen.feet_low = minf(seen.feet_low, foot.y)
			var head: Vector3 = sk.global_transform * (sk.get_bone_global_pose(b.Head).origin + Vector3.UP * 0.07)
			seen.head = maxf(seen.head, head.x + 0.11 - FACE_X))
	print("HANDS ", seen)
	t.ok(seen.frames > 100, "hanging and drawn (%d frames)" % seen.frames)
	t.ok(stats.grip_error < 0.02, "both wrists on their grip points (%.4f m)" % stats.grip_error)
	t.ok(seen.wrist_up[0] > 0.005 and seen.wrist_up[1] < 0.05, "wrists just above the top (%.3f .. %.3f m): the palm rests on it" % seen.wrist_up)
	t.ok(seen.wrist_out[0] > 0.02 and seen.wrist_out[1] < 0.08, "wrists just out from the face (%.3f .. %.3f m): the forearm clears the edge" % seen.wrist_out)
	t.ok(seen.fingers > 0.95, "fingers over the top, into the wall (cos %.3f)" % seen.fingers)
	t.ok(seen.palm > 0.95, "palms down on the top (cos %.3f)" % seen.palm)
	t.ok(seen.arm > 0.85, "arms nearly straight: the body hangs from them (shoulder to wrist >= %.2f of the arm; one arm is straighter as the grip pose is a little asymmetric, and since 5.5 the braced feet hold the body out a little)" % seen.arm)
	t.ok(seen.head < 0.0, "the head is off the wall (%.3f m)" % seen.head)
	t.ok(seen.feet_into < -0.05, "the dangling feet stay off the wall (%.3f m)" % seen.feet_into)
	t.ok(seen.feet_low > 0.0, "and off the ground (lowest ankle %.2f m)" % seen.feet_low)
	t.eq(stats.overlap_ticks, 0, "the collider never penetrates the wall")


## The drawn body swings from the hands: the catch sets it going out from the wall, it bounces off the wall and dies
## away; a shimmy rolls it sideways; the legs follow through the hip, behind the body.
func test_the_hang_swings_and_settles(t) -> void:
	var scene = await _scene()
	await _place(scene, Vector3(38.0, 0.05, -85.0))
	var anim = scene.authored_animation
	var trace := {"pitch_max": 0.0, "pitch_late": 0.0, "roll_max": 0.0, "leg_lag": 0.0}
	await _run(scene, 840, _catch_policy(41.4, func(s, _i, _st):
		return _input(false, Vector2(1.0, 0.3) if s.traversal.mantle._hang_time > 4.0 and s.traversal.mantle._hang_time < 5.5 else Vector2.ZERO)),
		func(s, _st):
			if not s.traversal.mantle.hanging():
				return
			var h: float = s.traversal.mantle._hang_time
			if h < 3.5:
				trace.pitch_max = maxf(trace.pitch_max, anim.hang_swing.x)
			elif h < 4.0:
				trace.pitch_late = maxf(trace.pitch_late, absf(anim.hang_swing.x))
			else:
				trace.roll_max = maxf(trace.roll_max, absf(anim.hang_swing.y))
			trace.leg_lag = maxf(trace.leg_lag, (anim._legs - anim.hang_swing).length()))
	print("SWING ", trace)
	t.ok(trace.pitch_max > 0.04, "the catch swings the body out from the wall (%.3f rad)" % trace.pitch_max)
	t.ok(trace.pitch_late < trace.pitch_max * 0.25, "and the swing dies away (%.3f rad after 3.5 s)" % trace.pitch_late)
	t.ok(trace.roll_max > 0.02, "setting off and stopping a shimmy rolls it sideways (%.3f rad)" % trace.roll_max)
	t.ok(trace.leg_lag > 0.01, "the legs lag behind the body's swing (%.3f rad)" % trace.leg_lag)


## Stick right shimmies along the 3.0 m wall at shimmy_speed, hand over hand (one hand at a time, both on the lip), and
## stops where the lip steps up to a flush 3.6 m block (no corner to turn) instead of letting go; stick left comes back; one press then pulls up from the new place.
func test_shimmy_along_the_ledge_and_pull_up(t) -> void:
	var scene = await _scene()
	await _place(scene, Vector3(38.0, 0.05, -85.0))
	var anim = scene.authored_animation
	var mantle = scene.traversal.mantle
	var trace := {"start_z": NAN, "speed": 0.0, "steps0": anim.hand_steps, "end_z": NAN, "end_block": "", "back_z": NAN, "pressed": false}
	var speed: float = scene.capabilities.get_value("shimmy_speed")
	var stats: Dictionary = await _run(scene, 1500, _catch_policy(41.4, func(s, _i, _st):
		var h: float = mantle._hang_time
		if is_nan(trace.start_z) and h > 0.5:
			trace.start_z = s.body.global_position.z
		if h > 0.5 and h < 7.0:
			trace.speed = maxf(trace.speed, absf(mantle.shimmy_velocity))
			return _input(false, Vector2(1.0, 0.3))      # right: +z, toward the wall's end at z -81
		if h >= 7.0 and is_nan(trace.end_z):
			trace.end_z = s.body.global_position.z
			trace.end_block = mantle.shimmy_block
		if h >= 7.0 and h < 8.5:
			return _input(false, Vector2(-1.0, 0.3))     # left: back along the wall
		if h >= 8.5 and is_nan(trace.back_z):
			trace.back_z = s.body.global_position.z
		if h > 9.0 and not trace.pressed:
			trace.pressed = true
			return _input(true, Vector2(0, 1))
		return _input(false, Vector2(0, 1) if trace.pressed else Vector2.ZERO)))
	print("SHIMMY ", trace, " steps ", anim.hand_steps, " both ", anim.two_hands_moving)
	t.ok(absf(trace.speed - speed) < 0.01, "shimmies at shimmy_speed (%.2f m/s)" % trace.speed)
	var stop := -81.0 - MantleAction.HAND_SPAN - MantleAction.SHIMMY_LEAD
	t.ok(absf(trace.end_z - stop) < 0.05, "stops where the wall ends, both hands still on it (z %.2f, expected %.2f)" % [trace.end_z, stop])
	t.ok(trace.end_block in ["end", "corner_ledge", "corner_blocked"] and mantle.corners == 0, "and says why, without turning (%s; since 5.5 a flush 3.6 m block ends this wall)" % trace.end_block)
	t.ok(trace.back_z < trace.end_z - 0.8, "stick left comes back (z %.2f -> %.2f)" % [trace.end_z, trace.back_z])
	t.ok(anim.hand_steps - trace.steps0 >= 6, "hand over hand (%d hand moves)" % (anim.hand_steps - trace.steps0))
	t.eq(anim.two_hands_moving, 0, "never both hands off the ledge")
	t.ok(stats.grip_error < 0.03, "every hand on its grip point or its path while hanging (%.4f m)" % stats.grip_error)
	t.ok(stats.max_y > TOP - 0.01, "one press pulls up from the new place (%.2f m)" % stats.max_y)
	t.eq(stats.overlap_ticks, 0, "no penetration")


## Hang depth: at arm's length where there is room (3.0 m and 2.6 m walls: the feet well off the ground), as low as the
## ground allows otherwise; never higher than the authored grip.
func test_hang_depth_follows_the_room_below(t) -> void:
	var scene = await _scene()
	var depths := {}
	for wall in [["3.0", 38.0, 41.4, 3.0], ["2.6", 50.0, 53.4, 2.6]]:
		await _place(scene, Vector3(wall[1], 0.05, -85.0))
		var seen := {"feet": NAN}
		await _run(scene, 300, _catch_policy(wall[2], func(s, _i, _st):
			if s.traversal.mantle._hang_time > 0.3 and is_nan(seen.feet):
				seen.feet = s.body.global_position.y
			return _input(false, Vector2.ZERO)))
		depths[wall[0]] = float(wall[3]) - float(seen.feet)
	var full: float = scene.traversal.mantle.hand_reach(scene.body) - MantleAction.DANGLE_SLACK
	print("DEPTHS ", depths, " full ", full)
	t.ok(absf(depths["3.0"] - full) < 0.02, "3.0 m: hangs at arm's length (%.2f m below the top)" % depths["3.0"])
	t.ok(absf(depths["2.6"] - full) < 0.02 and 2.6 - depths["2.6"] > 0.3, "2.6 m: also at arm's length, feet %.2f m off the ground" % (2.6 - depths["2.6"]))
