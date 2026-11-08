extends RefCounted

const SCENE = preload("res://scenes/gait_treadmill.tscn")
const Presets = preload("res://tuning/preset_store.gd")
const Registry = preload("res://tuning/tunable_registry.gd")
const DT := 1.0 / 60.0

var _tree: SceneTree
var _scene


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_scene = SCENE.instantiate()
	_scene.options = {"no-tuning": "true", "no-window-state": "true"}
	_tree.root.add_child(_scene)
	await _tree.process_frame
	_scene.set_process(false)


func after_each() -> void:
	_scene.queue_free()
	await _tree.process_frame
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://walk_graph_test/graph.json" + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://walk_graph_test"))


func test_real_graph_and_generated_tracks(t) -> void:
	_scene.advance(DT)
	var a = _scene.visual.walk_animation
	t.ok(a.tree.active and a.tree.tree_root is AnimationNodeBlendTree, "real active blend tree")
	t.ok(a.player is AnimationPlayer, "real animation player")
	t.ok(a.player.get_animation("walk").get_track_count() == 16, "15 bone rotations and pelvis position")
	t.eq(a.player.get_animation("walk").track_get_key_count(0), a.SAMPLES + 1, "generated full loop")
	t.ok(a.tree.get("parameters/WalkBlend/blend_amount") == 1.0, "saved walk is the default graph input")


func test_characters_do_not_share_mutable_animation_clips(t) -> void:
	_scene.advance(DT)
	var other := SCENE.instantiate()
	other.options = {"no-tuning": "true", "no-window-state": "true"}
	_tree.root.add_child(other)
	await _tree.process_frame
	other.set_process(false)
	var first = _scene.visual.walk_animation
	var second = other.visual.walk_animation
	for name in ["walk", "body", "legacy", "RESET"]:
		t.ok(first.player.get_animation(name) != second.player.get_animation(name), "%s is per-character" % name)
	var before: Vector3 = _scene.visual.joint_position("foot_l")
	other.rig_params.set_value("thigh_length", 0.6)
	other.advance(DT)
	_scene.advance(0.0)
	t.ok(before.distance_to(_scene.visual.joint_position("foot_l")) < 1e-5, "editing another rig cannot alter this character")
	other.queue_free()
	await _tree.process_frame


func test_sandbox_uses_the_tree_without_changing_the_collision_rig(t) -> void:
	var sandbox: Node = load("res://scenes/flat_plane.tscn").instantiate()
	sandbox.options = {"no-tuning": "true", "no-capture": "true", "no-window-state": "true", "legacy-animation": "true"}
	_tree.root.add_child(sandbox)
	await _tree.process_frame
	sandbox.set_process(false)
	sandbox.set_physics_process(false)
	t.ok(sandbox.visual.walk_animation.tree.active, "sandbox tree active")
	t.ok(sandbox.gait_model.rig == null, "original visual rig retained")
	t.near(sandbox.visual.dims.thigh, 0.45, 1e-6, "original thigh length")
	var before := [sandbox.body.get_child(0).shape.height, sandbox.body.get_child(0).shape.radius]
	sandbox.visual.walk_animation.params.set_value("walk_blend", 0.0)
	sandbox.visual.walk_animation.params.set_value("playback_speed", 0.5)
	sandbox._process(DT)
	t.eq([sandbox.body.get_child(0).shape.height, sandbox.body.get_child(0).shape.radius], before, "graph controls do not resize collider")
	sandbox.queue_free()
	await _tree.process_frame


func test_tree_blend_values_change_the_actual_skeleton(t) -> void:
	_scene.gait_params.set_value("freeze", 1.0)
	_scene.gait_params.set_value("scrub", 0.25)
	_scene.advance(DT)
	var a = _scene.visual.walk_animation
	var walk: Vector3 = _scene.visual.joint_position("foot_l")
	a.tree.set("parameters/WalkBlend/blend_amount", 0.0)
	_scene.advance(0.0)
	t.eq(a.params.get_value("walk_blend"), 0.0, "remote inspector edit reaches tuning/presets")
	t.ok(walk.distance_to(_scene.visual.joint_position("foot_l")) > 0.03, "WalkBlend chooses a different actual pose")
	a.params.set_value("walk_blend", 1.0)
	_scene.advance(0.0)
	t.ok(walk.distance_to(_scene.visual.joint_position("foot_l")) < 1e-5, "tuning edit restores the graph pose")
	var chest: Quaternion = _scene.visual.skeleton.get_bone_pose_rotation(_scene.visual.bone_index.chest)
	a.params.set_value("body_blend", 0.0)
	_scene.advance(0.0)
	var without: Quaternion = _scene.visual.skeleton.get_bone_pose_rotation(_scene.visual.bone_index.chest)
	t.ok((chest * Vector3.UP).distance_to(without * Vector3.UP) > 1e-4, "BodyAdd changes the spring layer")


func test_generated_walk_alone_matches_planned_feet(t) -> void:
	var a = _scene.visual.walk_animation
	a.params.set_value("body_blend", 0.0)
	_scene.gait_params.set_value("freeze", 1.0)
	var worst := 0.0
	for i in 73:
		_scene.gait_params.set_value("scrub", float(i) / 73.0)
		_scene.advance(0.0)
		var pose: Dictionary = _scene.model.pose
		for side in ["l", "r"]:
			var sign_x := -1.0 if side == "l" else 1.0
			var hip: Vector3 = pose.pelvis + pose.pelvis_q * Vector3(sign_x * _scene.visual.dims.hip_x, -_scene.visual.dims.hip_drop, 0.0)
			var planned := Vector3(hip.x, pose["ankle_" + side].y, -pose["ankle_" + side].x)
			worst = maxf(worst, planned.distance_to(_scene.visual.joint_position("foot_" + side)))
	t.ok(worst < 0.001, "generated clip alone places both ankles within 1 mm: %.6f m" % worst)


func test_parameters_and_rig_refresh_clips_without_resetting_phase(t) -> void:
	_scene.gait_params.set_value("freeze", 1.0)
	_scene.gait_params.set_value("scrub", 0.2)
	_scene.advance(DT)
	var a = _scene.visual.walk_animation
	var generation: int = a.generation
	_scene.rig_params.set_value("thigh_length", 0.55)
	_scene.gait_params.set_value("step_height", 0.12)
	_scene.advance(0.0)
	t.eq(a.generation, generation + 1, "one combined regeneration")
	t.near(_scene.model.phase, 0.2, 1e-9, "phase preserved")
	_scene.gait_params.set_value("view_zoom", 1.1)
	_scene.gait_params.set_value("scrub", 0.4)
	_scene.advance(0.0)
	t.eq(a.generation, generation + 1, "camera and scrub edits do not rebake")
	t.near(_scene.model.phase, 0.4, 1e-9, "scrub still poses the tree")


func test_continuously_changing_speed_does_not_rebuild_the_loop_or_lose_pose_accuracy(t) -> void:
	_scene.set_running(true)
	var a = _scene.visual.walk_animation
	var worst := 0.0
	var generation := -1
	for body_blend in [0.0, 1.0]:
		a.params.set_value("body_blend", body_blend)
		for i in 360:
			var speed := (6.1 if i < 180 else 12.2) + 0.006 * sin(i * 1.7)
			var pose: Dictionary = _scene.model.update(DT, speed)
			_scene.visual.update_pose({"speed": speed, "vy": 0.0, "grounded": true, "crouching": false,
				"heading": i * 0.025, "accel_forward": 0.0, "gait": pose}, DT)
			if generation < 0:
				generation = a.generation
			t.eq(a.generation, generation, "turning-speed jitter and sprint changes do not rebake the full cycle")
			t.near(_scene.model.cycle.v, speed, 1e-9, "actual speed is neither quantized nor capped at 8 m/s")
			t.near(a.tree.get("parameters/Walk/current_position"), _scene.model.phase, 1e-5, "graph clock remains synchronized")
			worst = maxf(worst, _ankle_error(pose))
	t.ok(worst < 0.001, "speed-dependent samples retain <1 mm ankle error with BodyAdd off/on: %.6f m" % worst)
	t.eq(a.player.get_animation("walk").track_get_key_count(0), a.RUN_SAMPLES + 1, "sample updates never append duplicate keys")
	_scene.gait_params.set_value("run_knee_drive", 0.3)
	var pose: Dictionary = _scene.model.update(DT, 6.0)
	_scene.visual.update_pose({"speed": 6.0, "grounded": true, "gait": pose}, DT)
	t.eq(a.generation, generation + 1, "an actual gait edit still rebuilds all samples")


func test_speed_cache_handles_arbitrary_scrubs_idle_and_loop_boundaries_in_both_modes(t) -> void:
	var a = _scene.visual.walk_animation
	a.params.set_value("body_blend", 0.0)
	var worst := 0.0
	for running in [false, true]:
		_scene.set_running(running)
		_scene.gait_params.set_value("freeze", 1.0)
		var generation := -1
		for speed in ([0.0, 6.1, 12.2] if running else [0.0, 1.55, 3.5]):
			for phase in [0.995, 0.005, 0.375, 0.5, 1.0, 0.0, 0.625]:
				_scene.gait_params.set_value("scrub", phase)
				var pose: Dictionary = _scene.model.update(0.0, speed)
				_scene.visual.update_pose({"speed": speed, "grounded": true, "gait": pose}, 0.0)
				if generation < 0:
					generation = a.generation
				t.eq(a.generation, generation, "speed changes and arbitrary seeks do not rebuild the loop")
				t.near(a.tree.get("parameters/Walk/current_position"), _scene.model.phase, 1e-5, "native graph seeks to the requested phase")
				if pose.active:
					worst = maxf(worst, _ankle_error(pose))
		var clip: Animation = a.player.get_animation("walk")
		for track in clip.get_track_count():
			t.eq(clip.track_get_key_count(track), (a.RUN_SAMPLES if running else a.SAMPLES) + 1, "all tracks replace existing keys")
	t.ok(worst < 0.001, "scrubbed walk/run feet remain within 1 mm without the additive correction: %.6f m" % worst)


func _ankle_error(pose: Dictionary) -> float:
	var worst := 0.0
	var c: Dictionary = _scene.model.cycle
	for side in ["l", "r"]:
		var off: Vector3 = pose.pelvis_q * Vector3(-c.hip_x if side == "l" else c.hip_x, -c.hip_drop, 0.0)
		var ankle: Vector3 = pose["ankle_" + side]
		var planned := Vector3(pose.pelvis.x + off.x, ankle.y, -ankle.x)
		var actual: Vector3 = _scene.visual.skeleton.get_bone_global_pose(_scene.visual.bone_index["foot_" + side]).origin
		worst = maxf(worst, planned.distance_to(actual))
	return worst


func test_half_speed_stays_synchronized_with_belt_and_freeze(t) -> void:
	_scene.advance(DT)
	var a = _scene.visual.walk_animation
	a.params.set_value("playback_speed", 0.5)
	_scene.gait_params.set_value("time_scale", 0.5)
	_scene._sole_valid.fill(false)
	_scene._slip_peak.fill(0.0)
	_scene._slip_clock = 0.0
	var phase: float = _scene.model.phase
	var belt: float = _scene.belt_offset
	for i in 60:
		_scene.advance(DT)
		_scene._measure_slip(DT)
	t.near(fposmod(_scene.model.phase - phase, 1.0), float(_scene.model.cycle.rate) * 0.25, 1e-5, "both playback scales applied exactly once")
	t.near(_scene.belt_offset - belt, _scene.speed * 0.25, 1e-5, "same belt clock")
	t.near(a.tree.get("parameters/Walk/current_position"), _scene.model.phase, 1e-5, "native graph and model clocks agree")
	t.ok(maxf(_scene.slip_l, _scene.slip_r) < 0.003, "no time-scale foot slip: L %.6f R %.6f" % [_scene.slip_l, _scene.slip_r])
	_scene.gait_params.set_value("freeze", 1.0)
	_scene.gait_params.set_value("scrub", 0.6)
	_scene.advance(DT)
	var foot: Vector3 = _scene.visual.joint_position("foot_l")
	_scene.advance(0.0)
	t.ok(foot.distance_to(_scene.visual.joint_position("foot_l")) < 1e-6, "tree holds the scrubbed phase")


func test_graph_values_round_trip_through_existing_presets(t) -> void:
	var reg := Registry.new()
	var params = _scene.visual.walk_animation.params
	reg.register("graph", "Animation graph", params)
	params.set_value("walk_blend", 0.35)
	params.set_value("body_blend", 0.6)
	params.set_value("playback_speed", 0.75)
	var saved: Dictionary = reg.capture()
	var store := Presets.new("user://walk_graph_test")
	var result := store.save_preset("graph", saved)
	t.ok(result.ok, "saved")
	params.reset_all()
	var loaded := store.load_preset("graph", reg)
	t.ok(loaded.ok, "loaded")
	params.apply(loaded.targets.graph)
	t.eq(reg.capture(), saved, "all graph values persisted")
	t.near(_scene.visual.walk_animation.tree.get("parameters/WalkSpeed/scale"), 0.75, 1e-9, "restored native TimeScale")
