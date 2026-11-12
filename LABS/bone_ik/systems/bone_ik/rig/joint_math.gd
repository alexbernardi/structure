## Swing-twist joint angles.
##
## A joint motion M (a rotation in the proximal segment's frame) is split as M = swing * twist, where twist turns
## about the segment's long axis t and swing turns about an axis perpendicular to t. The swing is expressed as a
## rotation vector (axis * angle) and projected on two anatomical axes (flex, abd); twist is a signed angle about t.
## The three angles (flex, abd, twist) are therefore free of gimbal lock for any swing below 180 degrees, which is
## why ball joints (shoulder, hip) use this instead of Euler sequences. Angles are radians.
extends RefCounted

const EPS := 1e-9


## -> [swing: Quaternion, twist: Quaternion] with q = swing * twist and twist about `axis` (unit).
static func swing_twist(q: Quaternion, axis: Vector3) -> Array:
	var v := Vector3(q.x, q.y, q.z)
	var p := axis * v.dot(axis)
	var twist := Quaternion(p.x, p.y, p.z, q.w)
	if twist.length_squared() < EPS:
		twist = Quaternion.IDENTITY   # swing of exactly 180 degrees: twist is undefined, take none
	else:
		twist = twist.normalized()
	return [q * twist.inverse(), twist]


## Signed angle of a twist quaternion about `axis`, in (-PI, PI].
static func twist_angle(twist: Quaternion, axis: Vector3) -> float:
	var s := Vector3(twist.x, twist.y, twist.z).dot(axis)
	return wrapf(2.0 * atan2(s, twist.w), -PI, PI)


## Rotation vector (axis * angle, |angle| <= PI) of a rotation.
static func rotation_vector(q: Quaternion) -> Vector3:
	if q.w < 0.0:
		q = -q
	var v := Vector3(q.x, q.y, q.z)
	var s := v.length()
	if s < EPS:
		return v * 2.0
	return v / s * (2.0 * atan2(s, q.w))


static func from_rotation_vector(v: Vector3) -> Quaternion:
	var angle := v.length()
	if angle < EPS:
		return Quaternion.IDENTITY
	return Quaternion(v / angle, angle)


## M -> Vector3(flex, abd, twist). `t`, `f`, `a` are an orthonormal anatomical frame (twist, flex, abd axes).
static func decompose(m: Quaternion, t: Vector3, f: Vector3, a: Vector3) -> Vector3:
	var parts := swing_twist(m.normalized(), t)
	var s := rotation_vector(parts[0])
	return Vector3(s.dot(f), s.dot(a), twist_angle(parts[1], t))


static func compose(angles: Vector3, t: Vector3, f: Vector3, a: Vector3) -> Quaternion:
	return from_rotation_vector(f * angles.x + a * angles.y) * Quaternion(t, angles.z)


## Limits: {flex: {hard: Vector2(min, max), soft: Vector2}, abd: ..., twist: ...} in radians.
## Swing (flex, abd) is limited by an ellipse per quadrant (semi-axes = the limit on each side); twist by a range.
## Returns the nearest-direction point inside the hard limits (radial scaling in the swing plane).
static func clamp_angles(angles: Vector3, limits: Dictionary) -> Vector3:
	var out := angles
	var sw := _clamp_swing(Vector2(angles.x, angles.y), limits.flex.hard, limits.abd.hard)
	out.x = sw.x
	out.y = sw.y
	out.z = clampf(angles.z, limits.twist.hard.x, limits.twist.hard.y)
	return out


static func _clamp_swing(s: Vector2, fr: Vector2, ar: Vector2) -> Vector2:
	var fl := fr.y if s.x >= 0.0 else -fr.x
	var al := ar.y if s.y >= 0.0 else -ar.x
	if fl <= 1e-6 or al <= 1e-6:
		# Degenerate ellipse (a hinge side with no motion): clamp each component on its own.
		return Vector2(clampf(s.x, fr.x, fr.y), clampf(s.y, ar.x, ar.y))
	var r := (s.x / fl) * (s.x / fl) + (s.y / al) * (s.y / al)
	if r <= 1.0:
		return s
	return s / sqrt(r)


## How far a pose is past its limits, per axis kind. -> {hard: radians beyond the hard limit (0 = inside),
## soft: 0..1 progress from the soft limit to the hard limit (the future resistance input), axis: worst axis}.
static func limit_state(angles: Vector3, limits: Dictionary) -> Dictionary:
	var clamped := clamp_angles(angles, limits)
	var beyond := (angles - clamped).length()
	var soft_load := 0.0
	var worst := ""
	var keys := ["flex", "abd", "twist"]
	for i in 3:
		var v: float = angles[i]
		var lim: Dictionary = limits[keys[i]]
		var l := 0.0
		if v > lim.soft.y and lim.hard.y > lim.soft.y:
			l = (v - lim.soft.y) / (lim.hard.y - lim.soft.y)
		elif v < lim.soft.x and lim.hard.x < lim.soft.x:
			l = (lim.soft.x - v) / (lim.soft.x - lim.hard.x)
		l = clampf(l, 0.0, 1.0)
		if l > soft_load:
			soft_load = l
			worst = keys[i]
	return {"hard": beyond, "soft": soft_load, "axis": worst}
