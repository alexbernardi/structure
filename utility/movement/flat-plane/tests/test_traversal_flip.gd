## Movement Lab 5.3: the crouch flip. Space while crouched (on the ground or sliding) is a front flip: a physics jump
## that keeps the momentum, with the authored JogToFlip turn spread over the real airtime. Unpaced fixed-tick trials on
## lane M (open ground, a 1.0 m deck to flip off, a 0.5 m box to flip onto, a 1.0 m bar) and lane K (slide).
extends RefCounted

const Scene = preload("res://scenes/flat_plane.tscn")
const FlipClip = preload("res://traversal/flip_clip.gd")
const Profiles = preload("res://capability/movement_profiles.gd")
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


func _place(scene, landmark: String, at := Vector3.INF) -> void:
	scene.teleport_to(landmark)
	if at != Vector3.INF:
		scene.body.teleport(at)
	await _tree.physics_frame


static func _input(press := false, extra := {}) -> Dictionary:
	var input := {"move": Vector2.ZERO, "yaw": RUN_YAW, "sprint": false, "jump_pressed": press, "jump_held": press, "crouch": false}
	input.merge(extra, true)
	return input


## Runs the policy; records each flip's airborne ticks (phase shown, height, drawn feet and hips) and its landing.
func _run(scene, ticks: int, policy: Callable) -> Dictionary:
	var stats := {"flips": [], "max_vy": -INF, "air_speed": 0.0, "min_drawn_foot": INF, "max_hips_step": 0.0, "states": {}}
	var flips0: int = scene.traversal.flips
	var current := {}
	var skeleton: Skeleton3D = scene.authored_visual.skeleton
	var index: Dictionary = scene.authored_visual.bone_index
	var last_hips := Vector3.INF
	for i in ticks:
		if i % 240 == 0:
			await _tree.physics_frame
		scene.simulate_tick(policy.call(scene, i), DT)
		scene._process(DT)
		skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var tr = scene.traversal
		if tr.flipping:
			if current.is_empty() or tr.flip_time < current.last_time:
				current = {"start": scene.body.global_position, "phases": [], "max_y": -INF, "ground": scene.body.global_position.y,
					"speed0": Vector2(scene.body.velocity.x, scene.body.velocity.z).length(), "last_time": 0.0}
				stats.flips.append(current)
			current.last_time = tr.flip_time
			current.phases.append(tr.flip_phase)
			current.max_y = maxf(current.max_y, scene.body.global_position.y)
			stats.max_vy = maxf(stats.max_vy, scene.body.velocity.y)
			stats.air_speed = maxf(stats.air_speed, Vector2(scene.body.velocity.x, scene.body.velocity.z).length())
			var state: String = scene.authored_animation.model.state
			stats.states[state] = int(stats.states.get(state, 0)) + 1
			var hips: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(index.Hips).origin - scene.body.global_position
			if last_hips != Vector3.INF:
				stats.max_hips_step = maxf(stats.max_hips_step, hips.distance_to(last_hips))
			last_hips = hips
			for side in ["Left", "Right"]:
				var toe: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(index[side + "Toes"]).origin
				stats.min_drawn_foot = minf(stats.min_drawn_foot, toe.y - current.ground)
		elif not current.is_empty() and not current.has("landed"):
			current["landed"] = scene.body.global_position
			current["airtime"] = current.last_time
			current["final_phase"] = current.phases[-1] if current.phases.size() > 0 else 0.0
			last_hips = Vector3.INF
	stats["count"] = scene.traversal.flips - flips0
	stats["choices"] = scene.traversal.choices.duplicate()
	stats["refusal"] = scene.traversal.last_refusal
	var brief := []
	for f in stats.flips:
		brief.append({"airtime": snappedf(f.get("airtime", -1.0), 0.001), "final": snappedf(f.get("final_phase", -1.0), 0.001),
			"rise": snappedf(f.max_y - f.ground, 0.01), "land_y": snappedf((f.get("landed", Vector3.INF) as Vector3).y, 0.01)})
	print("FLIP ", JSON.stringify({"count": stats.count, "flips": brief, "choices": stats.choices, "refusal": stats.refusal,
		"air_speed": snappedf(stats.air_speed, 0.01), "min_foot": snappedf(stats.min_drawn_foot, 0.01),
		"hips_step": snappedf(stats.max_hips_step, 0.001), "states": stats.states}))
	return stats


## Space standing up is the ordinary jump; crouch + Space (standing still) is a front flip that leaves along the
## facing, rises on flip_impulse, turns through the authored clip and lands upright on the flat.
func test_crouch_press_flips_standing_press_jumps(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_m")
	var stats: Dictionary = await _run(scene, 120, func(_s, i): return _input(i == 10))
	t.eq(stats.count, 0, "Space while standing does not flip")
	t.eq(int(stats.choices.get("jump", 0)), 1, "it is the ordinary jump (%s)" % [stats.choices])
	await _place(scene, "lane_m")
	var stamina0: float = scene.traversal.resources.spent.stamina
	stats = await _run(scene, 200, func(_s, i): return _input(i == 30, {"crouch": i < 32}))
	t.eq(stats.count, 1, "crouch + Space flips (%s, %s)" % [stats.choices, stats.refusal])
	var flip: Dictionary = stats.flips[0] if stats.flips.size() > 0 else {}
	var impulse: float = scene.capabilities.get_value("flip_impulse")
	t.ok(absf(stats.max_vy - impulse) < 0.25, "takes off at flip_impulse (%.2f vs %.2f m/s)" % [stats.max_vy, impulse])
	t.ok(stats.air_speed >= scene.capabilities.get_value("flip_forward") - 0.05, "a standing flip still travels forward (%.2f m/s)" % stats.air_speed)
	t.ok(flip.get("final_phase", 0.0) >= FlipClip.LAND - 0.03, "the authored turn is complete at the landing (clip %.3f s)" % flip.get("final_phase", 0.0))
	t.ok(flip.has("landed") and absf((flip.landed as Vector3).y) < 0.05, "lands on the flat")
	t.ok(int(stats.states.get("Flip", 0)) > 0, "the animation shows the authored flip (%s)" % [stats.states])
	t.ok(stats.min_drawn_foot > -0.06, "the drawn feet never sink into the ground (%.3f m)" % stats.min_drawn_foot)
	t.ok(stats.max_hips_step < 0.12, "no snap in the drawn hips relative to the body (largest step %.3f m)" % stats.max_hips_step)
	t.ok(scene.traversal.resources.spent.stamina > stamina0, "a flip costs stamina")
	# Facing: with no motion and no stick, the flip goes along the view (yaw -90 deg: +X).
	t.ok(flip.has("landed") and (flip.landed as Vector3).x > (flip.start as Vector3).x + 0.8, "along the view direction")


## A slide + Space flips and keeps the slide's speed (the slide ends; the core carries the momentum through the air).
func test_slide_flip_keeps_momentum(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_k", Vector3(20.0, 0.05, -67.0))
	var state := {"pressed": false, "speed": 0.0}
	var stats: Dictionary = await _run(scene, 240, func(s, i):
		if s.traversal.sliding and s.traversal.slide_time > 0.3 and not state.pressed:
			state.pressed = true
			state.speed = s.traversal.slide_velocity.length()
			return _input(true, {"move": Vector2(0, 1), "sprint": true, "crouch": true})
		return _input(false, {"move": Vector2(0, 1), "sprint": true, "crouch": i > 60 and not state.pressed}))
	t.eq(stats.count, 1, "the slide press is a flip (%s)" % [stats.choices])
	t.ok(stats.air_speed > state.speed - 0.5, "keeps the slide's speed (%.2f -> %.2f m/s)" % [state.speed, stats.air_speed])
	t.ok(not scene.traversal.sliding, "the slide is over")
	var flip: Dictionary = stats.flips[0] if stats.flips.size() > 0 else {}
	t.ok(flip.get("final_phase", 0.0) >= FlipClip.LAND - 0.03, "turned fully before the landing (clip %.3f s)" % flip.get("final_phase", 0.0))
	t.ok(stats.min_drawn_foot > -0.06, "fading out of the slide pose, the drawn feet stay above the ground (%.3f m)" % stats.min_drawn_foot)
	# Without the flip capability the same press is the 5.2 slide jump.
	await _place(scene, "lane_k", Vector3(20.0, 0.05, -67.0))
	scene.capabilities.add(Profiles.sprained_ankle())
	state = {"pressed": false}
	stats = await _run(scene, 240, func(s, i):
		if s.traversal.sliding and s.traversal.slide_time > 0.2 and not state.pressed:
			state.pressed = true
			return _input(true, {"move": Vector2(0, 1), "sprint": true, "crouch": true})
		return _input(false, {"move": Vector2(0, 1), "sprint": true, "crouch": i > 60}))
	scene.capabilities.remove_source(Profiles.INJURY)
	t.eq(stats.count, 0, "an injured body does not flip")
	t.ok(stats.refusal.begins_with("flip: not_capable") or int(stats.choices.get("jump", 0)) > 0, "the press is the ordinary slide jump (%s, %s)" % [stats.choices, stats.refusal])


## The turn follows the airtime: off the 1.0 m deck it lasts longer, onto the 0.5 m box shorter, and both land upright.
func test_flip_off_a_drop_and_onto_a_box(t) -> void:
	var scene = await _scene()
	# Reference on the flat.
	await _place(scene, "lane_m")
	var flat: Dictionary = await _run(scene, 200, func(_s, i): return _input(i == 30, {"crouch": i < 32, "move": Vector2(0, 0.5)}))
	var flat_air: float = flat.flips[0].get("airtime", 0.0) if flat.flips.size() > 0 else 0.0
	t.ok(flat.min_drawn_foot > -0.06, "from a crouch-walk the drawn feet stay above the ground (%.3f m)" % flat.min_drawn_foot)
	# Off the deck (top 1.0 m, ends at x 59).
	await _place(scene, "lane_m_deck")
	var plan := {"pressed": false}
	var off: Dictionary = await _run(scene, 500, func(s, _i):
		var press: bool = not plan.pressed and s.body.global_position.x > 58.2
		if press:
			plan.pressed = true
		return _input(press, {"crouch": press or not plan.pressed, "move": Vector2(0, 1)}))
	var f_off: Dictionary = off.flips[0] if off.flips.size() > 0 else {}
	t.eq(off.count, 1, "flips off the deck (%s, %s)" % [off.choices, off.refusal])
	t.ok(f_off.has("landed") and (f_off.landed as Vector3).y < 0.12, "turned before reaching the ground below (y %.2f): the fall and landing take over" % (f_off.get("landed", Vector3.INF) as Vector3).y)
	t.ok(f_off.get("airtime", 0.0) > flat_air + 0.08, "a longer flight (%.3f vs %.3f s)" % [f_off.get("airtime", 0.0), flat_air])
	t.ok(f_off.get("final_phase", 0.0) >= FlipClip.LAND - 0.03, "turned fully on the longer flight (clip %.3f s)" % f_off.get("final_phase", 0.0))
	# Onto the box (top 0.5 m, x 64.5 .. 67.5).
	await _place(scene, "lane_m", Vector3(61.5, 0.05, -79.0))
	plan = {"pressed": false}
	var onto: Dictionary = await _run(scene, 400, func(s, _i):
		var press: bool = not plan.pressed and s.body.global_position.x > 63.9
		if press:
			plan.pressed = true
		return _input(press, {"crouch": press or not plan.pressed, "move": Vector2(0, 1)}))
	var f_on: Dictionary = onto.flips[0] if onto.flips.size() > 0 else {}
	t.eq(onto.count, 1, "flips at the box (%s, %s)" % [onto.choices, onto.refusal])
	t.ok(f_on.has("landed") and absf((f_on.landed as Vector3).y - 0.5) < 0.05, "lands on its 0.5 m top (y %.2f)" % (f_on.get("landed", Vector3.ZERO) as Vector3).y)
	t.ok(f_on.get("airtime", 1.0) < flat_air - 0.04, "a shorter flight (%.3f vs %.3f s)" % [f_on.get("airtime", 1.0), flat_air])
	t.ok(f_on.get("final_phase", 0.0) >= FlipClip.LAND - 0.03, "still turned fully (clip %.3f s)" % f_on.get("final_phase", 0.0))


## Refusals and buffering: no flip without standing room (sliding under lane K's 1.0 m bar: the press does nothing,
## the slide goes on); presses while upside down neither catch nor air jump, and one near the landing (inside the
## jump buffer) chains a second flip.
func test_flip_refusals_and_buffered_chain(t) -> void:
	var scene = await _scene()
	await _place(scene, "lane_k")
	var plan := {"pressed": false, "vy": -INF, "sliding_after": false}
	var stats: Dictionary = await _run(scene, 400, func(s, i):
		var x: float = s.body.global_position.x
		if plan.pressed:
			plan.vy = maxf(plan.vy, s.body.velocity.y)
			plan.sliding_after = plan.sliding_after or s.traversal.sliding
		if not plan.pressed and s.traversal.sliding and absf(x - 50.0) < 0.12:
			plan.pressed = true
			return _input(true, {"move": Vector2(0, 1), "sprint": true, "crouch": true})
		return _input(false, {"move": Vector2(0, 1), "sprint": true, "crouch": x > 46.0}))
	t.ok(plan.pressed, "reached the bar sliding")
	t.eq(stats.count, 0, "no flip under the bar")
	t.eq(scene.traversal.last_refusal, "flip: no_headroom", "refused for headroom")
	t.ok(plan.vy < 0.5, "nothing jumps into the bar (vy %.2f)" % plan.vy)
	t.ok(plan.sliding_after, "the slide carries on")
	# Presses while upside down are buffered; one just before the landing chains the next flip.
	await _place(scene, "lane_m")
	var chain := {"mid": false, "late": false, "mid_choice": ""}
	stats = await _run(scene, 300, func(s, i):
		var tr = s.traversal
		if not chain.mid and tr.flipping and tr.flip_phase > FlipClip.INVERTED - 0.05:
			chain.mid = true
			return _input(true, {"crouch": true})
		if chain.mid and chain.mid_choice == "":
			chain.mid_choice = tr.last_choice
		if not chain.late and tr.flipping and tr.flip_phase > FlipClip.LAND - 0.07:
			chain.late = true
			return _input(true, {"crouch": true})
		return _input(i == 30, {"crouch": true}))
	t.eq(chain.mid_choice, "buffered", "a press upside down is buffered (not a catch or air jump)")
	t.eq(stats.count, 2, "a press just before the landing chains a second flip (%s)" % [stats.choices])
	t.ok(stats.min_drawn_foot > -0.06, "the drawn feet stay above the ground in both flips (%.3f m)" % stats.min_drawn_foot)
