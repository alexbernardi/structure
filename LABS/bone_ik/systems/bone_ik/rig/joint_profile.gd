## Anatomical joint profile: loads data/joint_limits.json, mirrors the left side onto the right, and binds every
## joint to a rig definition (its rest frames). Converts between a bone's local pose rotation (what Skeleton3D and
## AnimationPlayer store) and anatomical angles (flex, abd, twist), and clamps poses to the hard limits.
##
## Joint motion, in the parent's rest-aligned model frame:   A = Pr * (L * L0^-1) * Pr^-1,   M = A * N^-1
##   L  = current local pose rotation, L0 = rest local rotation, Pr = parent's global rest rotation,
##   N  = rest -> anatomical neutral (identity except the shoulder, whose neutral is the hanging arm).
## M is split by joint_math.decompose about the anatomical frame (t, f, a). Because A is expressed relative to the
## proximal segment, the angles do not depend on how the rest of the body is posed.
extends RefCounted

const JointMath = preload("res://systems/bone_ik/rig/joint_math.gd")
const Humanoid = preload("res://systems/bone_ik/rig/humanoid.gd")
const DATA_PATH := "res://systems/bone_ik/data/joint_limits.json"
const AXES := ["flex", "abd", "twist"]

var spec := {}          ## parsed JSON (with mirrored right-side entries added)
var joints: Array = []  ## bound joints, parents before children
var by_bone := {}       ## bone name -> joint


static func load_spec(path := DATA_PATH) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("joints"):
		push_error("joint profile %s is not valid JSON" % path)
		return {}
	var mirrored := {}
	for name in data.joints:
		if String(name).begins_with("Left"):
			mirrored[Humanoid.mirror_name(name)] = mirror_entry(data.joints[name])
	for name in mirrored:
		data.joints[name] = mirrored[name]
	return data


## Mirror across the sagittal plane. Rotation axes are axial vectors: under the reflection x -> -x they map to
## (x, -y, -z). The twist keyword flips because "distal" on the left becomes the opposite rotation sense on the right.
static func mirror_entry(entry: Dictionary) -> Dictionary:
	var out := entry.duplicate(true)
	out.flex_axis = _mirror_axis(entry.flex_axis)
	out.abd_axis = _mirror_axis(entry.abd_axis)
	out.twist_axis = "proximal" if entry.twist_axis == "distal" else "distal"
	if entry.has("neutral"):
		out.neutral.axis = _mirror_axis(entry.neutral.axis)
	out.mirrored_from = "left"
	return out


static func _mirror_axis(a: Array) -> Array:
	return [a[0], -a[1], -a[2]]


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _init(definition := {}, path := DATA_PATH) -> void:
	spec = load_spec(path)
	if not definition.is_empty():
		bind(definition)


## Binds the profile to a rig definition (rig_builder.build output). Joints whose bone is absent are skipped.
func bind(definition: Dictionary) -> void:
	joints.clear()
	by_bone.clear()
	for bone in definition.bones:
		if not spec.joints.has(bone.name):
			continue
		var e: Dictionary = spec.joints[bone.name]
		var parent: Dictionary = definition.bones[bone.parent_index]
		var neutral := Quaternion.IDENTITY
		if e.has("neutral"):
			neutral = Quaternion(_vec(e.neutral.axis).normalized(), deg_to_rad(e.neutral.angle))
		var d_rest: Vector3 = (bone.tip - bone.global.origin).normalized()
		var t: Vector3 = (neutral * d_rest).normalized() * (1.0 if e.twist_axis == "distal" else -1.0)
		var f := _vec(e.flex_axis)
		f = (f - t * f.dot(t)).normalized()
		var a := _vec(e.abd_axis)
		a = (a - t * a.dot(t) - f * a.dot(f)).normalized()
		var limits := {}
		var limits_deg := {}
		for k in AXES:
			limits_deg[k] = {"soft": Vector2(e[k].soft[0], e[k].soft[1]), "hard": Vector2(e[k].hard[0], e[k].hard[1])}
			limits[k] = {"soft": limits_deg[k].soft * (PI / 180.0), "hard": limits_deg[k].hard * (PI / 180.0)}
		var j := {
			"bone": bone.name, "bone_index": definition.index[bone.name], "parent": parent.name,
			"type": e.type, "region": e.region, "labels": e.labels, "sources": e.sources, "notes": e.get("notes", ""),
			"t": t, "f": f, "a": a, "given_f": _vec(e.flex_axis), "given_a": _vec(e.abd_axis),
			"neutral": neutral, "neutral_inv": neutral.inverse(),
			"parent_rest": parent.global.basis.get_rotation_quaternion(),
			"rest_local": bone.local.basis.get_rotation_quaternion(),
			"d_rest": d_rest, "limits": limits, "limits_deg": limits_deg,
			"dynamics": e.get("dynamics", {"stiffness": null, "damping": null, "max_torque_nm": null}),
			"axis_local": (bone.global.basis.inverse() * d_rest).normalized(),   # own long axis, own frame
		}
		joints.append(j)
		by_bone[bone.name] = j


## Limb pairs aligned before the limits: [parent, child, kind]. Hinges first (they change the forearm's local
## rotation), then the forearm-rotation transfer from the hand.
const AXIAL_PAIRS := [
	["LeftUpperArm", "LeftLowerArm", "hinge"], ["RightUpperArm", "RightLowerArm", "hinge"],
	["LeftUpperLeg", "LeftLowerLeg", "hinge"], ["RightUpperLeg", "RightLowerLeg", "hinge"],
	["LeftLowerArm", "LeftHand", "forearm"], ["RightLowerArm", "RightHand", "forearm"],
]


## Hinge alignment (lossless): authored rigs often rotate the forearm or shin about the upper arm / thigh axis
## instead of rolling the upper arm / thigh. Writing the hinge motion as M = R(pd, alpha) * R(f, theta) * R(t, phi)
## (pd = the parent segment's long axis), the alpha part is moved to the parent's own axial roll. Every joint
## position is unchanged; the hinge keeps only flexion and its own axial rotation. The bending plane is ambiguous
## by 180 degrees (flexion theta with alpha, or -theta with alpha - 180), and undefined for a straight limb, where
## the roll can be split freely between the two segments (authored rigs sometimes differ by a full turn there).
## Candidates are the two plane readings plus every 15 degrees; the one with the smallest total hard-limit excess
## of both joints wins (ties: the smaller transfer). -> {parent, child, alpha}
static func align_hinge(p: Dictionary, c: Dictionary, parent_local: Quaternion, child_local: Quaternion) -> Dictionary:
	var m := motion(c, child_local)
	var pd: Vector3 = p.d_rest
	var u: Vector3 = (c.f as Vector3).cross(pd).normalized()   # where +flexion moves the distal segment
	var v := m * pd
	var v_perp := v - pd * v.dot(pd)
	var best := {"parent": parent_local, "child": child_local, "alpha": 0.0, "cost": INF}
	var candidates := [0.0]
	if v_perp.length() > 1e-4:
		var alpha := atan2(v_perp.dot(pd.cross(u)), v_perp.dot(u))
		candidates = [alpha, alpha - signf(alpha) * PI]
	best = _best_roll(p, c, parent_local, child_local, candidates, best)
	if best.cost > 1e-3:   # the cheap readings still violate a limit: search the roll split (rare, about 13x the cost)
		var grid := []
		for k in range(-11, 13):
			grid.append(k * PI / 12.0)
		best = _best_roll(p, c, parent_local, child_local, grid, best)
	best.erase("cost")
	return best


static func _best_roll(p: Dictionary, c: Dictionary, lp0: Quaternion, lc0: Quaternion, candidates: Array, best: Dictionary) -> Dictionary:
	for a in candidates:
		var q := Quaternion(p.axis_local, a)
		var lp := (lp0 * q).normalized()
		var lc := (q.inverse() * lc0).normalized()
		var cost: float = JointMath.limit_state(angles(p, lp), p.limits).hard + JointMath.limit_state(angles(c, lc), c.limits).hard
		cost += absf(a) * 1e-4   # tie-break: the smaller transfer
		if cost < best.cost:
			best = {"parent": lp, "child": lc, "alpha": a, "cost": cost}
	return best


## Forearm-rotation transfer (lossless): many rigs store pronation / supination on the hand bone. The hand motion's
## twist about the forearm axis is moved to the forearm's own roll (where the radius turns around the ulna); the
## hand keeps a pure swing (flexion and deviation). -> {parent, child, alpha}
static func align_forearm(p: Dictionary, c: Dictionary, parent_local: Quaternion, child_local: Quaternion) -> Dictionary:
	var m := motion(c, child_local)
	var pd: Vector3 = p.d_rest
	var tw: Quaternion = JointMath.swing_twist(m, pd)[1]
	var phi := JointMath.twist_angle(tw, pd)
	if absf(phi) < 1e-7:
		return {"parent": parent_local, "child": child_local, "alpha": 0.0}
	var q := Quaternion(p.axis_local, phi)
	return {"parent": (parent_local * q).normalized(), "child": (q.inverse() * child_local).normalized(), "alpha": phi}


## Applies every AXIAL_PAIRS alignment to `locals` (bone index -> local rotation; missing bones are read from
## `fallback`, a Callable(index) -> Quaternion). -> {locals: updated dictionary, transfers: {child bone: radians}}
func align_axial(locals: Dictionary, fallback: Callable, hinges := true, forearms := true) -> Dictionary:
	var out := locals.duplicate()
	var transfers := {}
	for pair in AXIAL_PAIRS:
		if (pair[2] == "hinge" and not hinges) or (pair[2] == "forearm" and not forearms):
			continue
		var p: Dictionary = joint(pair[0])
		var c: Dictionary = joint(pair[1])
		if p.is_empty() or c.is_empty():
			continue
		var lp: Quaternion = out[p.bone_index] if out.has(p.bone_index) else fallback.call(p.bone_index)
		var lc: Quaternion = out[c.bone_index] if out.has(c.bone_index) else fallback.call(c.bone_index)
		var r := align_hinge(p, c, lp, lc) if pair[2] == "hinge" else align_forearm(p, c, lp, lc)
		out[p.bone_index] = r.parent
		out[c.bone_index] = r.child
		transfers[pair[1]] = r.alpha
	return {"locals": out, "transfers": transfers}


## Joint motion M (model frame of the proximal segment, measured from anatomical neutral) of a local rotation.
static func motion(j: Dictionary, local: Quaternion) -> Quaternion:
	var pr: Quaternion = j.parent_rest
	var a: Quaternion = pr * (local * (j.rest_local as Quaternion).inverse()) * pr.inverse()
	return (a * j.neutral_inv).normalized()


## Local rotation -> Vector3(flex, abd, twist) in radians.
static func angles(j: Dictionary, local: Quaternion) -> Vector3:
	return JointMath.decompose(motion(j, local), j.t, j.f, j.a)


## Vector3(flex, abd, twist) radians -> local rotation.
static func local_from_angles(j: Dictionary, ang: Vector3) -> Quaternion:
	var m := JointMath.compose(ang, j.t, j.f, j.a)
	var pr: Quaternion = j.parent_rest
	return (pr.inverse() * (m * j.neutral) * pr * j.rest_local).normalized()


## -> {local: clamped local rotation, angles: before, clamped: after, hard: radians beyond, soft: 0..1, axis}
static func clamp_local(j: Dictionary, local: Quaternion) -> Dictionary:
	var ang := angles(j, local)
	var state := JointMath.limit_state(ang, j.limits)
	var clamped := JointMath.clamp_angles(ang, j.limits)
	state.angles = ang
	state.clamped = clamped
	state.local = local if state.hard <= 1e-6 else local_from_angles(j, clamped)
	return state


func joint(bone: String) -> Dictionary:
	return by_bone.get(bone, {})
