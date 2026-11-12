## Canonical bone set of the Vitruvian rig.
##
## The 23 animation bones are Godot's SkeletonProfileHumanoid body bones: same names, same parents and the same
## global rest orientations as the profile's reference pose. Any clip imported with Godot's humanoid BoneMap and
## rest normalisation (the importer's default "overwrite axis") therefore plays on this rig with no rotation
## conversion. Six leaf twist helpers hang off the limbs; they are never inside a humanoid chain, so they cannot
## change what an animation track means.
##
## Convention (identical to the profile): character faces +Z, its left is +X, up is +Y, metres. In T-pose every
## local rotation equals the rest rotation.
extends RefCounted

const BODY := [
	"Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]

## name -> [parent, fraction along the parent segment, bone whose twist it samples, share of that twist]
## UpperArm/UpperLeg helpers sit near the proximal joint and counter-rotate half of their parent's own twist (keeps the
## shoulder / hip deformation stable). The forearm helper carries half of the hand's twist relative to the forearm:
## pronation and supination happen along the forearm (radius around ulna), not at the wrist.
const HELPERS := {
	"LeftUpperArmTwist": ["LeftUpperArm", 0.3, "LeftUpperArm", -0.5],
	"LeftLowerArmTwist": ["LeftLowerArm", 0.6, "LeftHand", 0.5],
	"LeftUpperLegTwist": ["LeftUpperLeg", 0.3, "LeftUpperLeg", -0.5],
	"RightUpperArmTwist": ["RightUpperArm", 0.3, "RightUpperArm", -0.5],
	"RightLowerArmTwist": ["RightLowerArm", 0.6, "RightHand", 0.5],
	"RightUpperLegTwist": ["RightUpperLeg", 0.3, "RightUpperLeg", -0.5],
}

## Region of each animation bone (used by colours, the body plan and future partial ragdoll masks).
const REGION := {
	"Root": "root", "Hips": "pelvis", "Spine": "spine", "Chest": "spine", "UpperChest": "spine",
	"Neck": "neck", "Head": "head",
	"LeftShoulder": "left_arm", "LeftUpperArm": "left_arm", "LeftLowerArm": "left_arm", "LeftHand": "left_arm",
	"RightShoulder": "right_arm", "RightUpperArm": "right_arm", "RightLowerArm": "right_arm", "RightHand": "right_arm",
	"LeftUpperLeg": "left_leg", "LeftLowerLeg": "left_leg", "LeftFoot": "left_leg", "LeftToes": "left_leg",
	"RightUpperLeg": "right_leg", "RightLowerLeg": "right_leg", "RightFoot": "right_leg", "RightToes": "right_leg",
}

static var _profile_bases := {}
static var _profile_parents := {}


static func all_bones() -> Array:
	var out := BODY.duplicate()
	out.append_array(HELPERS.keys())
	return out


static func side(bone: String) -> String:
	if bone.begins_with("Left"):
		return "L"
	if bone.begins_with("Right"):
		return "R"
	return "C"


static func mirror_name(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.substr(4)
	if bone.begins_with("Right"):
		return "Left" + bone.substr(5)
	return bone


static func is_helper(bone: String) -> bool:
	return HELPERS.has(bone)


## Global (model-space) rest basis of every profile bone, accumulated from SkeletonProfileHumanoid's reference poses.
static func profile_bases() -> Dictionary:
	if _profile_bases.is_empty():
		var profile := SkeletonProfileHumanoid.new()
		for i in profile.bone_size:
			var name := String(profile.get_bone_name(i))
			var parent := String(profile.get_bone_parent(i))
			var local := profile.get_reference_pose(i).basis
			_profile_bases[name] = local if parent == "" else (_profile_bases[parent] as Basis) * local
			_profile_parents[name] = parent
	return _profile_bases


static func profile_parents() -> Dictionary:
	profile_bases()
	return _profile_parents
