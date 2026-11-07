## Closed-form spring mathematics. Pure static functions, no state, no nodes.
##
## The spring is  x'' = -k (x - g) - c (x' - q)  with natural frequency f (Hz), damping ratio z (dimensionless):
##     w = 2 pi f,   k = w^2,   c = 2 z w
## where g is the goal position and q the goal's velocity. Writing u = x - g and r = x' - q (error and relative
## velocity) the goal drops out and the system is the plain damped oscillator  u' = r,  r' = -k u - c r.
## Its state after any time dt is a fixed linear map:
##     u(dt) = a u + b r        r(dt) = m u + e r        -> propagator(f, z, dt) = [a, b, m, e]
## computed in closed form for every regime, so integration is exact (no timestep error, unconditionally stable) and a
## step of dt1 followed by dt2 equals one step of dt1 + dt2. The goal is assumed to move linearly at q during the step.
##
##   z < 1  underdamped: elastic overshoot, oscillation decaying as e^(-z w t)
##   z = 1  critically damped: fastest return without overshoot
##   z > 1  overdamped: slower return, no overshoot
##
## Reference: https://theorangeduck.com/page/spring-roll-call (exact damper, damping-ratio springs).
extends RefCounted

const EPS := 1e-12
## |w_d^2| below this fraction of (z w)^2 is treated as exactly critical (sinc / exp forms agree to ~1e-9 there).
const CRITICAL_BAND := 1e-9
const MAX_FREQUENCY_HZ := 1000.0
const MAX_DAMPING_RATIO := 1000.0
const LN2 := 0.6931471805599453


static func is_finite_f(x: float) -> bool:
	return not (is_nan(x) or is_inf(x))


static func is_finite_v3(v: Vector3) -> bool:
	return is_finite_f(v.x) and is_finite_f(v.y) and is_finite_f(v.z)


static func is_finite_q(q: Quaternion) -> bool:
	return is_finite_f(q.x) and is_finite_f(q.y) and is_finite_f(q.z) and is_finite_f(q.w)


## sin(x) / x without the 0/0 at x = 0.
static func sinc(x: float) -> float:
	if absf(x) < 1e-4:
		var x2 := x * x
		return 1.0 - x2 / 6.0 + x2 * x2 / 120.0
	return sin(x) / x


static func regime_name(damping_ratio: float) -> String:
	if damping_ratio < 1.0 - 1e-6:
		return "underdamped"
	if damping_ratio > 1.0 + 1e-6:
		return "overdamped"
	return "critically damped"


## Linear map of (error, relative velocity) over `dt`: PackedFloat64Array [a, b, m, e].
## `frequency_hz` and `damping_ratio` are clamped to sane ranges; dt <= 0 gives the identity.
static func propagator(frequency_hz: float, damping_ratio: float, dt: float) -> PackedFloat64Array:
	if dt <= 0.0 or not is_finite_f(dt):
		return PackedFloat64Array([1.0, 0.0, 0.0, 1.0])
	var f := clampf(frequency_hz if is_finite_f(frequency_hz) else 0.0, 0.0, MAX_FREQUENCY_HZ)
	var z := clampf(damping_ratio if is_finite_f(damping_ratio) else 1.0, 0.0, MAX_DAMPING_RATIO)
	var w := TAU * f
	var k := w * w
	var y := z * w   # half the damping coefficient
	var disc := k - y * y
	if k < EPS and y < EPS:
		return PackedFloat64Array([1.0, dt, 0.0, 1.0])   # no spring, no damper: free motion
	if disc >= -CRITICAL_BAND * y * y:
		# under- and critically damped: sinc form is smooth through w_d = 0
		var wd := sqrt(maxf(disc, 0.0))
		var s := dt * sinc(wd * dt)          # sin(wd dt) / wd
		var c := cos(wd * dt)
		var env := exp(-y * dt)
		return PackedFloat64Array([env * (c + y * s), env * s, -env * k * s, env * (c - y * s)])
	# overdamped: two real decay rates y0 > y1 with y0 * y1 = k (y1 from k / y0 avoids cancellation when k is small)
	var root := sqrt(-disc)
	var y0 := y + root
	var y1 := k / y0
	var delta := y0 - y1
	var e0 := exp(-y0 * dt)
	var e1 := exp(-y1 * dt)
	return PackedFloat64Array([(y0 * e1 - y1 * e0) / delta, (e1 - e0) / delta, k * (e0 - e1) / delta, (y0 * e0 - y1 * e1) / delta])


## One scalar step. Returns [x, v]. The goal (g, q) is taken at the START of the step and moves at q during it.
static func step_scalar(x: float, v: float, g: float, q: float, p: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var u := x - g
	var r := v - q
	return PackedFloat64Array([g + q * dt + p[0] * u + p[1] * r, q + p[2] * u + p[3] * r])


## Peak overshoot of a step response from rest as a fraction of the step: exp(-pi z / sqrt(1 - z^2)) for z < 1.
static func overshoot_fraction(damping_ratio: float) -> float:
	if damping_ratio >= 1.0:
		return 0.0
	if damping_ratio <= 0.0:
		return 1.0
	return exp(-PI * damping_ratio / sqrt(1.0 - damping_ratio * damping_ratio))


## Time of the first peak of an underdamped step response (seconds); INF if there is no overshoot.
static func peak_time(frequency_hz: float, damping_ratio: float) -> float:
	if damping_ratio >= 1.0 or frequency_hz <= 0.0:
		return INF
	return PI / (TAU * frequency_hz * sqrt(1.0 - damping_ratio * damping_ratio))


## Frequency (Hz) of a critically damped spring whose error envelope e^(-w t) halves every `halflife` seconds.
static func frequency_from_halflife(halflife: float) -> float:
	return LN2 / (TAU * maxf(halflife, 1e-6))


## Peak displacement of the impulse response (x(0) = 0, x'(0) = v0) in units of v0 / w. Multiply by v0 / w to get the
## largest excursion; use it the other way round to pick the velocity kick that produces a chosen excursion.
static func impulse_peak_factor(damping_ratio: float) -> float:
	var z := maxf(damping_ratio, 0.0)
	if z < 1e-9:
		return 1.0
	if z < 1.0 - 1e-9:
		var s := sqrt(1.0 - z * z)
		return exp(-z / s * atan2(s, z))
	if z < 1.0 + 1e-9:
		return exp(-1.0)
	var root := sqrt(z * z - 1.0)
	var r1 := z - root
	var r2 := z + root
	var t_peak := log(r2 / r1) / (r2 - r1)
	return (exp(-r1 * t_peak) - exp(-r2 * t_peak)) / (r2 - r1)


# ------------------------------------------------------------------ first-order exact damper (no oscillation)

## Fraction of the remaining distance kept after dt for a damper that halves the distance every `halflife` seconds.
static func damper_keep(halflife: float, dt: float) -> float:
	if dt <= 0.0:
		return 1.0
	return exp(-LN2 * dt / maxf(halflife, 1e-6))


static func damp_scalar(x: float, goal: float, halflife: float, dt: float) -> float:
	return goal + (x - goal) * damper_keep(halflife, dt)


static func damp_vector3(x: Vector3, goal: Vector3, halflife: float, dt: float) -> Vector3:
	return goal + (x - goal) * damper_keep(halflife, dt)


static func damp_quaternion(q: Quaternion, goal: Quaternion, halflife: float, dt: float) -> Quaternion:
	var err := rotation_vector(q * goal.inverse())
	return rotation_from_vector(err * damper_keep(halflife, dt)) * goal


# ------------------------------------------------------------------ rotations as 3-vectors (axis * angle, shortest arc)

## Rotation vector of a unit quaternion: axis * angle with angle in [0, pi] (the shortest of the two equivalent arcs).
static func rotation_vector(q: Quaternion) -> Vector3:
	var n := q.normalized()
	if n.w < 0.0:
		n = Quaternion(-n.x, -n.y, -n.z, -n.w)
	var v := Vector3(n.x, n.y, n.z)
	var s := v.length()
	if s < 1e-12:
		return v * 2.0
	return v / s * (2.0 * atan2(s, n.w))


static func rotation_from_vector(r: Vector3) -> Quaternion:
	var a := r.length()
	if a < 1e-12:
		return Quaternion(r.x * 0.5, r.y * 0.5, r.z * 0.5, 1.0).normalized()
	return Quaternion(r / a, a)


## Rotation scaled by `factor` along its axis: factor 0 = identity, 1 = unchanged, 2 = twice the angle.
static func scale_rotation(q: Quaternion, factor: float) -> Quaternion:
	return rotation_from_vector(rotation_vector(q) * factor)
