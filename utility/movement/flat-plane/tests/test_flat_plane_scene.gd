extends RefCounted

const SCENE := "res://scenes/flat_plane.tscn"
const DT := 1.0 / 120.0
const FWD := Vector2(0, 1)

var _s
var _tree: SceneTree


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_s = load(SCENE).instantiate()
	_s.options = {"no-capture": "true"}
	_tree.root.add_child(_s)
	_s.set_physics_process(false)   # the tests drive the body themselves, one call per physics tick
	_s.set_process(false)
	await _tree.physics_frame
	await _tree.physics_frame


func after_each() -> void:
	_s.queue_free()
	await _tree.process_frame


func _frame(move := Vector2.ZERO, extra := {}) -> Dictionary:
	var f := {"move": move, "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}
	f.merge(extra, true)
	return f


func _run(frame: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		await _tree.physics_frame
		_s.body.simulate(frame, DT)


## Like _run, but returns the highest point the body reached.
func _run_max_height(frame: Dictionary, seconds: float) -> float:
	var top: float = _s.body.global_position.y
	for i in int(round(seconds / DT)):
		await _tree.physics_frame
		_s.body.simulate(frame, DT)
		top = maxf(top, _s.body.global_position.y)
	return top


## Teleports to a spot and lets the body settle on whatever is below it.
func _place(pos: Vector3) -> void:
	_s.body.global_position = pos
	_s.body.velocity = Vector3.ZERO
	_s.body.core.reset()
	await _run(_frame(), 0.3)


func test_scene_builds_every_module(t) -> void:
	t.ok(_s.world != null and _s.body != null and _s.visual != null and _s.cam != null, "world, body, visual, camera")
	t.ok(_s.world.get_node_or_null("Plane") != null and _s.world.get_node_or_null("Sun") != null and _s.world.get_node_or_null("WorldEnvironment") != null, "plane, sun, sky")
	for ramp in [10, 20, 30, 40, 50]:
		t.ok(_s.world.get_node_or_null("Ramp%d" % ramp) != null, "ramp %d" % ramp)
	t.ok(_s.world.get_node_or_null("Stair0_0") != null and _s.world.get_node_or_null("Block100") != null, "stairs and obstacles")
	t.ok(_s.world.get_node_or_null("SpawnPad") != null, "respawn pad")


func test_modules_are_separate_nodes(t) -> void:
	t.ok(_s.body is CharacterBody3D, "collision body")
	t.ok(_s.visual.get_parent() == _s.body and not (_s.visual is CollisionObject3D), "visual is a child, not the collider")
	t.ok(_s.cam.get_parent() == _s and _s.cam.target == _s.body, "camera is its own rig following the body")
	t.ok(_s.body.core != null and _s.body.core.p == _s.params.values, "simulation shares the live parameter dictionary")


func test_spawns_on_the_floor(t) -> void:
	await _run(_frame(), 0.3)
	t.ok(_s.body.is_on_floor(), "grounded after spawn")
	t.near(_s.body.global_position.y, 0.0, 0.03, "feet at ground level")


func test_walks_forward_to_max_speed(t) -> void:
	await _run(_frame(FWD), 1.5)
	var v: Vector3 = _s.body.velocity
	t.near(Vector2(v.x, v.z).length(), 4.5, 0.05, "reaches max ground speed on real collision")
	t.ok(_s.body.global_position.z < -3.0, "moved toward -Z: z = %.2f" % _s.body.global_position.z)


func test_jump_apex_matches_the_core(t) -> void:
	await _run(_frame(), 0.3)
	var top := 0.0
	await _tree.physics_frame
	_s.body.simulate(_frame(Vector2.ZERO, {"jump_pressed": true}), DT)
	for i in 120:
		await _tree.physics_frame
		_s.body.simulate(_frame(), DT)
		top = maxf(top, _s.body.global_position.y)
	t.near(top, 5.5 * 5.5 / (2.0 * 19.6), 0.08, "apex %.3f m vs v^2/2g" % top)
	await _run(_frame(), 1.0)
	t.ok(_s.body.is_on_floor(), "lands again")


func test_gentle_ramps_are_climbed_and_steep_ones_are_not(t) -> void:
	await _place(_s.world.landmarks["ramp_20"] + Vector3(0, 0.05, 4.0))
	await _run(_frame(FWD), 3.0)
	t.ok(_s.body.global_position.y > 1.0, "20 deg ramp climbed: y = %.2f" % _s.body.global_position.y)
	await _place(_s.world.landmarks["ramp_40"] + Vector3(0, 0.05, 4.0))
	await _run(_frame(FWD), 3.0)
	t.ok(_s.body.global_position.y > 1.0, "40 deg ramp (under the 46 deg limit) climbed: y = %.2f" % _s.body.global_position.y)
	await _place(_s.world.landmarks["ramp_50"] + Vector3(0, 0.05, 4.0))
	await _run(_frame(FWD), 3.0)
	t.ok(_s.body.global_position.y < 0.6, "50 deg ramp is too steep to walk up: y = %.2f" % _s.body.global_position.y)


func test_walkable_slope_limit_is_live_tunable(t) -> void:
	_s.params.set_value("max_walkable_slope", 60.0)
	await _place(_s.world.landmarks["ramp_50"] + Vector3(0, 0.05, 4.0))
	await _run(_frame(FWD), 3.0)
	t.ok(_s.body.global_position.y > 1.5, "with the limit raised to 60 deg the 50 deg ramp is walkable: y = %.2f" % _s.body.global_position.y)


func test_stairs_are_stepped_up_within_step_height(t) -> void:
	# Eight steps per flight; the flights end, so measure the highest point reached rather than the final height.
	for case in [["0.18", 1.4], ["0.30", 2.3]]:
		await _place(_s.world.landmarks["stairs_" + case[0]] + Vector3(-1.5, 0.05, 0))
		var top: float = await _run_max_height(_frame(Vector2(1, 0)), 3.0)   # +X is "right"
		t.ok(top >= case[1], "%s m risers: reached %.2f m of %.2f m" % [case[0], top, case[1]])


func test_a_riser_taller_than_the_step_height_blocks(t) -> void:
	await _place(_s.world.landmarks["stairs_0.50"] + Vector3(-1.5, 0.05, 0))
	var top: float = await _run_max_height(_frame(Vector2(1, 0)), 3.0)
	t.ok(top < 0.2, "0.50 m riser is not stepped: reached %.2f m" % top)
	_s.params.set_value("step_height", 0.55)
	top = await _run_max_height(_frame(Vector2(1, 0)), 3.0)
	t.ok(top > 3.5, "with step height 0.55 the flight can be climbed: reached %.2f m" % top)


func test_crouching_fits_under_the_lintel_and_standing_does_not(t) -> void:
	await _place(_s.world.landmarks["tunnel"])
	await _run(_frame(FWD, {"yaw": PI}), 2.0)   # yaw PI: forward = +Z
	t.ok(_s.body.global_position.z < 25.5, "standing is stopped by the 1.3 m lintel: z = %.2f" % _s.body.global_position.z)
	await _place(_s.world.landmarks["tunnel"])
	await _run(_frame(FWD, {"yaw": PI, "crouch": true}), 3.0)
	t.ok(_s.body.global_position.z > 28.0, "crouched passes through: z = %.2f" % _s.body.global_position.z)


func test_cannot_stand_up_under_a_low_ceiling(t) -> void:
	await _place(_s.world.landmarks["tunnel"])
	await _run(_frame(FWD, {"yaw": PI, "crouch": true}), 1.0)
	await _run(_frame(Vector2.ZERO, {"yaw": PI}), 0.5)   # release crouch under the lintel
	t.ok(_s.body.core.crouching, "stays crouched without headroom (z = %.2f)" % _s.body.global_position.z)
	t.near(_s.body.current_height(), 1.1, 0.001, "collider stays short")
	await _run(_frame(FWD, {"yaw": PI}), 3.0)
	await _run(_frame(), 0.5)
	t.ok(not _s.body.core.crouching, "stands once clear")


func test_crouch_shrinks_the_collider_and_keeps_feet_on_the_floor(t) -> void:
	await _run(_frame(), 0.3)
	var shape: CapsuleShape3D = _s.body.get_child(0).shape
	t.near(shape.height, 1.8, 0.001, "standing capsule")
	await _run(_frame(Vector2.ZERO, {"crouch": true}), 0.3)
	t.near(shape.height, 1.1, 0.001, "crouching capsule")
	t.ok(_s.body.is_on_floor() and absf(_s.body.global_position.y) < 0.03, "still on the floor")


func test_camera_yaw_steers_movement(t) -> void:
	await _run(_frame(FWD, {"yaw": PI / 2.0}), 1.5)
	t.ok(_s.body.global_position.x < -3.0 and absf(_s.body.global_position.z) < 0.5, "yaw 90 deg: forward is -X (x = %.2f)" % _s.body.global_position.x)


func test_live_parameter_changes_apply_immediately(t) -> void:
	await _place(Vector3(150, 0.05, 150))   # open ground: nothing to slow the run
	var right := Vector2(1, 0)
	await _run(_frame(right), 1.0)
	_s.params.set_value("max_ground_speed", 8.0)
	await _run(_frame(right), 1.0)
	var v: Vector3 = _s.body.velocity
	t.near(Vector2(v.x, v.z).length(), 8.0, 0.1, "no restart needed")
	_s.params.reset_all()
	await _run(_frame(right), 1.5)
	v = _s.body.velocity
	t.near(Vector2(v.x, v.z).length(), 4.5, 0.1, "reset returns to defaults")


func test_falling_off_the_world_respawns(t) -> void:
	var count := [0]
	_s.body.respawned.connect(func() -> void: count[0] += 1)
	_s.body.global_position = Vector3(300, -45, 0)
	await _run(_frame(), 0.1)
	t.eq(count[0], 1, "respawn signal")
	t.near(_s.body.global_position.distance_to(_s.world.spawn_transform.origin), 0.0, 0.2, "back at the spawn pad")
	t.eq(_s.body.core.velocity, Vector3.ZERO, "velocity cleared")


func test_landing_reports_impact_speed(t) -> void:
	var impacts := []
	_s.body.landed.connect(func(v: float) -> void: impacts.append(v))
	await _place(Vector3(0, 6.0, 12.0 + 6.0))
	await _run(_frame(), 1.5)   # a 6 m fall takes about 0.8 s
	t.ok(impacts.size() >= 1 and impacts[-1] > 8.0, "fell ~6 m, impact %s" % str(impacts))


func test_skeleton_structure(t) -> void:
	var v = _s.visual
	t.eq(v.skeleton.get_bone_count(), 15, "15 bones")
	for name in ["pelvis", "spine", "chest", "neck", "head", "upper_arm_l", "forearm_l", "upper_arm_r", "forearm_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]:
		t.ok(v.bone_index.has(name), "bone %s" % name)
	t.eq(v.skeleton.get_bone_parent(v.bone_index.shin_l), v.bone_index.thigh_l, "knee hangs from the thigh")
	t.eq(v.skeleton.get_bone_parent(v.bone_index.thigh_l), v.bone_index.pelvis, "thigh hangs from the pelvis")
	var meshes := 0
	for n in v.skeleton.get_children():
		if n is BoneAttachment3D and n.get_child_count() > 0 and n.get_child(0) is MeshInstance3D:
			meshes += 1
	t.eq(meshes, 15, "a primitive mesh on every bone")


func test_standing_pose_stands_on_the_ground(t) -> void:
	var v = _s.visual
	v.update_pose({"speed": 0.0, "grounded": true}, 0.1)
	t.near(v.joint_height("pelvis"), 1.0, 0.03, "hips about 1 m up")
	t.near(v.joint_height("foot_l") - 0.065, 0.0, 0.03, "feet on the ground")
	var head: float = v.joint_height("head")
	t.ok(head > 1.6 and head < 1.85, "head height %.2f" % head)


func test_gait_swings_the_legs_with_speed(t) -> void:
	var v = _s.visual
	var spread_idle := 0.0
	var spread_run := 0.0
	for i in 120:
		v.update_pose({"speed": 0.0, "grounded": true}, 1.0 / 60.0)
		spread_idle = maxf(spread_idle, absf(v.joint_height("foot_l") - v.joint_height("foot_r")))
	for i in 120:
		v.update_pose({"speed": 5.0, "grounded": true}, 1.0 / 60.0)
		spread_run = maxf(spread_run, absf(v.joint_height("foot_l") - v.joint_height("foot_r")))
	t.ok(spread_run > spread_idle + 0.1, "feet alternate while running: %.3f vs idle %.3f" % [spread_run, spread_idle])


func test_crouch_and_air_poses(t) -> void:
	var v = _s.visual
	for i in 30:
		v.update_pose({"speed": 0.0, "grounded": true}, 1.0 / 60.0)
	var stand: float = v.joint_height("pelvis")
	for i in 30:
		v.update_pose({"speed": 0.0, "grounded": true, "crouching": true}, 1.0 / 60.0)
	t.ok(v.joint_height("pelvis") < stand - 0.25, "crouch lowers the hips: %.2f -> %.2f" % [stand, v.joint_height("pelvis")])
	for i in 30:
		v.update_pose({"speed": 0.0, "grounded": false, "vy": 4.0}, 1.0 / 60.0)
	t.ok(v.air_blend > 0.9, "airborne pose engaged")
	var knee: float = v.skeleton.get_bone_pose_rotation(v.bone_index.shin_l).get_euler().x
	t.ok(knee < -0.5, "knees tucked in the air: %.2f rad" % knee)


func test_visual_turns_toward_the_heading(t) -> void:
	var v = _s.visual
	for i in 60:
		v.update_pose({"speed": 4.0, "grounded": true, "heading": -PI / 2.0}, 1.0 / 60.0)
	t.near(v.rotation.y, -PI / 2.0, 0.05, "faces its direction of travel")


func test_camera_follows_and_orbits(t) -> void:
	_s.cam.snap()
	await _tree.process_frame
	var target: Vector3 = _s.body.global_position + Vector3.UP * _s.cam.follow_height
	t.near(_s.cam.global_position.distance_to(target), 0.0, 0.1, "rig sits on the follow point")
	var cam_pos: Vector3 = _s.cam.camera.global_position
	t.ok(cam_pos.distance_to(target) > 1.0 and cam_pos.distance_to(target) < _s.cam.distance + 0.5, "camera is held behind the character")
	t.ok(cam_pos.z > target.z, "default view looks along -Z, so the camera is behind at +Z")
	_s.cam.look(Vector2(400, 0))
	t.ok(_s.cam.yaw < -0.5, "mouse right turns the view right (negative yaw)")
	_s.cam.look(Vector2(0, 100000))
	t.ok(_s.cam.pitch >= _s.cam.MIN_PITCH - 0.0001, "pitch is clamped")
	_s.cam.zoom(100.0)
	t.eq(_s.cam.distance, _s.cam.MAX_DISTANCE, "zoom is clamped")
