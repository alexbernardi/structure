extends RefCounted

const Params = preload("res://animation/locomotion_params.gd")
const Model = preload("res://animation/locomotion_model.gd")
const Visual = preload("res://character/authored_mannequin.gd")
const Animator = preload("res://animation/authored_animation.gd")
const DT := 1.0 / 120.0
var _tree: SceneTree
var _visual
var _animator
var _params


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_params = Params.create()
	_visual = Visual.new()
	_tree.root.add_child(_visual)
	await _tree.process_frame
	_animator = Animator.new()
	_visual.add_child(_animator)
	_animator.setup(_visual, _params)


func after_each() -> void:
	_visual.queue_free()
	await _tree.process_frame


func _state(speed: float, extra := {}) -> Dictionary:
	var result := {"speed": speed, "grounded": true, "vy": 0.0, "heading": 0.0, "accel_forward": 0.0}
	result.merge(extra, true)
	return result


func test_only_four_principal_controls_and_two_switches(t) -> void:
	t.eq(_params.ids().size(), 6, "four sliders, IK and legacy toggles only")
	var numbers := 0
	for definition in _params.definitions():
		t.eq(definition.affects, "visual", "no physical parameter")
		if definition.get("type", "") != "bool":
			numbers += 1
	t.eq(numbers, 4, "four principal tunables")
	t.ok(not _params.is_on("legacy"), "normal playback defaults to authored")


func test_requested_speed_trials_have_bounded_cadence_stride_and_finite_poses(t) -> void:
	for speed in [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0]:
		for i in 240:
			_animator.update(DT, _state(speed))
			t.ok(_animator.model.cadence >= Model.MIN_RATE and _animator.model.cadence <= Model.MAX_RATE, "bounded cadence")
			t.ok(_animator.model.stride >= 0.9 and _animator.model.stride <= 1.1, "no exaggerated stride")
			t.ok(_animator.max_correction <= Animator.MAX_FOOT_CORRECTION + 1e-6, "bounded foot correction")
			for bone in _visual.BONES:
				var transform: Transform3D = _visual.skeleton.get_bone_global_pose(_visual.bone_index[bone])
				t.ok(transform.origin.is_finite() and transform.basis.is_finite(), "finite %s at %.1f m/s" % [bone, speed])
		t.eq(_animator.model.state, "Idle" if speed == 0.0 else "Run", "walking is not a locomotion state")
		print("Authored %.1f m/s: cadence %.3f, stride %.3f, run weight %.3f, sprint blend %.3f" % [
			speed, _animator.model.cadence, _animator.model.stride, _animator.model.run_weight, _animator.model.sprint_blend])


func test_physical_state_owns_jump_fall_and_landing(t) -> void:
	_animator.update(DT, _state(6.0, {"grounded": false, "vy": 4.0}))
	t.eq(_animator.model.state, "Jump", "physical takeoff")
	_animator.update(DT, _state(6.0, {"grounded": false, "vy": -1.0}))
	t.eq(_animator.model.state, "Fall", "physical apex")
	_animator.update(DT, _state(6.0))
	t.eq(_animator.model.state, "Land", "physical contact")
	for i in 48:
		_animator.update(DT, _state(6.0))
	t.eq(_animator.model.state, "Run", "landing does not block movement while a long clip finishes")


func test_jog_and_sprint_share_native_cyclic_phase(t) -> void:
	var run: AnimationNodeBlendTree = _animator.machine.get_node("Run")
	var blend: AnimationNodeBlendSpace1D = run.get_node("Gaits")
	t.eq(blend.sync_mode, AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE, "different-length clips use normalized cyclic sync")
	for i in 600:
		_animator.update(DT, _state(6.0 + 1.5 * sin(i * 0.02)))
	t.eq(_animator.playback.get_current_node(), &"Run", "speed changes don't restart the state")
	t.eq(_animator.tree.root_motion_track, NodePath(""), "no root-motion consumer can move the body")


func test_final_modifier_pose_preserves_feet_and_prevents_flat_ground_penetration(t) -> void:
	var worst_sole := INF
	var worst_target_error := 0.0
	var largest_frame_step := 0.0
	var previous := {}
	for speed in [0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0]:
		for i in 240:
			_animator.update(DT, _state(speed))
			await _tree.process_frame
			if i < 60:
				continue
			for index in 2:
				var side := "Left" if index == 0 else "Right"
				var foot: Transform3D = _animator.final_feet[side]
				var target: Transform3D = _animator._targets[index].transform
				worst_target_error = maxf(worst_target_error, foot.origin.distance_to(target.origin))
				t.ok(foot.basis.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion()) < 0.002, "native IK retains authored ankle orientation")
				for point in _visual.sole_points[side]:
					worst_sole = minf(worst_sole, (foot * point).y)
				if previous.has(side) and i > 60:
					largest_frame_step = maxf(largest_frame_step, foot.origin.distance_to(previous[side]))
				previous[side] = foot.origin
	t.ok(worst_sole > -0.002, "final rendered sole penetration <2 mm: %.6f m" % worst_sole)
	t.ok(worst_target_error < 0.002, "IK reaches its bounded positional target within 2 mm: %.6f m" % worst_target_error)
	t.ok(largest_frame_step < 0.20, "loop/phase continuity: no ankle teleport >20 cm at 120 Hz: %.6f m" % largest_frame_step)


func test_state_crossfades_are_continuous_and_crouch_is_authored(t) -> void:
	var previous: Vector3
	var worst := 0.0
	for i in 720:
		var phase := i / 120
		var state := _state(0.0 if phase == 0 or phase == 5 else 6.0)
		if phase == 2:
			state.merge({"grounded": false, "vy": 4.0}, true)
		elif phase == 3:
			state.merge({"grounded": false, "vy": -4.0}, true)
		elif phase == 5:
			state.crouching = true
		_animator.update(DT, state)
		var hip: Vector3 = _visual.skeleton.get_bone_global_pose(_visual.bone_index.Hips).origin
		if i > 60:
			worst = maxf(worst, hip.distance_to(previous))
		previous = hip
	t.ok(worst < 0.10, "no hip pose jump >10 cm per 120 Hz sample through start/stop/jump/land/crouch: %.6f m" % worst)
	t.eq(_animator.model.state, "Crouch", "existing physical crouch uses the authentic crouch subset")
