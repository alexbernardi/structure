## Procedural walk cycle driven by a phase, not by a sine wave per joint. It plans where each ANKLE goes, then solves the
## legs from that, so the feet can be made to behave like feet:
##   * stance: the foot is fixed to the ground and rolls heel -> flat -> toe. In the hips' frame it therefore moves
##     backwards at exactly the walking speed (the treadmill belt), whatever the other settings are;
##   * swing: a cubic Hermite path from the toe-off pose to the next heel-strike pose that leaves and lands moving like
##     the stance foot (no stop-and-go), with a clearance bump on top and a floor so no sole point goes under the ground;
##   * legs: analytic two-bone IK in the sagittal plane for the real bone lengths, with a "reach assist" that lowers the
##     hips just enough that a planted foot is never pulled off the ground (the amount is reported).
## One cycle = one full stride (left heel strike at phase 0, right at 0.5). Everything here is visual: it reads nothing of
## the physics and gives the physics nothing.
##
## Frame of the planned points: x forward (the direction of walking), y up, origin at the pelvis' ground projection.
## Angles: positive foot pitch = toes up; leg angles use the skeleton's convention (positive rotation about X swings a
## hanging limb forward). Units are metres, seconds, radians.
extends RefCounted

const Visual = preload("res://character/character_visual.gd")

const THIGH := Visual.THIGH
const SHIN := Visual.SHIN
const ANKLE_H := Visual.ANKLE_H
const HIP_DROP := Visual.HIP_DROP
const HIP_X := 0.10
const HEEL := Vector2(-0.065, -ANKLE_H)   ## heel and toe contact points relative to the ankle joint, in (forward, up)
const TOE := Vector2(0.185, -ANKLE_H)
const FOOT_LEN := 0.25
const REFERENCE_SPEED := 1.4
const STEP_LENGTH_EXPONENT := 0.42        ## human step length grows roughly with speed^0.42
const MAX_SPEED := 8.0
const EPS := 1e-4

var p                       ## ParamSet of gait parameters (read live on every update)
var phase := 0.0            ## 0..1, left heel strike at 0
var pose: Dictionary = {"active": false}
var cycle: Dictionary = {}  ## derived constants of the current settings (see cycle_for)


func _init(params) -> void:
	p = params


# ------------------------------------------------------------------ cycle constants

## Everything the foot planner needs for a given speed and the current parameters.
func cycle_for(speed: float) -> Dictionary:
	var v := clampf(speed, 0.0, MAX_SPEED) if not is_nan(speed) else 0.0
	var step_len: float = p.get_value("step_length")
	if p.is_on("auto_step_length"):
		step_len *= pow(v / REFERENCE_SPEED, STEP_LENGTH_EXPONENT)
	step_len = clampf(step_len, 0.0, 1.6)
	var stride := 2.0 * step_len
	var duty: float = p.get_value("duty_factor")
	var roll: bool = p.is_on("foot_roll")
	var g := _smooth(v / 0.5)   # standing still: no roll, no lift, no body motion
	var flat_at: float = p.get_value("foot_flat_at")
	var rise_at := maxf(float(p.get_value("heel_rise_at")), flat_at + 0.05)
	return {
		"v": v, "step_len": step_len, "stride": stride, "d": duty, "roll": roll, "g": g,
		"q1": flat_at * duty, "q2": rise_at * duty,
		"th_h": deg_to_rad(p.get_value("heel_strike_angle")) * g if roll else 0.0,
		"th_t": deg_to_rad(p.get_value("toe_off_angle")) * g if roll else 0.0,
		"th_c": deg_to_rad(p.get_value("toe_clearance_angle")) * g if roll else 0.0,
		"hf0": stride * duty * 0.5 + HEEL.x,   # world position of the heel while flat: puts mid stance under the hip
		"lift": clampf(v / 0.3, 0.0, 1.0) * float(p.get_value("step_height")),
		"vm": p.get_value("velocity_match"),
		"peak_k": clampf(log(0.5) / log(clampf(float(p.get_value("swing_peak")), 0.05, 0.95)), 0.3, 3.3),
		"rate": v / stride if stride > 1e-4 else 0.0,   # cycles per second
	}


static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## A minimum with a rounded corner (never above the true minimum), so the hips ease down rather than kink when a
## planted foot starts to need the full leg.
static func _soft_min(a: float, b: float, k := 0.02) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


static func _rot(pt: Vector2, th: float) -> Vector2:
	var c := cos(th)
	var s := sin(th)
	return Vector2(pt.x * c - pt.y * s, pt.x * s + pt.y * c)


# ------------------------------------------------------------------ one foot

## Ankle pose while the foot is on the ground, q in [0, duty]: (forward, up, foot pitch). The point of the foot that
## touches the ground (heel, then the whole sole, then the toe) does not move in the world, only the pelvis does.
func stance(q: float, c: Dictionary) -> Vector3:
	var th := 0.0
	var pivot := 1   # 0 heel, 1 flat, 2 toe
	if c.roll:
		if q < c.q1:
			th = c.th_h * (1.0 - _smooth(q / maxf(c.q1, 1e-6)))
			pivot = 0
		elif q >= c.q2:
			th = -c.th_t * _smooth((q - c.q2) / maxf(c.d - c.q2, 1e-6))
			pivot = 2
	if pivot == 0:
		var r := _rot(HEEL, th)
		return Vector3(c.hf0 - r.x - c.stride * q, -r.y, th)
	if pivot == 2:
		var r2 := _rot(TOE, th)
		return Vector3(c.hf0 + FOOT_LEN - r2.x - c.stride * q, -r2.y, th)
	return Vector3(c.hf0 - HEEL.x - c.stride * q, ANKLE_H, th)


## Where the ground-contact point (the pivot) is, forward of the pelvis, while the foot is planted.
func contact_point(q: float, c: Dictionary) -> float:
	if c.roll and q >= c.q2:
		return c.hf0 + FOOT_LEN - c.stride * q
	return c.hf0 - c.stride * q


func _dstance(q: float, c: Dictionary, side: int) -> Vector3:
	var h := 1e-4
	if side < 0:
		return (stance(q, c) - stance(q - h, c)) / h
	return (stance(q + h, c) - stance(q, c)) / h


## Ankle pose in the swing, q in [duty, 1).
func swing(q: float, c: Dictionary) -> Vector3:
	var s := clampf((q - c.d) / maxf(1.0 - c.d, 1e-6), 0.0, 1.0)
	var p0 := stance(c.d, c)
	var p1 := stance(0.0, c)   # the next heel strike: the cycle is periodic in the pelvis frame
	var k: float = (1.0 - c.d) * c.vm
	var m0 := _dstance(c.d, c, -1) * k
	var m1 := _dstance(0.0, c, 1) * k
	var s2 := s * s
	var s3 := s2 * s
	var out := p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + p1 * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)
	var bump := pow(sin(PI * pow(s, c.peak_k)), 2.0)
	out.y += c.lift * bump
	out.z += c.th_c * pow(sin(PI * s), 2.0)
	return out


## Ankle pose for any phase of one foot (its own phase: 0 = its heel strike).
func ankle_at(q: float, c: Dictionary) -> Vector3:
	var a := stance(q, c) if q < c.d else swing(q, c)
	var low := a.y + minf(_rot(HEEL, a.z).y, _rot(TOE, a.z).y)   # the lowest point of the sole
	if low < 0.0:
		a.y -= low
	return a


## The ankle's planned path over one cycle as (forward, up) points, for drawing.
func path_points(n := 96) -> PackedVector2Array:
	var out := PackedVector2Array()
	if cycle.is_empty():
		return out
	for i in n + 1:
		var a := ankle_at(float(i) / float(n) * 0.9999, cycle)
		out.append(Vector2(a.x, a.y))
	return out


# ------------------------------------------------------------------ legs

## Sagittal two-bone IK: the thigh angle (forward positive) and knee flexion for an ankle at (dx forward, dy up) from the hip.
static func solve_leg(dx: float, dy: float) -> Vector2:
	var d := clampf(sqrt(dx * dx + dy * dy), absf(THIGH - SHIN) + 1e-3, THIGH + SHIN - 1e-6)
	var cos_beta := clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0)
	var cos_knee := clampf((THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN), -1.0, 1.0)
	var knee := PI - acos(cos_knee)
	var thigh := atan2(dx, -dy) + acos(cos_beta)
	return Vector2(thigh, knee)


## Forward kinematics of solve_leg (for tests and the overlay): ankle offset (forward, up) from the hip.
static func leg_reach(thigh: float, knee: float) -> Vector2:
	var a := Vector2(sin(thigh) * THIGH, -cos(thigh) * THIGH)
	var b := Vector2(sin(thigh - knee) * SHIN, -cos(thigh - knee) * SHIN)
	return a + b


# ------------------------------------------------------------------ update

func update(dt: float, speed: float) -> Dictionary:
	if is_nan(dt) or is_inf(dt) or dt < 0.0:
		return pose
	if not p.is_on("gait_model"):
		pose = {"active": false}
		return pose
	cycle = cycle_for(speed)
	if p.is_on("freeze"):
		phase = fposmod(float(p.get_value("scrub")), 1.0)
	else:
		phase = fposmod(phase + cycle.rate * minf(dt, 0.25) * float(p.get_value("time_scale")), 1.0)
	pose = pose_at(phase)
	return pose


## The complete pose for a phase with the current parameters and the speed of the last update.
func pose_at(q_left: float) -> Dictionary:
	var c := cycle
	if c.is_empty():
		c = cycle_for(0.0)
		cycle = c
	var g: float = c.g
	var q_right := fposmod(q_left + 0.5, 1.0)
	var al := ankle_at(q_left, c)
	var ar := ankle_at(q_right, c)

	# pelvis
	var bob := 0.0
	if p.is_on("fx_pelvis_bob"):
		bob = float(p.get_value("pelvis_bob")) * 0.5 * (1.0 - cos(4.0 * PI * q_left)) * g
	var dip := 0.0
	if p.is_on("fx_loading_dip"):
		var u := clampf(fmod(q_left, 0.5) / 0.16, 0.0, 1.0)
		dip = float(p.get_value("loading_dip")) * pow(sin(PI * u), 2.0) * g
	var sway := 0.0
	if p.is_on("fx_pelvis_sway"):
		sway = -float(p.get_value("pelvis_sway")) * sin(TAU * q_left) * g
	var yaw := 0.0
	if p.is_on("fx_pelvis_rotation"):
		yaw = -deg_to_rad(p.get_value("pelvis_rotation")) * cos(TAU * q_left) * g
	var tilt := 0.0
	if p.is_on("fx_pelvic_tilt"):
		tilt = -deg_to_rad(p.get_value("pelvic_tilt")) * sin(TAU * q_left) * g
	var pelvis_q := Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.BACK, tilt)
	var y_target := ANKLE_H + HIP_DROP + float(p.get_value("stand_height")) * (THIGH + SHIN) + bob - dip

	# reach assist: never ask a planted foot for more than the leg can give
	var offs: Array[Vector3] = [pelvis_q * Vector3(-HIP_X, -HIP_DROP, 0.0), pelvis_q * Vector3(HIP_X, -HIP_DROP, 0.0)]
	var ankles: Array[Vector3] = [al, ar]
	var y := y_target
	var reach := (THIGH + SHIN) * 0.9995
	for i in 2:
		var dx: float = ankles[i].x + offs[i].z   # hip is at -z forward of the pelvis origin
		var room := sqrt(maxf(reach * reach - dx * dx, 0.0))
		y = _soft_min(y, ankles[i].y + room - offs[i].y)
	var assist := y_target - y

	var legs: Array[Vector2] = []
	for i in 2:
		var dx2: float = ankles[i].x + offs[i].z
		var dy2: float = ankles[i].y - (y + offs[i].y)
		legs.append(solve_leg(dx2, dy2))
	var foot_l: float = al.z - legs[0].x + legs[0].y
	var foot_r: float = ar.z - legs[1].x + legs[1].y

	# arms and trunk
	var arm_amp := deg_to_rad(p.get_value("arm_swing")) if p.is_on("fx_arm_swing") else 0.0
	var arm_off := deg_to_rad(p.get_value("arm_phase"))
	var arm_l := -arm_amp * cos(TAU * q_left + arm_off) * g
	var arm_r := arm_amp * cos(TAU * q_left + arm_off) * g
	var elbow_base := deg_to_rad(p.get_value("elbow_bend")) if p.is_on("fx_elbow_bend") else 0.0
	var norm_l := clampf(arm_l / maxf(arm_amp, 1e-4), -1.0, 1.0)
	var norm_r := clampf(arm_r / maxf(arm_amp, 1e-4), -1.0, 1.0)
	var counter := deg_to_rad(p.get_value("shoulder_counter")) * cos(TAU * q_left) * g if p.is_on("fx_shoulder_counter") else 0.0

	var dsup := clampf(2.0 * c.d - 1.0, 0.0, 1.0)
	return {
		"active": true, "phase": q_left, "speed": c.v, "gait_amount": g,
		"step_length": c.step_len, "stride_length": c.stride, "stride_time": 1.0 / c.rate if c.rate > 1e-6 else INF,
		"cadence": 120.0 * c.rate, "duty": c.d, "double_support": dsup,
		"thigh_l": legs[0].x, "knee_l": legs[0].y, "foot_l": foot_l,
		"thigh_r": legs[1].x, "knee_r": legs[1].y, "foot_r": foot_r,
		"ankle_l": al, "ankle_r": ar,
		"contact_l": q_left < c.d, "contact_r": q_right < c.d,
		"stance_l": q_left / c.d if q_left < c.d else -1.0, "stance_r": q_right / c.d if q_right < c.d else -1.0,
		"pelvis": Vector3(sway, y, 0.0), "pelvis_q": pelvis_q, "pelvis_yaw": yaw, "pelvis_tilt": tilt,
		"reach_assist": assist, "y_target": y_target,
		"chest_yaw": counter, "torso_lean": deg_to_rad(p.get_value("torso_lean")) * g,
		"arm_l": arm_l, "arm_r": arm_r,
		"elbow_l": elbow_base * (1.0 + 0.5 * norm_l), "elbow_r": elbow_base * (1.0 + 0.5 * norm_r),
	}
