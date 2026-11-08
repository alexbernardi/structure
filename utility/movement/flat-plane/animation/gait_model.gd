## Procedural walk/run cycle driven by a phase, not by a sine wave per joint. It plans where each ANKLE goes, then solves the
## legs from that, so the feet can be made to behave like feet:
##   * stance: the foot is fixed to the ground and rolls heel -> flat -> toe. In the hips' frame it therefore moves
##     backwards at exactly the walking speed (the treadmill belt), whatever the other settings are. The ankle passes
##     under the hip at `midstance_at` of the stance (a little before half way), so the legs straddle the hips. The heel
##     rocker starts the moment the heel lands and the toe rocker is still turning at toe-off (`roll_flow`);
##   * swing: a quintic Hermite path from the toe-off pose to the next heel-strike pose that leaves and lands moving
##     (velocity AND acceleration) like the stance foot, so there is no jolt where the two hand over, plus a clearance
##     bump and a floor under the sole; the foot's rotation is always handed over whole;
##   * hips: a wave at twice the stride frequency (running compresses in support and rises in flight). When the
##     stride is too long for support the whole sinusoid is lowered by a constant amount computed once per setting.
##     Running swing feet recover within reach instead of lowering the body; planted feet stay on the ground;
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
const GaitParams = preload("res://animation/gait_params.gd")
const Reference = preload("res://animation/walk_reference.gd")

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
const RUN_REFERENCE_SPEED := 4.5
const RUN_STEP_EXPONENT := 0.65
const MAX_SPEED := 15.0
const LOWERING_SAMPLES := 32
const D := 2e-3                           ## step of the one-sided differences that hand the stance foot's motion to the swing
## Shape of the heel and toe rocker at roll_flow = 1 (slope and curvature at the contact end, in units of the roll interval).
const HEEL_ROCKER_SLOPE := 0.3
const HEEL_ROCKER_CURVE := 6.0
const TOE_ROCKER_SLOPE := 1.0
const TOE_ROCKER_CURVE := 2.0

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
	var running: bool = p.is_on("run_mode")
	var value := func(id: String) -> float: return p.get_value(GaitParams.profile_id(id, running))
	var step_len: float = value.call("step_length")
	if p.is_on("auto_step_length"):
		step_len *= pow(v / (RUN_REFERENCE_SPEED if running else REFERENCE_SPEED), RUN_STEP_EXPONENT if running else STEP_LENGTH_EXPONENT)
	step_len = clampf(step_len, 0.0, 2.4 if running else 1.6)
	var stride := 2.0 * step_len
	var roll: bool = p.is_on("foot_roll")
	var g := _smooth(v / 0.5)   # standing still: no roll, no lift, no body motion
	var duty: float = value.call("duty_factor")
	if running:
		duty = lerpf(float(p.get_value("duty_factor")), duty, g)
	var flat_at: float = p.get_value("foot_flat_at")
	var rise_at := maxf(float(p.get_value("heel_rise_at")), flat_at + 0.05)
	var c := {
		"v": v, "step_len": step_len, "stride": stride, "d": duty, "roll": roll, "g": g, "dims": dm, "running": running,
		"thigh": dm.thigh, "shin": dm.shin, "ankle_h": dm.ankle_h, "hip_x": dm.hip_x, "hip_drop": dm.hip_drop,
		"heel": dm.heel, "toe": dm.toe, "foot_len": dm.foot_len,
		"reach": _reach(dm.thigh, dm.shin, deg_to_rad(p.get_value("knee_min_flex"))),
		"q1": flat_at * duty, "q2": rise_at * duty,
		"th_h": deg_to_rad(p.get_value("heel_strike_angle")) * g if roll else 0.0,
		"th_t": deg_to_rad(p.get_value("toe_off_angle")) * g if roll else 0.0,
		"th_c": deg_to_rad(p.get_value("toe_clearance_angle")) * g if roll else 0.0,
		"flow": float(p.get_value("roll_flow")),
		# world position of the heel while flat: the ankle passes under the hip at this fraction of the stance
		"hf0": stride * duty * float(value.call("midstance_at")) + dm.heel.x,
		"lift": clampf(v / 0.3, 0.0, 1.0) * float(value.call("step_height")),
		"knee_drive": clampf(v / 0.3, 0.0, 1.0) * float(p.get_value("run_knee_drive")) if running else 0.0,
		"swing_forward": g * float(value.call("swing_forward")),
		"swing_peak": float(value.call("swing_peak")),
		"reference_fit": 1.0 if running else float(p.get_value("reference_fit")),
		"vm": p.get_value("velocity_match"),
		"peak_k": clampf(log(0.5) / log(clampf(float(value.call("swing_peak")), 0.05, 0.95)), 0.3, 3.3),
		"rate": v / stride if stride > 1e-4 else 0.0,   # cycles per second
		"lower": 0.0,
		# whole-body airborne rise, fading out with speed and as the flight interval closes
		"flight_lift": g * clampf((0.5 - duty) / 0.2, 0.0, 1.0) * float(p.get_value("run_flight_lift")) if running else 0.0,
	}
	c["swing_plan"] = _swing_plan(c)
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


## Quintic from 0 to 1 that starts with slope `s` and curvature `a` and ends at rest (zero slope and curvature).
## With s = a = 0 it is exactly _smooth5. Used for the foot roll: the contact end keeps the swing's motion going.
static func _roll_ease(u: float, s: float, a: float) -> float:
	var t := clampf(u, 0.0, 1.0)
	var t2 := t * t
	var t3 := t2 * t
	var t4 := t3 * t
	var t5 := t4 * t
	return (10.0 * t3 - 15.0 * t4 + 6.0 * t5) + s * (t - 6.0 * t3 + 8.0 * t4 - 3.0 * t5) \
		+ a * (0.5 * t2 - 1.5 * t3 + 1.5 * t4 - 0.5 * t5)


static func _rot(pt: Vector2, th: float) -> Vector2:
	var c := cos(th)
	var s := sin(th)
	return Vector2(pt.x * c - pt.y * s, pt.x * s + pt.y * c)


# ------------------------------------------------------------------ one foot

## Ankle pose while the foot is on the ground, q in [0, duty]: (forward, up, foot pitch). The point of the foot that
## touches the ground (heel, then the whole sole, then the toe) does not move in the world, only the pelvis does.
func stance(q: float, c: Dictionary) -> Vector3:
	var roll := _stance_roll(q, c)
	var th: float = roll[0]
	var pivot: int = roll[1]
	if pivot == 0:
		var r := _rot(c.heel, th)
		return Vector3(c.hf0 - r.x - c.stride * q, -r.y, th)
	if pivot == 2:
		var r2 := _rot(c.toe, th)
		return Vector3(c.hf0 + c.foot_len - r2.x - c.stride * q, -r2.y, th)
	return Vector3(c.hf0 - c.heel.x - c.stride * q, c.ankle_h, th)


## Foot pitch and the planted pivot (0 heel, 1 flat, 2 toe) at stance phase q.
func _stance_roll(q: float, c: Dictionary) -> Array:
	if c.roll:
		var flow: float = c.flow
		if q < c.q1:
			# heel rocker: the toe starts dropping the instant the heel lands (curvature, no hold) and settles flat softly
			return [c.th_h * (1.0 - _roll_ease(q / maxf(c.q1, 1e-6), HEEL_ROCKER_SLOPE * flow, HEEL_ROCKER_CURVE * flow)), 0]
		if q >= c.q2:
			# toe rocker: the heel lifts softly and the foot is still rotating when the toe leaves the ground
			return [-c.th_t * (1.0 - _roll_ease(1.0 - (q - c.q2) / maxf(c.d - c.q2, 1e-6), TOE_ROCKER_SLOPE * flow, TOE_ROCKER_CURVE * flow)), 2]
	return [0.0, 1]


## stance() without rounding to a single-precision Vector3, for differentiating over very small phase steps.
func _stance_exact(q: float, c: Dictionary) -> PackedFloat64Array:
	var roll := _stance_roll(q, c)
	var th: float = roll[0]
	var pivot: int = roll[1]
	if pivot == 1:
		return PackedFloat64Array([c.hf0 - c.heel.x - c.stride * q, c.ankle_h, th])
	var pt: Vector2 = c.heel if pivot == 0 else c.toe
	var rx: float = pt.x * cos(th) - pt.y * sin(th)
	var ry: float = pt.x * sin(th) + pt.y * cos(th)
	var base: float = c.hf0 if pivot == 0 else c.hf0 + c.foot_len
	return PackedFloat64Array([base - rx - c.stride * q, -ry, th])


## Where the ground-contact point (the pivot) is, forward of the pelvis, while the foot is planted.
func contact_point(q: float, c: Dictionary) -> float:
	if c.roll and q >= c.q2:
		return c.hf0 + c.foot_len - c.stride * q
	return c.hf0 - c.stride * q


## First and second derivative (per cycle) of the stance path at its two ends, as one-sided second-order differences.
func _end_derivatives(c: Dictionary, at_end: bool) -> Array[Vector3]:
	var h: float = D * (0.1 if c.running and c.v >= 0.5 else 1.0)
	if c.running:
		# Single-precision samples over such a small step would turn rounding into a handoff acceleration error large
		# enough to dip the toe into the belt just after toe-off.
		var dir := -1.0 if at_end else 1.0
		var q0: float = c.d if at_end else 0.0
		var f: Array[PackedFloat64Array] = []
		for k in 4:
			f.append(_stance_exact(q0 + dir * k * h, c))
		var vel := Vector3.ZERO
		var acc := Vector3.ZERO
		for j in 3:
			vel[j] = -dir * (3.0 * f[0][j] - 4.0 * f[1][j] + f[2][j]) / (2.0 * h)
			acc[j] = (2.0 * f[0][j] - 5.0 * f[1][j] + 4.0 * f[2][j] - f[3][j]) / (h * h)
		return [vel, acc]
	if at_end:
		var q: float = c.d
		var f0 := stance(q, c)
		var f1 := stance(q - h, c)
		var f2 := stance(q - 2.0 * h, c)
		var f3 := stance(q - 3.0 * h, c)
		return [(3.0 * f0 - 4.0 * f1 + f2) / (2.0 * h), (2.0 * f0 - 5.0 * f1 + 4.0 * f2 - f3) / (h * h)]
	var g0 := stance(0.0, c)
	var g1 := stance(h, c)
	var g2 := stance(2.0 * h, c)
	var g3 := stance(3.0 * h, c)
	return [(-3.0 * g0 + 4.0 * g1 - g2) / (2.0 * h), (2.0 * g0 - 5.0 * g1 + 4.0 * g2 - g3) / (h * h)]


## Clearance bump over the swing, 0 at both ends (with zero slope and curvature there), 1 at the chosen peak time.
func swing_bump(s: float, c: Dictionary) -> float:
	return pow(maxf(sin(PI * pow(clampf(s, 0.0, 1.0), c.peak_k)), 0.0), 3.0)


func _swing_plan(c: Dictionary) -> Dictionary:
	var p0 := stance(c.d, c)
	var p1 := stance(0.0, c)
	var span: float = 1.0 - c.d
	var vm := Vector3(c.vm, c.vm, 1.0)
	var e0 := _end_derivatives(c, true)
	var e1 := _end_derivatives(c, false)
	var times: Array[float] = [0.0, c.swing_peak, (1.0 + c.swing_peak) * 0.5, 1.0]
	if c.running:
		# Keep the rear leg long at Flight; the later knot folds the lead knee while keeping its ankle near the hips.
		times[2] = lerpf(c.swing_peak, 1.0, 0.76)
	var points: Array[Vector3] = [p0]
	for i in 2:
		var pitch: float = -c.th_t * (80.0 / 75.0 if i == 0 else 12.0 / 75.0)
		var progress := Reference.swing_progress(i + 2)
		var height: float = c.lift * (1.0 if i == 0 else 1.0 / 12.0)
		if c.running:
			pitch = -c.th_t * (0.85 if i == 0 else 0.08)
			progress = -0.18 if i == 0 else 1.0
			height = c.lift if i == 0 else c.knee_drive
		var floor_height := -minf(_rot(c.heel, pitch).y, _rot(c.toe, pitch).y)
		points.append(Vector3(lerpf(p0.x, p1.x, progress), floor_height + height, pitch))
	points.append(p1)
	var velocities: Array[Vector3] = [e0[0] * span * vm, Vector3.ZERO, Vector3.ZERO, e1[0] * span * vm]
	var accelerations: Array[Vector3] = [e0[1] * span * span, Vector3.ZERO, Vector3.ZERO, e1[1] * span * span]
	for i in [1, 2]:
		var before := times[i] - times[i - 1]
		var after := times[i + 1] - times[i]
		velocities[i] = (points[i + 1] - points[i - 1]) / (before + after)
		accelerations[i] = 2.0 * ((points[i + 1] - points[i]) / after - (points[i] - points[i - 1]) / before) / (before + after)
	if c.running:
		velocities[1].x *= 0.5   # the recovering heel lingers behind the hips, then the knee drives through
	var plan := {"times": times, "points": points, "velocities": velocities, "accelerations": accelerations, "clearance_lift": 0.0, "landing_clearance_lift": 0.0}
	# Rotating the toe between Passing and Up can put it below a straight interpolated ankle arc.
	# Lift that segment smoothly rather than relying on the hard sole floor (which would drag the toe and kink the knee).
	for sample in range(1, 32):
		var u := float(sample) / 32.0
		var point := _swing_segment(plan, 1, u)
		var s := lerpf(times[1], times[2], u)
		var pitch: float = point.z + c.th_c * swing_bump(s, c)
		var floor_height := -minf(_rot(c.heel, pitch).y, _rot(c.toe, pitch).y)
		var envelope := _clearance_envelope(u)
		plan.clearance_lift = maxf(plan.clearance_lift, (floor_height + minf(0.002, c.lift / 12.0) - point.y) / envelope)
	plan.clearance_lift = minf(plan.clearance_lift, c.lift) # zero-clearance edits may skim the floor, never generate a huge corrective arc
	if c.running:
		for sample in range(1, 32):
			var u := float(sample) / 32.0
			var point := _swing_segment(plan, 2, u)
			var s := lerpf(times[2], times[3], u)
			var pitch: float = point.z + c.th_c * swing_bump(s, c)
			var floor_height := -minf(_rot(c.heel, pitch).y, _rot(c.toe, pitch).y)
			var envelope := _clearance_envelope(u)
			# This segment ends with the heel on the belt, so the safety margin fades with the envelope; a fixed margin
			# divided by the vanishing envelope just before touchdown would demand a huge late lift and a stomping drop.
			plan.landing_clearance_lift = maxf(plan.landing_clearance_lift, (floor_height - point.y) / envelope + minf(0.002, c.lift / 12.0))
		plan.landing_clearance_lift = minf(plan.landing_clearance_lift, c.lift)
	return plan


static func _swing_segment(plan: Dictionary, i: int, u: float) -> Vector3:
	var span: float = plan.times[i + 1] - plan.times[i]
	return Reference.hermite(plan.points[i], plan.points[i + 1],
		plan.velocities[i] * span, plan.velocities[i + 1] * span,
		plan.accelerations[i] * span * span, plan.accelerations[i + 1] * span * span, u)


static func _clearance_envelope(u: float) -> float:
	# Peak late in the segment, where the descending toe needs room; C2-zero at both measured landmarks.
	return pow(1.5 * u, 6.0) * pow(3.0 * (1.0 - u), 3.0)


## Swing through walking Passing/Up or running heel-recovery/knee-drive knots, sharing stance derivatives at both ends.
func swing(q: float, c: Dictionary) -> Vector3:
	var s := clampf((q - c.d) / maxf(1.0 - c.d, 1e-6), 0.0, 1.0)
	var plan: Dictionary = c.swing_plan
	var pts: Array = plan.points
	var vel: Array = plan.velocities
	var acc: Array = plan.accelerations
	var out := Reference.hermite(pts[0], pts[3], vel[0], vel[3], acc[0], acc[3], s)
	var bump := swing_bump(s, c)
	out.y += c.lift * bump
	if c.reference_fit > 0.0:
		var i := 0 if s < plan.times[1] else (1 if s < plan.times[2] else 2)
		var span: float = plan.times[i + 1] - plan.times[i]
		var u: float = (s - plan.times[i]) / span
		var fitted := _swing_segment(plan, i, u)
		if i == 1:
			fitted.y += plan.clearance_lift * _clearance_envelope(u)
		elif i == 2 and c.running:
			fitted.y += plan.landing_clearance_lift * _clearance_envelope(u)
		out = out.lerp(fitted, c.reference_fit)
	# A cubic-zero envelope preserves both endpoint derivatives even with an early/late clearance peak.
	out.x += c.swing_forward * pow(s * (1.0 - s) / (c.swing_peak * (1.0 - c.swing_peak)), 3.0)
	out.z += c.th_c * bump
	return out


## Ankle pose for any phase of one foot (its own phase: 0 = its heel strike).
func ankle_at(q: float, c: Dictionary) -> Vector3:
	var a := stance(q, c) if q < c.d else swing(q, c)
	var low: float = a.y + minf(_rot(c.heel, a.z).y, _rot(c.toe, a.z).y)   # the lowest point of the sole
	if low < 0.0:
		a.y -= low
	if q >= c.d:
		a.y += flight_lift(q, c)
		if c.running:
			# An airborne foot can recover toward the hip; it must not pull the entire running cycle into a crouch.
			var body := _body_frame(q, c)
			var off: Vector3 = body.offs[0]
			var hip := Vector2(-off.z, body.y + off.y)
			var delta := Vector2(a.x, a.y) - hip
			var distance := delta.length()
			if distance > 1e-6:
				var blend := 0.010
				var h := maxf(blend - absf(distance - c.reach), 0.0) / blend
				var radius: float = minf(distance, c.reach) - blend * h * h * h / 6.0
				var reachable := hip + delta * (radius / distance)
				a.x = reachable.x
				a.y = reachable.y
				var floor_height := -minf(_rot(c.heel, a.z).y, _rot(c.toe, a.z).y)
				if a.y < floor_height:
					a.y = floor_height
					var dy := a.y - hip.y
					var room := sqrt(maxf(c.reach * c.reach - dy * dy, 0.0))
					a.x = hip.x + clampf(a.x - hip.x, -room, room)
	return a


## How far the whole body (hips and both feet) is raised while no foot touches the belt. The same for both feet and
## the pelvis at any moment, so the legs keep their shape; zero, with zero slope and curvature, at toe-off and landing.
func flight_lift(q: float, c: Dictionary) -> float:
	var height: float = c.get("flight_lift", 0.0)
	var span: float = 0.5 - c.d
	if height <= 0.0 or span <= 1e-6:
		return 0.0
	var u: float = (fposmod(q, 0.5) - c.d) / span
	if u <= 0.0 or u >= 1.0:
		return 0.0
	return height * 64.0 * pow(u * (1.0 - u), 3.0)


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
	var f := _body_frame(q_left, c)
	f["al"] = ankle_at(q_left, c)
	f["ar"] = ankle_at(fposmod(q_left + 0.5, 1.0), c)
	return f


func _body_frame(q_left: float, c: Dictionary) -> Dictionary:
	var g: float = c.g
	var bob := 0.0
	if p.is_on("fx_pelvis_bob"):
		var wave := lerpf(0.5 * (1.0 - cos(4.0 * PI * q_left)), Reference.hip_wave(q_left), c.reference_fit)
		if c.running:
			var loading_phase: float = c.d * 0.25
			wave = 0.5 * (cos(4.0 * PI * loading_phase) - cos(4.0 * PI * (q_left - loading_phase)))
		bob = float(p.get_value(GaitParams.profile_id("pelvis_bob", c.running))) * wave * g
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
	var y_target: float = c.ankle_h + c.hip_drop + float(p.get_value("stand_height")) * (c.thigh + c.shin) + bob - dip + flight_lift(q_left, c)
	var offs := [pelvis_q * Vector3(-c.hip_x, -c.hip_drop, 0.0), pelvis_q * Vector3(c.hip_x, -c.hip_drop, 0.0)]
	var y: float = y_target - c.lower
	if c.running:
		for k in 2:
			var q: float = q_left if k == 0 else fposmod(q_left + 0.5, 1.0)
			if q < c.d:
				y = _soft_min(y, _ankle_hip_limit(stance(q, c), offs[k], c) - 0.002)
	return {
		"sway": sway, "yaw": yaw, "tilt": tilt, "pelvis_q": pelvis_q, "y_target": y_target, "y": y, "offs": offs,
	}


## The highest the hips may be at for foot k (0 left, 1 right) to stay reachable.
func _hip_limit(f: Dictionary, k: int, c: Dictionary) -> float:
	var a: Vector3 = f.al if k == 0 else f.ar
	var off: Vector3 = f.offs[k]
	return _ankle_hip_limit(a, off, c)


func _ankle_hip_limit(a: Vector3, off: Vector3, c: Dictionary) -> float:
	var dx: float = a.x + off.z   # a hip is at -z forward of the pelvis origin
	var room := sqrt(maxf(c.reach * c.reach - dx * dx, 0.0))
	return a.y + room - off.y


## How far the whole hip path has to be lowered (a constant) so that no foot ever has to be pulled off the ground.
func _lowering(c: Dictionary) -> float:
	var worst := 0.0
	if c.running:
		for i in LOWERING_SAMPLES + 1:
			var q: float = c.d * float(i) / float(LOWERING_SAMPLES)
			var f := _body_frame(q, c)
			worst = maxf(worst, f.y_target - _ankle_hip_limit(stance(q, c), f.offs[0], c))
		return worst + 0.016 * c.g
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
	var y: float = f.y if c.running else f.y_target - c.lower
	# a last safety net for what the sampled lowering could miss; rounded so it cannot kink the path
	if not c.running:
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
	var arm_amp := deg_to_rad(p.get_value(GaitParams.profile_id("arm_swing", c.running))) if p.is_on("fx_arm_swing") else 0.0
	var arm_off := deg_to_rad(p.get_value("arm_phase"))
	var arm_angle := TAU * (q_left + (0.10 if c.running else 0.0)) + arm_off
	var arm_l := -arm_amp * cos(arm_angle) * g
	var arm_r := arm_amp * cos(arm_angle) * g
	var elbow_base := deg_to_rad(p.get_value(GaitParams.profile_id("elbow_bend", c.running))) if p.is_on("fx_elbow_bend") else 0.0
	var norm_l := clampf(arm_l / maxf(arm_amp, 1e-4), -1.0, 1.0)
	var norm_r := clampf(arm_r / maxf(arm_amp, 1e-4), -1.0, 1.0)
	var elbow_l := elbow_base * (1.0 + (0.12 if c.running else 0.5) * norm_l)
	var elbow_r := elbow_base * (1.0 + (0.12 if c.running else 0.5) * norm_r)
	var ref_l := Reference.arm(q_left + 0.5 + arm_off / TAU)
	var ref_r := Reference.arm(q_left + arm_off / TAU)
	var arm_fit: float = 0.0 if c.running else c.reference_fit
	arm_l = lerpf(arm_l, ref_l.x * arm_amp * g, arm_fit)
	arm_r = lerpf(arm_r, ref_r.x * arm_amp * g, arm_fit)
	elbow_l = lerpf(elbow_l, ref_l.y * elbow_base, arm_fit * g)
	elbow_r = lerpf(elbow_r, ref_r.y * elbow_base, arm_fit * g)
	var counter := deg_to_rad(p.get_value("shoulder_counter")) * cos(TAU * q_left) * g if p.is_on("fx_shoulder_counter") else 0.0

	var dsup := clampf(2.0 * c.d - 1.0, 0.0, 1.0)
	return {
		"active": true, "phase": q_left, "speed": c.v, "gait_amount": g, "running": c.running,
		"step_length": c.step_len, "stride_length": c.stride, "stride_time": 1.0 / c.rate if c.rate > 1e-6 else INF,
		"cadence": 120.0 * c.rate, "duty": c.d, "double_support": dsup,
		"flight_fraction": maxf(1.0 - 2.0 * c.d, 0.0), "flight": q_left >= c.d and q_right >= c.d,
		"thigh_l": legs[0].x, "knee_l": legs[0].y, "foot_l": foot_l,
		"thigh_r": legs[1].x, "knee_r": legs[1].y, "foot_r": foot_r,
		"ankle_l": al, "ankle_r": ar,
		"contact_l": q_left < c.d, "contact_r": q_right < c.d,
		"stance_l": q_left / c.d if q_left < c.d else -1.0, "stance_r": q_right / c.d if q_right < c.d else -1.0,
		"pelvis": Vector3(f.sway, y, 0.0), "pelvis_q": f.pelvis_q, "pelvis_yaw": f.yaw, "pelvis_tilt": f.tilt,
		"reach_assist": assist, "y_target": f.y_target,
		"chest_yaw": counter, "torso_lean": deg_to_rad(p.get_value(GaitParams.profile_id("torso_lean", c.running))) * g,
		"spine_curve": deg_to_rad(p.get_value("spine_curve")), "head_level": float(p.get_value("head_level")),
		"arm_l": arm_l, "arm_r": arm_r,
		"elbow_l": elbow_l, "elbow_r": elbow_r,
	}


## A minimum with a rounded corner (never above the true minimum): it only matters within a few millimetres of the limit.
static func _soft_min(a: float, b: float, k := 0.006) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25
