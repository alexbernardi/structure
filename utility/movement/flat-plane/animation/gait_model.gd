## Procedural walk cycle driven by a phase, not by a sine wave per joint. It plans where each ANKLE goes, then solves the
## legs from that, so the feet can be made to behave like feet:
##   * stance: the foot is fixed to the ground and rolls heel -> flat -> toe. In the hips' frame it therefore moves
##     backwards at exactly the walking speed (the treadmill belt), whatever the other settings are;
##   * swing: a quintic Hermite path from the toe-off pose to the next heel-strike pose that leaves and lands moving
##     (velocity AND acceleration) like the stance foot, so there is no jolt where the two hand over, plus a clearance
##     bump and a floor under the sole;
##   * hips: a sinusoid at twice the stride frequency (highest over a stance leg, lowest at double support). When the
##     stride is too long for the legs the whole sinusoid is lowered by a constant amount computed once per setting, so
##     a planted foot is never pulled off the ground and the hip path stays a smooth sine (the amount is reported);
##   * legs: analytic two-bone IK in the sagittal plane for the rig's real bone lengths; the knee never locks fully
##     straight.
## One cycle = one full stride (left heel strike at phase 0, right at 0.5). Everything here is visual: it reads nothing of
## the physics and gives the physics nothing.
##
## Frame of the planned points: x forward (the direction of walking), y up, origin at the pelvis' ground projection.
## Angles: positive foot pitch = toes up; leg angles use the skeleton's convention (positive rotation about X swings a
## hanging limb forward). Units are metres, seconds, radians.
extends RefCounted

const Visual = preload("res://character/character_visual.gd")
const RigParams = preload("res://animation/rig_params.gd")

## The original rig's dimensions (a rig parameter set with every value at its default gives the same numbers).
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
const LOWERING_SAMPLES := 32
const D := 2e-3                           ## step of the one-sided differences that hand the stance foot's motion to the swing

var p                       ## ParamSet of gait parameters (read live on every update)
var rig                     ## ParamSet of rig proportions, or null for the original rig
var phase := 0.0            ## 0..1, left heel strike at 0
var pose: Dictionary = {"active": false}
var cycle: Dictionary = {}  ## derived constants of the current settings (see cycle_for)

var _cache_key := -1
var _cache: Dictionary = {}


func _init(params, rig_params = null) -> void:
	p = params
	rig = rig_params


# ------------------------------------------------------------------ cycle constants

## Everything the foot planner needs for a given speed and the current parameters. Cached until a parameter or the speed changes.
func cycle_for(speed: float) -> Dictionary:
	var v := clampf(speed, 0.0, MAX_SPEED) if not is_nan(speed) else 0.0
	var key := hash([p.values.hash(), rig.values.hash() if rig != null else 0, snappedf(v, 1e-6)])
	if key == _cache_key and not _cache.is_empty():
		return _cache
	var dm := RigParams.dims(rig)
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
	var c := {
		"v": v, "step_len": step_len, "stride": stride, "d": duty, "roll": roll, "g": g, "dims": dm,
		"thigh": dm.thigh, "shin": dm.shin, "ankle_h": dm.ankle_h, "hip_x": dm.hip_x, "hip_drop": dm.hip_drop,
		"heel": dm.heel, "toe": dm.toe, "foot_len": dm.foot_len,
		"reach": _reach(dm.thigh, dm.shin, deg_to_rad(p.get_value("knee_min_flex"))),
		"q1": flat_at * duty, "q2": rise_at * duty,
		"th_h": deg_to_rad(p.get_value("heel_strike_angle")) * g if roll else 0.0,
		"th_t": deg_to_rad(p.get_value("toe_off_angle")) * g if roll else 0.0,
		"th_c": deg_to_rad(p.get_value("toe_clearance_angle")) * g if roll else 0.0,
		"hf0": stride * duty * 0.5 + dm.heel.x,   # world position of the heel while flat: puts mid stance under the hip
		"lift": clampf(v / 0.3, 0.0, 1.0) * float(p.get_value("step_height")),
		"vm": p.get_value("velocity_match"),
		"peak_k": clampf(log(0.5) / log(clampf(float(p.get_value("swing_peak")), 0.05, 0.95)), 0.3, 3.3),
		"rate": v / stride if stride > 1e-4 else 0.0,   # cycles per second
		"lower": 0.0,
	}
	c.lower = _lowering(c)
	_cache = c
	_cache_key = key
	return c


## The farthest an ankle can be from its hip when the knee is bent by at least `flex` radians.
static func _reach(thigh: float, shin: float, flex: float) -> float:
	return sqrt(maxf(thigh * thigh + shin * shin + 2.0 * thigh * shin * cos(flex), 0.0))


static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Quintic ease: value, slope and curvature are all zero at both ends, so a roll that uses it has no jolt at either end.
static func _smooth5(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


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
			th = c.th_h * (1.0 - _smooth5(q / maxf(c.q1, 1e-6)))
			pivot = 0
		elif q >= c.q2:
			th = -c.th_t * _smooth5((q - c.q2) / maxf(c.d - c.q2, 1e-6))
			pivot = 2
	if pivot == 0:
		var r := _rot(c.heel, th)
		return Vector3(c.hf0 - r.x - c.stride * q, -r.y, th)
	if pivot == 2:
		var r2 := _rot(c.toe, th)
		return Vector3(c.hf0 + c.foot_len - r2.x - c.stride * q, -r2.y, th)
	return Vector3(c.hf0 - c.heel.x - c.stride * q, c.ankle_h, th)


## Where the ground-contact point (the pivot) is, forward of the pelvis, while the foot is planted.
func contact_point(q: float, c: Dictionary) -> float:
	if c.roll and q >= c.q2:
		return c.hf0 + c.foot_len - c.stride * q
	return c.hf0 - c.stride * q


## First and second derivative (per cycle) of the stance path at its two ends, as one-sided second-order differences.
func _end_derivatives(c: Dictionary, at_end: bool) -> Array[Vector3]:
	if at_end:
		var q: float = c.d
		var f0 := stance(q, c)
		var f1 := stance(q - D, c)
		var f2 := stance(q - 2.0 * D, c)
		var f3 := stance(q - 3.0 * D, c)
		return [(3.0 * f0 - 4.0 * f1 + f2) / (2.0 * D), (2.0 * f0 - 5.0 * f1 + 4.0 * f2 - f3) / (D * D)]
	var g0 := stance(0.0, c)
	var g1 := stance(D, c)
	var g2 := stance(2.0 * D, c)
	var g3 := stance(3.0 * D, c)
	return [(-3.0 * g0 + 4.0 * g1 - g2) / (2.0 * D), (2.0 * g0 - 5.0 * g1 + 4.0 * g2 - g3) / (D * D)]


## Clearance bump over the swing, 0 at both ends (with zero slope and curvature there), 1 at the chosen peak time.
func swing_bump(s: float, c: Dictionary) -> float:
	return pow(maxf(sin(PI * pow(clampf(s, 0.0, 1.0), c.peak_k)), 0.0), 3.0)


## Ankle pose in the swing, q in [duty, 1).
func swing(q: float, c: Dictionary) -> Vector3:
	var s := clampf((q - c.d) / maxf(1.0 - c.d, 1e-6), 0.0, 1.0)
	var p0 := stance(c.d, c)
	var p1 := stance(0.0, c)   # the next heel strike: the cycle is periodic in the pelvis frame
	var span: float = 1.0 - c.d
	var vm: float = c.vm
	var e0 := _end_derivatives(c, true)
	var e1 := _end_derivatives(c, false)
	var v0: Vector3 = e0[0] * span * vm
	var a0: Vector3 = e0[1] * span * span * vm * vm
	var v1: Vector3 = e1[0] * span * vm
	var a1: Vector3 = e1[1] * span * span * vm * vm
	var s2 := s * s
	var s3 := s2 * s
	var s4 := s3 * s
	var s5 := s4 * s
	var out := p0 * (1.0 - 10.0 * s3 + 15.0 * s4 - 6.0 * s5) + v0 * (s - 6.0 * s3 + 8.0 * s4 - 3.0 * s5) \
		+ a0 * (0.5 * s2 - 1.5 * s3 + 1.5 * s4 - 0.5 * s5) + p1 * (10.0 * s3 - 15.0 * s4 + 6.0 * s5) \
		+ v1 * (-4.0 * s3 + 7.0 * s4 - 3.0 * s5) + a1 * (0.5 * s3 - s4 + 0.5 * s5)
	var bump := swing_bump(s, c)
	out.y += c.lift * bump
	out.z += c.th_c * bump
	return out


## Ankle pose for any phase of one foot (its own phase: 0 = its heel strike).
func ankle_at(q: float, c: Dictionary) -> Vector3:
	var a := stance(q, c) if q < c.d else swing(q, c)
	var low: float = a.y + minf(_rot(c.heel, a.z).y, _rot(c.toe, a.z).y)   # the lowest point of the sole
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
static func solve_leg(dx: float, dy: float, thigh_len := THIGH, shin_len := SHIN) -> Vector2:
	var d := clampf(sqrt(dx * dx + dy * dy), absf(thigh_len - shin_len) + 1e-3, thigh_len + shin_len - 1e-6)
	var cos_beta := clampf((thigh_len * thigh_len + d * d - shin_len * shin_len) / (2.0 * thigh_len * d), -1.0, 1.0)
	var cos_knee := clampf((thigh_len * thigh_len + shin_len * shin_len - d * d) / (2.0 * thigh_len * shin_len), -1.0, 1.0)
	var knee := PI - acos(cos_knee)
	var thigh := atan2(dx, -dy) + acos(cos_beta)
	return Vector2(thigh, knee)


## Forward kinematics of solve_leg (for tests and the overlay): ankle offset (forward, up) from the hip.
static func leg_reach(thigh: float, knee: float, thigh_len := THIGH, shin_len := SHIN) -> Vector2:
	var a := Vector2(sin(thigh) * thigh_len, -cos(thigh) * thigh_len)
	var b := Vector2(sin(thigh - knee) * shin_len, -cos(thigh - knee) * shin_len)
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


## Both ankles, the pelvis' rotation and the height the hips would like to be at, before the legs are solved.
func _frame(q_left: float, c: Dictionary) -> Dictionary:
	var g: float = c.g
	var al := ankle_at(q_left, c)
	var ar := ankle_at(fposmod(q_left + 0.5, 1.0), c)
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
	var y_target: float = c.ankle_h + c.hip_drop + float(p.get_value("stand_height")) * (c.thigh + c.shin) + bob - dip
	return {
		"al": al, "ar": ar, "sway": sway, "yaw": yaw, "tilt": tilt, "pelvis_q": pelvis_q, "y_target": y_target,
		"offs": [pelvis_q * Vector3(-c.hip_x, -c.hip_drop, 0.0), pelvis_q * Vector3(c.hip_x, -c.hip_drop, 0.0)],
	}


## The highest the hips may be at for foot k (0 left, 1 right) to stay reachable.
func _hip_limit(f: Dictionary, k: int, c: Dictionary) -> float:
	var a: Vector3 = f.al if k == 0 else f.ar
	var off: Vector3 = f.offs[k]
	var dx: float = a.x + off.z   # a hip is at -z forward of the pelvis origin
	var room := sqrt(maxf(c.reach * c.reach - dx * dx, 0.0))
	return a.y + room - off.y


## How far the whole hip path has to be lowered (a constant) so that no foot ever has to be pulled off the ground.
func _lowering(c: Dictionary) -> float:
	var worst := 0.0
	var qs: Array[float] = []
	for i in LOWERING_SAMPLES:
		qs.append(0.5 * float(i) / float(LOWERING_SAMPLES))   # the second half of the cycle is this one with the legs swapped
	for i in 12:
		qs.append(0.06 * float(i) / 12.0 + 0.003)             # extra care around heel strike, where the reach is greatest
	for q in qs:
		var f := _frame(q, c)
		for k in 2:
			worst = maxf(worst, f.y_target - _hip_limit(f, k, c))
	return worst + 0.002 if worst > 1e-9 else 0.0


## The complete pose for a phase with the current parameters and the speed of the last update.
func pose_at(q_left: float) -> Dictionary:
	var c := cycle
	if c.is_empty():
		c = cycle_for(0.0)
		cycle = c
	var g: float = c.g
	var q_right := fposmod(q_left + 0.5, 1.0)
	var f := _frame(q_left, c)
	var al: Vector3 = f.al
	var ar: Vector3 = f.ar
	var offs: Array = f.offs
	var ankles: Array[Vector3] = [al, ar]
	var y: float = f.y_target - c.lower
	# a last safety net for what the sampled lowering could miss; rounded so it cannot kink the path
	for k in 2:
		y = _soft_min(y, _hip_limit(f, k, c) - 0.002)
	var assist: float = f.y_target - y

	var legs: Array[Vector2] = []
	for k in 2:
		var dx: float = ankles[k].x + offs[k].z
		var dy: float = ankles[k].y - (y + offs[k].y)
		legs.append(solve_leg(dx, dy, c.thigh, c.shin))
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
		"pelvis": Vector3(f.sway, y, 0.0), "pelvis_q": f.pelvis_q, "pelvis_yaw": f.yaw, "pelvis_tilt": f.tilt,
		"reach_assist": assist, "y_target": f.y_target,
		"chest_yaw": counter, "torso_lean": deg_to_rad(p.get_value("torso_lean")) * g,
		"arm_l": arm_l, "arm_r": arm_r,
		"elbow_l": elbow_base * (1.0 + 0.5 * norm_l), "elbow_r": elbow_base * (1.0 + 0.5 * norm_r),
	}


## A minimum with a rounded corner (never above the true minimum): it only matters within a few millimetres of the limit.
static func _soft_min(a: float, b: float, k := 0.006) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25
