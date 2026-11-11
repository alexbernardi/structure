extends RefCounted

const World = preload("res://tests/flat_world.gd")
const Core = preload("res://systems/movement_core/movement/movement_core.gd")

const FWD := Vector2(0, 1)


func _world() -> World:
	var w := World.new()
	w.core.grounded = true
	return w


func test_reaches_exactly_the_max_ground_speed(t) -> void:
	var w := _world()
	w.run(w.input(FWD), 1.5)
	t.near(w.core.horizontal_speed(), 6.0, 0.001, "top speed = max_ground_speed")
	t.ok(w.core.velocity.z < 0.0 and absf(w.core.velocity.x) < 0.0001, "forward is -Z for yaw 0")


func test_acceleration_rate(t) -> void:
	var w := _world()
	w.run(w.input(FWD), 0.05)
	t.near(w.core.horizontal_speed(), 45.0 * 0.05, 0.2, "after 50 ms about ground_accel * t")
	w.run(w.input(FWD), 0.2)
	t.ok(w.core.horizontal_speed() > 5.9, "within 0.25 s it is near the cap")


func test_sprint_and_crouch_speeds(t) -> void:
	var w := _world()
	w.run(w.input(FWD, {"sprint": true}), 1.5)
	t.near(w.core.horizontal_speed(), 6.0 * 2.0, 0.001, "sprint multiplier")
	var c := _world()
	c.run(c.input(FWD, {"crouch": true, "sprint": true}), 1.5)
	t.near(c.core.horizontal_speed(), 2.0, 0.001, "crouch speed wins over sprint")
	t.ok(c.core.crouching, "crouching state")


func test_diagonal_input_is_not_faster(t) -> void:
	var w := _world()
	w.run(w.input(Vector2(1, 1)), 1.5)
	t.near(w.core.horizontal_speed(), 6.0, 0.001, "W+D is normalised")


func test_stops_and_friction_matters(t) -> void:
	var w := _world()
	w.core.velocity = Vector3(0, 0, -4.5)
	w.run(w.input(), 0.5)
	t.ok(w.core.horizontal_speed() < 0.01, "stops within half a second with defaults")
	var slippery := _world()
	slippery.core.p.ground_friction = 0.5
	slippery.core.p.braking = 0.0
	slippery.core.velocity = Vector3(0, 0, -4.5)
	slippery.run(slippery.input(), 0.5)
	t.ok(slippery.core.horizontal_speed() > 2.0, "low friction and braking keep sliding")


func test_braking_helps_when_turning_around(t) -> void:
	var w := _world()
	w.core.velocity = Vector3(0, 0, -4.5)
	w.run(w.input(Vector2(0, -1)), 0.2)   # press back while moving forward
	t.ok(w.core.velocity.z > -2.0, "braking reduces the opposing speed fast: %.2f" % w.core.velocity.z)


func test_momentum_above_the_cap_is_bled_not_clipped(t) -> void:
	var w := _world()
	w.core.velocity = Vector3(0, 0, -9.0)
	w.tick(w.input(FWD))
	t.ok(w.core.horizontal_speed() > 8.0, "one tick later the extra speed is still there: %.2f" % w.core.horizontal_speed())
	w.run(w.input(FWD), 1.0)
	t.near(w.core.horizontal_speed(), 6.0, 0.01, "and friction brings it back to the cap")


func test_sideways_sliding_is_cut_quickly(t) -> void:
	var w := _world()
	w.core.velocity = Vector3(4.5, 0, 0)
	w.run(w.input(FWD), 0.3)
	t.ok(absf(w.core.velocity.x) < 0.5, "sideways momentum decays exponentially (friction 7/s): %.2f" % w.core.velocity.x)
	w.run(w.input(FWD), 0.3)
	t.ok(absf(w.core.velocity.x) < 0.1, "and is gone 0.3 s later: %.2f" % w.core.velocity.x)


func test_jump_height_matches_physics(t) -> void:
	var w := _world()
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))
	var top := w.peak_height(w.input(), 1.0)
	var expected := 5.5 * 5.5 / (2.0 * 19.6)
	t.near(top, expected, 0.08, "apex ~ v^2 / 2g = %.3f m (got %.3f)" % [expected, top])
	w.run(w.input(), 1.0)
	t.near(w.pos.y, 0.0, 0.0001, "lands back on the floor")
	t.ok(w.core.grounded, "grounded again")


func test_gravity_is_applied_in_the_air_only(t) -> void:
	var w := _world()
	w.run(w.input(), 0.2)
	t.eq(w.core.velocity.y, 0.0, "no gravity on the ground")
	w.pos.y = 5.0
	w.core.grounded = false
	w.run(w.input(), 0.5)
	t.near(w.core.velocity.y, -19.6 * 0.5, 0.2, "falls at g")


func test_terminal_velocity(t) -> void:
	var w := _world()
	w.core.p.max_fall_speed = 12.0
	w.pos.y = 500.0
	w.core.grounded = false
	w.run(w.input(), 3.0)
	t.near(w.core.velocity.y, -12.0, 0.001, "clamped at max_fall_speed")


func test_coyote_time_allows_a_late_jump(t) -> void:
	var w := _world()
	w.run(w.input(), 0.1)
	# walk off a ledge: the world stops reporting ground
	w.pos.y = 0.5
	w.core.velocity.y = 0.0
	w.run(w.input(), 0.05)
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))
	t.ok(w.core.velocity.y > 4.0, "jump 50 ms after leaving the ground works (coyote 100 ms): vy %.2f" % w.core.velocity.y)


func test_coyote_time_expires(t) -> void:
	var w := _world()
	w.run(w.input(), 0.1)
	w.pos.y = 5.0   # high enough that it is still falling when the press happens
	w.run(w.input(), 0.25)
	var vy := w.core.velocity.y
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))
	t.ok(w.core.velocity.y < vy, "no jump after the coyote window: vy %.2f -> %.2f" % [vy, w.core.velocity.y])


func test_coyote_time_zero_disables_it(t) -> void:
	var w := _world()
	w.core.p.coyote_time = 0.0
	w.run(w.input(), 0.1)
	w.pos.y = 0.5
	w.tick(w.input())
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))
	t.ok(w.core.velocity.y <= 0.0, "with coyote 0 a mid-air press does nothing immediately")


func test_jump_buffer_fires_on_landing(t) -> void:
	var w := _world()
	w.pos.y = 0.08
	w.core.grounded = false
	w.core.velocity.y = -3.0
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))   # pressed just before touching down
	var jumped := false
	for i in 60:
		w.tick(w.input())
		if w.core.velocity.y > 4.0:
			jumped = true
			break
	t.ok(jumped, "the buffered press jumps on landing")


func test_jump_buffer_expires(t) -> void:
	var w := _world()
	w.pos.y = 3.0
	w.core.grounded = false
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))   # far too early
	var jumped := false
	for i in 300:
		w.tick(w.input())
		if w.core.velocity.y > 4.0:
			jumped = true
	t.ok(not jumped, "a press 0.5 s+ before landing is forgotten")


func test_jump_buffer_time_is_tunable(t) -> void:
	var w := _world()
	w.core.p.jump_buffer_time = 0.5
	w.pos.y = 1.0   # lands in ~0.25 s
	w.core.grounded = false
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))
	var jumped := false
	for i in 120:
		w.tick(w.input())
		if w.core.velocity.y > 4.0:
			jumped = true
			break
	t.ok(jumped, "a longer buffer reaches the landing")


func test_air_strafing_gains_speed_beyond_the_ground_cap(t) -> void:
	# Fixed view: strafing can only add speed until its projection reaches the air cap -> sqrt(4.5^2 + 1.2^2).
	var fixed := _world()
	fixed.core.p.air_control = 0.0
	fixed.pos.y = 50.0
	fixed.core.grounded = false
	fixed.core.velocity = Vector3(0, 0, -4.5)
	fixed.run(fixed.input(Vector2(1, 0)), 1.0)
	t.near(fixed.core.horizontal_speed(), sqrt(4.5 * 4.5 + 1.2 * 1.2), 0.02, "a fixed view gains only a little: %.2f" % fixed.core.horizontal_speed())
	# Turning the view with the velocity (what a player does with the mouse) keeps the wish perpendicular: speed keeps growing.
	var w := _world()
	w.core.p.air_control = 0.0
	w.pos.y = 500.0
	w.core.grounded = false
	w.core.velocity = Vector3(0, 0, -4.5)
	for i in 120:
		var v := w.core.velocity
		var yaw := atan2(-v.x, -v.z)
		w.tick(w.input(Vector2(1, 0), {"yaw": yaw}))
	var expected := sqrt(4.5 * 4.5 + 30.0 * 30.0 * (1.0 / 120.0) * 1.0)   # each tick adds a perpendicular a*dt: v^2 += (a*dt)^2
	t.near(w.core.horizontal_speed(), expected, 0.05, "air strafing with a turning view: 4.50 -> %.2f m/s in 1 s (analytic %.2f)" % [w.core.horizontal_speed(), expected])
	t.ok(w.core.horizontal_speed() > 5.0, "clearly above the 4.5 m/s ground cap")


func test_air_cap_limits_speed_built_along_the_wish_direction(t) -> void:
	var w := _world()
	w.core.p.air_control = 0.0
	w.pos.y = 80.0
	w.core.grounded = false
	w.run(w.input(FWD), 1.0)
	t.near(w.core.horizontal_speed(), 1.2, 0.01, "from standstill the air cap (1.2 m/s) is the limit")
	w.core.p.air_speed_cap = 3.0
	w.run(w.input(FWD), 1.0)
	t.near(w.core.horizontal_speed(), 3.0, 0.01, "raising the cap raises it")


func test_air_control_steers_without_changing_speed(t) -> void:
	var w := _world()
	w.pos.y = 80.0
	w.core.grounded = false
	w.core.p.air_speed_cap = 0.0   # isolate steering from acceleration
	w.core.velocity = Vector3(0, 0, -5.0)
	w.run(w.input(Vector2(1, 0)), 0.5)
	t.near(w.core.horizontal_speed(), 5.0, 0.01, "speed preserved while turning")
	t.ok(w.core.velocity.x > 1.0, "direction turned toward the wish: vx %.2f" % w.core.velocity.x)
	var none := _world()
	none.pos.y = 80.0
	none.core.grounded = false
	none.core.p.air_speed_cap = 0.0
	none.core.p.air_control = 0.0
	none.core.velocity = Vector3(0, 0, -5.0)
	none.run(none.input(Vector2(1, 0)), 0.5)
	t.near(none.core.velocity.x, 0.0, 0.001, "with air_control 0 the direction is fixed")


func test_bunny_hop_keeps_speed_where_walking_loses_it(t) -> void:
	var hop := _world()
	hop.core.p.auto_jump = 1.0
	hop.core.velocity = Vector3(0, 0, -7.0)
	hop.run(hop.input(FWD, {"jump_held": true}), 3.0)
	var walk := _world()
	walk.core.velocity = Vector3(0, 0, -7.0)
	walk.run(walk.input(FWD), 3.0)
	t.near(walk.core.horizontal_speed(), 6.0, 0.01, "ground running bleeds 7 m/s back to the cap")
	t.ok(hop.core.horizontal_speed() > 6.0, "chained jumps keep the momentum: %.2f" % hop.core.horizontal_speed())


func test_slope_too_steep_is_not_ground(t) -> void:
	var w := _world()
	w.floor_normal = Vector3(sin(deg_to_rad(60)), cos(deg_to_rad(60)), 0)
	w.core.p.max_walkable_slope = 46.0
	w.run(w.input(), 0.1)
	t.ok(not w.core.grounded, "60 deg > 46 deg limit")
	w.core.p.max_walkable_slope = 70.0
	w.run(w.input(), 0.1)
	t.ok(w.core.grounded, "raising the limit makes it walkable")


func test_uphill_is_slower_than_flat_and_downhill_is_not(t) -> void:
	var angle := deg_to_rad(30)
	var n := Vector3(sin(angle), cos(angle), 0.0)   # surface rises toward -X
	var speeds := {}
	for case in [["uphill", Vector2(-1, 0)], ["downhill", Vector2(1, 0)]]:
		var w := World.new()
		w.pos.y = 0.0
		w.floor_normal = n
		w.core.grounded = true
		for i in 240:
			w.core.step(w.input(case[1]), {"grounded": true, "normal": n, "can_stand": true}, World.DT)
		speeds[case[0]] = w.core.velocity.length()
	t.ok(speeds.uphill < speeds.downhill - 0.3, "uphill %.2f < downhill %.2f" % [speeds.uphill, speeds.downhill])
	t.near(speeds.downhill, 6.0, 0.02, "downhill reaches the normal cap")


func test_slope_penalty_can_be_removed(t) -> void:
	var angle := deg_to_rad(30)
	var n := Vector3(sin(angle), cos(angle), 0.0)
	var w := World.new()
	w.core.p.slope_speed_penalty = 0.0
	w.core.grounded = true
	for i in 240:
		w.core.step(w.input(Vector2(-1, 0)), {"grounded": true, "normal": n, "can_stand": true}, World.DT)
	t.near(w.core.velocity.length(), 6.0, 0.02, "no penalty -> full speed uphill")


func test_crouch_needs_headroom_to_stand(t) -> void:
	var c := Core.new()
	var inp := {"move": Vector2.ZERO, "yaw": 0.0, "crouch": true}
	c.step(inp, {"grounded": true, "normal": Vector3.UP, "can_stand": true}, 1.0 / 120.0)
	t.ok(c.crouching, "crouching")
	inp.crouch = false
	c.step(inp, {"grounded": true, "normal": Vector3.UP, "can_stand": false}, 1.0 / 120.0)
	t.ok(c.crouching, "stays crouched under a low ceiling")
	c.step(inp, {"grounded": true, "normal": Vector3.UP, "can_stand": true}, 1.0 / 120.0)
	t.ok(not c.crouching, "stands when there is room")


func test_yaw_rotates_the_wish_direction(t) -> void:
	var w := _world()
	w.run(w.input(FWD, {"yaw": PI / 2.0}), 1.0)
	t.ok(w.core.velocity.x < -4.0 and absf(w.core.velocity.z) < 0.01, "yaw 90 deg: forward becomes -X")


func test_simulation_is_deterministic(t) -> void:
	var results := []
	for run in 2:
		var w := _world()
		for i in 600:
			var inp := w.input(Vector2(sin(i * 0.05), 1.0), {"jump_pressed": i % 97 == 0, "sprint": i % 200 < 100, "yaw": i * 0.002})
			w.tick(inp)
		results.append([w.pos, w.core.velocity])
	t.eq(results[0], results[1], "identical inputs give bit-identical trajectories")


func test_telemetry_fields(t) -> void:
	var w := _world()
	w.tick(w.input(FWD))
	t.ok(w.core.acceleration.length() > 10.0, "acceleration is measured: %.1f" % w.core.acceleration.length())
	t.near(w.core.wish_speed, 6.0, 0.001, "wish speed reported")
	w.tick(w.input(Vector2.ZERO, {"jump_pressed": true}))
	t.ok(w.core.just_jumped, "jump event flag")
