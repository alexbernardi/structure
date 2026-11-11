extends RefCounted

## Proportions: the rig parameter set, the visual re-proportioning live, the gait model planning for any body, and the
## drag-and-drop handles that edit it.

const SCENE := "res://scenes/gait_treadmill.tscn"
const RigParams = preload("res://systems/movement_core/animation/rig_params.gd")
const GaitParams = preload("res://animation/gait_params.gd")
const GaitModel = preload("res://animation/gait_model.gd")
const Visual = preload("res://systems/movement_core/character/character_visual.gd")

var _tree: SceneTree
var _s


func before_each() -> void:
	_tree = Engine.get_main_loop()


func after_each() -> void:
	if _s != null and is_instance_valid(_s):
		_s.queue_free()
		await _tree.process_frame
	_s = null


func _boot(extra := {}) -> Node:
	var s: Node = load(SCENE).instantiate()
	var opts := {"no-hardware": "true", "no-window-state": "true", "no-tuning": "true"}
	opts.merge(extra, true)
	s.options = opts
	_tree.root.add_child(s)
	await _tree.process_frame   # _ready runs on the first frame and re-enables processing, so disable it afterwards
	s.set_process(false)
	_s = s
	return s


func _run(s: Node, seconds: float) -> void:
	for i in int(round(seconds / (1.0 / 60.0))):
		s.advance(1.0 / 60.0)
		s._measure_slip(1.0 / 60.0)


func _dist(v, a: String, b: String) -> float:
	return v.joint_position(a).distance_to(v.joint_position(b))


# ------------------------------------------------------------------ the parameter set

func test_rig_definitions_are_consistent_and_visual_only(t) -> void:
	var p = RigParams.create()
	t.eq(p.check_definitions(), [], "ids unique, ranges ordered, defaults inside")
	for d in p.definitions():
		t.eq(d.affects, "visual", "%s does not touch the simulation" % d.id)
		t.ok(String(d.unit) != "" and RigParams.GROUPS.has(d.group), "%s has a unit and a group" % d.id)
	t.ok(p.definitions().size() >= 19, "%d proportions" % p.definitions().size())


func test_a_null_rig_is_the_original_rig_and_original_values_give_the_same_dims(t) -> void:
	var d := RigParams.dims(null)
	var original = RigParams.create()
	for id in RigParams.ORIGINAL:
		original.set_value(id, float(RigParams.ORIGINAL[id]))
	var q := RigParams.dims(original)
	for k in d:
		t.eq(d[k], q[k], "dims %s: null and a set holding the original values agree" % k)
	t.ok(RigParams.dims(RigParams.create()).scale != 1.0, "(the saved defaults are the proportions tuned on 2026-11-07, not the original rig)")
	t.near(d.thigh, Visual.THIGH, 1e-12, "thigh")
	t.near(d.shin, Visual.SHIN, 1e-12, "shin")
	t.near(d.ankle_h, Visual.ANKLE_H, 1e-12, "ankle height")
	t.near(d.hip_drop, Visual.HIP_DROP, 1e-12, "hip drop")
	t.near(d.heel.x, GaitModel.HEEL.x, 1e-12, "heel")
	t.near(d.toe.x, GaitModel.TOE.x, 1e-12, "toe")
	t.near(d.hip_x, GaitModel.HIP_X, 1e-12, "hip offset")


func test_scale_multiplies_every_length_and_radius(t) -> void:
	var p = RigParams.create()
	p.set_value("scale", 1.0)
	var base := RigParams.dims(p)
	p.set_value("scale", 1.25)
	var big := RigParams.dims(p)
	for k in ["thigh", "shin", "ankle_h", "foot_len", "hip_x", "torso", "chest", "neck", "head_r", "shoulder_x", "upper_arm", "forearm", "thigh_r", "shin_r", "upper_arm_r", "forearm_r"]:
		t.near(big[k], base[k] * 1.25, 1e-9, "%s scales" % k)
	t.eq(big.torso_w, base.torso_w, "(width and depth are multipliers, not lengths)")


# ------------------------------------------------------------------ the visual

func _visual() -> Node:
	var v := Visual.new()
	_tree.root.add_child(v)
	await _tree.process_frame
	return v


func test_applying_the_original_proportions_changes_nothing(t) -> void:
	var a := await _visual()
	var b := await _visual()
	var original = RigParams.create()
	for id in RigParams.ORIGINAL:
		original.set_value(id, float(RigParams.ORIGINAL[id]))
	b.apply_rig(original)
	for bone in a.bone_index:
		t.ok(a.skeleton.get_bone_rest(a.bone_index[bone]).is_equal_approx(b.skeleton.get_bone_rest(b.bone_index[bone])), "%s rest pose unchanged" % bone)
	for bone in a._meshes:
		var ma: Mesh = a._meshes[bone].mesh
		var mb: Mesh = b._meshes[bone].mesh
		t.eq(ma.get_class(), mb.get_class(), "%s mesh type" % bone)
		t.ok(a._meshes[bone].position.is_equal_approx(b._meshes[bone].position), "%s mesh offset unchanged" % bone)
		t.ok(a._meshes[bone].scale.is_equal_approx(b._meshes[bone].scale), "%s mesh scale unchanged" % bone)
		if ma is BoxMesh:
			t.ok((ma as BoxMesh).size.is_equal_approx((mb as BoxMesh).size), "%s box size unchanged: %s vs %s" % [bone, (ma as BoxMesh).size, (mb as BoxMesh).size])
		elif ma is CapsuleMesh:
			t.near((ma as CapsuleMesh).radius, (mb as CapsuleMesh).radius, 1e-6, "%s radius unchanged" % bone)
			t.near((ma as CapsuleMesh).height, (mb as CapsuleMesh).height, 1e-4, "%s height unchanged: %s vs %s" % [bone, (ma as CapsuleMesh).height, (mb as CapsuleMesh).height])
		elif ma is SphereMesh:
			t.near((ma as SphereMesh).radius, (mb as SphereMesh).radius, 1e-6, "%s sphere unchanged" % bone)
			t.near((ma as SphereMesh).height, (mb as SphereMesh).height, 1e-6, "%s sphere height unchanged" % bone)
	a.queue_free()
	b.queue_free()
	await _tree.process_frame


func test_each_length_parameter_moves_its_joint_by_exactly_that_much(t) -> void:
	var v := await _visual()
	var rig = RigParams.create()
	rig.set_value("scale", 1.0)
	rig.set_value("thigh_length", 0.55)
	rig.set_value("shin_length", 0.38)
	rig.set_value("upper_arm_length", 0.34)
	rig.set_value("forearm_length", 0.22)
	rig.set_value("torso_length", 0.33)
	rig.set_value("chest_length", 0.30)
	rig.set_value("neck_length", 0.12)
	rig.set_value("hip_width", 0.13)
	rig.set_value("shoulder_width", 0.27)
	v.apply_rig(rig)
	v.update_pose({"speed": 0.0, "grounded": true}, 0.0)
	t.near(_dist(v, "thigh_l", "shin_l"), 0.55, 1e-4, "hip to knee = thigh length")
	t.near(_dist(v, "shin_l", "foot_l"), 0.38, 1e-4, "knee to ankle = shin length")
	t.near(_dist(v, "upper_arm_l", "forearm_l"), 0.34, 1e-4, "shoulder to elbow = upper arm length")
	t.near(v.bone_tip("forearm_l", 0.22).distance_to(v.joint_position("forearm_l")), 0.22, 1e-4, "elbow to wrist = forearm length")
	t.near(_dist(v, "pelvis", "chest"), 0.33, 1e-4, "pelvis to chest joint = lower torso length")
	t.near(_dist(v, "chest", "neck"), 0.30, 1e-4, "chest joint to neck = chest length")
	t.near(_dist(v, "neck", "head"), 0.12, 1e-4, "neck length")
	t.near(_dist(v, "thigh_l", "thigh_r"), 0.26, 1e-4, "hip joints are 2 x hip width apart")
	t.near(_dist(v, "upper_arm_l", "upper_arm_r"), 0.54, 1e-4, "shoulder joints are 2 x shoulder width apart")
	t.near(v.joint_height("foot_l"), rig.get_value("ankle_height"), 1e-3, "standing pose: the ankle is at its height above the ground (hips follow the legs)")
	v.queue_free()
	await _tree.process_frame


## Size of a mesh as drawn (its mesh's box times the instance's scale), in the bone's frame.
func _mesh_extent(mi: MeshInstance3D) -> Vector3:
	return mi.mesh.get_aabb().size * mi.scale


func test_thickness_and_size_rebuild_the_meshes(t) -> void:
	var v := await _visual()
	var rig = RigParams.create()
	rig.set_value("scale", 1.0)
	rig.set_value("shoulder_width", 0.23)
	rig.set_value("thigh_radius", 0.11)
	rig.set_value("forearm_radius", 0.03)
	rig.set_value("head_radius", 0.14)
	rig.set_value("foot_length", 0.32)
	rig.set_value("torso_width", 1.4)
	rig.set_value("torso_depth", 0.6)
	v.apply_rig(rig)
	t.near((v._meshes.thigh_l.mesh as CapsuleMesh).radius, 0.11, 1e-6, "thigh radius")
	t.near((v._meshes.forearm_r.mesh as CapsuleMesh).radius, 0.03, 1e-6, "forearm radius")
	t.near((v._meshes.head.mesh as SphereMesh).height, 0.28, 1e-6, "head size: twice its radius tall")
	t.near((v._meshes.foot_l.mesh as BoxMesh).size.z, 0.32, 1e-6, "foot length")
	var chest_aabb := _mesh_extent(v._meshes.chest)
	rig.set_value("torso_width", 1.0)
	rig.set_value("torso_depth", 1.0)
	v.apply_rig(rig)
	var chest_default := _mesh_extent(v._meshes.chest)
	t.near(chest_aabb.x, chest_default.x * 1.4, 1e-4, "torso width multiplies the chest's width")
	t.near(chest_aabb.z, chest_default.z * 0.6, 1e-4, "and depth its depth")
	t.near(chest_aabb.y, chest_default.y, 1e-4, "but not its height")
	var hand := _mesh_extent(v._meshes.hand_l)
	t.ok(hand.y > 0.1 and hand.z < hand.x, "a hand is thin in the walking plane, not a long thick extension of the forearm: %s" % hand)
	t.near(hand.y, rig.get_value("forearm_length") * Visual.HAND_LENGTH_RATIO, 1e-5, "hand length uses the shared mesh/overlay ratio")
	rig.set_value("scale", 1.2)
	v.apply_rig(rig)
	t.near((v._meshes.thigh_l.mesh as CapsuleMesh).radius, 0.11 * 1.2, 1e-6, "overall size scales the radii too")
	v.queue_free()
	await _tree.process_frame


func test_the_posed_walk_keeps_its_feet_on_the_ground_for_any_body(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var worst_plan := 0.0
	var sunk := 0.0
	var planted_gap := 0.0
	var v := await _visual()
	for trial in 12:
		var rig = RigParams.create()
		for d in rig.definitions():
			rig.set_value(d.id, lerpf(d.min, d.max, 0.2 + 0.6 * rng.randf()))
		v.apply_rig(rig)
		var gp = GaitParams.create()
		var m := GaitModel.new(gp, rig)
		m.cycle = m.cycle_for(rng.randf_range(0.6, 1.5))
		for i in 12:
			var pose: Dictionary = m.pose_at(float(i) / 12.0)
			v.update_pose({"speed": 1.2, "grounded": true, "gait": pose}, 1.0 / 60.0)
			for side in ["l", "r"]:
				var sx := -1.0 if side == "l" else 1.0
				var hip: Vector3 = Vector3(pose.pelvis.x, pose.pelvis.y, 0.0) + pose.pelvis_q * Vector3(sx * m.cycle.hip_x, -m.cycle.hip_drop, 0.0)
				var reach := GaitModel.leg_reach(pose["thigh_" + side], pose["knee_" + side], m.cycle.thigh, m.cycle.shin)
				var expected: Vector3 = hip + Vector3(0.0, reach.y, -reach.x)
				worst_plan = maxf(worst_plan, expected.distance_to(v.joint_position("foot_" + side)))
				var fp: Transform3D = v.skeleton.get_bone_global_pose(v.bone_index["foot_" + side])
				var low := minf((fp * Vector3(0.0, -m.cycle.ankle_h, -m.cycle.heel.x)).y, (fp * Vector3(0.0, -m.cycle.ankle_h, -m.cycle.toe.x)).y)
				sunk = maxf(sunk, -low)
				if pose["contact_" + side]:
					planted_gap = maxf(planted_gap, absf(low))
	t.ok(worst_plan < 3e-4, "12 random bodies x 12 phases x 2 legs: the posed ankle is within %s m of the plan" % worst_plan)
	t.ok(sunk < 1e-3, "no sole sinks into the ground in any of them: %s m" % sunk)
	t.ok(planted_gap < 1e-3, "and planted soles touch it: %s m" % planted_gap)
	v.queue_free()
	await _tree.process_frame


# ------------------------------------------------------------------ the scene

func test_a_proportion_change_reaches_the_skeleton_and_the_gait_plan(t) -> void:
	var s := await _boot()
	await _run(s, 0.5)
	var leg_before: float = _dist(s.visual, "thigh_l", "shin_l")
	var step_before: float = s.model.cycle.reach
	s.rig_params.set_value("thigh_length", 0.58)
	await _run(s, 0.1)
	var k: float = s.rig_params.get_value("scale")
	t.near(_dist(s.visual, "thigh_l", "shin_l"), 0.58 * k, 1e-4, "the skeleton re-proportions without a restart (was %.3f)" % leg_before)
	t.ok(s.model.cycle.reach > step_before + 0.05, "and the gait model plans for the longer leg")
	t.near(s.visual.dims.thigh, 0.58 * k, 1e-9, "the visual's dimensions follow")


func test_planted_feet_still_do_not_slip_with_a_different_body(t) -> void:
	var s := await _boot({"rig.thigh_length": "0.55", "rig.shin_length": "0.5", "rig.foot_length": "0.3", "rig.scale": "1.15", "rig.hip_width": "0.14"})
	await _run(s, 1.5)
	await _run(s, 1.2)
	t.ok(s.slip_l < 0.003 and s.slip_r < 0.003, "taller, long-legged, wide-hipped: planted slip L %.1f R %.1f mm/s" % [1000.0 * s.slip_l, 1000.0 * s.slip_r])


func test_changing_proportions_while_walking_does_not_pop(t) -> void:
	var s := await _boot()
	await _run(s, 1.0)
	var last: float = s.visual.joint_height("head")
	var worst := 0.0
	var base_scale: float = s.rig_params.get_value("scale")
	for i in 60:
		s.rig_params.set_value("scale", base_scale * (1.0 + 0.002 * i))   # a slow drag of the size handle
		s.advance(1.0 / 60.0)
		var h: float = s.visual.joint_height("head")
		worst = maxf(worst, absf(h - last))
		last = h
	t.ok(worst < 0.03, "the head moves smoothly while the size is dragged: at most %.1f mm per frame" % (1000.0 * worst))


# ------------------------------------------------------------------ the handles

func _handle(s: Node, label: String) -> int:
	for i in s.rig_editor._handles.size():
		if s.rig_editor._handles[i].label == label:
			return i
	return -1


func _press(s: Node, pos: Vector2) -> bool:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return s.rig_editor.handle_input(ev)


func _release(s: Node, pos: Vector2) -> bool:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	return s.rig_editor.handle_input(ev)


func _move(s: Node, pos: Vector2, rel: Vector2) -> bool:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.relative = rel
	return s.rig_editor.handle_input(ev)


func test_editing_is_off_by_default_and_the_handles_exist_only_while_it_is_on(t) -> void:
	var s := await _boot()
	t.ok(not s.rig_editor.active(), "off by default")
	t.ok(not _press(s, Vector2(100, 100)), "clicks pass through when editing is off")
	s.gait_params.set_value("edit_rig", 1.0)
	s.rig_editor._handles = s.rig_editor.build_handles()
	t.ok(s.rig_editor.active() and s.rig_editor._handles.size() >= 20, "%d handles while editing" % s.rig_editor._handles.size())
	var labels := {}
	for h in s.rig_editor._handles:
		labels[h.param] = true
	for d in RigParams.definitions():
		if d.id != "scale":
			t.ok(labels.has(d.id), "%s has a handle (the size has the Ctrl+wheel and the controller)" % d.id)


func test_the_handles_sit_on_the_posed_joints(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("edit_rig", 1.0)
	await _run(s, 0.3)
	var hs: Array[Dictionary] = s.rig_editor.build_handles()
	var by := {}
	for h in hs:
		by[h.label] = h
	t.near(by["Thigh length"].pos.distance_to(s.visual.to_global(s.visual.joint_position("shin_l"))), 0.0, 1e-6, "the thigh handle is the knee")
	t.near(by["Shin length"].pos.distance_to(s.visual.to_global(s.visual.joint_position("foot_l"))), 0.0, 1e-6, "the shin handle is the ankle")
	t.near(by["Neck length"].pos.distance_to(s.visual.to_global(s.visual.joint_position("head"))), 0.0, 1e-6, "the neck handle is the head joint")
	t.near(by["Thigh length"].dir.length(), 1.0, 1e-5, "directions are unit vectors")
	t.ok(by["Thigh length"].dir.dot((s.visual.joint_position("shin_l") - s.visual.joint_position("thigh_l")).normalized()) > 0.99, "pointing along the bone, away from the parent joint")


func test_dragging_a_handle_changes_its_parameter_by_the_dragged_distance(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("edit_rig", 1.0)
	await _run(s, 0.3)
	s.rig_editor._handles = s.rig_editor.build_handles()
	var i := _handle(s, "Thigh length")
	var h: Dictionary = s.rig_editor._handles[i]
	var p: Vector2 = s.rig_editor._screen(h)
	var before: float = s.rig_params.get_value("thigh_length")
	t.ok(_press(s, p), "pressing on the handle starts a drag")
	t.eq(s.rig_editor.dragging, i, "and remembers which")
	var h_px: float = s.get_viewport().get_visible_rect().size.y
	var rel := Vector2(0.0, 0.03 * h_px)   # a few percent of the window height, down the screen
	t.ok(_move(s, p + rel, rel), "moving while dragging is consumed")
	var mpp: float = s.rig_editor._metres_per_pixel(h.pos)
	var cam: Camera3D = s.cam
	var world: Vector3 = cam.global_transform.basis.x * rel.x * mpp - cam.global_transform.basis.y * rel.y * mpp
	var expected: float = before + world.dot(h.dir) * h.gain
	t.near(s.rig_params.get_value("thigh_length"), expected, 0.0051, "the thigh grew by the distance dragged along it: %.3f -> %.3f (expected %.3f)" % [before, s.rig_params.get_value("thigh_length"), expected])
	t.ok(s.rig_params.get_value("thigh_length") > before, "dragging the knee down lengthens the thigh")
	t.ok(_release(s, p + rel), "releasing ends it")
	t.eq(s.rig_editor.dragging, -1, "")


func test_small_drags_are_not_lost_to_the_parameter_step(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("edit_rig", 1.0)
	await _run(s, 0.3)
	s.rig_editor._handles = s.rig_editor.build_handles()
	var i := _handle(s, "Shin length")
	var p: Vector2 = s.rig_editor._screen(s.rig_editor._handles[i])
	var before: float = s.rig_params.get_value("shin_length")
	_press(s, p)
	var step := 0.0006 * s.get_viewport().get_visible_rect().size.y   # about 1.4 mm of drag per move, far below the 5 mm step
	for k in 40:
		_move(s, p + Vector2(0, step * (k + 1)), Vector2(0, step))
	_release(s, p)
	t.ok(s.rig_params.get_value("shin_length") > before + 0.01, "forty tiny moves add up: %.3f -> %.3f" % [before, s.rig_params.get_value("shin_length")])


func test_dragging_past_a_limit_clamps_and_comes_straight_back(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("edit_rig", 1.0)
	await _run(s, 0.3)
	s.rig_editor._handles = s.rig_editor.build_handles()
	var i := _handle(s, "Thigh length")
	var p: Vector2 = s.rig_editor._screen(s.rig_editor._handles[i])
	_press(s, p)
	_move(s, p + Vector2(0, 4000), Vector2(0, 4000))
	var max_v: float = s.rig_params.def("thigh_length").max
	t.eq(s.rig_params.get_value("thigh_length"), max_v, "clamped at the maximum")
	_move(s, p + Vector2(0, 3960), Vector2(0, -40))
	t.ok(s.rig_params.get_value("thigh_length") < max_v, "and moving back reduces it at once (it is not stuck beyond the limit)")
	_release(s, p)


func test_width_handles_need_a_view_that_can_show_the_width(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("edit_rig", 1.0)
	await _run(s, 0.3)
	s.rig_editor._handles = s.rig_editor.build_handles()
	var visible_side := 0
	for h in s.rig_editor._handles:
		if h.kind == "width" and s.rig_editor._visible(h):
			visible_side += 1
	t.eq(visible_side, 0, "no width handle in the pure side view")
	s.set_view("front")
	await _tree.process_frame   # the camera's projection catches up with its new transform one frame later
	s.rig_editor._handles = s.rig_editor.build_handles()
	var visible_front := 0
	for h in s.rig_editor._handles:
		if h.kind == "width" and s.rig_editor._visible(h):
			visible_front += 1
	t.ok(visible_front >= 6, "%d width handles in the front view" % visible_front)
	var i := _handle(s, "Hip joint offset")
	var before: float = s.rig_params.get_value("hip_width")
	var p: Vector2 = s.rig_editor._screen(s.rig_editor._handles[i])
	_press(s, p)
	var outward: Vector2 = s.rig_editor._screen({"pos": s.rig_editor._handles[i].pos + s.rig_editor._handles[i].dir * 0.1}) - p
	var rel := outward.normalized() * 0.04 * s.get_viewport().get_visible_rect().size.y
	_move(s, p + rel, rel)
	t.ok(s.rig_params.get_value("hip_width") > before, "dragging a hip outward widens the hips: %.3f -> %.3f (dragging %d, outward %s, rel %s, acc %s)" % [before, s.rig_params.get_value("hip_width"), s.rig_editor.dragging, outward, rel, s.rig_editor._accumulated])
	_release(s, p)


func test_a_click_away_from_every_handle_is_left_alone_and_backspace_resets(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("edit_rig", 1.0)
	await _run(s, 0.3)
	s.rig_editor._handles = s.rig_editor.build_handles()
	t.ok(not _press(s, Vector2(2, 2)), "a click on empty space is not consumed")
	s.rig_params.set_value("thigh_length", 0.6)
	s.rig_params.set_value("head_radius", 0.15)
	var ev := InputEventKey.new()
	ev.keycode = KEY_BACKSPACE
	ev.pressed = true
	t.ok(s.rig_editor.handle_input(ev), "Backspace is consumed in edit mode")
	t.eq(s.rig_params.get_value("thigh_length"), s.rig_params.def("thigh_length").default, "the thigh is back")
	t.eq(s.rig_params.get_value("head_radius"), s.rig_params.def("head_radius").default, "and the head")


func test_edit_mode_freezes_the_walk_and_resumes_it_afterwards(t) -> void:
	var s := await _boot()
	await _run(s, 0.5)
	t.ok(not s.gait_params.is_on("freeze"), "walking")
	s.gait_params.set_value("edit_rig", 1.0)
	s.advance(1.0 / 60.0)
	t.ok(s.gait_params.is_on("freeze"), "entering edit mode freezes the cycle")
	s.gait_params.set_value("edit_rig", 0.0)
	s.advance(1.0 / 60.0)
	t.ok(not s.gait_params.is_on("freeze"), "leaving it resumes the walk")
	s.gait_params.set_value("freeze", 1.0)
	s.gait_params.set_value("edit_rig", 1.0)
	s.advance(1.0 / 60.0)
	s.gait_params.set_value("edit_rig", 0.0)
	s.advance(1.0 / 60.0)
	t.ok(s.gait_params.is_on("freeze"), "a walk the user had frozen stays frozen")


func test_ctrl_wheel_resizes_the_character_and_plain_wheel_zooms(t) -> void:
	var s := await _boot()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.ctrl_pressed = true
	var size_before: float = s.rig_params.get_value("scale")
	var zoom_before: float = s.gait_params.get_value("view_zoom")
	s._unhandled_input(ev)
	t.ok(s.rig_params.get_value("scale") > size_before, "Ctrl + wheel up makes the character bigger")
	t.eq(s.gait_params.get_value("view_zoom"), zoom_before, "and does not zoom the camera")
	ev.ctrl_pressed = false
	s._unhandled_input(ev)
	t.ok(s.gait_params.get_value("view_zoom") > zoom_before, "the plain wheel zooms the camera")
