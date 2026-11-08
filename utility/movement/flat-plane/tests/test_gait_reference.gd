extends RefCounted

const GP = preload("res://animation/gait_params.gd")
const RP = preload("res://animation/rig_params.gd")
const GM = preload("res://animation/gait_model.gd")
const Ref = preload("res://animation/walk_reference.gd")


func test_swing_interpolates_the_measured_passing_and_up_landmarks(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	var c: Dictionary = m.cycle_for(1.55)
	var start: Vector3 = m.ankle_at(c.d, c)
	var finish: Vector3 = m.ankle_at(0.0, c)
	for i in [1, 2]:
		var phase: float = c.d + (1.0 - c.d) * c.swing_plan.times[i]
		var a: Vector3 = m.ankle_at(phase, c)
		t.near((a.x - start.x) / (finish.x - start.x), Ref.swing_progress(i + 1), 1e-6, "measured hip-relative forward progress")
		t.near(rad_to_deg(a.z), -80.0 if i == 1 else -12.0, 1e-4, "toe-down Passing, almost level Up")
		var sole := minf(GM._rot(c.heel, a.z).y, GM._rot(c.toe, a.z).y) + a.y
		t.near(sole, c.lift * (1.0 if i == 1 else 1.0 / 12.0), 1e-6, "sole clearance at the landmark")
		t.near(phase, 0.75 if i == 1 else 0.875, 0.001, "landmark coincides with the reference checkpoint")


func test_internal_swing_knots_share_velocity_and_acceleration(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	var c: Dictionary = m.cycle_for(1.55)
	for i in [1, 2]:
		var q: float = c.d + (1.0 - c.d) * c.swing_plan.times[i]
		var h := 0.001
		var at: Vector3 = m.ankle_at(q, c)
		var left: Vector3 = m.ankle_at(q - h, c)
		var right: Vector3 = m.ankle_at(q + h, c)
		var left2: Vector3 = m.ankle_at(q - 2.0 * h, c)
		var right2: Vector3 = m.ankle_at(q + 2.0 * h, c)
		var vl := (3.0 * at - 4.0 * left + left2) / (2.0 * h)
		var vr := (-3.0 * at + 4.0 * right - right2) / (2.0 * h)
		t.ok((vl - vr).length() < 0.03, "no velocity corner at internal knot: %s" % (vl - vr).length())
		var al := (at - 2.0 * left + left2) / (h * h)
		var ar := (right2 - 2.0 * right + at) / (h * h)
		t.ok((al - ar).length() < 15.0, "continuous acceleration within finite-difference truncation: %s" % (al - ar).length())


func test_toe_stays_airborne_between_passing_and_up(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	for speed in [0.8, 1.55, 2.0]:
		var c: Dictionary = m.cycle_for(speed)
		var lowest := INF
		for i in range(1, 200):
			var q: float = c.d + (1.0 - c.d) * lerpf(c.swing_plan.times[1], c.swing_plan.times[2], i / 200.0)
			var a: Vector3 = m.ankle_at(q, c)
			lowest = minf(lowest, a.y + minf(GM._rot(c.heel, a.z).y, GM._rot(c.toe, a.z).y))
		t.ok(lowest > 0.001, "no early toe drag or hard-floor kink at %.2f m/s: clearance %.4f m" % [speed, lowest])


func test_low_clearance_edits_cannot_inflate_the_correction(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	for height in [0.0, 0.005, 0.01, 0.065]:
		p.set_value("step_height", height)
		var c: Dictionary = m.cycle_for(1.55)
		t.ok(c.swing_plan.clearance_lift <= height, "automatic correction is bounded by the requested clearance")
		for i in 100:
			var q: float = c.d + (1.0 - c.d) * i / 100.0
			var a: Vector3 = m.ankle_at(q, c)
			t.ok(a.y < c.foot_len + c.ankle_h + 2.0 * height, "no exploding arc when a user drags clearance to zero")


func test_reference_bone_ratios_and_passing_up_knee_angles(t) -> void:
	var p = GP.create()
	var dm: Dictionary = RP.dims(RP.create())
	t.near(dm.thigh / dm.shin, 74.0 / 72.0, 0.03, "nearly equal upper and lower legs, as measured")
	var shoulder_ratio: float = (dm.hip_drop + dm.torso + dm.chest * (0.22 / 0.26)) / (dm.thigh + dm.shin)
	var measured := 0.0
	for i in 4:
		measured += Ref.HIPS[i].distance_to(Ref.SHOULDERS[i]) / Ref.LEG_PIXELS / 4.0
	t.near(shoulder_ratio, measured, 0.03, "hip-to-shoulder relative to leg length")
	var m = GM.new(p, RP.create())
	m.cycle = m.cycle_for(1.55)
	for i in [2, 3]:
		var pose: Dictionary = m.pose_at(Ref.PHASES[i])
		var stance_angle := absf(rad_to_deg((Ref.STANCE_KNEES[i] - Ref.HIPS[i]).angle_to(Ref.STANCE_ANKLES[i] - Ref.STANCE_KNEES[i])))
		var swing_angle := absf(rad_to_deg((Ref.SWING_KNEES[i] - Ref.HIPS[i]).angle_to(Ref.SWING_ANKLES[i] - Ref.SWING_KNEES[i])))
		t.near(rad_to_deg(pose.knee_l), stance_angle, 10.0, "support knee fits the approximate 2D reference")
		t.near(rad_to_deg(pose.knee_r), swing_angle, 10.0, "swing knee fits the approximate 2D reference")


func test_hips_reach_down_and_up_at_the_reference_times(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	m.cycle = m.cycle_for(1.55)
	var low := INF
	var high := -INF
	var low_q := 0.0
	var high_q := 0.0
	for i in 200:
		var q := i / 400.0
		var pose: Dictionary = m.pose_at(q)
		if pose.pelvis.y < low:
			low = pose.pelvis.y
			low_q = q
		if pose.pelvis.y > high:
			high = pose.pelvis.y
			high_q = q
	t.near(low_q, 0.10, 0.015, "low near Down")
	t.near(high_q, 0.35, 0.015, "high near Up, not Passing")
	t.near(high - low, p.get_value("pelvis_bob"), 0.003, "requested excursion is retained")


func test_legacy_blend_and_reference_arm_switches_still_work(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	p.set_value("reference_fit", 0.0)
	m.cycle = m.cycle_for(1.55)
	var legacy: Dictionary = m.pose_at(0.125)
	t.near(legacy.arm_r, deg_to_rad(p.get_value("arm_swing")) * cos(TAU * 0.125), 1e-6, "legacy cosine arms")
	var c: Dictionary = m.cycle
	var plan: Dictionary = c.swing_plan
	var s := 0.41
	var expected := Ref.hermite(plan.points[0], plan.points[3], plan.velocities[0], plan.velocities[3],
		plan.accelerations[0], plan.accelerations[3], s)
	expected.y += c.lift * m.swing_bump(s, c)
	t.near(m.swing(c.d + s * (1.0 - c.d), c), expected, 1e-6, "legacy single-segment path retained")
	p.set_value("reference_fit", 1.0)
	m.cycle = m.cycle_for(1.55)
	for i in 8:
		var pose: Dictionary = m.pose_at(i / 8.0)
		t.near(rad_to_deg(pose.arm_r), Ref.ARM_DEGREES[i].x, 1e-4, "reference upper-arm checkpoint")
		t.near(rad_to_deg(pose.elbow_r), Ref.ARM_DEGREES[i].y, 1e-4, "reference elbow checkpoint")
	p.set_value("fx_arm_swing", 0.0)
	p.set_value("fx_elbow_bend", 0.0)
	m.cycle = m.cycle_for(1.55)
	var off: Dictionary = m.pose_at(0.125)
	t.near(off.arm_r, 0.0, 1e-9, "arm switch respected")
	t.near(off.elbow_r, 0.0, 1e-9, "elbow switch respected")
