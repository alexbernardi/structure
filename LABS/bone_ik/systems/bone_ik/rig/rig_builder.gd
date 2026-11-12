## Builds the Vitruvian rig definition (bones, rests, landmarks, measurements) from a Proportions object.
## Pure data: no nodes. `apply_to(skeleton, definition)` writes it into a Skeleton3D.
##
## Model space: feet on y = 0, character faces +Z, its left is +X (SkeletonProfileHumanoid convention).
## The rest pose is the profile's T-pose: arms horizontal along +-X, palms down, legs vertical.
## Every animation bone's global rest basis is the profile's reference basis, whatever the proportions.
extends RefCounted

const Humanoid = preload("res://systems/bone_ik/rig/humanoid.gd")
const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")

## Small anatomical offsets, as fractions of stature (z: forward +). Spinal joints sit behind the hip-joint line
## (the sacrum and vertebral bodies are posterior to the hip joints); the sternoclavicular joint is in front of the
## spine. Derived from the normalised reference rig shipped with movement_core, rounded; see BONE-IK-PROPORTIONS.md.
const Z_HIPS := -0.008
const Z_SPINE := -0.010
const Z_CHEST := -0.001
const Z_UPPER_CHEST := -0.004
const Z_NECK := -0.007
const Z_HEAD := 0.002
const HIPS_ABOVE_HIP_JOINTS := 0.35   # share of the pelvis segment: the pelvis bone pivots mid-pelvis
const CLAVICLE_X := 0.011             # sternoclavicular joint, half-width / stature
const CLAVICLE_DROP := 0.017          # below C7/T1
const CLAVICLE_Z := 0.035             # in front of the neck base
const SHOULDER_DROP := 0.026          # glenohumeral centre below C7/T1
const SHOULDER_Z := -0.005
const HEEL_BEHIND_ANKLE := 0.20       # share of foot length behind the ankle joint
const BALL_AHEAD_ANKLE := 0.52        # first metatarsophalangeal joint ahead of the ankle, share of foot length
const BALL_HEIGHT := 0.011            # MTP joint centre height / stature


## -> {bones: Array[Dictionary], index: {name: int}, landmarks: {name: Vector3}, measurements: {}, dims: {}}
## bone = {name, parent (name or ""), parent_index, global: Transform3D, local: Transform3D, tip: Vector3 (model),
##         side: "L"/"R"/"C", region, helper: bool}
static func build(proportions) -> Dictionary:
	var d: Dictionary = proportions.derive()
	var h: float = d.height
	var bases := Humanoid.profile_bases()
	var parents := Humanoid.profile_parents()
	var pos := {}
	var hip_y: float = d.hip_joint_height
	var pelvis: float = d.torso * Proportions.TORSO_SPLIT[0]
	pos.Root = Vector3.ZERO
	pos.Hips = Vector3(0, hip_y + pelvis * HIPS_ABOVE_HIP_JOINTS, Z_HIPS * h)
	# Spine pivots at L5/S1 (after the pelvis share), Chest at T12/L1, UpperChest mid-thorax, Neck at C7/T1.
	var split: Array = Proportions.TORSO_SPLIT
	pos.Spine = Vector3(0, hip_y + d.torso * split[0], Z_SPINE * h)
	pos.Chest = Vector3(0, pos.Spine.y + d.torso * split[1], Z_CHEST * h)
	pos.UpperChest = Vector3(0, pos.Chest.y + d.torso * split[2], Z_UPPER_CHEST * h)
	pos.Neck = Vector3(0, d.neck_base_height, Z_NECK * h)
	pos.Head = Vector3(0, d.head_pivot_height, Z_HEAD * h)
	var neck: Vector3 = pos.Neck
	var tips := {}
	var soles := {}
	tips.Head = Vector3(0, h, pos.Head.z)
	for s in [["Left", 1.0, "left"], ["Right", -1.0, "right"]]:
		var p: String = s[0]
		var sx: float = s[1]
		var k: String = s[2]
		pos[p + "Shoulder"] = Vector3(sx * CLAVICLE_X * h, neck.y - CLAVICLE_DROP * h, neck.z + CLAVICLE_Z * h)
		var gh := Vector3(sx * d.shoulder_width * 0.5, neck.y - SHOULDER_DROP * h, neck.z + SHOULDER_Z * h)
		pos[p + "UpperArm"] = gh
		pos[p + "LowerArm"] = gh + Vector3(sx * d[k + "_upper_arm"], 0, 0)
		pos[p + "Hand"] = pos[p + "LowerArm"] + Vector3(sx * d[k + "_forearm"], 0, 0)
		tips[p + "Hand"] = pos[p + "Hand"] + Vector3(sx * d[k + "_hand"], 0, 0)
		var hx: float = sx * d.pelvis_width * 0.5
		pos[p + "UpperLeg"] = Vector3(hx, hip_y, 0)
		pos[p + "LowerLeg"] = Vector3(hx, hip_y - d[k + "_thigh"], 0)
		var ankle_y: float = hip_y - d[k + "_thigh"] - d[k + "_shank"]
		var sole: float = ankle_y - d.ankle_height   # 0 unless the legs are intentionally asymmetric
		soles[k] = sole
		pos[p + "Foot"] = Vector3(hx, ankle_y, 0)
		pos[p + "Toes"] = Vector3(hx, sole + BALL_HEIGHT * h, BALL_AHEAD_ANKLE * d.foot)
		tips[p + "Toes"] = Vector3(hx, sole, (1.0 - HEEL_BEHIND_ANKLE) * d.foot)
	var bones: Array[Dictionary] = []
	var index := {}
	for name in Humanoid.BODY:
		var parent: String = parents[name]
		var g := Transform3D(bases[name], pos[name])
		bones.append({"name": name, "parent": parent, "global": g, "side": Humanoid.side(name),
			"region": Humanoid.REGION[name], "helper": false})
		index[name] = bones.size() - 1
	# Tips: the primary child joint, or the leaf end point.
	var primary := {"Root": "Hips", "Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck",
		"Neck": "Head"}
	for p in ["Left", "Right"]:
		primary[p + "Shoulder"] = p + "UpperArm"
		primary[p + "UpperArm"] = p + "LowerArm"
		primary[p + "LowerArm"] = p + "Hand"
		primary[p + "UpperLeg"] = p + "LowerLeg"
		primary[p + "LowerLeg"] = p + "Foot"
		primary[p + "Foot"] = p + "Toes"
	for bone in bones:
		var n: String = bone.name
		bone.tip = tips[n] if tips.has(n) else pos[primary[n]]
	for name in Humanoid.HELPERS:
		var spec: Array = Humanoid.HELPERS[name]
		var parent_bone: Dictionary = bones[index[spec[0]]]
		var at: Vector3 = parent_bone.global.origin.lerp(parent_bone.tip, spec[1])
		var tip: Vector3 = parent_bone.global.origin.lerp(parent_bone.tip, minf(1.0, spec[1] + 0.2))
		bones.append({"name": name, "parent": spec[0], "global": Transform3D(parent_bone.global.basis, at), "tip": tip,
			"side": Humanoid.side(name), "region": Humanoid.REGION[spec[0]], "helper": true,
			"twist_source": spec[2], "twist_share": spec[3]})
		index[name] = bones.size() - 1
	for bone in bones:
		bone.parent_index = index[bone.parent] if bone.parent != "" else -1
		var parent_global: Transform3D = bones[bone.parent_index].global if bone.parent_index >= 0 else Transform3D.IDENTITY
		bone.local = parent_global.affine_inverse() * bone.global
		bone.length = bone.global.origin.distance_to(bone.tip)
	var landmarks := {
		"vertex": tips.Head, "navel": Vector3(0, d.navel_height, 0),
		"fingertip_l": tips.LeftHand, "fingertip_r": tips.RightHand,
		"toe_tip_l": tips.LeftToes, "toe_tip_r": tips.RightToes,
		"heel_l": Vector3(pos.LeftFoot.x, soles.left, -HEEL_BEHIND_ANKLE * d.foot),
		"heel_r": Vector3(pos.RightFoot.x, soles.right, -HEEL_BEHIND_ANKLE * d.foot),
		"pubis": Vector3(0, hip_y, 0),
	}
	var measurements := {
		"stature": tips.Head.y - minf(soles.left, soles.right),
		"arm_span": tips.LeftHand.x - tips.RightHand.x,
		"hip_joint_height": hip_y,
		"navel_height": d.navel_height,
		"shoulder_joint_width": pos.LeftUpperArm.x - pos.RightUpperArm.x,
		"hip_joint_width": pos.LeftUpperLeg.x - pos.RightUpperLeg.x,
		"leg_length_l": pos.LeftUpperLeg.y - pos.LeftFoot.y + d.ankle_height,
		"leg_length_r": pos.RightUpperLeg.y - pos.RightFoot.y + d.ankle_height,
		"foot_length": d.foot,
		"hand_length": d.hand,
		"head_neck": d.head_neck,
	}
	return {"bones": bones, "index": index, "landmarks": landmarks, "measurements": measurements, "dims": d,
		"proportions": proportions.values.duplicate()}


## Clears `skeleton` and writes the definition's bones and rests; poses reset to rest.
static func apply_to(skeleton: Skeleton3D, definition: Dictionary) -> void:
	skeleton.clear_bones()
	for bone in definition.bones:
		var i := skeleton.add_bone(bone.name)
		if bone.parent_index >= 0:
			skeleton.set_bone_parent(i, bone.parent_index)
		skeleton.set_bone_rest(i, bone.local)
	skeleton.motion_scale = 1.0   # the animation adapter writes hip positions in metres
	skeleton.reset_bone_poses()
