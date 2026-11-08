extends RefCounted

const GP = preload("res://animation/gait_params.gd")
const RP = preload("res://animation/rig_params.gd")
const GM = preload("res://animation/gait_model.gd")
const RunReference = preload("res://animation/run_reference.gd")
const DT := 1.0 / 60.0
const MODEL_SPEEDS := [2.5, 4.5, 6.0, 7.0, 8.0, 12.0, 15.0]
const SCENE_SPEEDS := [2.5, 4.5, 6.0, 7.0, 8.0, 12.0]
var _scene
var _tree: SceneTree


func before_each() -> void:
	_tree = Engine.get_main_loop()


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		await _tree.process_frame
	_scene = null


func _model():
	var p = GP.create()
	p.set_value("run_mode", 1.0)
	return GM.new(p, RP.create())


func _run_speed() -> float:
	return GP.create().def("run_speed").default


func _boot() -> Node:
	_scene = load("res://scenes/gait_treadmill.tscn").instantiate()
	_scene.options = {"no-tuning": "true", "no-hardware": "true", "no-window-state": "true", "gait-mode": "run"}
	_tree.root.add_child(_scene)
	await _tree.process_frame
	_scene.set_process(false)
	_scene.advance(0.0)
	return _scene


func _sole(a: Vector3, c: Dictionary) -> float:
	return a.y + minf(GM._rot(c.heel, a.z).y, GM._rot(c.toe, a.z).y)


func test_running_has_flight_instead_of_double_support(t) -> void:
	var m = _model()
	var speed := _run_speed()
	for duty in [0.18, 0.22, 0.34, 0.48]:
		m.p.set_value("run_duty_factor", duty)
		m.cycle = m.cycle_for(speed)
		var flight := 0
		var double_support := 0
		for i in 1000:
			var pose: Dictionary = m.pose_at(i / 1000.0)
			flight += int(pose.flight)
			double_support += int(pose.contact_l and pose.contact_r)
		t.eq(double_support, 0, "running never has two planted feet")
		t.near(flight / 1000.0, 1.0 - 2.0 * duty, 0.003, "flight share follows stance duration")
		t.near(m.pose_at(0.0).flight_fraction, 1.0 - 2.0 * duty, 1e-9, "readout agrees with actual contacts")
		t.near(m.cycle.rate * m.cycle.stride, speed, 1e-9, "stride and cadence still match belt speed")


func test_default_run_starts_at_seven_meters_per_second_with_a_runners_cycle(t) -> void:
	var p = GP.create()
	t.near(p.def("run_speed").default, 7.0, 1e-9, "default running belt: 7 m/s (15.7 mph)")
	t.ok(p.def("run_speed").max >= GM.MAX_SPEED, "the slider reaches the model's top speed")
	var m = _model()
	var c: Dictionary = m.cycle_for(_run_speed())
	var step: float = c.stride * 0.5
	var cadence: float = c.rate * 120.0
	var contact_s: float = c.d / c.rate
	var flight_s: float = (0.5 - c.d) / c.rate
	var flight_travel: float = flight_s * c.v
	print("run default: step %.2f m, %.0f steps/min, contact %.3f s, hip lowering %.3f m" % [step, cadence, contact_s, c.lower])
	t.ok(step > 2.15 and step < 2.30, "longer than the previous 1.80 m step: %.2f m" % step)
	t.ok(cadence > 180.0 and cadence < 200.0, "less hurried than the previous 233 steps/min: %.0f" % cadence)
	t.ok(contact_s > 0.09 and contact_s < 0.16, "short fast-running ground contact: %.3f s" % contact_s)
	t.ok(flight_s > 0.19 and flight_s < 0.22, "longer airborne interval than the previous 0.144 s: %.3f" % flight_s)
	t.ok(flight_travel > 1.35 and flight_travel < 1.5, "a forward bound, previously 1.01 m in flight: %.2f m" % flight_travel)
	t.ok(c.lower < 0.025, "the longer run stays tall instead of crouching to reach: %.3f m" % c.lower)


func test_default_run_ankles_are_reachable_and_flight_is_really_airborne(t) -> void:
	var m = _model()
	for speed in MODEL_SPEEDS:
		m.cycle = m.cycle_for(speed)
		var c: Dictionary = m.cycle
		var worst := 0.0
		var lowest_flight := INF
		var lowest_flight_phase := 0.0
		var max_swing := 0.0
		var min_stance := 180.0
		var max_stance := 0.0
		for i in 400:
			var q := i / 400.0
			var pose: Dictionary = m.pose_at(q)
			for side in ["l", "r"]:
				var off: Vector3 = pose.pelvis_q * Vector3(-c.hip_x if side == "l" else c.hip_x, -c.hip_drop, 0)
				var a: Vector3 = pose["ankle_" + side]
				var solved := GM.leg_reach(pose["thigh_" + side], pose["knee_" + side], c.thigh, c.shin)
				worst = maxf(worst, solved.distance_to(Vector2(a.x + off.z, a.y - pose.pelvis.y - off.y)))
				t.ok(_sole(a, c) >= -1e-6, "sole never penetrates the belt")
				var knee: float = rad_to_deg(pose["knee_" + side])
				if pose["contact_" + side]:
					min_stance = minf(min_stance, knee)
					max_stance = maxf(max_stance, knee)
					t.near(_sole(a, c), 0.0, 1e-6, "contact foot is actually on the belt")
				else:
					max_swing = maxf(max_swing, knee)
				var half_phase := fposmod(q, 0.5)
				if pose.flight and half_phase > c.d + 0.025 and half_phase < 0.475:
					var sole := _sole(a, c)
					if sole < lowest_flight:
						lowest_flight = sole
						lowest_flight_phase = q
		print("run %.1f m/s: stance knee %.1f..%.1f, recovery %.1f, flight sole %.3f m, FK %.6f m, hip lowering %.3f m" % [
			speed, min_stance, max_stance, max_swing, lowest_flight, worst, c.lower])
		print("  lowest flight sole phase %.3f" % lowest_flight_phase)
		t.ok(worst < 1e-5, "running IK reaches every planned ankle: %.6f m" % worst)
		t.ok(lowest_flight > 0.001, "both soles clear the belt during flight: %.4f m" % lowest_flight)
		# The photo's flight pose keeps the rear leg fairly long; recovery still bends visibly without a full heel tuck.
		var tuck := 145.0 if speed < 5.0 else 160.0
		t.ok(max_swing > 75.0 and max_swing < tuck, "heel recovery is visibly bent without folding flat: %.1f deg" % max_swing)
		t.ok(min_stance >= 13.0 and max_stance - min_stance > 8.0, "support compresses then extends without locking")


func test_run_hips_compress_in_support_and_rise_in_flight(t) -> void:
	var m = _model()
	m.cycle = m.cycle_for(_run_speed())
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
	t.near(low_q, m.cycle.d * 0.25, 0.01, "load early enough to extend before toe-off")
	t.ok(high_q > m.cycle.d + 0.1 and high_q < 0.4, "highest well inside flight")
	t.near(m.cycle.flight_lift, m.p.get_value("run_flight_lift"), 1e-9, "default speed and contact time get the full flight lift")
	t.ok(high - low > 0.20 and high - low < 0.23, "visible rise combines push-off and whole-body flight")


func test_running_push_off_extends_the_loaded_leg_and_keeps_a_smooth_hip_path(t) -> void:
	var m = _model()
	for speed in MODEL_SPEEDS:
		m.cycle = m.cycle_for(speed)
		var c: Dictionary = m.cycle
		var reversals := 0
		var previous_y: float = m.pose_at(0.0).pelvis.y
		var was_rising := false
		var loaded_knee := 0.0
		for i in range(1, 500):
			var q := i / 1000.0
			var pose: Dictionary = m.pose_at(q)
			var rising: bool = pose.pelvis.y > previous_y
			if i > 1 and rising != was_rising:
				reversals += 1
			previous_y = pose.pelvis.y
			was_rising = rising
			t.near(pose.pelvis.y, pose.y_target - c.lower, 1e-6, "no local reach correction dips or clips the hip wave")
			if q < c.d:
				loaded_knee = maxf(loaded_knee, rad_to_deg(pose.knee_l))
		t.eq(reversals, 2, "%.1f m/s: one loading trough and one flight apex per step" % speed)
		if speed == _run_speed():
			var takeoff: Dictionary = m.pose_at(c.d)
			var extension: float = loaded_knee - rad_to_deg(takeoff.knee_l)
			var upward: float = (m.pose_at(c.d + 0.001).pelvis.y - m.pose_at(c.d - 0.001).pelvis.y) / 0.002 * c.rate
			t.ok(extension > 20.0 and extension < 35.0, "the support leg drives from loaded flexion into toe-off: %.1f degrees" % extension)
			t.ok(rad_to_deg(takeoff.knee_l) < 30.0, "the pushing leg is almost extended, not crouched")
			t.ok(upward > 1.0 and upward < 1.5, "the body is already rising at toe-off: %.2f m/s" % upward)


func test_airborne_reach_does_not_lower_the_running_support_poses(t) -> void:
	var m = _model()
	m.cycle = m.cycle_for(_run_speed())
	var lower: float = m.cycle.lower
	var hips: Array[Vector3] = []
	for i in 200:
		hips.append(m.pose_at(i / 200.0).pelvis)
	for recovery in [0.05, 0.55]:
		m.p.set_value("run_step_height", recovery)
		m.cycle = m.cycle_for(_run_speed())
		var c: Dictionary = m.cycle
		t.near(c.lower, lower, 1e-9, "only planted feet set the cycle's constant hip lowering")
		for i in 200:
			var pose: Dictionary = m.pose_at(i / 200.0)
			t.near(pose.pelvis, hips[i], 1e-6, "editing heel recovery leaves the powered hip trajectory alone")
			for side in ["l", "r"]:
				var off: Vector3 = pose.pelvis_q * Vector3(-c.hip_x if side == "l" else c.hip_x, -c.hip_drop, 0.0)
				var a: Vector3 = pose["ankle_" + side]
				var distance := Vector2(a.x + off.z, a.y - pose.pelvis.y - off.y).length()
				t.ok(distance <= c.reach + 1e-6, "an overextended airborne foot recovers within reach")
				t.ok(_sole(a, c) >= -1e-6, "reach correction never pushes a sole below the belt")


func test_flight_lift_raises_the_whole_body_without_changing_leg_shape(t) -> void:
	var m = _model()
	var lift: float = m.p.get_value("run_flight_lift")
	var speed := _run_speed()
	m.cycle = m.cycle_for(speed)
	t.ok(lift > 0.05, "the default flight is visible")
	var mid: float = (m.cycle.d + 0.5) * 0.5
	var lifted: Array[Dictionary] = []
	for q in [0.1, mid, mid + 0.5]:
		lifted.append(m.pose_at(q))
	m.p.set_value("run_flight_lift", 0.0)
	m.cycle = m.cycle_for(speed)
	var flat: Array[Dictionary] = []
	for q in [0.1, mid, mid + 0.5]:
		flat.append(m.pose_at(q))
	t.near(lifted[0].pelvis, flat[0].pelvis, 1e-9, "no lift while a foot supports the body")
	for i in [1, 2]:
		t.near(lifted[i].pelvis.y - flat[i].pelvis.y, lift, 1e-6, "mid-flight raises the hips by the full lift")
		for side in ["l", "r"]:
			t.near(lifted[i]["ankle_" + side].y - flat[i]["ankle_" + side].y, lift, 1e-6, "and both airborne feet with them")
			t.near(lifted[i]["knee_" + side], flat[i]["knee_" + side], 1e-6, "so the legs keep the same shape")
	m.p.set_value("run_flight_lift", lift)
	var c: Dictionary = m.cycle_for(speed)
	for edge in [c.d, 0.5]:
		var h := 0.0005
		var rise: float = m.flight_lift(edge + h, c) + m.flight_lift(edge - h, c)
		t.ok(rise < 1e-6, "lift starts and ends at the touchdown/toe-off instants without a jump: %.8f" % rise)


func test_run_landing_foot_settles_onto_the_belt_instead_of_stomping(t) -> void:
	var m = _model()
	for speed in MODEL_SPEEDS:
		m.cycle = m.cycle_for(speed)
		var c: Dictionary = m.cycle
		t.ok(c.swing_plan.landing_clearance_lift < 0.02, "%.1f m/s: no late corrective hop before touchdown: %.3f m" % [speed, c.swing_plan.landing_clearance_lift])
		var late := _sole(m.pose_at(0.47).ankle_r, c)
		var sooner := _sole(m.pose_at(0.44).ankle_r, c)
		t.ok(late < 0.06 and sooner > late, "%.1f m/s: the landing foot is nearly down 0.03 cycle early (%.3f m) and still descending" % [speed, late])
		var lowest: float = m.pose_at(0.44).ankle_r.y
		var rise := 0.0
		for i in range(1, 61):
			var height: float = m.pose_at(0.44 + i * 0.001).ankle_r.y
			lowest = minf(lowest, height)
			rise = maxf(rise, height - lowest)
		# Matching the heel rocker's acceleration allows a sub-millimetre rise, not a visible late hop.
		t.ok(rise < 0.001, "%.1f m/s: no extra ankle hop on final descent: %.6f m" % [speed, rise])


func test_run_handover_is_continuous_and_left_right_are_symmetric(t) -> void:
	var m = _model()
	for speed in MODEL_SPEEDS:
		m.cycle = m.cycle_for(speed)
		var c: Dictionary = m.cycle
		for boundary in [c.d, 1.0]:
			t.near(m.swing(boundary, c), m.stance(c.d if boundary == c.d else 0.0, c), 1e-5, "no position jump")
			var h := 0.0001
			var before: Vector3 = (m.ankle_at(boundary - h, c) - m.ankle_at(boundary - 2.0 * h, c)) / h
			var after: Vector3 = (m.ankle_at(fposmod(boundary + 2.0 * h, 1.0), c) - m.ankle_at(fposmod(boundary + h, 1.0), c)) / h
			var mismatch := Vector2(after.x - before.x, after.y - before.y).length() / float(c.stride)
			t.ok(mismatch < 0.04, "%.1f m/s phase %.2f: ankle velocity mismatch %.4f of stride/cycle" % [speed, boundary, mismatch])
		for i in 50:
			var a: Dictionary = m.pose_at(i / 50.0)
			var b: Dictionary = m.pose_at(fposmod(i / 50.0 + 0.5, 1.0))
			for part in ["thigh", "knee", "foot", "arm", "elbow"]:
				t.near(a[part + "_l"], b[part + "_r"], 1e-5, "half-cycle symmetry")


func test_run_settings_cannot_change_the_walk_when_run_mode_is_off(t) -> void:
	var p = GP.create()
	var m = GM.new(p, RP.create())
	m.cycle = m.cycle_for(1.55)
	var before: Dictionary = m.pose_at(0.25)
	for d in p.definitions():
		if d.id.begins_with("run_") and d.id != "run_mode":
			p.set_value(d.id, d.max)
	m.cycle = m.cycle_for(1.55)
	t.eq(m.pose_at(0.25), before, "all independent running controls leave the approved walk untouched")


func test_running_at_rest_has_no_flight_or_stepping(t) -> void:
	var m = _model()
	m.cycle = m.cycle_for(0.0)
	for i in 40:
		var pose: Dictionary = m.pose_at(i / 40.0)
		t.ok(not pose.flight, "no flight at rest")
		t.near(pose.flight_fraction, 0.0, 1e-9, "no airborne interval at rest")
		t.near(pose.ankle_l, pose.ankle_r, 1e-6, "both feet stay under the body")
		t.near(_sole(pose.ankle_l, m.cycle), 0.0, 1e-6, "resting soles stay on the belt")
	t.near(m.cycle.rate, 0.0, 1e-9, "cycle stops")


func test_running_reference_landmarks_have_the_expected_support_and_joint_shapes(t) -> void:
	var m = _model()
	var c: Dictionary = m.cycle_for(_run_speed())
	m.cycle = c
	var phases := RunReference.phases(c.d)
	t.eq(RunReference.LABELS, ["Contact", "Down", "Passing", "Flight"], "matches the labeled reference poses")
	t.near(phases[0], 0.0, 1e-9, "Contact is the heel strike")
	t.ok(phases[1] > 0.0 and phases[1] < c.d, "Down is loaded within stance")
	t.ok(phases[2] > phases[1] and phases[2] < c.d, "Passing is late in the same support, as the recovering foot comes through")
	t.ok(phases[3] > c.d and phases[3] < 0.5, "the five frames span one step, so Flight precedes the opposite contact")
	var contact: Dictionary = m.pose_at(phases[0])
	var down: Dictionary = m.pose_at(phases[1])
	var passing: Dictionary = m.pose_at(phases[2])
	var flight: Dictionary = m.pose_at(phases[3])
	t.ok(contact.contact_l and not contact.contact_r, "Contact reference leg is planted")
	t.ok(rad_to_deg(contact.knee_l) < rad_to_deg(contact.knee_r), "Contact has an extended support leg and bent recovery leg")
	t.ok(down.contact_l and not down.contact_r, "Down remains in supported loading")
	t.ok(down.pelvis.y < contact.pelvis.y, "Down is lower than Contact")
	t.ok(rad_to_deg(down.knee_l) > rad_to_deg(contact.knee_l), "Down bends the support knee")
	t.ok(passing.contact_l and not passing.contact_r, "Passing keeps the same support leg")
	t.ok(rad_to_deg(passing.knee_r) > rad_to_deg(passing.knee_l) + 35.0, "Passing has a folded recovery knee over a long support leg")
	t.ok(absf(passing.ankle_r.x) < 0.3 and passing.ankle_r.y > passing.ankle_l.y + 0.15, "the recovering foot is passing high beside the hips")
	t.ok(flight.flight, "both feet leave the belt at the reference Flight checkpoint")
	t.ok(_sole(flight.ankle_l, c) > 0.1 and _sole(flight.ankle_r, c) > 0.25, "Flight is visibly airborne, not skimming the belt")
	t.ok(flight.pelvis.y - contact.pelvis.y > 0.06, "the hips rise into flight: %.3f m" % (flight.pelvis.y - contact.pelvis.y))
	t.ok(flight.ankle_r.x > 0.1 and flight.ankle_r.x < 0.25 and flight.ankle_l.x < -0.45, "Flight keeps the forward foot near the hips and the trailing foot well behind")
	t.ok(rad_to_deg(flight.thigh_r) > 50.0 and rad_to_deg(flight.thigh_r) < 70.0, "the leading thigh angles forward below horizontal")
	t.ok(rad_to_deg(flight.knee_r) > 75.0 and rad_to_deg(flight.knee_r) < 100.0 and rad_to_deg(flight.knee_l) < 30.0, "Flight matches the reference's bent lead knee and long rear leg")
	t.near(rad_to_deg(flight.torso_lean), 15.0, 0.01, "the running trunk leans forward like the side-view reference")
	t.ok(flight.arm_l > 0.0 and flight.arm_r < 0.0 and flight.elbow_l > 1.4 and flight.elbow_r > 1.2, "the arms counter-drive with bent elbows")


## Sample close enough not to cross a later reach correction; sum scalar doubles rather than amplify Vector3 rounding.
func _one_sided_acceleration(m, c: Dictionary, q: float, direction: float) -> Vector2:
	var h := 0.0005 * direction
	var a0: Vector3 = m.ankle_at(fposmod(q, 1.0), c)
	var a1: Vector3 = m.ankle_at(fposmod(q + h, 1.0), c)
	var a2: Vector3 = m.ankle_at(fposmod(q + 2.0 * h, 1.0), c)
	var a3: Vector3 = m.ankle_at(fposmod(q + 3.0 * h, 1.0), c)
	return Vector2(
		(2.0 * a0.x - 5.0 * a1.x + 4.0 * a2.x - a3.x) / (h * h),
		(2.0 * a0.y - 5.0 * a1.y + 4.0 * a2.y - a3.y) / (h * h))


func test_run_acceleration_is_continuous_at_contact_and_internal_knots(t) -> void:
	var m = _model()
	var worst := 0.0
	for speed in MODEL_SPEEDS:
		var c: Dictionary = m.cycle_for(speed)
		var boundaries: Array[float] = [c.d, 1.0]
		for i in [1, 2]:
			boundaries.append(c.d + (1.0 - c.d) * c.swing_plan.times[i])
		for b in boundaries:
			var before := _one_sided_acceleration(m, c, b, -1.0)
			var after := _one_sided_acceleration(m, c, b, 1.0)
			var mismatch: float = (before - after).length() / c.stride
			if mismatch > worst:
				worst = mismatch
	t.ok(worst < 4.0, "running retains the walking acceleration tolerance: %.3f stride-lengths/cycle squared" % worst)


func test_treadmill_mode_buttons_keep_independent_speeds_and_pose_checkpoints(t) -> void:
	var s := await _boot()
	t.ok(s.gait_params.is_on("run_mode"), "explicit launch mode")
	t.near(s.speed, 7.0, 1e-6, "running speed, not the walking belt speed")
	t.eq(s.cam.projection, Camera3D.PROJECTION_PERSPECTIVE, "perspective retained")
	t.eq(s.view, "side-left", "right-to-left retained")
	var d: float = s.model.cycle.d
	var phases := RunReference.phases(d)
	for i in 4:
		s.pose_buttons[i].pressed.emit()
		s.advance(DT)
		t.near(s.model.phase, phases[i], 0.0026, "running checkpoint, within scrub resolution")
	t.ok(s.model.pose.flight, "Flight button pauses with both feet airborne")
	s.gait_params.set_value("run_duty_factor", 0.4)
	s.pose_buttons[3].pressed.emit()
	s.advance(DT)
	t.near(s.model.phase, RunReference.phases(0.4)[3], 0.0026, "Flight checkpoint follows edited contact timing, within scrub resolution")
	t.ok(s.model.pose.flight, "the moved Flight checkpoint is still airborne")
	t.eq(s.visual.walk_animation.player.get_animation("walk").track_get_key_count(0), s.visual.walk_animation.RUN_SAMPLES + 1, "denser running clip")
	s.gait_params.set_value("run_speed", 5.0)
	s.walk_button.pressed.emit()
	s.advance(DT)
	t.near(s.speed, 1.55, 1e-6, "walk speed was preserved")
	t.eq(s.pose_buttons[2].text, "Passing", "walking checkpoints return")
	t.eq(s.visual.walk_animation.player.get_animation("walk").track_get_key_count(0), s.visual.walk_animation.SAMPLES + 1, "walking sampling unchanged")
	s.run_button.pressed.emit()
	s.advance(DT)
	t.near(s.speed, 5.0, 1e-6, "running speed was preserved")
	t.eq(s.pose_buttons[2].text, "Passing", "running checkpoints return")


func test_running_real_skeleton_contacts_and_clip_precision(t) -> void:
	var s := await _boot()
	s.gait_params.set_value("freeze", 1.0)
	var worst_clip := 0.0
	var flight_clearance := INF
	for additive in [1.0, 0.0]:
		s.visual.walk_animation.params.set_value("body_blend", additive)
		for speed in SCENE_SPEEDS:
			s.gait_params.set_value("run_speed", speed)
			s.set_running(false)
			s.set_running(true)
			for i in 200:
				s.gait_params.set_value("scrub", i / 200.0)
				s.advance(0.0)
				var pose: Dictionary = s.model.pose
				var c: Dictionary = s.model.cycle
				for side in ["l", "r"]:
					var fp: Transform3D = s.visual.skeleton.get_bone_global_pose(s.visual.bone_index["foot_" + side])
					var off: Vector3 = pose.pelvis_q * Vector3(-c.hip_x if side == "l" else c.hip_x, -c.hip_drop, 0)
					var a: Vector3 = pose["ankle_" + side]
					var expected := Vector3(pose.pelvis.x + off.x, a.y, -a.x)
					worst_clip = maxf(worst_clip, fp.origin.distance_to(expected))
					var heel: Vector3 = fp * Vector3(0, -c.ankle_h, -c.heel.x)
					var toe: Vector3 = fp * Vector3(0, -c.ankle_h, -c.toe.x)
					var sole := minf(heel.y, toe.y)
					if pose["contact_" + side]:
						t.near(sole, 0.0, 0.001, "actual skeleton contact, with and without additive correction")
					if pose.flight and fposmod(pose.phase, 0.5) > c.d + 0.02 and fposmod(pose.phase, 0.5) < 0.48:
						flight_clearance = minf(flight_clearance, sole)
	print("running skeleton: max ankle error %.6f m, minimum interior-flight sole %.4f m" % [worst_clip, flight_clearance])
	t.ok(worst_clip < 0.001, "running clip places ankles within 1 mm: %.6f m" % worst_clip)
	t.ok(flight_clearance > 0.001, "actual posed soles clear the belt during flight")


func test_planted_running_feet_do_not_slip(t) -> void:
	var s := await _boot()
	for speed in SCENE_SPEEDS:
		s.gait_params.set_value("run_speed", speed)
		for i in 240:
			s.advance(DT)
			s._measure_slip(DT)
		t.ok(maxf(s.slip_l, s.slip_r) < 0.003, "%.1f m/s: running planted slip L %.4f R %.4f m/s" % [speed, s.slip_l, s.slip_r])
