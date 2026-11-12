## Test helper: forward kinematics over a rig definition with some local rotations replaced (no nodes involved).
extends RefCounted

const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")


## overrides: bone name -> local rotation. -> {bone name: model-space Transform3D}
static func globals(definition: Dictionary, overrides := {}) -> Dictionary:
	var out := {}
	var list := []
	for bone in definition.bones:
		var local: Transform3D = bone.local
		if overrides.has(bone.name):
			local = Transform3D(Basis(overrides[bone.name]), local.origin)
		var g: Transform3D = local if bone.parent_index < 0 else list[bone.parent_index] * local
		list.append(g)
		out[bone.name] = g
	return out


## Model-space tip (end point) of a bone under the given pose.
static func tip(definition: Dictionary, g: Dictionary, bone: String) -> Vector3:
	var b: Dictionary = definition.bones[definition.index[bone]]
	return (g[bone] as Transform3D) * ((b.global as Transform3D).affine_inverse() * (b.tip as Vector3))


## Pose from anatomical angles in degrees: {bone: Vector3(flex, abd, twist)} -> {bone: local rotation}
static func pose(profile, degrees: Dictionary, clamp := false) -> Dictionary:
	var out := {}
	for bone in degrees:
		var j: Dictionary = profile.joint(bone)
		var q := JointProfile.local_from_angles(j, (degrees[bone] as Vector3) * (PI / 180.0))
		out[bone] = JointProfile.clamp_local(j, q).local if clamp else q
	return out
