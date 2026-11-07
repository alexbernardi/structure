extends RefCounted

const GaitParams = preload("res://animation/gait_params.gd")
const GaitModel = preload("res://animation/gait_model.gd")

var _p
var _m


func before_each() -> void:
	_p = GaitParams.create()
	_m = GaitModel.new(_p)


func after_each() -> void:
	_m = null
	_p = null


func _prime(speed: float) -> Dictionary:
	_m.cycle = _m.cycle_for(speed)
	return _m.cycle


## Every parameter somewhere in its legal range, switches random (the master stays on, the cycle is not frozen).
func _randomise(rng: RandomNumberGenerator) -> void:
	for d in _p.definitions():
		if d.id == "freeze" or d.id == "gait_model":
			continue
		if d.get("type", "") == "bool":
			_p.set_value(d.id, float(rng.randi_range(0, 1)))
		else:
			_p.set_value(d.id, lerpf(d.min, d.max, rng.randf()))


func _sole_corners(a: Vector3) -> Array[Vector2]:
	var h := GaitModel._rot(GaitModel.HEEL, a.z)
	var f := GaitModel._rot(GaitModel.TOE, a.z)
	return [Vector2(a.x + h.x, a.y + h.y), Vector2(a.x + f.x, a.y + f.y)]


# ------------------------------------------------------------------ cycle numbers

func test_cycle_numbers_at_the_defaults(t) -> void:
	var c := _prime(1.2)
	var expected_step := 0.68 * pow(1.2 / 1.4, 0.42)
	t.near(c.step_len, expected_step, 1e-9, "step length grows with speed^0.42")
	t.near(c.stride, 2.0 * expected_step, 1e-9, "stride = two steps")
	t.near(c.rate * c.stride, 1.2, 1e-9, "cycles per second x stride = the walking speed")
	t.near(120.0 * c.rate, 60.0 * 1.2 / expected_step, 1e-9, "cadence in steps per minute")
	t.ok(120.0 * c.rate > 100.0 and 120.0 * c.rate < 125.0, "a human cadence at an easy walk: %.0f steps/min" % (120.0 * c.rate))
	_p.set_value("auto_step_length", 0.0)
	t.near(_prime(2.0).step_len, 0.68, 1e-9, "fixed step length when auto is off")
	t.near(_prime(2.0).rate * 2.0 * 0.68, 2.0, 1e-9, "and the cadence takes up the speed")


# ------------------------------------------------------------------ feet behave like feet

func test_planted_foot_is_fixed_to_the_ground_at_every_setting(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	var worst_height := 0.0
	var checked := 0
	for trial in 40:
		_randomise(rng)
		var v := rng.randf_range(0.2, 3.0)
		var c := _prime(v)
		var bounds: Array[float] = [0.0, c.d]
		if c.roll:
			bounds = [0.0, c.q1, c.q2, c.d]
		for k in bounds.size() - 1:
			var lo := bounds[k] + 1e-3
			var hi := bounds[k + 1] - 2.5e-3
			if hi - lo < 4e-3:
				continue
			for i in 6:
				var q := lerpf(lo, hi, float(i) / 5.0)
				var dq := 1e-3   # positions are single precision: a wider step keeps the rounding out of the slope
				# the contact corner: the heel until the heel rises, then the toe
				var use_toe: bool = c.roll and q >= c.q2
				var a := _sole_corners(_m.stance(q, c))
				var b := _sole_corners(_m.stance(q + dq, c))
				var idx := 1 if use_toe else 0
				worst_height = maxf(worst_height, absf(a[idx].y))
				# in the pelvis frame the planted point must move back by exactly the pelvis' advance: stride per cycle
				worst = maxf(worst, absf((b[idx].x - a[idx].x) / dq + c.stride))
				checked += 1
	t.ok(checked > 300, "%d samples" % checked)
	t.ok(worst < 1e-3, "the planted point's speed relative to the hips = -(walking speed) in cycle units; worst error %s" % worst)
	t.ok(worst_height < 1e-6, "and it stays exactly on the ground: worst height %s m" % worst_height)


func test_no_part_of_the_sole_goes_below_the_ground(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lowest := 1.0
	for trial in 60:
		_randomise(rng)
		var c := _prime(rng.randf_range(0.0, 3.5))
		for i in 200:
			var a: Vector3 = _m.ankle_at(float(i) / 200.0, c)
			for pt in _sole_corners(a):
				lowest = minf(lowest, pt.y)
	t.ok(lowest > -1e-6, "lowest sole point over 60 random settings x 200 phases: %s m" % lowest)


func test_the_flat_foot_phase_is_flat_on_the_ground(t) -> void:
	var c := _prime(1.2)
	var q: float = (c.q1 + c.q2) * 0.5
	var a: Vector3 = _m.stance(q, c)
	t.near(a.z, 0.0, 1e-9, "no pitch")
	t.near(a.y, GaitModel.ANKLE_H, 1e-6, "ankle at its standing height")
	var corners := _sole_corners(a)
	t.near(corners[0].y, 0.0, 1e-6, "heel down")
	t.near(corners[1].y, 0.0, 1e-6, "toe down")


func test_heel_strike_is_toe_up_and_toe_off_is_toe_down(t) -> void:
	var c := _prime(1.2)
	t.near(rad_to_deg(_m.stance(0.0, c).z), 18.0, 1e-4, "heel strike angle from the parameter")
	t.near(rad_to_deg(_m.stance(c.d, c).z), -30.0, 1e-4, "toe-off angle from the parameter")
	_p.set_value("foot_roll", 0.0)
	c = _prime(1.2)
	for q in [0.0, 0.2, 0.4, 0.55, 0.8, 0.95]:
		t.near(_m.ankle_at(q, c).z, 0.0, 1e-12, "no roll: the foot stays flat at q=%.2f" % q)


func test_the_swing_path_has_no_jump_at_toe_off_or_heel_strike_at_any_setting(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var worst := 0.0
	for trial in 40:
		_randomise(rng)
		var c := _prime(rng.randf_range(0.3, 3.0))
		worst = maxf(worst, (_m.stance(c.d, c) - _m.swing(c.d, c)).length())
		worst = maxf(worst, (_m.swing(1.0, c) - _m.stance(0.0, c)).length())
	t.ok(worst < 1e-5, "the swing starts exactly at the toe-off pose and ends exactly at the next heel strike: worst gap %s m" % worst)


func test_the_swing_leaves_and_lands_moving_like_the_stance_foot(t) -> void:
	var worst := 0.0
	for speed in [0.5, 0.9, 1.2, 1.6, 2.0, 2.5]:
		_p.reset_all()
		_p.set_value("step_height", 0.0)
		_p.set_value("toe_clearance_angle", 0.0)
		var c := _prime(speed)
		var h := 5e-4   # single-precision positions: keep the rounding out of the slopes
		for boundary in [c.d, 1.0]:
			var v1: Vector3 = (_m.ankle_at(boundary - h, c) - _m.ankle_at(boundary - 2.0 * h, c)) / h
			var v2: Vector3 = (_m.ankle_at(fposmod(boundary + 2.0 * h, 1.0), c) - _m.ankle_at(fposmod(boundary + h, 1.0), c)) / h
			worst = maxf(worst, Vector2(v2.x - v1.x, v2.y - v1.y).length() / c.stride)
	t.ok(worst < 0.03, "the ankle's velocity does not change across the hand-over (forward and up): worst %.4f of a stride per cycle" % worst)

func test_velocity_match_zero_stops_the_foot_at_both_ends(t) -> void:
	_p.set_value("velocity_match", 0.0)
	_p.set_value("step_height", 0.0)
	_p.set_value("toe_clearance_angle", 0.0)
	var c := _prime(1.4)
	var h := 1e-4
	var v_start: float = ((_m.ankle_at(c.d + 2.0 * h, c) - _m.ankle_at(c.d + h, c)) / h).length()
	var v_stance: float = ((_m.ankle_at(c.d - h, c) - _m.ankle_at(c.d - 2.0 * h, c)) / h).length()
	t.ok(v_start < 0.2 * v_stance, "the swing starts almost at rest (%.3f vs the stance foot's %.3f)" % [v_start, v_stance])


func test_foot_clearance_follows_the_parameter(t) -> void:
	var mid := []
	for hgt in [0.0, 0.07, 0.15]:
		_p.set_value("step_height", hgt)
		var c := _prime(1.2)
		mid.append(_m.swing(c.d + 0.5 * (1.0 - c.d), c).y)
	t.near(mid[1] - mid[0], 0.07, 1e-5, "0.07 m of clearance lifts the mid-swing ankle by 0.07 m")
	t.near(mid[2] - mid[0], 0.15, 1e-5, "0.15 m lifts it by 0.15 m")
	_p.set_value("step_height", 0.07)
	var c2 := _prime(0.0)
	t.near(_m.swing(c2.d + 0.5 * (1.0 - c2.d), c2).y, GaitModel.ANKLE_H, 1e-6, "no lift while standing: the foot never steps in place")

func test_the_peak_timing_moves_the_highest_point(t) -> void:
	var peaks := []
	for timing in [0.35, 0.5, 0.65]:
		_p.set_value("swing_peak", timing)
		var c := _prime(1.2)
		var best_q := 0.0
		var best := -1.0
		for i in 600:
			var s := float(i) / 600.0
			var bump: float = _m.swing_bump(s, c)
			if bump > best:
				best = bump
				best_q = s
		peaks.append(best_q)
	t.near(peaks[0], 0.35, 0.01, "early peak")
	t.near(peaks[1], 0.5, 0.01, "centred peak")
	t.near(peaks[2], 0.65, 0.01, "late peak")


# ------------------------------------------------------------------ legs

func test_the_legs_put_every_ankle_where_it_was_planned(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var worst := 0.0
	var checked := 0
	var unreachable := 0
	for trial in 40:
		_randomise(rng)
		var c := _prime(rng.randf_range(0.0, 2.6))
		for i in 40:
			var pose: Dictionary = _m.pose_at(float(i) / 40.0)
			for side in 2:
				var sx := -1.0 if side == 0 else 1.0
				var off: Vector3 = pose.pelvis_q * Vector3(sx * GaitModel.HIP_X, -GaitModel.HIP_DROP, 0.0)
				var hip_f := -off.z
				var hip_y: float = pose.pelvis.y + off.y
				var planned: Vector3 = pose.ankle_l if side == 0 else pose.ankle_r
				var thigh: float = pose.thigh_l if side == 0 else pose.thigh_r
				var knee: float = pose.knee_l if side == 0 else pose.knee_r
				var reach := GaitModel.leg_reach(thigh, knee)
				if Vector2(planned.x - hip_f, planned.y - hip_y).length() > (GaitModel.THIGH + GaitModel.SHIN) * 0.999:
					unreachable += 1
					continue
				worst = maxf(worst, Vector2(hip_f + reach.x - planned.x, hip_y + reach.y - planned.y).length())
				checked += 1
	t.ok(checked > 2000, "%d legs checked (%d out of reach)" % [checked, unreachable])
	t.ok(worst < 1e-5, "forward kinematics of the solved legs reproduces the planned ankle; worst error %s m" % worst)


func test_knees_only_bend_backwards(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var lowest := 9.0
	for trial in 30:
		_randomise(rng)
		_prime(rng.randf_range(0.0, 3.0))
		for i in 80:
			var pose: Dictionary = _m.pose_at(float(i) / 80.0)
			lowest = minf(lowest, minf(pose.knee_l, pose.knee_r))
	t.ok(lowest > -1e-9, "knee flexion is never negative: %s" % lowest)


func test_the_hips_come_down_instead_of_lifting_a_planted_foot(t) -> void:
	_p.set_value("step_length", 1.0)
	_p.set_value("stand_height", 1.0)
	_p.set_value("pelvis_bob", 0.08)
	var c := _prime(2.4)
	var assisted := 0.0
	var worst := 0.0
	for i in 200:
		var pose: Dictionary = _m.pose_at(float(i) / 200.0)
		assisted = maxf(assisted, pose.reach_assist)
		t.ok(pose.pelvis.y <= pose.y_target + 1e-9, "never above the requested height")
		worst = maxf(worst, absf(pose.y_target - pose.pelvis.y - pose.reach_assist))
		if pose.contact_l and pose.stance_l > 0.2 and pose.stance_l < 0.8:
			var reach := GaitModel.leg_reach(pose.thigh_l, pose.knee_l)
			var off: Vector3 = pose.pelvis_q * Vector3(-GaitModel.HIP_X, -GaitModel.HIP_DROP, 0.0)
			worst = maxf(worst, absf(-off.z + reach.x - pose.ankle_l.x) - 1e-3)
	t.ok(assisted > 0.03, "an oversized stride needs the hips lowered: %.3f m" % assisted)
	t.ok(worst < 1e-3, "and the reported assist is exactly the lowering, planted feet stay planted: %s" % worst)


func test_the_defaults_lower_the_hips_by_a_small_constant_amount(t) -> void:
	for speed in [0.8, 1.0, 1.2, 1.4]:
		_prime(speed)
		var lo := 9.0
		var hi := -9.0
		for i in 200:
			var a: float = _m.pose_at(float(i) / 200.0).reach_assist
			lo = minf(lo, a)
			hi = maxf(hi, a)
		t.ok(hi < 0.04, "%.1f m/s: the hips are lowered by at most %.1f mm so no knee has to lock" % [speed, 1000.0 * hi])
		t.ok(hi - lo < 0.004, "%.1f m/s: and by the same amount all through the cycle (spread %.1f mm), so the hip path stays a sine" % [speed, 1000.0 * (hi - lo)])


func _sine_fit(ys: Array) -> Dictionary:
	var n := ys.size()
	var c := 0.0
	var a := 0.0
	var b := 0.0
	for i in n:
		var q := float(i) / n
		c += ys[i]
		a += ys[i] * cos(4.0 * PI * q)
		b += ys[i] * sin(4.0 * PI * q)
	c /= n
	a *= 2.0 / n
	b *= 2.0 / n
	var rss := 0.0
	for i in n:
		var q := float(i) / n
		var e: float = ys[i] - (c + a * cos(4.0 * PI * q) + b * sin(4.0 * PI * q))
		rss += e * e
	var amp := sqrt(a * a + b * b)
	return {"amp": amp, "ratio": sqrt(rss / n) / maxf(amp, 1e-9)}


func test_the_hip_path_is_a_clean_sine_at_twice_the_stride_frequency(t) -> void:
	for speed in [0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 2.0]:
		_prime(speed)
		var ys := []
		for i in 400:
			ys.append(_m.pose_at(float(i) / 400.0).pelvis.y)
		var fit := _sine_fit(ys)
		t.ok(fit.ratio < 0.03, "%.1f m/s: the hip height is within %.1f %% of a pure sine (amplitude %.1f mm)" % [speed, 100.0 * fit.ratio, 1000.0 * fit.amp])
	_p.set_value("loading_dip", 0.02)
	_prime(1.2)
	var dipped := []
	for i in 400:
		dipped.append(_m.pose_at(float(i) / 400.0).pelvis.y)
	t.ok(_sine_fit(dipped).ratio > 0.05, "(the loading dip, off by default, is what makes it less of a sine)")


func test_the_knee_is_never_straighter_than_its_setting(t) -> void:
	for flex in [6.0, 12.0, 20.0]:
		_p.set_value("knee_min_flex", flex)
		for speed in [0.9, 1.4, 2.2]:
			_prime(speed)
			var lowest := 99.0
			for i in 300:
				var pose: Dictionary = _m.pose_at(float(i) / 300.0)
				lowest = minf(lowest, rad_to_deg(minf(pose.knee_l, pose.knee_r)))
			t.ok(lowest > flex - 0.6, "knee limit %.0f deg at %.1f m/s: least flexion seen %.1f deg" % [flex, speed, lowest])


## Ankle acceleration (forward, up) per cycle^2 by a centred second difference.
func _ankle_acc(c: Dictionary, q: float, h: float) -> Vector2:
	var a: Vector3 = _m.ankle_at(fposmod(q - h, 1.0), c) - 2.0 * _m.ankle_at(fposmod(q, 1.0), c) + _m.ankle_at(fposmod(q + h, 1.0), c)
	return Vector2(a.x, a.y) / (h * h)


func test_acceleration_is_continuous_where_the_swing_hands_over_to_the_stance(t) -> void:
	var worst := 0.0
	var h := 2e-3
	for speed in [0.8, 1.2, 1.6]:
		var c := _prime(speed)
		for boundary in [c.d, 1.0]:
			var b: float = boundary
			# extrapolate the acceleration to the boundary from each side with a straight line through two samples
			var b1 := _ankle_acc(c, b - 0.012, h)
			var b2 := _ankle_acc(c, b - 0.008, h)
			var a1 := _ankle_acc(c, b + 0.008, h)
			var a2 := _ankle_acc(c, b + 0.012, h)
			var from_before := b2 + (b2 - b1) / 0.004 * 0.008
			var from_after := a1 - (a2 - a1) / 0.004 * 0.008
			worst = maxf(worst, (from_before - from_after).length() / c.stride)
	t.ok(worst < 8.0, "the ankle's acceleration, extrapolated to toe-off and heel strike from both sides, differs by at most %.1f stride-lengths per cycle squared (a jolt would be 10s)" % worst)

func test_the_hip_path_has_the_requested_bob(t) -> void:
	_p.set_value("loading_dip", 0.0)
	_p.set_value("pelvis_bob", 0.02)
	_prime(0.9)
	var lo := 9.0
	var hi := -9.0
	for i in 400:
		var y: float = _m.pose_at(float(i) / 400.0).y_target
		lo = minf(lo, y)
		hi = maxf(hi, y)
	t.near(hi - lo, 0.02 * GaitModel._smooth(0.9 / 0.5), 1e-6, "range of the requested hip height equals the bob (scaled in only above a standstill)")
	var peak: Dictionary = _m.pose_at(0.25)
	var low: Dictionary = _m.pose_at(0.0)
	t.ok(peak.y_target > low.y_target, "highest over the stance leg (quarter cycle), lowest at double support")


# ------------------------------------------------------------------ gait structure

func test_double_support_matches_the_stance_fraction(t) -> void:
	for duty in [0.5, 0.56, 0.6, 0.7]:
		_p.set_value("duty_factor", duty)
		_prime(1.3)
		var both := 0
		var neither := 0
		var n := 2000
		for i in n:
			var pose: Dictionary = _m.pose_at((float(i) + 0.5) / n)
			if pose.contact_l and pose.contact_r:
				both += 1
			if not pose.contact_l and not pose.contact_r:
				neither += 1
		t.near(float(both) / n, maxf(2.0 * duty - 1.0, 0.0), 2.0 / n + 1e-3, "double support at stance %.2f" % duty)
		t.eq(neither, 0, "a foot is always down in walking (stance %.2f)" % duty)


func test_the_right_leg_is_the_left_leg_half_a_cycle_later(t) -> void:
	for fx in ["fx_pelvis_rotation", "fx_pelvic_tilt", "fx_pelvis_sway"]:
		_p.set_value(fx, 0.0)
	_prime(1.4)
	var worst := 0.0
	for i in 100:
		var q := float(i) / 100.0
		var a: Dictionary = _m.pose_at(q)
		var b: Dictionary = _m.pose_at(fposmod(q + 0.5, 1.0))
		worst = maxf(worst, absf(a.thigh_l - b.thigh_r) + absf(a.knee_l - b.knee_r) + absf(a.foot_l - b.foot_r) + absf(a.arm_l - b.arm_r) + absf(a.elbow_l - b.elbow_r))
	t.ok(worst < 1e-5, "left and right are the same motion half a cycle apart: %s" % worst)


func test_arms_swing_against_the_legs(t) -> void:
	_prime(1.4)
	var p0: Dictionary = _m.pose_at(0.0)
	t.ok(p0.thigh_l > p0.thigh_r, "left leg forward at left heel strike")
	t.ok(p0.arm_l < 0.0 and p0.arm_r > 0.0, "so the left arm is back and the right arm forward")
	t.near(p0.arm_r, deg_to_rad(24.0) * p0.gait_amount, 1e-9, "amplitude from the parameter")
	_p.set_value("arm_phase", 30.0)
	var late: Dictionary = _m.pose_at(0.0)
	t.ok(absf(late.arm_r - p0.arm_r) > 0.05, "the timing offset shifts the swing")


func test_pelvis_and_shoulders_turn_against_each_other(t) -> void:
	_prime(1.4)
	var pose: Dictionary = _m.pose_at(0.0)
	t.ok(pose.pelvis_yaw < 0.0, "pelvis turned so the left (forward) hip leads")
	t.ok(pose.chest_yaw > 0.0, "shoulders turned the other way")
	t.near(rad_to_deg(pose.pelvis_yaw), -5.0 * pose.gait_amount, 1e-6, "amplitudes from the parameters")
	var mid: Dictionary = _m.pose_at(0.25)
	t.ok(mid.pelvis.x < 0.0, "hips shifted toward the left stance foot at left mid stance")
	t.ok(mid.pelvis_tilt < 0.0, "and the right (swing) hip dropped: tilt about +Z negative")
	var right_hip_y: float = (mid.pelvis_q * Vector3(0.1, 0, 0)).y
	var left_hip_y: float = (mid.pelvis_q * Vector3(-0.1, 0, 0)).y
	t.ok(right_hip_y < left_hip_y, "right hip is lower: %.4f vs %.4f" % [right_hip_y, left_hip_y])


func test_every_switch_removes_exactly_its_own_effect(t) -> void:
	_prime(1.4)
	var base: Dictionary = _m.pose_at(0.2)
	t.ok(absf(base.pelvis.x) > 1e-4 and absf(base.pelvis_yaw) > 1e-4 and absf(base.pelvis_tilt) > 1e-4, "everything on: the pelvis moves")
	var cases := {
		"fx_pelvis_sway": func(p: Dictionary) -> bool: return p.pelvis.x == 0.0,
		"fx_pelvis_rotation": func(p: Dictionary) -> bool: return p.pelvis_yaw == 0.0,
		"fx_pelvic_tilt": func(p: Dictionary) -> bool: return p.pelvis_tilt == 0.0,
		"fx_shoulder_counter": func(p: Dictionary) -> bool: return p.chest_yaw == 0.0,
		"fx_arm_swing": func(p: Dictionary) -> bool: return p.arm_l == 0.0 and p.arm_r == 0.0,
		"fx_elbow_bend": func(p: Dictionary) -> bool: return p.elbow_l == 0.0 and p.elbow_r == 0.0,
	}
	for fx in cases:
		_p.set_value(fx, 0.0)
		var after: Dictionary = _m.pose_at(0.2)
		t.ok(cases[fx].call(after), "%s off zeroes its effect" % fx)
		_p.set_value(fx, 1.0)
	var y_on: float = _m.pose_at(0.25).y_target
	_p.set_value("fx_pelvis_bob", 0.0)
	_p.set_value("fx_loading_dip", 0.0)
	var flat := []
	for i in 50:
		flat.append(_m.pose_at(float(i) / 50.0).y_target)
	t.ok(flat.max() - flat.min() < 1e-12, "bob and dip off: the requested hip height is constant")
	t.ok(y_on > flat[0], "(and it was moving before)")
	_p.set_value("gait_model", 0.0)
	_m.update(0.01, 1.4)
	t.ok(not _m.pose.active, "the master switch gives an inactive pose")


func test_standing_still_is_calm(t) -> void:
	_prime(0.0)
	for i in 50:
		var pose: Dictionary = _m.pose_at(float(i) / 50.0)
		t.near(pose.ankle_l.x, 0.0, 1e-9, "feet under the hips")
		t.near(pose.ankle_l.z, 0.0, 1e-12, "feet flat")
		t.near(pose.pelvis.x, 0.0, 1e-12, "no sway")
		t.near(pose.pelvis_yaw, 0.0, 1e-12, "no rotation")
		t.near(pose.arm_l, 0.0, 1e-12, "arms still")
		t.near(pose.pelvis.y, pose.y_target, 1e-3, "hips at standing height")


# ------------------------------------------------------------------ time

func test_phase_advances_at_the_cadence_and_scales_with_time(t) -> void:
	var rate: float = _prime(1.2).rate
	_m.phase = 0.0
	for i in 120:
		_m.update(1.0 / 120.0, 1.2)
	t.near(_m.phase, fposmod(rate, 1.0), 1e-9, "one second moves the phase by the cadence in cycles")
	_m.phase = 0.0
	_p.set_value("time_scale", 0.5)
	for i in 120:
		_m.update(1.0 / 120.0, 1.2)
	t.near(_m.phase, fposmod(rate * 0.5, 1.0), 1e-9, "half-speed playback")


func test_freeze_holds_the_scrub_position_and_resumes_from_it(t) -> void:
	_p.set_value("freeze", 1.0)
	_p.set_value("scrub", 0.37)
	for i in 30:
		_m.update(0.05, 1.4)
	t.near(_m.phase, 0.37, 1e-12, "held at the scrub position however long it runs")
	var frozen: Dictionary = _m.pose
	_m.update(0.05, 1.4)
	t.eq(_m.pose.thigh_l, frozen.thigh_l, "the pose does not change either")
	_p.set_value("freeze", 0.0)
	_m.update(0.1, 1.4)
	t.ok(_m.phase > 0.37 and _m.phase < 0.37 + 0.2, "unfreezing continues from where it stopped: %.3f" % _m.phase)


func _worst_tick(speed_at: Callable, seconds: float) -> float:
	var m = GaitModel.new(_p)
	var prev: Dictionary = {}
	var worst := 0.0
	var dt := 1.0 / 120.0
	for i in int(seconds / dt):
		var pose: Dictionary = m.update(dt, speed_at.call(float(i) * dt))
		if not prev.is_empty():
			for k in ["thigh_l", "knee_l", "thigh_r", "knee_r", "foot_l", "foot_r"]:
				worst = maxf(worst, absf(pose[k] - prev[k]))
			worst = maxf(worst, absf(pose.pelvis.y - prev.pelvis.y) * 10.0)
		prev = pose
	return worst


func test_no_pops_when_the_speed_changes_smoothly(t) -> void:
	var steady: float = _worst_tick(func(_s: float) -> float: return 2.4, 3.0)
	var sweep: float = _worst_tick(func(s: float) -> float: return maxf(1.2 + 1.2 * sin(s * 1.4), 0.0), 6.0)
	t.ok(sweep < steady * 1.25, "sweeping 0..2.4 m/s changes no joint faster per tick than steady walking at 2.4 m/s does: %.3f vs %.3f rad" % [sweep, steady])
	t.ok(_worst_tick(func(_s: float) -> float: return 1.2, 3.0) < 0.08, "and an ordinary walk moves each joint by less than 0.08 rad per 120 Hz tick")

# ------------------------------------------------------------------ robustness

func test_every_setting_gives_finite_numbers(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bad := 0
	var count := 0
	for trial in 150:
		_randomise(rng)
		var v := rng.randf_range(-1.0, 12.0)
		_m.update(rng.randf_range(0.0, 0.3), v)
		for i in 20:
			var pose: Dictionary = _m.pose_at(float(i) / 20.0)
			for k in ["thigh_l", "knee_l", "foot_l", "thigh_r", "knee_r", "foot_r", "arm_l", "arm_r", "elbow_l", "elbow_r", "chest_yaw", "torso_lean", "reach_assist"]:
				count += 1
				if not is_finite(pose[k]):
					bad += 1
			count += 1
			if not (is_finite(pose.pelvis.x) and is_finite(pose.pelvis.y) and is_finite(pose.pelvis_q.x)):
				bad += 1
	t.eq(bad, 0, "no NaN or infinity in %d values over 150 random settings, speeds from -1 to 12 m/s" % count)


func test_bad_inputs_are_ignored(t) -> void:
	_m.update(0.02, 1.2)
	var before: float = _m.phase
	_m.update(NAN, 1.2)
	_m.update(INF, 1.2)
	_m.update(-1.0, 1.2)
	t.eq(_m.phase, before, "NaN, infinite and negative time steps do nothing")
	var pose: Dictionary = _m.update(0.01, NAN)
	t.ok(is_finite(pose.thigh_l) and is_finite(_m.phase), "a NaN speed is treated as standing")
	pose = _m.update(100.0, 1.2)
	t.ok(is_finite(_m.phase) and _m.phase >= 0.0 and _m.phase < 1.0, "a huge step is capped and the phase stays in range")
