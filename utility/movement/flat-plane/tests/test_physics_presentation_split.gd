extends RefCounted

## Architectural requirement of Movement Lab 2.0: physical movement and presentation are separate. Whatever the
## procedural animation does (now or in later phases), the authoritative body must not notice.

const SCENE := "res://scenes/flat_plane.tscn"
const DT := 1.0 / 120.0

var _tree: SceneTree


func before_each() -> void:
	_tree = Engine.get_main_loop()


func _boot(extra := {}) -> Node:
	var s: Node = load(SCENE).instantiate()
	var opts := {"no-capture": "true", "no-hardware": "true", "no-tuning": "true", "no-window-state": "true"}
	opts.merge(extra, true)
	s.options = opts
	_tree.root.add_child(s)
	await _tree.process_frame   # a scene added before the tree has started only runs _ready (which re-enables its processing) on the first frame
	s.set_physics_process(false)
	s.set_process(false)
	await _tree.physics_frame
	await _tree.physics_frame
	return s


## A fixed script of inputs: run, turn, jump, crouch, stop, strafe.
func _input_for(i: int) -> Dictionary:
	var f := {"move": Vector2.ZERO, "yaw": 0.0, "jump_pressed": false, "jump_held": false, "sprint": false, "crouch": false}
	var sec := float(i) * DT
	if sec < 1.0:
		f.move = Vector2(0, 1)
	elif sec < 1.6:
		f.move = Vector2(1, 1)
		f.yaw = (sec - 1.0) * 2.0
		f.sprint = true
	elif sec < 2.2:
		f.move = Vector2(0, 1)
		f.jump_pressed = i == int(1.6 / DT) + 3
		f.jump_held = true
	elif sec < 3.0:
		f.move = Vector2(-1, 0)
		f.crouch = true
	return f


## Records body position + velocity every physics tick. `animate` runs the real per-frame presentation each tick.
func _trajectory(animate: bool, extra := {}) -> Array:
	var s: Node = await _boot(extra)
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	var out := []
	for i in int(3.5 / DT):
		await _tree.physics_frame
		s.body.simulate(_input_for(i), DT)
		if animate:
			s._process(DT)
		out.append([s.body.global_position, s.body.velocity, s.body.core.grounded, s.body.core.crouching])
	var shape: CylinderShape3D = s.body.get_child(0).shape
	out.append([shape.height, shape.radius, s.body.get_child(0).position])
	s.queue_free()
	await _tree.process_frame
	return out


func test_physics_is_bit_identical_with_and_without_procedural_animation(t) -> void:
	var with_anim: Array = await _trajectory(true)
	var without_anim: Array = await _trajectory(false, {"no-animation": "true"})
	t.eq(with_anim.size(), without_anim.size(), "same number of ticks")
	var first_difference := -1
	for i in with_anim.size():
		if with_anim[i] != without_anim[i]:
			first_difference = i
			break
	t.eq(first_difference, -1, "no tick differs (position, velocity, grounded, crouching, collider)%s" % ("" if first_difference < 0 else ": tick %d with=%s without=%s" % [first_difference, str(with_anim[first_difference]), str(without_anim[first_difference])]))
	t.ok(with_anim.size() > 400, "a long enough script ran: %d ticks" % with_anim.size())


func test_the_controller_runs_with_no_visual_at_all(t) -> void:
	var reference: Array = await _trajectory(false, {"no-animation": "true"})
	var s: Node = await _boot({"no-animation": "true"})
	s.visual.queue_free()
	await _tree.process_frame
	s.body.teleport(Vector3(120, 0.05, 120))
	await _tree.physics_frame
	var last: Array = []
	for i in int(3.5 / DT):
		await _tree.physics_frame
		s.body.simulate(_input_for(i), DT)
		last = [s.body.global_position, s.body.velocity, s.body.core.grounded, s.body.core.crouching]
	t.eq(last, reference[reference.size() - 2], "removing the humanoid entirely changes nothing about where the body ends up")
	s.queue_free()
	await _tree.process_frame


func test_posing_never_touches_the_body_or_its_collider(t) -> void:
	var s: Node = await _boot()
	await _tree.physics_frame
	var before := [s.body.global_position, s.body.velocity, (s.body.get_child(0).shape as CylinderShape3D).height, s.body.get_child(0).position, s.body.collision_layer, s.body.collision_mask]
	for state in [
		{"speed": 0.0, "grounded": true}, {"speed": 1000.0, "grounded": true, "accel_forward": 5000.0},
		{"speed": 5.0, "grounded": false, "vy": -300.0, "landed_impact": 500.0}, {"speed": 3.0, "crouching": true, "heading": 12.0},
		{"speed": -4.0, "vy": 9.0, "grounded": false},
	]:
		for i in 30:
			s.visual.update_pose(state, 1.0 / 60.0)
	var after := [s.body.global_position, s.body.velocity, (s.body.get_child(0).shape as CylinderShape3D).height, s.body.get_child(0).position, s.body.collision_layer, s.body.collision_mask]
	t.eq(after, before, "position, velocity, collider size and offset, collision layers: all untouched by posing")
	s.queue_free()
	await _tree.process_frame


func test_presentation_state_lives_outside_the_simulation_core(t) -> void:
	var s: Node = await _boot()
	var core_props := []
	for p in s.body.core.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			core_props.append(String(p.name))
	for banned in ["lean", "phase", "dip", "crouch_blend", "air_blend", "skeleton", "step_offset"]:
		t.ok(not core_props.has(banned), "the movement core holds no presentation variable '%s'" % banned)
	t.ok(not s.body.core.get_script().resource_path.contains("visual"), "the core is its own script")
	s.queue_free()
	await _tree.process_frame


func test_no_animation_option_leaves_the_pose_at_rest(t) -> void:
	var s: Node = await _boot({"no-animation": "true"})
	t.ok(not s.animation_enabled, "flag read")
	var rest: float = s.visual.joint_height("pelvis")
	s.set_process(true)
	for i in 20:
		await _tree.process_frame
	t.near(s.visual.joint_height("pelvis"), rest, 0.0001, "pelvis never moves from its rest pose without animation")
	s.queue_free()
	await _tree.process_frame
