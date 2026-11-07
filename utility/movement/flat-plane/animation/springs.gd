## Reusable analytic springs: Scalar, Vector3 and Rotation (see spring_math.gd for the maths).
##
## Common behaviour
##  - frequency_hz / damping_ratio set the response; amplitude scales the goal (0 = ignore the input, 1 = follow it);
##  - target + target_velocity: the goal moves at target_velocity during each step (feed-forward, no tracking lag);
##    the stored target advances with it, so a target that moves at constant velocity needs no per-frame update;
##  - limits clamp the output and remove the velocity pushing into the limit (no wind-up);
##  - reset() / teleport() / shift() / snap() handle discontinuities (respawn, teleport, world shifts);
##  - precision: Scalar works in doubles (matches a 0.2 ms RK4 reference to ~1e-6 and is exact to ~1e-12 between tick rates);
##    Vector and Rotation hold Godot's single-precision Vector3 / Quaternion, so they are accurate to ~1e-6 per step
##    (round-off accumulates to ~1e-5 over hundreds of steps and stays bounded);
##  - non-finite inputs are rejected (counted in rejected_inputs), non-finite state self-heals by snapping to the goal,
##    and dt is clamped to [0, MAX_DT], so a hitch or a bad value can never blow the spring up.
extends RefCounted

const Math = preload("res://animation/spring_math.gd")

const MAX_DT := 1.0


class Scalar:
	extends RefCounted
	var frequency_hz := 3.0
	var damping_ratio := 1.0
	var amplitude := 1.0
	var min_value := -INF
	var max_value := INF
	var max_speed := INF
	var x := 0.0
	var v := 0.0
	var target := 0.0
	var target_velocity := 0.0
	var rejected_inputs := 0

	var _p := PackedFloat64Array([1.0, 0.0, 0.0, 1.0])
	var _pf := NAN
	var _pz := NAN
	var _pdt := NAN

	func _init(freq := 3.0, zeta := 1.0, start := 0.0) -> void:
		frequency_hz = freq
		damping_ratio = zeta
		x = start
		target = start

	## Returns false (and keeps the old goal) if a value is not finite.
	func set_target(g: float, q := 0.0) -> bool:
		if not Math.is_finite_f(g) or not Math.is_finite_f(q):
			rejected_inputs += 1
			return false
		target = g
		target_velocity = q
		return true

	func effective_target() -> float:
		return target * amplitude

	func displacement() -> float:
		return x - effective_target()

	func step(dt: float) -> float:
		if not Math.is_finite_f(dt):
			rejected_inputs += 1
			return x
		dt = clampf(dt, 0.0, MAX_DT)
		if dt <= 0.0:
			return x
		if not (Math.is_finite_f(x) and Math.is_finite_f(v)):
			snap()
		if dt != _pdt or frequency_hz != _pf or damping_ratio != _pz:
			_p = Math.propagator(frequency_hz, damping_ratio, dt)
			_pdt = dt
			_pf = frequency_hz
			_pz = damping_ratio
		var r := Math.step_scalar(x, v, target * amplitude, target_velocity * amplitude, _p, dt)
		x = r[0]
		v = r[1]
		target += target_velocity * dt
		_apply_limits()
		return x

	func _apply_limits() -> void:
		if x > max_value:
			x = max_value
			v = minf(v, 0.0)
		elif x < min_value:
			x = min_value
			v = maxf(v, 0.0)
		if is_finite(max_speed):
			v = clampf(v, -max_speed, max_speed)

	func reset(x0 := 0.0, v0 := 0.0) -> void:
		x = x0
		v = v0

	## Jump to a new value with no residual motion.
	func teleport(x_new: float) -> void:
		x = x_new
		v = 0.0

	## Move state and goal together (the world moved, not the spring's situation).
	func shift(delta: float) -> void:
		x += delta
		target += delta

	## Sit exactly on the goal, moving with it.
	func snap() -> void:
		x = effective_target()
		v = target_velocity * amplitude

	## Mechanical energy per unit mass relative to the goal: 0.5 r^2 + 0.5 k u^2.
	func energy() -> float:
		var w := TAU * frequency_hz
		var u := displacement()
		var r := v - target_velocity * amplitude
		return 0.5 * r * r + 0.5 * w * w * u * u


class Vector:
	extends RefCounted
	var frequency_hz := 3.0
	var damping_ratio := 1.0
	var amplitude := 1.0
	var limit_length := INF   ## maximum |x| (offset springs); outward velocity is removed at the limit
	var max_speed := INF
	var x := Vector3.ZERO
	var v := Vector3.ZERO
	var target := Vector3.ZERO
	var target_velocity := Vector3.ZERO
	var rejected_inputs := 0

	var _p := PackedFloat64Array([1.0, 0.0, 0.0, 1.0])
	var _pf := NAN
	var _pz := NAN
	var _pdt := NAN

	func _init(freq := 3.0, zeta := 1.0, start := Vector3.ZERO) -> void:
		frequency_hz = freq
		damping_ratio = zeta
		x = start
		target = start

	func set_target(g: Vector3, q := Vector3.ZERO) -> bool:
		if not Math.is_finite_v3(g) or not Math.is_finite_v3(q):
			rejected_inputs += 1
			return false
		target = g
		target_velocity = q
		return true

	func effective_target() -> Vector3:
		return target * amplitude

	func displacement() -> Vector3:
		return x - effective_target()

	func step(dt: float) -> Vector3:
		if not Math.is_finite_f(dt):
			rejected_inputs += 1
			return x
		dt = clampf(dt, 0.0, MAX_DT)
		if dt <= 0.0:
			return x
		if not (Math.is_finite_v3(x) and Math.is_finite_v3(v)):
			snap()
		if dt != _pdt or frequency_hz != _pf or damping_ratio != _pz:
			_p = Math.propagator(frequency_hz, damping_ratio, dt)
			_pdt = dt
			_pf = frequency_hz
			_pz = damping_ratio
		var g := target * amplitude
		var q := target_velocity * amplitude
		var u := x - g
		var r := v - q
		x = g + q * dt + u * _p[0] + r * _p[1]
		v = q + u * _p[2] + r * _p[3]
		target += target_velocity * dt
		_apply_limits()
		return x

	func _apply_limits() -> void:
		if is_finite(limit_length):
			var len := x.length()
			if len > limit_length:
				var n := x / len
				x = n * limit_length
				var outward := v.dot(n)
				if outward > 0.0:
					v -= n * outward
		if is_finite(max_speed) and v.length() > max_speed:
			v = v.normalized() * max_speed

	func reset(x0 := Vector3.ZERO, v0 := Vector3.ZERO) -> void:
		x = x0
		v = v0

	func teleport(x_new: Vector3) -> void:
		x = x_new
		v = Vector3.ZERO

	func shift(delta: Vector3) -> void:
		x += delta
		target += delta

	func snap() -> void:
		x = effective_target()
		v = target_velocity * amplitude

	func energy() -> float:
		var w := TAU * frequency_hz
		var u := displacement()
		var r := v - target_velocity * amplitude
		return 0.5 * r.length_squared() + 0.5 * w * w * u.length_squared()


class Rotation:
	extends RefCounted
	## Orientation spring on the rotation vector of the error (shortest arc, so goal and -goal are the same goal).
	## Exact for a static goal; for a moving goal it uses the usual small-error approximation of the reference.
	var frequency_hz := 3.0
	var damping_ratio := 1.0
	var amplitude := 1.0           ## scales the goal's rotation from `rest`: 0 = stay at rest, 1 = follow, 2 = exaggerate
	var rest := Quaternion.IDENTITY
	var max_angle := INF           ## maximum angle (rad) away from `rest`; outward angular velocity is removed
	var max_angular_speed := INF
	var q := Quaternion.IDENTITY   ## current orientation
	var w := Vector3.ZERO          ## angular velocity (rad/s, world frame)
	var goal := Quaternion.IDENTITY
	var goal_angular_velocity := Vector3.ZERO
	var rejected_inputs := 0

	var _p := PackedFloat64Array([1.0, 0.0, 0.0, 1.0])
	var _pf := NAN
	var _pz := NAN
	var _pdt := NAN

	func _init(freq := 3.0, zeta := 1.0, start := Quaternion.IDENTITY) -> void:
		frequency_hz = freq
		damping_ratio = zeta
		q = start
		goal = start

	func set_target(g: Quaternion, goal_w := Vector3.ZERO) -> bool:
		if not Math.is_finite_q(g) or g.length_squared() < 1e-12 or not Math.is_finite_v3(goal_w):
			rejected_inputs += 1
			return false
		goal = g.normalized()
		goal_angular_velocity = goal_w
		return true

	func effective_goal() -> Quaternion:
		return rest * Math.scale_rotation(rest.inverse() * goal, amplitude)

	## Remaining rotation from the goal as a vector (axis * angle), world frame.
	func error_vector() -> Vector3:
		return Math.rotation_vector(q * effective_goal().inverse())

	func angle_to_goal() -> float:
		return error_vector().length()

	func step(dt: float) -> Quaternion:
		if not Math.is_finite_f(dt):
			rejected_inputs += 1
			return q
		dt = clampf(dt, 0.0, MAX_DT)
		if dt <= 0.0:
			return q
		if not (Math.is_finite_q(q) and Math.is_finite_v3(w)) or q.length_squared() < 1e-12:
			snap()
		if dt != _pdt or frequency_hz != _pf or damping_ratio != _pz:
			_p = Math.propagator(frequency_hz, damping_ratio, dt)
			_pdt = dt
			_pf = frequency_hz
			_pz = damping_ratio
		var g := effective_goal()
		var gw := goal_angular_velocity * amplitude
		var u := Math.rotation_vector(q.normalized() * g.inverse())
		var r := w - gw
		var u2 := u * _p[0] + r * _p[1]
		var r2 := u * _p[2] + r * _p[3]
		var g2 := Math.rotation_from_vector(gw * dt) * g   # the goal keeps turning during the step
		q = (Math.rotation_from_vector(u2) * g2).normalized()
		w = r2 + gw
		goal = (Math.rotation_from_vector(goal_angular_velocity * dt) * goal).normalized()
		_apply_limits()
		return q

	func _apply_limits() -> void:
		if is_finite(max_angle):
			var away := Math.rotation_vector(q * rest.inverse())
			var angle := away.length()
			if angle > max_angle:
				var axis := away / angle
				q = Math.rotation_from_vector(axis * max_angle) * rest
				var outward := w.dot(axis)
				if outward > 0.0:
					w -= axis * outward
		if is_finite(max_angular_speed) and w.length() > max_angular_speed:
			w = w.normalized() * max_angular_speed

	func reset(q0 := Quaternion.IDENTITY, w0 := Vector3.ZERO) -> void:
		q = q0.normalized()
		w = w0

	func teleport(q_new: Quaternion) -> void:
		q = q_new.normalized()
		w = Vector3.ZERO

	## Rotate the state and the goal together (the character turned instantly; the spring's situation did not change).
	func shift(delta: Quaternion) -> void:
		q = (delta * q).normalized()
		goal = (delta * goal).normalized()
		w = delta * w
		goal_angular_velocity = delta * goal_angular_velocity

	func snap() -> void:
		q = effective_goal()
		w = goal_angular_velocity * amplitude


## Semi-implicit Euler with a fixed-frame update. Present ONLY so the diagnostic and the tests can show what the
## analytic springs avoid: it drifts at coarse timesteps and explodes once k dt^2 is large.
class NaiveEuler:
	extends RefCounted
	var frequency_hz := 3.0
	var damping_ratio := 1.0
	var x := 0.0
	var v := 0.0
	var target := 0.0
	var target_velocity := 0.0

	func _init(freq := 3.0, zeta := 1.0, start := 0.0) -> void:
		frequency_hz = freq
		damping_ratio = zeta
		x = start
		target = start

	func step(dt: float) -> float:
		var w := TAU * frequency_hz
		v += (-w * w * (x - target) - 2.0 * damping_ratio * w * (v - target_velocity)) * dt
		x += v * dt
		target += target_velocity * dt
		return x
