extends RefCounted

const GP = preload("res://animation/gait_params.gd")
const RP = preload("res://animation/rig_params.gd")
const GM = preload("res://animation/gait_model.gd")
const DT := 1.0 / 60.0
var _s
var _tree: SceneTree


func before_each() -> void:
	_tree = Engine.get_main_loop()


func after_each() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
		await _tree.process_frame
	_s = null


func _boot() -> Node:
	_s = load("res://scenes/gait_treadmill.tscn").instantiate()
	_s.options = {"no-tuning": "true", "no-hardware": "true", "no-window-state": "true"}
	_tree.root.add_child(_s)
	await _tree.process_frame
	_s.set_process(false)
	_s.advance(DT)
	return _s


func _edit(s: Node) -> void:
	s.gait_params.set_value("edit_path", 1.0)
	s.advance(DT)
	s.path_editor._process(0.0)


func _button(s: Node, pos: Vector2, pressed: bool) -> bool:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.pressed = pressed
	return s.path_editor.handle_input(ev)


func _motion(s: Node, pos: Vector2, relative: Vector2) -> bool:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.relative = relative
	return s.path_editor.handle_input(ev)


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func test_defaults_extend_the_stance_knee_then_flex_it_in_swing(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	m.cycle = m.cycle_for(1.55)
	var stance_min := 180.0
	var stance_max := 0.0
	var swing_max := 0.0
	for i in 200:
		var pose: Dictionary = m.pose_at(i / 200.0)
		var flex := rad_to_deg(pose.knee_l)
		if pose.contact_l:
			stance_min = minf(stance_min, flex)
			stance_max = maxf(stance_max, flex)
		else:
			swing_max = maxf(swing_max, flex)
	t.ok(stance_min < 20.0 and stance_min >= 13.0, "near straight without locking: %.1f deg" % stance_min)
	t.ok(stance_max - stance_min > 17.0, "stance flexion varies, rather than holding a crouch: %.1f..%.1f" % [stance_min, stance_max])
	t.ok(swing_max > 70.0 and swing_max < 90.0, "the reference's bent Passing knee: %.1f deg" % swing_max)


func test_swing_offset_moves_the_handle_but_never_the_planted_foot(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	for peak in [0.3, 0.53, 0.7]:
		p.set_value("swing_peak", peak)
		p.set_value("swing_forward", 0.0)
		var base: Dictionary = m.cycle_for(1.55)
		p.set_value("swing_forward", 0.1)
		var edited: Dictionary = m.cycle_for(1.55)
		var q: float = base.d + peak * (1.0 - base.d)
		t.near(m.ankle_at(q, edited).x - m.ankle_at(q, base).x, 0.1, 1e-6, "the selected swing point moves by exactly the offset")
		for i in 61:
			var phase: float = base.d * i / 60.0
			t.near(m.ankle_at(phase, edited), m.ankle_at(phase, base), 1e-6, "stance and toe-off unchanged")
		for boundary in [base.d, 1.0]:
			t.near(m.swing(boundary, edited), m.swing(boundary, base), 1e-6, "handover position unchanged")
			var h: float = 0.002 * (1.0 - base.d)
			var inside: float = boundary + h if boundary == base.d else boundary - h
			t.ok(absf(m.swing(inside, edited).x - m.swing(inside, base).x) < 1e-6, "offset fades cubically at the handover")


func test_path_mode_switches_editors_and_preserves_playback(t) -> void:
	var s := await _boot()
	t.ok(not s.path_editor.active(), "no handles by default")
	s.set_view("front")
	s._unhandled_input(_key(KEY_P))
	s.advance(DT)
	t.ok(s.path_editor.editable() and s.gait_params.is_on("freeze"), "P opens a paused side-view path editor")
	t.eq(s.view, "side-left", "front view is switched to the reference editing plane")
	s._unhandled_input(_key(KEY_E))
	s.advance(DT)
	t.ok(s.gait_params.is_on("edit_rig") and not s.gait_params.is_on("edit_path"), "edit modes are exclusive")
	s._unhandled_input(_key(KEY_E))
	s.advance(DT)
	t.ok(not s.gait_params.is_on("freeze"), "leaving the other editor restores original playback")
	s.gait_params.set_value("freeze", 1.0)
	_edit(s)
	s._unhandled_input(_key(KEY_P))
	s.advance(DT)
	t.ok(s.gait_params.is_on("freeze"), "an already paused cycle stays paused")


func test_dragging_the_swing_point_tracks_the_pointer_in_both_side_projections(t) -> void:
	var s := await _boot()
	_edit(s)
	for view in ["side", "side-left"]:
		for ortho in [1.0, 0.0]:
			s.set_view(view)
			s.gait_params.set_value("view_ortho", ortho)
			s._apply_camera()
			s.gait_params.set_value("swing_forward", 0.0)
			s.gait_params.set_value("step_height", 0.065)
			s.advance(DT)
			s.path_editor._process(0.0)
			var h: Dictionary = s.path_editor._handles[2]
			var point: Vector2 = h.point
			var start: Vector2 = s.path_editor.screen(point)
			var finish: Vector2 = s.path_editor.screen(point + Vector2(0.05, 0.03))
			var generation: int = s.visual.walk_animation.generation
			t.ok(_button(s, start, true), "grab swing handle in %s, ortho %s" % [view, ortho])
			t.ok(_motion(s, finish, finish - start), "mouse motion is consumed")
			t.ok(_button(s, finish, false), "release handle")
			s.advance(DT)
			var after: Vector2 = s.path_editor.build_handles()[2].point
			t.ok(after.distance_to(point + Vector2(0.05, 0.03)) < 0.003, "path follows the world-space drag: %s -> %s" % [point, after])
			t.ok(s.visual.walk_animation.generation > generation, "edits regenerate the real skeleton's clip")


func test_endpoint_drags_move_one_end_and_keep_the_other_anchored(t) -> void:
	var s := await _boot()
	_edit(s)
	for auto in [0.0, 1.0]:
		s.gait_params.set_value("auto_step_length", auto)
		for index in [0, 1]:
			s.gait_params.set_value("step_length", 0.61)
			s.gait_params.set_value("midstance_at", 0.4)
			s.advance(DT)
			s.path_editor._process(0.0)
			var before: Array = s.path_editor.build_handles()
			var start: Vector2 = s.path_editor.screen(before[index].point)
			var delta := Vector2(0.06 if index == 0 else -0.06, 0.0)
			var finish: Vector2 = s.path_editor.screen(before[index].point + delta)
			t.ok(_button(s, start, true), "grab endpoint")
			_motion(s, finish, finish - start)
			_button(s, finish, false)
			var after: Array = s.path_editor.build_handles()
			t.near(after[index].point.x, before[index].point.x + delta.x, 0.012, "dragged endpoint follows, within parameter quantization")
			t.near(after[1 - index].point.x, before[1 - index].point.x, 0.012, "other endpoint remains anchored")
			t.near(after[index].point.y, before[index].point.y, 1e-6, "ground contact height cannot be dragged off the belt")


func test_running_path_edits_and_reset_leave_the_walk_profile_untouched(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("step_height", 0.11)
	var walk := {}
	for id in ["step_length", "midstance_at", "step_height", "swing_forward"]:
		walk[id] = s.gait_params.get_value(id)
	s.run_button.pressed.emit()
	s.advance(DT)
	_edit(s)
	for index in [0, 1, 2]:
		s.path_editor._process(0.0)
		var before: Array = s.path_editor.build_handles()
		var start: Vector2 = s.path_editor.screen(before[index].point)
		var delta := Vector2(0.04 if index != 1 else -0.04, 0.03 if index == 2 else 0.0)
		var finish: Vector2 = s.path_editor.screen(before[index].point + delta)
		t.ok(_button(s, start, true), "grab running handle")
		_motion(s, finish, finish - start)
		_button(s, finish, false)
		s.advance(DT)
		var after: Array = s.path_editor.build_handles()
		t.ok(after[index].point.distance_to(before[index].point + delta) < 0.012, "running handle follows pointer")
		if index < 2:
			t.near(after[1 - index].point.x, before[1 - index].point.x, 0.012, "other contact endpoint remains anchored")
	for id in walk:
		t.eq(s.gait_params.get_value(id), walk[id], "running drags do not edit the walk")
	s.path_editor.handle_input(_key(KEY_BACKSPACE))
	for id in walk:
		t.eq(s.gait_params.get_value(id), walk[id], "running reset also preserves walk tuning")
		t.eq(s.gait_params.get_value("run_" + id), s.gait_params.def("run_" + id).default, "running path reset")


func test_switching_modes_mid_drag_cancels_the_original_profile(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("step_height", 0.11)
	s.gait_params.set_value("run_step_height", 0.4)
	for running in [true, false]:
		s.set_running(running)
		s.advance(DT)
		_edit(s)
		var start: Vector2 = s.path_editor.screen(s.path_editor._handles[2].point)
		t.ok(_button(s, start, true), "start a path edit")
		s.path_editor.drag_by(Vector2(0.05, 0.03))
		var id := "run_step_height" if running else "step_height"
		t.near(s.gait_params.get_value(id), 0.43 if running else 0.14, 1e-9, "drag changed the active profile")
		s.set_running(not running)
		s.advance(DT)
		t.eq(s.path_editor.dragging, -1, "mode switch releases the drag")
		t.near(s.gait_params.get_value("step_height"), 0.11, 1e-9, "original walking value restored or preserved")
		t.near(s.gait_params.get_value("run_step_height"), 0.4, 1e-9, "original running value restored or preserved")
		t.near(s.gait_params.get_value("swing_forward"), 0.0, 1e-9, "walk horizontal edit cancelled")
		t.near(s.gait_params.get_value("run_swing_forward"), 0.0, 1e-9, "run horizontal edit cancelled")


func test_small_drags_accumulate_and_limits_reverse_immediately(t) -> void:
	var s := await _boot()
	_edit(s)
	var start: Vector2 = s.path_editor.screen(s.path_editor._handles[2].point)
	_button(s, start, true)
	for i in 20:
		s.path_editor.drag_by(Vector2(0.0005, 0.0))
	t.near(s.gait_params.get_value("swing_forward"), 0.01, 1e-9, "sub-step movements accumulate")
	s.path_editor.drag_by(Vector2(10.0, 10.0))
	t.near(s.gait_params.get_value("swing_forward"), 0.2, 1e-9, "horizontal maximum")
	t.near(s.gait_params.get_value("step_height"), 0.2, 1e-9, "vertical maximum")
	s.path_editor.drag_by(Vector2(-0.02, -0.02))
	t.near(s.gait_params.get_value("swing_forward"), 0.18, 1e-9, "return immediately from the limit")
	t.near(s.gait_params.get_value("step_height"), 0.18, 1e-9, "vertical return")
	s.gait_params.set_value("stand_height", 0.91)
	t.ok(s.path_editor.handle_input(_key(KEY_ESCAPE)), "Escape cancels")
	t.near(s.gait_params.get_value("swing_forward"), 0.0, 1e-9, "cancel restores the original path")
	t.near(s.gait_params.get_value("step_height"), 0.065, 1e-9, "and clearance")
	t.near(s.gait_params.get_value("stand_height"), 0.91, 1e-9, "cancel does not revert other controls changed during the drag")


func test_hip_handle_reset_and_disabled_views(t) -> void:
	var s := await _boot()
	_edit(s)
	var start: Vector2 = s.path_editor.screen(s.path_editor._handles[3].point)
	t.ok(_button(s, start, true), "grab requested hip height")
	s.path_editor.drag_by(Vector2(0.0, -0.03))
	_button(s, start, false)
	t.ok(s.gait_params.get_value("stand_height") < 0.92, "lowering the handle increases knee bend")
	t.ok(s.path_editor.handle_input(_key(KEY_BACKSPACE)), "Backspace resets only path/hip parameters")
	t.near(s.gait_params.get_value("stand_height"), 0.95, 1e-9, "new default restored")
	t.ok(s.gait_params.is_on("edit_path"), "reset does not exit the editor")
	s.set_view("front")
	s.path_editor._process(0.0)
	t.ok(not s.path_editor.editable() and s.path_editor._handles.is_empty(), "front view has an explanatory banner instead of un-draggable handles")
	t.ok(not _button(s, start, true), "front-view clicks pass through")
	s.set_view("side")
	s.gait_params.set_value("walk_speed", 0.0)
	for i in 60:
		s.advance(DT)
	s.path_editor._process(0.0)
	t.ok(not s.path_editor.editable(), "standing still is explicitly not editable")


func test_viewport_input_routes_path_drags_and_does_not_change_proportions(t) -> void:
	var s := await _boot()
	var viewport: Viewport = s.get_viewport()
	var rig_before: Dictionary = s.rig_params.snapshot()
	viewport.push_input(_key(KEY_P), true)
	s.advance(DT)
	s.path_editor._process(0.0)
	t.ok(s.path_editor.editable(), "the real viewport routes P to the path editor")
	var point: Vector2 = s.path_editor._handles[2].point
	var start: Vector2 = s.path_editor.screen(point)
	var finish: Vector2 = s.path_editor.screen(point + Vector2(0.04, 0.025))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	viewport.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	motion.relative = finish - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = finish
	viewport.push_input(release, true)
	s.advance(DT)
	t.near(s.gait_params.get_value("swing_forward"), 0.04, 1e-9, "scene input reaches the horizontal path edit")
	t.near(s.gait_params.get_value("step_height"), 0.09, 1e-9, "and the vertical path edit")
	t.eq(s.rig_params.snapshot(), rig_before, "path input never leaks into the proportion editor")
	t.eq(s.path_editor.dragging, -1, "mouse release ends the drag through the real input pipeline")
