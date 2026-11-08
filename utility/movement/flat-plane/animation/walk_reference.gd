## Approximate landmarks read from the user's 2026-11-07 walk strip (1118 x 423 pixels).
## These are a 2D fitting guide, not motion capture: perspective and occlusion make the two feet's apparent floors differ.
extends RefCounted

const PHASES := [0.0, 0.125, 0.25, 0.375]
const LABELS := ["Contact", "Down", "Passing", "Up"]
const HIPS := [Vector2(980, 232), Vector2(752, 236), Vector2(537, 225), Vector2(358, 218)]
const SHOULDERS := [Vector2(974, 127), Vector2(750, 129), Vector2(531, 125), Vector2(351, 121)]
const STANCE_KNEES := [Vector2(940, 301), Vector2(712, 304), Vector2(516, 295), Vector2(367, 290)]
const STANCE_ANKLES := [Vector2(919, 359), Vector2(713, 365), Vector2(535, 363), Vector2(393, 358)]
const SWING_KNEES := [Vector2(1018, 293), Vector2(783, 299), Vector2(509, 291), Vector2(322, 283)]
const SWING_ANKLES := [Vector2(1057, 355), Vector2(839, 345), Vector2(582, 338), Vector2(336, 359)]
const LEG_PIXELS := 146.0 # mean projected thigh + shin across the eight visible legs
const ARM_DEGREES := [
	Vector3(38, 30, 0), Vector3(30, 34, 0), Vector3(0, 12, 0), Vector3(-34, 16, 0),
	Vector3(-38, 14, 0), Vector3(-30, 16, 0), Vector3(0, 12, 0), Vector3(34, 34, 0),
]


## Forward progress between the trailing Down ankle and the next Contact ankle, after aligning each frame at the hips.
static func swing_progress(index: int) -> float:
	var start: float = HIPS[1].x - SWING_ANKLES[1].x
	var finish: float = HIPS[0].x - STANCE_ANKLES[0].x
	var point: float = HIPS[index].x - SWING_ANKLES[index].x
	return (point - start) / (finish - start)


## Fit the two-step hip wave to the four measured heights. Zero at Contact, unit peak-to-peak excursion.
static func hip_wave(q: float) -> float:
	var a: float = (HIPS[2].y - HIPS[0].y) * 0.5
	var b: float = (HIPS[3].y - HIPS[1].y) * 0.5
	return (a * cos(4.0 * PI * q) + b * sin(4.0 * PI * q) - a) / (2.0 * Vector2(a, b).length())


## Quintic Hermite with derivatives expressed over this segment (C2 when adjacent segments share derivatives).
static func hermite(p0: Vector3, p1: Vector3, v0: Vector3, v1: Vector3, a0: Vector3, a1: Vector3, s: float) -> Vector3:
	var s2 := s * s
	var s3 := s2 * s
	var s4 := s3 * s
	var s5 := s4 * s
	return p0 * (1.0 - 10.0 * s3 + 15.0 * s4 - 6.0 * s5) + v0 * (s - 6.0 * s3 + 8.0 * s4 - 3.0 * s5) \
		+ a0 * (0.5 * s2 - 1.5 * s3 + 1.5 * s4 - 0.5 * s5) + p1 * (10.0 * s3 - 15.0 * s4 + 6.0 * s5) \
		+ v1 * (-4.0 * s3 + 7.0 * s4 - 3.0 * s5) + a1 * (0.5 * s3 - s4 + 0.5 * s5)


static func arm(q: float) -> Vector2:
	var position := fposmod(q, 1.0) * 8.0
	var i := int(position)
	var p0: Vector3 = ARM_DEGREES[i]
	var p1: Vector3 = ARM_DEGREES[(i + 1) % 8]
	var prev: Vector3 = ARM_DEGREES[(i + 7) % 8]
	var next: Vector3 = ARM_DEGREES[(i + 2) % 8]
	var value := hermite(p0, p1, _arm_tangent(prev, p0, p1), _arm_tangent(p0, p1, next),
		Vector3.ZERO, Vector3.ZERO, position - i)
	return Vector2(value.x / 38.0, value.y / 20.0)


static func _arm_tangent(before: Vector3, point: Vector3, after: Vector3) -> Vector3:
	var a := point - before
	var b := after - point
	var tangent := Vector3.ZERO
	for axis in 2:
		if a[axis] * b[axis] > 0.0:
			tangent[axis] = 2.0 * a[axis] * b[axis] / (a[axis] + b[axis])
	return tangent
