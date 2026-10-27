extends RefCounted

const Model = preload("../src/movement_model.gd")
const Sim = preload("trajectory_sim.gd")
const DT := 1.0 / 60.0
const GOLDEN := "res://fixtures/golden_trajectory.json"

var p: Dictionary


func before_each() -> void:
	p = Model.default_params()


func _horizontal_speed(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func test_accelerates_to_walk_speed_and_caps(t) -> void:
	var v := Vector3.ZERO
	for i in 60:
		v = Model.step(v, Vector3(0, 0, -1), true, false, DT, p)
		t.ok(_horizontal_speed(v) <= p.walk_speed + 1e-4, "speed never exceeds walk_speed (step %d)" % i)
	t.near(_horizontal_speed(v), p.walk_speed, 1e-4, "reaches walk_speed within 1 s")


func test_diagonal_input_is_not_faster(t) -> void:
	var v := Vector3.ZERO
	for i in 120:
		v = Model.step(v, Vector3(1, 0, 1), true, false, DT, p)
	t.near(_horizontal_speed(v), p.walk_speed, 1e-4, "diagonal speed capped at walk_speed")


func test_stops_without_input(t) -> void:
	var v := Vector3(p.walk_speed, 0, 0)
	var frames := 0
	while _horizontal_speed(v) > 0.0 and frames < 600:
		v = Model.step(v, Vector3.ZERO, true, false, DT, p)
		frames += 1
	# Analytic braking time; float32 rounding may leave a residual needing one extra frame.
	var expected_frames := ceili(p.walk_speed / p.ground_decel / DT)
	t.ok(frames >= expected_frames and frames <= expected_frames + 1,
		"braking time follows ground_decel: %d frames, expected %d(+1)" % [frames, expected_frames])


func test_jump_apex_matches_formula(t) -> void:
	var y := 0.0
	var apex := 0.0
	var v := Model.step(Vector3.ZERO, Vector3.ZERO, true, true, DT, p)
	t.eq(v.y, float(p.jump_velocity), "jump sets vertical velocity")
	for i in 240:
		y += v.y * DT
		apex = maxf(apex, y)
		if y <= 0.0:
			break
		v = Model.step(v, Vector3.ZERO, false, false, DT, p)
	t.near(apex, Model.jump_apex_height(p), p.jump_velocity * DT, "apex within one step of v^2/2g")


func test_air_control_is_limited(t) -> void:
	var v := Vector3(p.walk_speed, 3.0, 0)
	var next := Model.step(v, Vector3(-1, 0, 0), false, false, DT, p)
	var change := Vector2(next.x - v.x, next.z - v.z).length()
	t.near(change, p.air_accel * DT, 1e-5, "air acceleration bounded by air_accel")


func test_cannot_jump_while_airborne(t) -> void:
	var v := Model.step(Vector3(0, 2.0, 0), Vector3.ZERO, false, true, DT, p)
	t.ok(v.y < 2.0, "jump input ignored in the air")


func test_delta_is_clamped(t) -> void:
	var v0 := Vector3(1, 0, 0)
	t.eq(Model.step(v0, Vector3(0, 0, -1), true, false, 0.0, p), v0, "zero delta is a no-op")
	t.eq(Model.step(v0, Vector3(0, 0, -1), true, false, -1.0, p), v0, "negative delta is a no-op")
	var big := Model.step(Vector3.ZERO, Vector3.ZERO, false, false, 5.0, p)
	t.near(big.y, -p.gravity * Model.MAX_DELTA, 1e-5, "huge delta clamped to MAX_DELTA")


func test_fall_speed_is_capped(t) -> void:
	var v := Vector3.ZERO
	for i in 600:
		v = Model.step(v, Vector3.ZERO, false, false, DT, p)
	t.eq(v.y, -float(p.max_fall_speed), "terminal fall speed")


## Server validation relies on this bound holding for ANY input sequence.
func test_random_inputs_never_exceed_max_speed_bounds(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var v := Vector3.ZERO
	var max_h := Model.max_horizontal_speed(p)
	var max_v := Model.max_vertical_speed(p)
	var violations := 0
	for i in 20000:
		var wish := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		v = Model.step(v, wish, rng.randf() < 0.5, rng.randf() < 0.1, rng.randf_range(-0.05, 0.5), p)
		if _horizontal_speed(v) > max_h + 1e-4 or absf(v.y) > max_v + 1e-4:
			violations += 1
	t.eq(violations, 0, "speed bounds hold for 20k random steps")


func test_deterministic_trajectory_matches_golden(t) -> void:
	var a := Sim.simulate(p)
	t.eq(a, Sim.simulate(p), "two runs in one process are identical")
	if not t.ok(FileAccess.file_exists(GOLDEN), "golden fixture exists (run tools/make_golden.gd)"):
		return
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var rows: Array = golden.rows
	t.eq(rows.size(), a.size(), "golden row count")
	# Vector3 stores float32: compare at that precision so "exact" means bit-identical simulation.
	var max_diff := 0.0
	var exact := true
	for i in mini(rows.size(), a.size()):
		var expected_row := PackedFloat32Array(rows[i])
		var actual_row := PackedFloat32Array(a[i])
		exact = exact and expected_row == actual_row
		for k in 6:
			max_diff = maxf(max_diff, absf(expected_row[k] - actual_row[k]))
	t.ok(max_diff <= 1e-5, "trajectory within 1e-5 of golden (max diff %s)" % String.num_scientific(max_diff))
	print("    golden comparison: bit_exact_float32=%s max_diff=%s golden_from='%s'" % [
		exact, String.num_scientific(max_diff), golden.get("generated_on", "?")])
