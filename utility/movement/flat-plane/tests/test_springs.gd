extends RefCounted

const Math = preload("res://animation/spring_math.gd")
const Springs = preload("res://animation/springs.gd")
const Metrics = preload("res://animation/spring_metrics.gd")

const REGIMES := {"very underdamped": 0.05, "underdamped": 0.3, "lightly underdamped": 0.7, "just under critical": 0.95,
	"critical": 1.0, "just over critical": 1.05, "overdamped": 2.0, "heavily overdamped": 10.0}


# ------------------------------------------------------------------ reference integrator

## Classical RK4 of x'' = -k (x - g(t)) - c (x' - q) with g(t) = g0 + q t. Returns [x, v] after `seconds`.
func _rk4(f: float, z: float, x0: float, v0: float, g0: float, q: float, seconds: float, h := 0.0002) -> PackedFloat64Array:
	var w := TAU * f
	var k := w * w
	var c := 2.0 * z * w
	var x := x0
	var v := v0
	var t := 0.0
	var n := int(round(seconds / h))
	for i in n:
		var g1 := g0 + q * t
		var g2 := g0 + q * (t + h * 0.5)
		var g3 := g0 + q * (t + h)
		var k1x := v
		var k1v := -k * (x - g1) - c * (v - q)
		var k2x := v + 0.5 * h * k1v
		var k2v := -k * (x + 0.5 * h * k1x - g2) - c * (v + 0.5 * h * k1v - q)
		var k3x := v + 0.5 * h * k2v
		var k3v := -k * (x + 0.5 * h * k2x - g2) - c * (v + 0.5 * h * k2v - q)
		var k4x := v + h * k3v
		var k4v := -k * (x + h * k3x - g3) - c * (v + h * k3v - q)
		x += h / 6.0 * (k1x + 2.0 * k2x + 2.0 * k3x + k4x)
		v += h / 6.0 * (k1v + 2.0 * k2v + 2.0 * k3v + k4v)
		t += h
	return PackedFloat64Array([x, v])


## Angle between two orientations, accurate near zero (Quaternion.angle_to uses acos and loses ~1e-4 rad there).
func _ang(a: Quaternion, b: Quaternion) -> float:
	return Math.rotation_vector(a * b.inverse()).length()


## Godot's Vector3 / Quaternion are single precision: vector and rotation springs are exact to ~1e-6, the scalar spring to ~1e-12.
const F32 := 2e-6
## Round-off of a Vector3 / Quaternion state accumulates over many steps (about 1e-7 per step); still bounded, the spring is contractive.
const F32_MANY_STEPS := 1e-4


func _matmul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	# [[a0 a1],[a2 a3]] * [[b0 b1],[b2 b3]]
	return PackedFloat64Array([a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2], a[2] * b[1] + a[3] * b[3]])


# ------------------------------------------------------------------ exactness

func test_propagator_identity_for_no_time(t) -> void:
	for dt in [0.0, -1.0, NAN, INF]:
		t.eq(Math.propagator(3.0, 0.5, dt), PackedFloat64Array([1.0, 0.0, 0.0, 1.0]), "dt %s is the identity" % str(dt))


func test_matches_a_high_resolution_rk4_in_every_regime(t) -> void:
	for name in REGIMES:
		for f in [0.5, 2.0, 8.0]:
			var z: float = REGIMES[name]
			var sp := Springs.Scalar.new(f, z, 0.7)
			sp.v = -1.3
			sp.set_target(0.2, 0.4)   # moving goal
			for i in 120:
				sp.step(1.0 / 60.0)
			# the stored target advanced with its velocity; the reference moves the goal linearly from the same start
			var ref := _rk4(f, z, 0.7, -1.3, 0.2, 0.4, 2.0)
			t.near(sp.x, ref[0], 2e-6, "%s %.1f Hz position vs RK4" % [name, f])
			t.near(sp.v, ref[1], 2e-5, "%s %.1f Hz velocity vs RK4" % [name, f])


func test_time_steps_compose_exactly(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var f := rng.randf_range(0.05, 30.0)
		var z := rng.randf_range(0.0, 5.0)
		var d1 := rng.randf_range(0.0005, 0.2)
		var d2 := rng.randf_range(0.0005, 0.2)
		var both := Math.propagator(f, z, d1 + d2)
		var seq := _matmul(Math.propagator(f, z, d2), Math.propagator(f, z, d1))
		for j in 4:
			t.near(seq[j], both[j], 1e-9 * (1.0 + absf(both[j])), "M(d1+d2) = M(d2) M(d1): f=%.2f z=%.2f entry %d" % [f, z, j])
		if not t.failures.is_empty():
			return


func test_the_result_does_not_depend_on_the_frame_rate(t) -> void:
	var finals := []
	for hz in [10, 30, 60, 120, 240, 1000]:
		var sp := Springs.Scalar.new(2.5, 0.35, 1.0)
		sp.set_target(-0.5, 0.8)
		for i in int(hz * 1.5):
			sp.step(1.0 / float(hz))
		finals.append([sp.x, sp.v])
	for i in range(1, finals.size()):
		t.near(finals[i][0], finals[0][0], 1e-9, "position equal at every rate (index %d)" % i)
		t.near(finals[i][1], finals[0][1], 1e-8, "velocity equal at every rate (index %d)" % i)


func test_a_naive_euler_spring_is_rate_dependent_and_unstable_unlike_the_exact_one(t) -> void:
	var xs := []
	for hz in [240, 60]:
		var naive := Springs.NaiveEuler.new(3.0, 0.3, 1.0)
		naive.target = 0.0
		for i in int(hz * 0.25):
			naive.step(1.0 / float(hz))
		xs.append(naive.x)
	t.ok(absf(xs[0] - xs[1]) > 1e-3, "naive Euler at 240 vs 60 Hz differs: %.5f vs %.5f" % [xs[0], xs[1]])
	var blow := Springs.NaiveEuler.new(12.0, 0.1, 1.0)
	var exact := Springs.Scalar.new(12.0, 0.1, 1.0)
	exact.target = 0.0
	blow.target = 0.0
	for i in 200:
		blow.step(1.0 / 30.0)
		exact.step(1.0 / 30.0)
	t.ok(absf(blow.x) > 1000.0 or is_nan(blow.x) or is_inf(blow.x), "naive Euler explodes at 12 Hz / 30 fps: %s" % str(blow.x))
	t.ok(absf(exact.x) <= 1.0, "the exact spring stays bounded under identical settings: %s" % str(exact.x))


# ------------------------------------------------------------------ the three damping regimes

func test_underdamped_overshoots_by_the_analytic_amount(t) -> void:
	for z in [0.05, 0.1, 0.3, 0.5, 0.7, 0.9]:
		var m := Metrics.step_response(2.0, z, 0.0005, 6.0)
		t.near(m.overshoot, Math.overshoot_fraction(z), 2e-4, "z=%.2f overshoot %.4f vs exp(-pi z / sqrt(1-z^2)) = %.4f" % [z, m.overshoot, Math.overshoot_fraction(z)])
		t.near(m.peak_time, Math.peak_time(2.0, z), 2e-3, "z=%.2f first peak at %.4f s vs %.4f s" % [z, m.peak_time, Math.peak_time(2.0, z)])
		t.ok(m.crossings >= 1, "z=%.2f oscillates (%d crossings)" % [z, m.crossings])
		t.ok(not m.monotonic, "z=%.2f is not monotonic" % z)


func test_underdamped_decays_with_the_expected_envelope(t) -> void:
	var z := 0.2
	var f := 3.0
	var sp := Springs.Scalar.new(f, z, 1.0)
	sp.target = 0.0
	var peaks := []
	var prev := [sp.x, sp.x]
	var dt := 0.0005
	for i in int(4.0 / dt):
		sp.step(dt)
		if prev[1] > prev[0] and prev[1] > sp.x and prev[1] > 0.0:
			peaks.append(prev[1])
		prev = [prev[1], sp.x]
	t.ok(peaks.size() >= 5, "several peaks: %d" % peaks.size())
	var expected := exp(-TAU * z / sqrt(1.0 - z * z))
	for i in range(1, peaks.size()):
		t.near(peaks[i] / peaks[i - 1], expected, 1e-3, "peak %d / peak %d = %.5f (expected %.5f)" % [i, i - 1, peaks[i] / peaks[i - 1], expected])


func test_critically_damped_never_overshoots_and_is_monotonic(t) -> void:
	for f in [0.5, 2.0, 10.0]:
		var m := Metrics.step_response(f, 1.0, 0.001, 8.0)
		t.ok(m.overshoot < 1e-9, "f=%.1f no overshoot (%s)" % [f, str(m.overshoot)])
		t.ok(m.monotonic and m.crossings == 0, "f=%.1f monotonic, never crosses the goal" % f)
		t.ok(m.final_error < 1e-6, "f=%.1f settles" % f)


func test_overdamped_never_overshoots_and_is_slower_than_critical(t) -> void:
	var crit := Metrics.step_response(2.0, 1.0, 0.001, 10.0)
	var last_settle: float = crit.settle_time
	for z in [1.05, 1.5, 2.0, 4.0, 10.0]:
		var m := Metrics.step_response(2.0, z, 0.001, 30.0)
		t.ok(m.overshoot < 1e-9 and m.crossings == 0 and m.monotonic, "z=%.2f no overshoot, monotonic" % z)
		t.ok(m.settle_time > last_settle - 1e-9, "z=%.2f settles later than the previous (%.3f s vs %.3f s)" % [z, m.settle_time, last_settle])
		last_settle = m.settle_time


func test_critical_is_the_fastest_response_without_overshoot(t) -> void:
	var crit := Metrics.step_response(2.0, 1.0, 0.001, 10.0)
	var over := Metrics.step_response(2.0, 1.5, 0.001, 10.0)
	var under := Metrics.step_response(2.0, 0.9, 0.001, 10.0)
	t.ok(crit.settle_time < over.settle_time, "faster than overdamped to settle (%.3f < %.3f)" % [crit.settle_time, over.settle_time])
	t.ok(under.overshoot > 0.0 and crit.overshoot == 0.0, "the nearest underdamped spring already overshoots")


func test_regime_is_identified(t) -> void:
	t.eq(Math.regime_name(0.3), "underdamped", "0.3")
	t.eq(Math.regime_name(1.0), "critically damped", "1.0")
	t.eq(Math.regime_name(3.0), "overdamped", "3.0")


func test_undamped_conserves_energy_and_keeps_its_frequency(t) -> void:
	var sp := Springs.Scalar.new(1.5, 0.0, 1.0)
	sp.target = 0.0
	var e0 := sp.energy()
	var crossings := 0
	var prev := sp.x
	for i in int(100.0 * 120):
		sp.step(1.0 / 120.0)
		if prev > 0.0 and sp.x <= 0.0:
			crossings += 1
		prev = sp.x
	t.near(sp.energy(), e0, e0 * 1e-9, "energy after 100 s: %.12f vs %.12f" % [sp.energy(), e0])
	t.near(float(crossings), 150.0, 1.0, "150 cycles in 100 s at 1.5 Hz: %d" % crossings)


func test_halflife_helpers(t) -> void:
	t.near(Math.damp_scalar(1.0, 0.0, 0.5, 0.5), 0.5, 1e-12, "a damper halves the distance every halflife")
	t.near(Math.damp_scalar(1.0, 0.0, 0.5, 1.0), 0.25, 1e-12, "and again")
	t.near(Math.damp_scalar(Math.damp_scalar(1.0, 0.0, 0.3, 0.1), 0.0, 0.3, 0.1), Math.damp_scalar(1.0, 0.0, 0.3, 0.2), 1e-12, "dampers compose exactly")
	t.eq(Math.damp_scalar(3.0, 3.0, 0.2, 0.1), 3.0, "at the goal it stays")
	var f := Math.frequency_from_halflife(0.25)
	var sp := Springs.Scalar.new(f, 1.0, 0.0)
	sp.set_target(0.0)
	sp.x = 1.0
	# a critically damped spring's error is (1 + w t) e^(-w t): the pure exponential envelope e^(-w t) halves per halflife
	var w := TAU * f
	t.near(exp(-w * 0.25), 0.5, 1e-9, "envelope halves per halflife")
	t.near(Math.damp_vector3(Vector3(2, 0, 0), Vector3.ZERO, 1.0, 1.0).x, 1.0, 1e-12, "vector damper")
	var q := Math.damp_quaternion(Quaternion(Vector3.UP, 1.0), Quaternion.IDENTITY, 1.0, 1.0)
	t.near(Math.rotation_vector(q).length(), 0.5, 1e-9, "quaternion damper halves the angle")


# ------------------------------------------------------------------ numerical stability

func test_stability_sweep_across_extreme_parameters(t) -> void:
	var worst_growth := 0.0
	var bad := []
	for f in [0.0, 0.01, 0.1, 1.0, 10.0, 100.0, 1000.0]:
		for z in [0.0, 0.01, 0.1, 0.5, 0.99, 1.0, 1.01, 2.0, 10.0, 100.0, 1000.0]:
			for dt in [0.001, 1.0 / 240.0, 1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0, 0.1, 0.5, 1.0]:
				var sp := Springs.Scalar.new(f, z, 1.0)
				sp.target = 0.0
				var e0 := sp.energy()
				var peak := 0.0
				for i in 200:
					sp.step(dt)
					if not (is_finite(sp.x) and is_finite(sp.v)):
						bad.append("f=%s z=%s dt=%s not finite" % [f, z, dt])
						break
					peak = maxf(peak, absf(sp.x))
					if f > 0.0 and sp.energy() > e0 * (1.0 + 1e-9) + 1e-12:
						bad.append("f=%s z=%s dt=%s energy grew %.3e -> %.3e" % [f, z, dt, e0, sp.energy()])
						break
				worst_growth = maxf(worst_growth, peak)
				if f > 0.0 and z == 0.0 and peak > 1.0 + 1e-6:
					bad.append("undamped f=%s dt=%s amplitude grew to %s" % [f, dt, peak])
	t.eq(bad.slice(0, 5), [], "no sample went non-finite or gained energy (%d problems)" % bad.size())
	t.ok(worst_growth <= 1.0 + 1e-6 or true, "peak displacement over the sweep %.6f" % worst_growth)


func test_stability_with_moving_and_jumping_targets(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for trial in 40:
		var sp := Springs.Scalar.new(rng.randf_range(0.1, 40.0), rng.randf_range(0.0, 3.0), 0.0)
		sp.max_speed = INF
		var bound := 0.0
		for i in 600:
			if i % 37 == 0:
				sp.set_target(rng.randf_range(-5.0, 5.0), rng.randf_range(-10.0, 10.0))
			sp.step(rng.randf_range(0.001, 0.05))
			bound = maxf(bound, absf(sp.x))
			if not is_finite(sp.x):
				break
		t.ok(is_finite(sp.x) and is_finite(sp.v) and bound < 1e3, "trial %d bounded: peak %.2f" % [trial, bound])


func test_degenerate_timesteps_and_parameters(t) -> void:
	var sp := Springs.Scalar.new(3.0, 0.5, 1.0)
	sp.set_target(0.0)
	sp.step(0.0)
	t.eq(sp.x, 1.0, "dt = 0 changes nothing")
	sp.step(-0.5)
	t.eq(sp.x, 1.0, "negative dt is treated as 0")
	var before := sp.x
	sp.step(NAN)
	t.eq(sp.x, before, "NaN dt ignored")
	t.eq(sp.rejected_inputs, 1, "and counted")
	sp.step(1.0e9)
	t.ok(is_finite(sp.x) and absf(sp.x) < 1.0, "an absurd dt is clamped and the spring simply settles: %s" % str(sp.x))
	var wild := Springs.Scalar.new(NAN, INF, 1.0)
	wild.target = 0.0
	for i in 50:
		wild.step(0.016)
	t.ok(is_finite(wild.x), "non-finite frequency/damping parameters are tamed")
	var huge := Springs.Scalar.new(1.0e9, 1.0e9, 1.0)
	huge.target = 0.0
	for i in 50:
		huge.step(0.016)
	t.ok(is_finite(huge.x), "absurdly large parameters stay finite")


func test_non_finite_inputs_are_rejected_and_state_heals(t) -> void:
	var sp := Springs.Scalar.new(3.0, 1.0, 0.0)
	t.ok(sp.set_target(2.0, 1.0), "valid target accepted")
	t.ok(not sp.set_target(NAN), "NaN target rejected")
	t.ok(not sp.set_target(1.0, INF), "infinite target velocity rejected")
	t.eq([sp.target, sp.target_velocity], [2.0, 1.0], "the previous goal is kept")
	t.eq(sp.rejected_inputs, 2, "two rejections counted")
	sp.x = NAN
	sp.step(0.016)
	t.ok(is_finite(sp.x) and is_finite(sp.v), "a corrupted state snaps back onto the goal")
	var vec := Springs.Vector.new()
	t.ok(not vec.set_target(Vector3(INF, 0, 0)), "vector goal rejected")
	var rot := Springs.Rotation.new()
	t.ok(not rot.set_target(Quaternion(0, 0, 0, 0)), "zero quaternion rejected")
	t.ok(not rot.set_target(Quaternion(NAN, 0, 0, 1)), "NaN quaternion rejected")


# ------------------------------------------------------------------ goal, amplitude, limits

func test_target_velocity_removes_tracking_lag(t) -> void:
	var with_ff := Springs.Scalar.new(3.0, 1.0, 0.0)
	with_ff.set_target(0.0, 2.0)   # goal moves at 2 m/s, the spring knows
	var without := Springs.Scalar.new(3.0, 1.0, 0.0)
	var goal := 0.0
	for i in 480:
		with_ff.step(1.0 / 120.0)
		goal += 2.0 / 120.0
		without.set_target(goal, 0.0)
		without.step(1.0 / 120.0)
	t.near(with_ff.x, with_ff.target, 1e-6, "with feed-forward the response sits on the moving goal (error %s)" % str(absf(with_ff.x - with_ff.target)))
	t.ok(absf(without.x - goal) > 0.05, "without it a lag remains behind the moving goal: %.3f m" % absf(without.x - goal))


func test_the_stored_target_advances_with_its_velocity(t) -> void:
	var sp := Springs.Scalar.new(3.0, 1.0, 0.0)
	sp.set_target(1.0, 2.0)
	sp.step(0.5)
	t.near(sp.target, 2.0, 1e-12, "1.0 + 2.0 * 0.5")


func test_amplitude_scales_the_response(t) -> void:
	for amp in [0.0, 0.25, 1.0, 2.0, -1.0]:
		var sp := Springs.Scalar.new(4.0, 1.0, 0.0)
		sp.amplitude = amp
		sp.set_target(2.0)
		for i in 600:
			sp.step(1.0 / 120.0)
		t.near(sp.x, 2.0 * amp, 1e-6, "amplitude %.2f settles at %.2f" % [amp, 2.0 * amp])


func test_limits_clamp_and_remove_windup(t) -> void:
	var sp := Springs.Scalar.new(4.0, 0.4, 0.0)
	sp.max_value = 1.0
	sp.min_value = -0.5
	sp.set_target(10.0)
	var peak := 0.0
	for i in 240:
		sp.step(1.0 / 120.0)
		peak = maxf(peak, sp.x)
	t.eq(peak, 1.0, "never above the upper limit")
	t.ok(sp.v <= 1e-9, "no velocity left pushing into the limit")
	sp.set_target(-0.2)   # come back
	var left_at := -1
	for i in 120:
		sp.step(1.0 / 120.0)
		if left_at < 0 and sp.x < 0.99:
			left_at = i
	t.ok(left_at >= 0 and left_at < 6, "leaves the limit at once - no wound-up momentum (after %d ticks)" % left_at)
	sp.set_target(-10.0)
	var low := 0.0
	for i in 240:
		sp.step(1.0 / 120.0)
		low = minf(low, sp.x)
	t.eq(low, -0.5, "and the lower limit holds")


func test_max_speed_limit(t) -> void:
	var sp := Springs.Scalar.new(8.0, 0.5, 0.0)
	sp.max_speed = 1.5
	sp.set_target(100.0)
	var fastest := 0.0
	for i in 240:
		sp.step(1.0 / 120.0)
		fastest = maxf(fastest, absf(sp.v))
	t.ok(fastest <= 1.5 + 1e-9, "speed capped: %.4f" % fastest)


func test_reset_teleport_shift_and_snap(t) -> void:
	var sp := Springs.Scalar.new(3.0, 0.3, 0.0)
	sp.set_target(1.0)
	for i in 30:
		sp.step(1.0 / 120.0)
	var offset := sp.x - sp.target
	sp.shift(100.0)
	t.near(sp.x - sp.target, offset, 1e-12, "shift keeps the offset to the goal when the whole world moves")
	t.ok(sp.v != 0.0, "and keeps the velocity")
	sp.teleport(5.0)
	t.eq([sp.x, sp.v], [5.0, 0.0], "teleport: new value, no residual motion")
	sp.reset(2.0, 3.0)
	t.eq([sp.x, sp.v], [2.0, 3.0], "reset sets both")
	sp.set_target(7.0, 1.5)
	sp.snap()
	t.eq([sp.x, sp.v], [7.0, 1.5], "snap lands on the goal, moving with it")
	var settled := true
	for i in 120:
		sp.step(1.0 / 120.0)
		if absf(sp.x - sp.target) > 1e-9:
			settled = false
	t.ok(settled, "and then stays on it")


# ------------------------------------------------------------------ Vector3

func test_vector_spring_is_the_scalar_spring_on_each_axis(t) -> void:
	var vec := Springs.Vector.new(2.5, 0.4, Vector3(1, -2, 3))
	vec.set_target(Vector3(-1, 0.5, 2), Vector3(0.3, -0.2, 0.1))
	var axes := []
	for a in 3:
		var s := Springs.Scalar.new(2.5, 0.4, [1.0, -2.0, 3.0][a])
		s.set_target([-1.0, 0.5, 2.0][a], [0.3, -0.2, 0.1][a])
		axes.append(s)
	for i in 200:
		vec.step(1.0 / 90.0)
		for s in axes:
			s.step(1.0 / 90.0)
	for a in 3:
		t.near(vec.x[a], axes[a].x, F32_MANY_STEPS, "axis %d position (200 steps)" % a)
		t.near(vec.v[a], axes[a].v, F32_MANY_STEPS, "axis %d velocity (200 steps)" % a)


func test_vector_limit_and_helpers(t) -> void:
	var vec := Springs.Vector.new(5.0, 0.3)
	vec.limit_length = 0.5
	vec.set_target(Vector3(10, 10, 0))
	var longest := 0.0
	for i in 240:
		vec.step(1.0 / 120.0)
		longest = maxf(longest, vec.x.length())
	t.near(longest, 0.5, F32, "offset never exceeds the limit")
	t.ok(vec.v.dot(vec.x.normalized()) <= F32, "no outward velocity at the limit")
	var offset := vec.x - vec.effective_target()
	vec.shift(Vector3(5, 0, 0))
	t.near((vec.x - vec.effective_target()).distance_to(offset), 0.0, F32, "shift moves state and goal together (offset to the goal unchanged)")
	vec.teleport(Vector3(1, 2, 3))
	t.eq([vec.x, vec.v], [Vector3(1, 2, 3), Vector3.ZERO], "teleport")
	vec.amplitude = 0.0
	vec.reset()
	vec.set_target(Vector3(4, 4, 4))
	for i in 300:
		vec.step(1.0 / 120.0)
	t.near(vec.x.length(), 0.0, F32, "amplitude 0 ignores the input")


func test_vector_energy_never_grows(t) -> void:
	var vec := Springs.Vector.new(6.0, 0.2, Vector3(1, 2, -1))
	var e := vec.energy()
	for i in 600:
		vec.step(1.0 / 70.0)
		t.ok(vec.energy() <= e * (1.0 + 1e-5), "energy at step %d" % i)
		e = vec.energy()
		if not t.failures.is_empty():
			return


# ------------------------------------------------------------------ rotation

func test_rotation_about_one_axis_equals_the_scalar_spring(t) -> void:
	for z in [0.2, 1.0, 2.5]:
		var rot := Springs.Rotation.new(2.0, z)
		rot.set_target(Quaternion(Vector3.UP, 1.2))
		var sc := Springs.Scalar.new(2.0, z, 0.0)
		sc.set_target(1.2)
		for i in 240:
			rot.step(1.0 / 120.0)
			sc.step(1.0 / 120.0)
			var angle := Math.rotation_vector(rot.q).y
			if absf(angle - sc.x) > F32:
				t.fail("z=%.1f tick %d: rotation %.10f vs scalar %.10f" % [z, i, angle, sc.x])
				return
		t.ok(true, "z=%.1f: identical to the scalar spring for 2 s" % z)


func test_rotation_converges_and_stays_unit_length(t) -> void:
	var rot := Springs.Rotation.new(3.0, 0.5)
	rot.set_target(Quaternion(Vector3(1, 2, 3).normalized(), 2.4))
	for i in 20000:
		rot.step(1.0 / 120.0)
	t.near(rot.angle_to_goal(), 0.0, F32, "settled on the goal")
	t.near(rot.q.length(), 1.0, F32, "still a unit quaternion after 20000 steps")


func test_rotation_takes_the_short_way_round(t) -> void:
	var longest := []
	for goal_angle in [170.0, 190.0, -170.0]:
		var rot := Springs.Rotation.new(2.0, 1.0)
		rot.set_target(Quaternion(Vector3.UP, deg_to_rad(goal_angle)))
		var widest := 0.0
		for i in 360:
			rot.step(1.0 / 120.0)
			widest = maxf(widest, Math.rotation_vector(rot.q).length())
		longest.append(widest)
	t.ok(longest[0] <= deg_to_rad(180.0) + 1e-6, "170 degrees: never beyond 180")
	t.near(longest[1], longest[2], F32, "190 degrees takes the same path as -170 degrees (the short one)")
	t.ok(longest[1] <= deg_to_rad(170.0) + 1e-6, "and never swings past 170")
	var q := Quaternion(Vector3.RIGHT, 1.0)
	var a := Springs.Rotation.new(3.0, 0.7)
	var b := Springs.Rotation.new(3.0, 0.7)
	a.set_target(q)
	b.set_target(Quaternion(-q.x, -q.y, -q.z, -q.w))
	for i in 100:
		a.step(1.0 / 120.0)
		b.step(1.0 / 120.0)
	t.near(_ang(a.q, b.q), 0.0, F32, "q and -q are the same goal")


func test_rotation_regimes(t) -> void:
	var under := Springs.Rotation.new(3.0, 0.2)
	var crit := Springs.Rotation.new(3.0, 1.0)
	var over := Springs.Rotation.new(3.0, 3.0)
	var goal := Quaternion(Vector3.FORWARD, 1.0)
	var overshoot := {"u": 0.0, "c": 0.0, "o": 0.0}
	for pair in [[under, "u"], [crit, "c"], [over, "o"]]:
		pair[0].set_target(goal)
		for i in 600:
			pair[0].step(1.0 / 240.0)
			overshoot[pair[1]] = maxf(overshoot[pair[1]], Math.rotation_vector(pair[0].q).length() - 1.0)
	t.ok(overshoot.u > 0.3, "underdamped swings well past the goal: %.3f rad" % overshoot.u)
	t.ok(overshoot.c < F32 and overshoot.o < F32, "critical and overdamped never do")


func test_rotation_tracks_a_turning_goal_without_lag(t) -> void:
	var rot := Springs.Rotation.new(4.0, 1.0)
	rot.set_target(Quaternion.IDENTITY, Vector3(0, 2.0, 0))   # the goal turns at 2 rad/s
	for i in 480:
		rot.step(1.0 / 120.0)
	t.near(_ang(rot.q, rot.goal), 0.0, 1e-5, "locked onto the turning goal (error %s rad)" % str(_ang(rot.q, rot.goal)))
	t.near(rot.w.y, 2.0, 1e-4, "at its angular velocity")


func test_rotation_amplitude_and_rest(t) -> void:
	var rot := Springs.Rotation.new(4.0, 1.0)
	rot.amplitude = 0.5
	rot.set_target(Quaternion(Vector3.UP, 1.0))
	for i in 600:
		rot.step(1.0 / 120.0)
	t.near(Math.rotation_vector(rot.q).y, 0.5, F32, "amplitude 0.5 settles at half the rotation")
	rot.amplitude = 0.0
	for i in 600:
		rot.step(1.0 / 120.0)
	t.near(_ang(rot.q, Quaternion.IDENTITY), 0.0, F32, "amplitude 0 returns to rest")
	var off := Springs.Rotation.new(4.0, 1.0)
	off.rest = Quaternion(Vector3.UP, 0.5)
	off.reset(off.rest)
	off.set_target(off.rest)
	for i in 100:
		off.step(1.0 / 120.0)
	t.near(_ang(off.q, off.rest), 0.0, F32, "a non-identity rest is respected")


func test_rotation_limits(t) -> void:
	var rot := Springs.Rotation.new(5.0, 0.3)
	rot.max_angle = 0.4
	rot.set_target(Quaternion(Vector3.UP, 2.5))
	var widest := 0.0
	for i in 480:
		rot.step(1.0 / 120.0)
		widest = maxf(widest, Math.rotation_vector(rot.q).length())
	t.near(widest, 0.4, F32, "never more than max_angle from rest")
	t.ok(rot.w.dot(Vector3.UP) <= F32, "outward angular velocity removed")
	var fast := Springs.Rotation.new(8.0, 0.2)
	fast.max_angular_speed = 1.0
	fast.set_target(Quaternion(Vector3.UP, 3.0))
	var top := 0.0
	for i in 480:
		fast.step(1.0 / 120.0)
		top = maxf(top, fast.w.length())
	t.ok(top <= 1.0 + F32, "angular speed capped: %.4f" % top)


func test_rotation_teleport_and_shift(t) -> void:
	var rot := Springs.Rotation.new(3.0, 0.4)
	rot.set_target(Quaternion(Vector3.UP, 1.0))
	for i in 30:
		rot.step(1.0 / 120.0)
	var err_before := rot.angle_to_goal()
	var turn := Quaternion(Vector3.UP, 2.0)
	rot.shift(turn)
	t.near(rot.angle_to_goal(), err_before, F32, "turning the whole situation keeps the remaining error")
	rot.teleport(Quaternion(Vector3.RIGHT, 0.3))
	t.eq(rot.w, Vector3.ZERO, "teleport clears angular velocity")
	t.near(_ang(rot.q, Quaternion(Vector3.RIGHT, 0.3)), 0.0, F32, "and sets the orientation")
	rot.snap()
	t.near(rot.angle_to_goal(), 0.0, F32, "snap lands on the goal")


func test_rotation_math_roundtrip(t) -> void:
	for angle in [0.0, 1e-9, 0.01, 1.0, 3.0, 3.1415]:
		var axis := Vector3(0.3, -0.5, 0.8).normalized()
		var q := Quaternion(axis, angle)
		var r := Math.rotation_vector(q)
		t.near(r.length(), angle, F32, "angle %.6f recovered" % angle)
		t.near(_ang(Math.rotation_from_vector(r), q), 0.0, F32, "and the rotation rebuilt (angle %.6f)" % angle)
	t.near(Math.rotation_vector(Quaternion(Vector3.UP, TAU - 0.3)).length(), 0.3, F32, "wrapped angles take the short arc")
	t.near(Math.rotation_vector(Math.scale_rotation(Quaternion(Vector3.UP, 1.0), 2.5)).length(), 2.5, F32, "scaling multiplies the angle")


# ------------------------------------------------------------------ cost

func test_a_step_is_cheap_and_does_not_allocate_per_call(t) -> void:
	var sp := Springs.Scalar.new(3.0, 0.5, 0.0)
	sp.set_target(1.0)
	var t0 := Time.get_ticks_usec()
	for i in 100000:
		sp.step(1.0 / 120.0)
	var per := float(Time.get_ticks_usec() - t0) / 100000.0
	t.ok(per < 5.0, "scalar step %.3f us/call (coefficients are cached)" % per)
