extends RefCounted

const Dyn = preload("res://animation/body_dynamics.gd")
const BodyParams = preload("res://animation/body_params.gd")
const Math = preload("res://animation/spring_math.gd")
const Springs = preload("res://animation/springs.gd")

var _p
var _d: Dyn


func before_each() -> void:
	_p = BodyParams.create()
	_d = Dyn.new(_p)


func after_each() -> void:
	_d = null
	_p = null


## Kinematics of a character facing -Z (heading 0).
func _k(accel := Vector3.ZERO, velocity := Vector3.ZERO, extra := {}) -> Dictionary:
	var k := {"velocity": velocity, "accel": accel, "heading": 0.0 if velocity.length() > 0.5 else NAN, "grounded": true,
		"gait_phase": 0.0, "gait_amount": 0.0, "landed_impact": 0.0}
	k.merge(extra, true)
	return k


func _run(seconds: float, k: Dictionary, hz := 120.0) -> Dictionary:
	for i in int(round(seconds * hz)):
		_d.update(1.0 / hz, k)
	return _d.pose


# ------------------------------------------------------------------ neutral and switches

func test_at_rest_every_offset_is_zero(t) -> void:
	var pose := _run(2.0, _k())
	for key in ["torso_pitch", "torso_yaw", "torso_roll", "pelvis_drop", "bob", "sway", "head_pitch", "head_yaw", "head_roll", "arm_pitch_l", "arm_roll_l", "arm_pitch_r", "arm_roll_r", "pelvis_twist", "shoulder_twist"]:
		t.near(pose[key], 0.0, 1e-9, "%s at rest" % key)
	t.near(pose.pelvis_shift.length(), 0.0, 1e-9, "no weight shift at rest")
	t.ok(pose.active, "the model is active")


func test_master_switch_turns_everything_off_and_back_on_cleanly(t) -> void:
	_run(1.0, _k(Vector3(0, 0, -30), Vector3(0, 0, -4)))
	t.ok(absf(_d.pose.torso_pitch) > 0.05, "leaning before")
	_p.set_value("body_dynamics", 0.0)
	var pose := _d.update(1.0 / 120.0, _k(Vector3(0, 0, -30), Vector3(0, 0, -4)))
	t.ok(not pose.active, "inactive")
	t.eq(pose.torso_pitch, 0.0, "no lean while off")
	_p.set_value("body_dynamics", 1.0)
	pose = _d.update(1.0 / 120.0, _k())
	t.near(pose.torso_pitch, 0.0, 1e-6, "switching back on starts from rest, not from a stale lean")


func test_each_effect_switch_silences_exactly_its_effect(t) -> void:
	var forward := _k(Vector3(0, 0, -30), Vector3(0, 0, -4))
	var cases := {
		"fx_torso_lean": ["torso_pitch", forward],
		"fx_torso_lateral": ["torso_roll", _k(Vector3(15, 0, 0), Vector3(0, 0, -4))],
		"fx_pelvis_shift": ["pelvis_shift", forward],
		"fx_head": ["head_pitch", forward],
		"fx_arms": ["arm_pitch_l", forward],
	}
	for flag in cases:
		var key: String = cases[flag][0]
		var k: Dictionary = cases[flag][1]
		_d = Dyn.new(_p)
		_p.reset_all()
		_run(1.0, k)
		var on: float = _d.pose[key].length() if _d.pose[key] is Vector3 else absf(_d.pose[key])
		t.ok(on > 0.003, "%s: %s responds when on (%.4f)" % [flag, key, on])
		_d = Dyn.new(_p)
		_p.set_value(flag, 0.0)
		_run(1.0, k)
		var off: float = _d.pose[key].length() if _d.pose[key] is Vector3 else absf(_d.pose[key])
		t.near(off, 0.0, 1e-9, "%s off: %s is silent" % [flag, key])
	_p.reset_all()


func test_disabling_one_effect_leaves_the_others_alone(t) -> void:
	var k := _k(Vector3(15, 0, -30), Vector3(0, 0, -4))
	var full := Dyn.new(BodyParams.create())
	for i in 120:
		full.update(1.0 / 120.0, k)
	_p.set_value("fx_torso_lateral", 0.0)
	_run(1.0, k)
	t.near(_d.pose.torso_pitch, full.pose.torso_pitch, 1e-9, "forward lean identical with lateral lean disabled")
	t.near(_d.pose.torso_roll, 0.0, 1e-9, "roll gone")


# ------------------------------------------------------------------ torso

func test_forward_acceleration_leans_forward_and_braking_leans_back(t) -> void:
	var pose := _run(1.0, _k(Vector3(0, 0, -25), Vector3(0, 0, -2)))
	t.ok(pose.torso_pitch > 0.05, "accelerating forward: lean forward (%.3f rad)" % pose.torso_pitch)
	_d.reset()
	pose = _run(1.0, _k(Vector3(0, 0, 25), Vector3(0, 0, -2)))
	t.ok(pose.torso_pitch < 0.0 or absf(pose.torso_pitch) < 0.06, "braking leans less than accelerating (%.3f)" % pose.torso_pitch)
	_d.reset()
	_p.set_value("lean_speed_gain", 0.0)
	pose = _run(1.0, _k(Vector3(0, 0, 25), Vector3(0, 0, -2)))
	t.ok(pose.torso_pitch < -0.05, "with the steady speed lean removed, braking leans BACK (%.3f)" % pose.torso_pitch)


func test_lean_scales_with_acceleration_and_amplitude(t) -> void:
	_p.set_value("lean_speed_gain", 0.0)
	var small: float = _run(1.0, _k(Vector3(0, 0, -5), Vector3(0, 0, -1))).torso_pitch
	_d.reset()
	var big: float = _run(1.0, _k(Vector3(0, 0, -15), Vector3(0, 0, -1))).torso_pitch
	t.near(big / small, 3.0, 0.05, "three times the acceleration, three times the lean (%.4f / %.4f)" % [big, small])
	_d.reset()
	_p.set_value("torso_lean_amp", 0.5)
	var half: float = _run(1.0, _k(Vector3(0, 0, -15), Vector3(0, 0, -1))).torso_pitch
	t.near(half, big * 0.5, 1e-3, "amplitude 0.5 halves it")
	_d.reset()
	_p.set_value("torso_lean_amp", 0.0)
	t.near(_run(1.0, _k(Vector3(0, 0, -15), Vector3(0, 0, -1))).torso_pitch, 0.0, 1e-9, "amplitude 0 removes it")


func test_steady_running_leans_in_proportion_to_speed(t) -> void:
	var slow: float = _run(1.5, _k(Vector3.ZERO, Vector3(0, 0, -2))).torso_pitch
	_d.reset()
	var fast: float = _run(1.5, _k(Vector3.ZERO, Vector3(0, 0, -7))).torso_pitch
	t.ok(fast > slow * 2.5 and slow > 0.0, "faster = leans further: %.3f -> %.3f rad" % [slow, fast])


func test_lean_is_limited_whatever_the_acceleration(t) -> void:
	_p.set_value("lean_max_deg", 20.0)
	var worst := 0.0
	for i in 600:
		_d.update(1.0 / 120.0, _k(Vector3(0, 0, -10000), Vector3(0, 0, -100)))
		worst = maxf(worst, absf(_d.pose.torso_pitch))
	t.ok(worst <= deg_to_rad(20.0) * Dyn.OVERSHOOT_ALLOWANCE + 1e-6, "never beyond the configured limit plus the overshoot allowance: %.3f rad" % worst)
	_p.set_value("lean_max_deg", 40.0)
	for i in 600:
		_d.update(1.0 / 120.0, _k(Vector3(0, 0, -10000), Vector3(0, 0, -100)))
		worst = maxf(worst, absf(_d.pose.torso_pitch))
	t.ok(worst <= Dyn.TORSO_PITCH_HARD + 1e-6, "and never past the hard joint limit even at 40 degrees: %.3f" % worst)


func test_stopping_gives_elastic_follow_through_then_returns_to_neutral(t) -> void:
	_p.set_value("torso_damping", 0.25)
	_run(1.0, _k(Vector3(0, 0, -30), Vector3(0, 0, -4)))
	var leaned: float = _d.pose.torso_pitch
	t.ok(leaned > 0.05, "leaning forward")
	var lowest := 9.0
	var final_pitch := 0.0
	for i in 480:
		_d.update(1.0 / 120.0, _k())   # input released and stopped
		lowest = minf(lowest, _d.pose.torso_pitch)
		final_pitch = _d.pose.torso_pitch
	t.ok(lowest < -0.005, "underdamped: it swings back PAST neutral (%.4f rad)" % lowest)
	t.near(final_pitch, 0.0, 1e-3, "and settles at neutral")
	_d.reset()
	_p.set_value("torso_damping", 1.2)
	_run(1.0, _k(Vector3(0, 0, -30), Vector3(0, 0, -4)))
	lowest = 9.0
	for i in 480:
		_d.update(1.0 / 120.0, _k())
		lowest = minf(lowest, _d.pose.torso_pitch)
	t.ok(lowest > -1e-6, "overdamped: returns without overshoot (%.6f)" % lowest)


func test_spring_frequency_sets_how_fast_the_torso_responds(t) -> void:
	var times := []
	for f in [1.0, 3.0, 9.0]:
		_d = Dyn.new(_p)
		_p.set_value("torso_freq", f)
		_p.set_value("torso_damping", 1.0)
		_p.set_value("lean_speed_gain", 0.0)
		var target: float = 0.008 * 20.0
		var t95 := -1.0
		for i in 600:
			_d.update(1.0 / 120.0, _k(Vector3(0, 0, -20), Vector3(0, 0, -1)))
			if t95 < 0.0 and _d.pose.torso_pitch >= 0.95 * target:
				t95 = float(i + 1) / 120.0
		times.append(t95)
	t.ok(times[0] > times[1] and times[1] > times[2] and times[2] > 0.0, "higher frequency = faster: %s s" % str(times))


func test_turning_right_leans_right_and_anticipates_the_turn(t) -> void:
	# velocity turning toward +X (the character's right) -> centripetal acceleration to the right
	var turning := _k(Vector3(12, 0, 0), Vector3(0, 0, -4), {"heading": 0.0})
	var pose := _run(0.8, turning)
	t.ok(pose.torso_roll > 0.03, "leans into a right turn (roll %.3f)" % pose.torso_roll)
	_d.reset()
	_p.set_value("fx_torso_lateral", 1.0)
	# a heading that keeps rotating clockwise (toward the right = negative rotation.y)
	var heading := 0.0
	var yaw := 0.0
	for i in 120:
		heading -= 2.0 / 120.0   # turning right at 2 rad/s
		_d.update(1.0 / 120.0, _k(Vector3(8, 0, 0), Vector3(-sin(heading), 0, -cos(heading)) * 4.0, {"heading": heading}))
		yaw = _d.pose.torso_yaw
	t.ok(yaw > 0.05, "the torso yaws ahead into a right turn (%.3f rad)" % yaw)
	_d.reset()
	heading = 0.0
	for i in 120:
		heading += 2.0 / 120.0   # and mirrored
		_d.update(1.0 / 120.0, _k(Vector3(-8, 0, 0), Vector3(-sin(heading), 0, -cos(heading)) * 4.0, {"heading": heading}))
	t.ok(_d.pose.torso_yaw < -0.05, "and into a left turn (%.3f rad)" % _d.pose.torso_yaw)


func test_anticipation_follows_the_lead_parameter(t) -> void:
	var results := []
	for lead in [0.0, 0.12, 0.3]:
		_d = Dyn.new(_p)
		_p.set_value("anticipation_lead", lead)
		var heading := 0.0
		for i in 120:
			heading -= 2.0 / 120.0
			_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(-sin(heading), 0, -cos(heading)) * 4.0, {"heading": heading}))
		results.append(_d.pose.torso_yaw)
	t.ok(results[0] < 1e-6 and results[1] < results[2] and results[1] > 0.02, "more lead = more anticipation: %s" % str(results))


# ------------------------------------------------------------------ pelvis

func test_weight_shifts_against_acceleration_and_is_bounded(t) -> void:
	var pose := _run(1.0, _k(Vector3(0, 0, -30), Vector3(0, 0, -3)))
	t.ok(pose.pelvis_shift.z > 0.005, "hips shift backward (+z) when speeding up: %.4f m" % pose.pelvis_shift.z)
	_d.reset()
	pose = _run(1.0, _k(Vector3(20, 0, 0), Vector3(0, 0, -3)))
	t.ok(pose.pelvis_shift.x < -0.003, "and outward (left) in a right turn: %.4f m" % pose.pelvis_shift.x)
	_d.reset()
	var worst := 0.0
	for i in 480:
		_d.update(1.0 / 120.0, _k(Vector3(0, 0, -100000), Vector3(0, 0, -3)))
		worst = maxf(worst, _d.pose.pelvis_shift.length())
	t.ok(worst <= _p.get_value("weight_shift_max") + 1e-6, "never beyond the configured maximum: %.4f m" % worst)


func test_gait_bob_and_sway_follow_the_phase_and_speed(t) -> void:
	var top_bob := 0.0
	var left := 0.0
	var right := 0.0
	for i in 480:
		var phase := float(i) / 120.0 * TAU * 1.5
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(0, 0, -5), {"gait_phase": phase, "gait_amount": 0.8}))
		if i > 120:
			top_bob = maxf(top_bob, _d.pose.bob)
			left = minf(left, _d.pose.sway)
			right = maxf(right, _d.pose.sway)
	t.ok(top_bob > 0.01 and top_bob <= _p.get_value("bob_height") * 0.8 + 1e-6, "bob up to %.4f m (limit %.4f)" % [top_bob, _p.get_value("bob_height") * 0.8])
	t.ok(left < -0.005 and right > 0.005, "sways to both sides (%.4f .. %.4f m)" % [left, right])
	_d.reset()
	var still := 0.0
	for i in 240:
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"gait_phase": float(i) * 0.3, "gait_amount": 0.0}))
		still = maxf(still, absf(_d.pose.sway) + _d.pose.bob)
	t.near(still, 0.0, 1e-9, "a standing character does not bob or sway even if the phase advances")
	_d.reset()
	var airborne := 0.0
	for i in 240:
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(0, 0, -5), {"gait_phase": float(i) * 0.3, "gait_amount": 1.0, "grounded": false}))
		airborne = maxf(airborne, _d.pose.bob)
	t.ok(airborne < 1e-3, "nor in the air (%.5f)" % airborne)


func test_sway_amplitude_controls(t) -> void:
	var peaks := []
	for amp in [0.0, 1.0, 2.0]:
		_d = Dyn.new(_p)
		_p.set_value("hip_sway_amp", amp)
		var peak := 0.0
		for i in 360:
			_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(0, 0, -5), {"gait_phase": float(i) / 120.0 * TAU * 1.5, "gait_amount": 1.0}))
			if i > 100:
				peak = maxf(peak, absf(_d.pose.sway))
		peaks.append(peak)
	t.near(peaks[0], 0.0, 1e-9, "0 = none")
	t.near(peaks[2] / peaks[1], 2.0, 0.05, "2 = double: %s" % str(peaks))


# ------------------------------------------------------------------ landing

func test_landing_compresses_then_rebounds_and_recovers(t) -> void:
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 8.0}))
	var deepest := 0.0
	var highest := 0.0
	var depth_tick := 0
	for i in 600:
		_d.update(1.0 / 120.0, _k())
		if _d.pose.pelvis_drop < deepest:
			deepest = _d.pose.pelvis_drop
			depth_tick = i
		highest = maxf(highest, _d.pose.pelvis_drop)
	t.ok(deepest < -0.05, "the hips drop (%.3f m)" % deepest)
	t.near(deepest, -8.0 * 0.012, 0.004, "by the configured amount: impact x gain x compression = %.3f m" % (-8.0 * 0.012))
	t.ok(highest > 0.003, "then rebound above rest (%.4f m)" % highest)
	t.near(_d.pose.pelvis_drop, 0.0, 1e-4, "and recover completely")
	t.ok(depth_tick < 40, "the deepest point comes quickly (%d ticks)" % depth_tick)


func test_compression_scales_with_impact_and_the_compression_parameter(t) -> void:
	var depths := []
	for impact in [3.0, 6.0, 12.0]:
		_d = Dyn.new(_p)
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": impact}))
		var d := 0.0
		for i in 120:
			_d.update(1.0 / 120.0, _k())
			d = minf(d, _d.pose.pelvis_drop)
		depths.append(d)
	t.near(depths[1] / depths[0], 2.0, 0.05, "double the impact, double the compression: %s" % str(depths))
	_d = Dyn.new(_p)
	_p.set_value("landing_compression", 0.0)
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 10.0}))
	var none := 0.0
	for i in 120:
		_d.update(1.0 / 120.0, _k())
		none = minf(none, _d.pose.pelvis_drop)
	t.near(none, 0.0, 1e-9, "compression 0 = no dip")


func test_the_dip_is_exact_for_any_landing_spring(t) -> void:
	for zeta in [0.1, 0.45, 0.9, 1.0, 1.5, 4.0]:
		_p.reset_all()
		_d = Dyn.new(_p)
		_p.set_value("landing_damping", zeta)
		_p.set_value("landing_rebound", 0.0)
		_d.update(1.0 / 240.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 10.0}))
		var deepest := 0.0
		for i in 600:
			_d.update(1.0 / 240.0, _k())
			deepest = minf(deepest, _d.pose.pelvis_drop)
		t.near(deepest, -0.12, 0.004, "damping %.2f: deepest %.4f m (asked for 0.12)" % [zeta, deepest])


func test_peak_factor_matches_a_simulated_impulse_response(t) -> void:
	for zeta in [0.05, 0.3, 0.7, 1.0, 2.0, 8.0]:
		var sp := Springs.Scalar.new(2.0, zeta, 0.0)
		sp.v = 1.0 * TAU * 2.0   # unit v0 / w
		var peak := 0.0
		for i in 8000:
			sp.step(0.0005)
			peak = maxf(peak, absf(sp.x))
		t.near(peak, Math.impulse_peak_factor(zeta), 2e-4, "zeta %.2f: peak %.5f vs analytic %.5f" % [zeta, peak, Math.impulse_peak_factor(zeta)])


func test_rebound_parameter_returns_energy(t) -> void:
	var highs := []
	for rebound in [0.0, 0.5, 1.5]:
		_p.reset_all()
		_d = Dyn.new(_p)
		_p.set_value("landing_rebound", rebound)
		_p.set_value("landing_damping", 0.8)
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 10.0}))
		var high := 0.0
		for i in 600:
			_d.update(1.0 / 120.0, _k())
			high = maxf(high, _d.pose.pelvis_drop)
		highs.append(high)
	t.ok(highs[0] < highs[1] and highs[1] < highs[2], "more rebound = a higher rise above rest: %s" % str(highs))


func test_compression_is_capped_and_the_landing_effect_can_be_disabled(t) -> void:
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 500.0}))
	var deepest := 0.0
	for i in 240:
		_d.update(1.0 / 120.0, _k())
		deepest = minf(deepest, _d.pose.pelvis_drop)
	t.ok(deepest >= -_p.get_value("landing_max") - 1e-9, "never deeper than landing_max (%.3f)" % deepest)
	_d = Dyn.new(_p)
	_p.set_value("fx_landing", 0.0)
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 20.0}))
	t.eq(_d.pose.pelvis_drop, 0.0, "fx_landing off")
	t.eq(_p.get_value("landing_max"), 0.2, "(the cap is a parameter, 0.2 m by default)")


func test_light_touchdowns_do_nothing(t) -> void:
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 0.5}))
	t.eq(_d.pose.pelvis_drop, 0.0, "a step down is not a landing")


# ------------------------------------------------------------------ head, shoulders, arms

func test_head_stays_level_against_the_torso_lean(t) -> void:
	_p.set_value("head_stabilization", 1.0)
	var pose := _run(1.5, _k(Vector3(0, 0, -25), Vector3(0, 0, -3)))
	t.ok(pose.torso_pitch > 0.05, "torso leaning %.3f" % pose.torso_pitch)
	t.near(pose.head_pitch, -pose.torso_pitch, 0.003, "full stabilisation: head counter-rotates exactly (%.4f vs %.4f)" % [pose.head_pitch, -pose.torso_pitch])
	_d.reset()
	_p.set_value("head_stabilization", 0.0)
	pose = _run(1.5, _k(Vector3(0, 0, -25), Vector3(0, 0, -3)))
	t.near(pose.head_pitch, 0.0, 1e-6, "none: the head just rides the torso")
	_d.reset()
	_p.set_value("head_stabilization", 0.5)
	pose = _run(1.5, _k(Vector3(0, 0, -25), Vector3(0, 0, -3)))
	t.near(pose.head_pitch, -0.5 * pose.torso_pitch, 0.003, "partial: half")


func test_head_leads_turns_and_lags_through_its_spring(t) -> void:
	var heading := 0.0
	var early := 0.0
	var late := 0.0
	for i in 90:
		heading -= 2.5 / 120.0 * 3.0 / 3.0
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(-sin(heading), 0, -cos(heading)) * 4.0, {"heading": heading}))
		if i == 5:
			early = _d.pose.head_yaw
		late = _d.pose.head_yaw
	t.ok(late > early + 0.01, "the head yaw builds up through its spring rather than snapping (%.4f then %.4f)" % [early, late])
	t.ok(late <= deg_to_rad(_p.get_value("head_max_yaw_deg")) + 1e-9, "and respects its limit")


func test_shoulders_counter_rotate_the_pelvis(t) -> void:
	var worst_same := 0
	for i in 240:
		var phase := float(i) / 120.0 * TAU * 1.5
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(0, 0, -5), {"gait_phase": phase, "gait_amount": 1.0}))
		if absf(_d.pose.pelvis_twist) > 0.02 and signf(_d.pose.pelvis_twist) == signf(_d.pose.shoulder_twist):
			worst_same += 1
	t.eq(worst_same, 0, "shoulders always twist against the pelvis")
	_d.reset()
	_p.set_value("shoulder_counter_amp", 0.0)
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(0, 0, -5), {"gait_phase": 1.2, "gait_amount": 1.0}))
	t.eq(_d.pose.shoulder_twist, 0.0, "amplitude 0 = none")


func test_arms_lag_and_overshoot_sudden_changes(t) -> void:
	var swing_back := 0.0
	var swing_forward := 0.0
	for i in 60:
		_d.update(1.0 / 120.0, _k(Vector3(0, 0, -30), Vector3(0, 0, -3)))
		swing_back = minf(swing_back, _d.pose.arm_pitch_l)
	for i in 240:
		_d.update(1.0 / 120.0, _k())
		swing_forward = maxf(swing_forward, _d.pose.arm_pitch_l)
	t.ok(swing_back < -0.02, "arms trail behind when speeding up (%.3f rad)" % swing_back)
	t.ok(swing_forward > 0.003, "and swing forward past neutral when it stops (%.4f rad)" % swing_forward)
	t.near(_d.pose.arm_pitch_l, 0.0, 1e-3, "then settle")
	_d.reset()
	var heading := 0.0
	var out_l := 0.0
	var out_r := 0.0
	for i in 60:
		heading -= 3.0 / 120.0
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(-sin(heading), 0, -cos(heading)) * 4.0, {"heading": heading}))
		out_l = maxf(out_l, _d.pose.arm_roll_l)
		out_r = minf(out_r, _d.pose.arm_roll_r)
	t.ok(out_l > 0.02 and out_r < -0.02, "turning right: the outer (left) arm swings out, the inner one in (%.3f / %.3f)" % [out_l, out_r])


func test_follow_through_amplitude_scales_arm_motion(t) -> void:
	var peaks := []
	for amount in [0.0, 1.0, 2.0]:
		_d = Dyn.new(_p)
		_p.set_value("follow_through", amount)
		var worst := 0.0
		for i in 60:
			_d.update(1.0 / 120.0, _k(Vector3(0, 0, -30), Vector3(0, 0, -3)))
			worst = minf(worst, _d.pose.arm_pitch_l)
		peaks.append(worst)
	t.near(peaks[0], 0.0, 1e-9, "0 = none")
	t.ok(peaks[2] < peaks[1] and peaks[1] < -0.01, "more follow-through = more motion: %s" % str(peaks))


func test_arm_swing_amplitude_is_passed_through(t) -> void:
	_p.set_value("arm_swing_amp", 1.6)
	_d.update(1.0 / 120.0, _k())
	t.eq(_d.pose.arm_scale, 1.6, "the visual multiplies its gait arm swing by this")


# ------------------------------------------------------------------ rotation lag

func test_the_body_turns_toward_its_heading_through_a_spring(t) -> void:
	_d.reset(0.0)
	var yaws := []
	for i in 240:
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(-4, 0, 0), {"heading": deg_to_rad(90.0)}))
		yaws.append(_d.pose.facing_yaw)
	t.ok(yaws[3] < deg_to_rad(90.0) * 0.5, "not instant: %.1f degrees after 4 ticks" % rad_to_deg(yaws[3]))
	t.near(yaws[239], deg_to_rad(90.0), 0.01, "arrives at the heading")


func test_rotation_lag_slows_turning(t) -> void:
	var settle := []
	for lag in [0.5, 1.0, 3.0]:
		_d = Dyn.new(_p)
		_p.set_value("rotation_lag", lag)
		_p.set_value("rotation_damping", 1.0)
		_d.reset(0.0)
		var t90 := -1.0
		for i in 720:
			_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(-4, 0, 0), {"heading": deg_to_rad(90.0)}))
			if t90 < 0.0 and _d.pose.facing_yaw >= deg_to_rad(90.0) * 0.9:
				t90 = float(i + 1) / 120.0
		settle.append(t90)
	t.ok(settle[0] < settle[1] and settle[1] < settle[2] and settle[0] > 0.0, "more lag = slower to face the new heading: %s s" % str(settle))


func test_facing_takes_the_short_way_across_the_wrap(t) -> void:
	_d.reset(deg_to_rad(170.0))
	var widest := 0.0
	var prev: float = _d.pose.facing_yaw
	for i in 240:
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(0, 0, 4), {"heading": deg_to_rad(-170.0)}))
		widest = maxf(widest, absf(_d.pose.facing_yaw - prev))
		prev = _d.pose.facing_yaw
	t.ok(widest < deg_to_rad(5.0), "170 -> -170 degrees is a 20 degree turn, never a 340 degree sweep (largest tick %.2f deg)" % rad_to_deg(widest))
	t.near(angle_difference(_d.pose.facing_yaw, deg_to_rad(-170.0)), 0.0, 0.01, "and it lands on the heading")


func test_facing_holds_when_standing_and_without_lag_it_still_turns(t) -> void:
	_d.reset(1.0)
	_run(1.0, _k())
	t.near(_d.pose.facing_yaw, 1.0, 1e-6, "a standing character keeps its facing")
	_p.set_value("fx_facing_lag", 0.0)
	_d.reset(0.0)
	var yaw := 0.0
	for i in 120:
		_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3(-4, 0, 0), {"heading": deg_to_rad(90.0)}))
		yaw = _d.pose.facing_yaw
	t.near(yaw, deg_to_rad(90.0), 0.02, "with the lag effect off the body still faces its heading (a fast damper)")


# ------------------------------------------------------------------ reset, robustness, rate independence

func test_teleport_clears_all_motion(t) -> void:
	_run(1.0, _k(Vector3(10, 0, -30), Vector3(0, 0, -5), {"gait_phase": 1.0, "gait_amount": 1.0}))
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 9.0}))
	_d.update(1.0 / 120.0, _k(Vector3.ZERO, Vector3.ZERO, {"teleported": true}))
	var pose: Dictionary = _d.pose
	for key in ["torso_pitch", "torso_roll", "pelvis_drop", "head_pitch", "arm_pitch_l", "arm_roll_r", "bob", "sway"]:
		t.near(pose[key], 0.0, 1e-9, "%s cleared" % key)
	t.near(pose.pelvis_shift.length(), 0.0, 1e-9, "weight shift cleared")


func test_extreme_and_bad_input_never_breaks_the_pose(t) -> void:
	for k in [
		_k(Vector3(1e9, 0, -1e9), Vector3(1e6, 0, 1e6)), _k(Vector3(NAN, 0, 0), Vector3(0, 0, -3)),
		_k(Vector3.ZERO, Vector3(INF, 0, 0)), _k(Vector3.ZERO, Vector3.ZERO, {"landed_impact": 1e9}),
		_k(Vector3(0, 0, -5), Vector3(0, 0, -5), {"gait_phase": 1e12, "gait_amount": 50.0}),
	]:
		_d = Dyn.new(_p)
		for i in 240:
			_d.update(1.0 / 120.0, k)
		var finite := true
		for key in _d.pose:
			var v: Variant = _d.pose[key]
			if v is float and (is_nan(v) or is_inf(v)):
				finite = false
			elif v is Vector3 and not Math.is_finite_v3(v):
				finite = false
		if not finite:
			# a NaN acceleration is bad input; the model must recover once input is sane again
			for i in 240:
				_d.update(1.0 / 120.0, _k())
			finite = true
			for key in _d.pose:
				var v2: Variant = _d.pose[key]
				if v2 is float and (is_nan(v2) or is_inf(v2)):
					finite = false
		t.ok(finite, "finite after %s" % str(k.accel))


func test_zero_and_huge_timesteps(t) -> void:
	var before: Dictionary = _d.update(1.0 / 120.0, _k(Vector3(0, 0, -20), Vector3(0, 0, -3)))
	var same: Dictionary = _d.update(0.0, _k(Vector3(0, 0, -20), Vector3(0, 0, -3)))
	t.eq(same.torso_pitch, before.torso_pitch, "dt = 0 changes nothing")
	_d.update(5.0, _k(Vector3(0, 0, -20), Vector3(0, 0, -3)))
	t.ok(is_finite(_d.pose.torso_pitch) and absf(_d.pose.torso_pitch) <= Dyn.TORSO_PITCH_HARD, "a 5 second hitch is clamped and harmless")


func test_the_pose_does_not_depend_on_the_frame_rate(t) -> void:
	var results := []
	for hz in [30.0, 60.0, 120.0, 240.0]:
		_p.reset_all()
		_d = Dyn.new(_p)
		for i in int(1.5 * hz):
			var time: float = float(i) / hz
			var accel := Vector3(0, 0, -25.0 if time < 0.5 else 0.0)
			var vel := Vector3(0, 0, -minf(time, 0.5) * 8.0)
			_d.update(1.0 / hz, _k(accel, vel, {"landed_impact": 6.0 if i == int(1.0 * hz) else 0.0}))
		results.append([_d.pose.torso_pitch, _d.pose.pelvis_drop, _d.pose.arm_pitch_l])
	for i in range(1, results.size()):
		for j in 3:
			t.near(results[i][j], results[0][j], 0.01, "rate %d component %d: %.5f vs %.5f" % [i, j, results[i][j], results[0][j]])


func test_cost_per_update_is_small(t) -> void:
	var k := _k(Vector3(3, 0, -10), Vector3(0, 0, -5), {"gait_phase": 0.0, "gait_amount": 0.8})
	var t0 := Time.get_ticks_usec()
	for i in 20000:
		k.gait_phase = float(i) * 0.05
		_d.update(1.0 / 144.0, k)
	var per := float(Time.get_ticks_usec() - t0) / 20000.0
	t.ok(per < 80.0, "full body update %.1f us (budget: well under the 6900 us frame)" % per)
