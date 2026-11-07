extends RefCounted

const SCENE := "res://scenes/spring_diagnostic.tscn"
const Math = preload("res://animation/spring_math.gd")
const Springs = preload("res://animation/springs.gd")

var _d
var _tree: SceneTree


func before_each() -> void:
	_tree = Engine.get_main_loop()
	_d = load(SCENE).instantiate()
	_d.options = {"no-window-state": "true"}
	_tree.root.add_child(_d)
	await _tree.process_frame
	_d.set_process(false)   # the tests advance the experiment themselves, deterministically
	_d.paused = true


func after_each() -> void:
	_d.queue_free()
	await _tree.process_frame


func test_scene_builds_and_runs(t) -> void:
	_d.advance(3.0)
	t.ok(_d.samples.size() > 150, "samples were recorded: %d" % _d.samples.size())
	t.ok(_d._plot != null and _d._dial != null and _d._readout != null, "plot, dial and readout exist")
	t.ok(is_finite(_d.spring.x) and is_finite(_d.rot_spring.q.length()), "everything finite")


func test_measured_overshoot_matches_the_theory(t) -> void:
	_d.mode = 0
	_d.period = 3.0
	_d.set_frequency(2.0)
	for z in [0.15, 0.3, 0.6]:
		_d.clear()
		_d.time = 0.0
		_d._next_change = 0.0
		_d.spring.reset(0.0, 0.0)
		_d.set_damping(z)
		_d.tick_index = 0   # 240 Hz: fine enough to resolve the peak
		_d.advance(7.0)
		t.ok(not _d.last_measure.is_empty(), "z=%.2f a completed step exists" % z)
		t.near(_d.measured_overshoot_pct(), _d.theory_overshoot_pct(), 0.6, "z=%.2f measured %.2f %% vs theory %.2f %%" % [z, _d.measured_overshoot_pct(), _d.theory_overshoot_pct()])


func test_critical_and_overdamped_show_no_overshoot(t) -> void:
	for z in [1.0, 3.0]:
		_d.clear()
		_d.time = 0.0
		_d._next_change = 0.0
		_d.spring.reset(0.0, 0.0)
		_d.set_damping(z)
		_d.tick_index = 0
		_d.period = 3.0
		_d.advance(7.0)
		t.near(_d.measured_overshoot_pct(), 0.0, 1e-6, "z=%.1f no overshoot" % z)
		t.ok(_d.measured_settle_time() > 0.0, "and a settle time is reported: %.3f s" % _d.measured_settle_time())


func test_the_three_reference_regimes_behave_as_labelled(t) -> void:
	_d.show_regimes = true
	_d.set_frequency(2.0)
	_d.period = 4.0
	_d.advance(3.9)
	var top := {"under": -9.0, "crit": -9.0, "over": -9.0}
	for s in _d.samples:
		for k in top:
			top[k] = maxf(top[k], float(s[k]))
	t.ok(top.under > 1.3, "underdamped overshoots the goal (peak %.3f)" % top.under)
	t.ok(top.crit <= 1.0 + 1e-6, "critical does not (peak %.6f)" % top.crit)
	t.ok(top.over <= 1.0 + 1e-6, "overdamped does not (peak %.6f)" % top.over)


func test_the_exact_spring_is_the_same_at_every_tick_rate(t) -> void:
	# A fixed target held from rest: the exact spring must land on the same state however finely time is sliced.
	var results := []
	for idx in [0, 1, 2, 3, 4]:   # 240, 120, 60, 30, 15 Hz
		_d.clear()
		_d.time = 0.0
		_d._next_change = 0.0
		_d._acc = 0.0
		_d.mode = 1            # manual: sets the target once, then holds it
		_d.set_frequency(2.5)
		_d.set_damping(0.35)
		_d.spring.reset(0.0, 0.0)
		_d.tick_index = idx
		_d.advance(2.0 + 1e-6)   # the epsilon keeps float rounding from dropping the last tick at some rates
		results.append([_d.spring.x, _d.spring.v, _d.time])
	for r in results:
		t.near(r[2], 2.0, 1e-5, "ran two seconds of simulated time")
	for i in range(1, results.size()):
		t.near(results[i][0], results[0][0], 1e-9, "position equal at tick rate index %d: %.12f vs %.12f" % [i, results[i][0], results[0][0]])
		t.near(results[i][1], results[0][1], 1e-8, "velocity equal at tick rate index %d" % i)
	var naive_xs := []
	for hz in [240.0, 15.0]:
		var n := Springs.NaiveEuler.new(2.5, 0.35, 0.0)
		n.target = 1.0
		for k in int(round(hz * 0.4)):   # 0.4 s: a whole number of ticks at both rates, and the response is still large
			n.step(1.0 / hz)
		naive_xs.append(n.x)
	t.ok(absf(naive_xs[0] - naive_xs[1]) > 0.01, "while the naive spring disagrees with itself between 240 and 15 Hz at 0.4 s: %.4f vs %.4f" % [naive_xs[0], naive_xs[1]])

func test_naive_euler_explodes_where_the_exact_spring_does_not(t) -> void:
	_d.set_frequency(12.0)
	_d.set_damping(0.1)
	_d.tick_index = 3   # 30 Hz
	_d.mode = 0
	_d.period = 2.0
	_d.advance(6.0)
	t.ok(absf(_d.naive.x) > 50.0 or is_nan(_d.naive.x) or is_inf(_d.naive.x), "the naive spring has blown up: %s" % str(_d.naive.x))
	t.ok(absf(_d.spring.x) < 3.0, "the analytic spring is fine: %.3f" % _d.spring.x)


func test_jittery_frame_times_do_not_destabilise_it(t) -> void:
	_d.tick_index = 5
	_d.mode = 4
	_d.set_frequency(8.0)
	_d.set_damping(0.2)
	_d.advance(30.0)
	t.ok(is_finite(_d.spring.x) and absf(_d.spring.x) < 3.0, "bounded with random 8-60 ms frames: %.3f" % _d.spring.x)


func test_output_limits_and_amplitude_apply(t) -> void:
	_d.use_limits = true
	_d.amplitude = 2.0
	_d._configure()
	_d.set_damping(0.3)
	_d.advance(6.0)
	var worst := 0.0
	for s in _d.samples:
		worst = maxf(worst, absf(float(s.x)))
	t.ok(worst <= 0.6 + 1e-9, "limits hold even with amplitude 2: %.4f" % worst)


func test_manual_mode_and_teleport(t) -> void:
	_d.mode = 1
	_d._next_change = 0.0
	_d.advance(0.5)
	_d.target_value = 1.0
	_d.manual_flip()
	t.eq(_d.spring.target, -1.0, "Space flips the target")
	_d.advance(2.0)
	_d.teleport()
	t.eq([_d.spring.x, _d.spring.v], [0.0, 0.0], "teleport clears the state")
	for k in _d.regimes:
		t.eq(_d.regimes[k].x, 0.0, "reference spring %s too" % k)


func test_rotation_dial_takes_the_short_way(t) -> void:
	_d.set_frequency(2.0)
	_d.set_damping(1.0)
	_d.period = 2.0
	var widest_step := 0.0
	var prev := 0.0
	var seen_goals := {}
	for i in 4000:
		_d.advance(1.0 / 60.0)
		var yaw: float = rad_to_deg(Math.rotation_vector(_d.rot_spring.q).y)
		seen_goals[_d.rotation_goal_deg] = true
		widest_step = maxf(widest_step, absf(angle_difference(deg_to_rad(prev), deg_to_rad(yaw))))
		prev = yaw
	t.ok(seen_goals.size() >= 5, "several goals visited: %s" % str(seen_goals.keys()))
	t.ok(widest_step < deg_to_rad(20.0), "never jumps more than 20 degrees in a tick: %.2f deg" % rad_to_deg(widest_step))


func test_readout_names_the_regime(t) -> void:
	for pair in [[0.25, "UNDERDAMPED"], [1.0, "CRITICALLY DAMPED"], [3.0, "OVERDAMPED"]]:
		_d.set_damping(pair[0])
		_d._update_readout()
		t.ok(_d._readout.text.contains(pair[1]), "regime %s shown for zeta %.2f" % [pair[1], pair[0]])
	t.ok(_d._readout.text.contains("Theory"), "theory line present")
