## Sets up Godot's native humanoid import mapping. Run once, then reimport with --editor --import.
extends SceneTree

const DIRECTORY := "res://assets/quaternius/"
const CORE := {
	"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
	"Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftUpperArm": "upperarm_l", "LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightUpperArm": "upperarm_r", "RightLowerArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l", "LeftFoot": "foot_l", "LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r", "RightLowerLeg": "calf_r", "RightFoot": "foot_r", "RightToes": "ball_r",
}


func _initialize() -> void:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	for bone in CORE:
		map.set_skeleton_bone_name(bone, CORE[bone])
	for side in ["Left", "Right"]:
		var suffix := "l" if side == "Left" else "r"
		for finger in ["Thumb", "Index", "Middle", "Ring", "Little"]:
			var source_name: String = "pinky" if finger == "Little" else finger.to_lower()
			var segments := ["Metacarpal", "Proximal", "Distal"] if finger == "Thumb" else ["Proximal", "Intermediate", "Distal"]
			for i in 3:
				map.set_skeleton_bone_name(side + finger + segments[i], "%s_%02d_%s" % [source_name, i + 1, suffix])
	var error := ResourceSaver.save(map, DIRECTORY + "humanoid_map.tres")
	if error != OK:
		push_error("Cannot save Quaternius BoneMap: %s" % error_string(error))
		quit(1)
		return
	for file in ["UAL1_Standard.glb", "UAL1_Standard_RM.glb"]:
		var source: Node = load(DIRECTORY + file).instantiate()
		var skeleton: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
		var path := "PATH:" + String(source.get_path_to(skeleton))
		var config := ConfigFile.new()
		error = config.load(DIRECTORY + file + ".import")
		if error != OK:
			push_error("Import the original GLB first: %s" % error_string(error))
			source.free()
			quit(1)
			return
		config.set_value("params", "_subresources", {"nodes": {path: {"retarget/bone_map": map}}})
		error = config.save(DIRECTORY + file + ".import")
		print("Native humanoid import mapping: %s -> %s" % [file, path])
		source.free()
		if error != OK:
			push_error("Cannot save native import settings: %s" % error_string(error))
			quit(1)
			return
	quit(0)
