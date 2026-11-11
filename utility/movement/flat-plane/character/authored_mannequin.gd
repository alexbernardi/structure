## Primitive target for native humanoid-normalized animation. No procedural pose writer.
extends Node3D

const Source = preload("res://assets/quaternius/UAL1_Standard.glb")
const TraversalSource = preload("res://assets/quaternius/UAL2_Traversal.glb")
const ClimbSource = preload("res://assets/quaternius/UAL2_Climb.glb")
const LegacyVisual = preload("res://character/character_visual.gd")
const ClipMirror = preload("res://traversal/clip_mirror.gd")
const MIRROR_VAULT := "SafetyVault_Mirror"   ## left-hand support, right-foot entry: the exact mirror of the authored vault
const CLIPS := ["Idle", "Jog_Fwd", "Sprint", "Jump_Start", "Jump", "Jump_Land", "Crouch_Idle", "Crouch_Fwd"]
const TRAVERSAL_CLIPS := ["SafetyVault"]
const CLIMB_CLIPS := ["ClimbUp_1m", "DoubleJump", "ClimbUp_2m", "Slide_Start", "Slide", "Slide_Exit", "JogToFlip"]   # the importer names Slide_Loop "Slide" (loop suffix)   ## Movement Lab 5.0: authored mantle and air jump (same CC0 package)
const BONES := ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

var skeleton := Skeleton3D.new()
var player := AnimationPlayer.new()
var source_scale := 1.0
var proportion_scale := 1.0
var bone_index := {}
var sole_points := {}
var traversal_clips: Array[String] = []   ## authored traversal clips that loaded and retargeted (empty = traversal off)
var traversal_source := TraversalSource
var climb_source := ClimbSource


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	var source: Node = Source.instantiate()
	var original: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	var original_player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
	source_scale = original.motion_scale
	var hip := original.find_bone("Hips")
	if hip < 0:
		push_error("Quaternius import lacks native humanoid mapping; run prepare_authored_assets.gd and reimport")
		source.free()
		return
	proportion_scale = 1.01 / original.get_bone_global_rest(hip).origin.y
	skeleton.motion_scale = original.motion_scale * proportion_scale
	for bone in BONES:
		var old := original.find_bone(bone)
		if old < 0:
			push_error("Missing mapped source bone: %s" % bone)
			source.free()
			return
		var index := skeleton.add_bone(bone)
		bone_index[bone] = index
		var parent := original.get_bone_parent(old)
		if parent >= 0:
			var parent_name := original.get_bone_name(parent)
			if not bone_index.has(parent_name):
				push_error("Unexpected humanoid parent for %s: %s" % [bone, parent_name])
				source.free()
				return
			skeleton.set_bone_parent(index, bone_index[parent_name])
		var rest := original.get_bone_rest(old)
		rest.origin *= proportion_scale
		skeleton.set_bone_rest(index, rest)
	skeleton.reset_bone_poses()
	player.name = "AnimationPlayer"
	add_child(player)
	var library := AnimationLibrary.new()
	for name in CLIPS:
		library.add_animation(name, _retarget(original_player.get_animation(name)))
	_add_traversal(library, original.get_bone_global_rest(hip).origin.y, traversal_source, TRAVERSAL_CLIPS)
	_add_traversal(library, original.get_bone_global_rest(hip).origin.y, climb_source, CLIMB_CLIPS)
	if traversal_clips.has("SafetyVault"):
		library.add_animation(MIRROR_VAULT, ClipMirror.mirror_animation(library.get_animation("SafetyVault")))
		traversal_clips.append(MIRROR_VAULT)
	player.add_animation_library("", library)
	source.free()
	_build_meshes()


func _retarget(animation: Animation) -> Animation:
	var clip: Animation = animation.duplicate(true)
	for track in range(clip.get_track_count() - 1, -1, -1):
		var path := clip.track_get_path(track)
		if path.get_subname_count() != 1 or not bone_index.has(String(path.get_subname(0))):
			clip.remove_track(track)
			continue
		clip.track_set_path(track, NodePath("Skeleton3D:" + String(path.get_subname(0))))
	return clip


## UAL2 shares UAL1's rig. A missing or incompatible source disables traversal instead of breaking locomotion.
func _add_traversal(library: AnimationLibrary, hip_height: float, packed: PackedScene, names: Array) -> void:
	if packed == null:
		push_warning("Authored traversal source missing; its moves are disabled")
		return
	var source: Node = packed.instantiate()
	var skeletons := source.find_children("*", "Skeleton3D", true, false)
	var players := source.find_children("*", "AnimationPlayer", true, false)
	var hip: int = skeletons[0].find_bone("Hips") if skeletons.size() == 1 else -1
	if hip < 0 or players.size() != 1 or absf(skeletons[0].get_bone_global_rest(hip).origin.y - hip_height) > 0.0005:
		push_warning("Authored traversal source is not on the UAL1-compatible humanoid rig; traversal disabled")
		source.free()
		return
	for name in names:
		if players[0].has_animation(name):
			library.add_animation(name, _retarget(players[0].get_animation(name)))
			traversal_clips.append(name)
		else:
			push_warning("Authored traversal clip missing: %s" % name)
	source.free()


func _rest(bone: String) -> Transform3D:
	return skeleton.get_bone_global_rest(bone_index[bone])


func _attach(bone: String, mesh: Mesh, world: Transform3D, colour: String) -> void:
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	skeleton.add_child(attach)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = LegacyVisual.COLOURS[colour]
	material.roughness = 0.85
	instance.material_override = material
	instance.transform = _rest(bone).affine_inverse() * world
	attach.add_child(instance)


func _segment(bone: String, end: String, radius: float, colour: String) -> void:
	var start := _rest(bone).origin
	var finish := _rest(end).origin
	var delta := finish - start
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(delta.length(), radius * 2.0)
	_attach(bone, mesh, Transform3D(Basis(Quaternion(Vector3.UP, delta.normalized())), (start + finish) * 0.5), colour)


func _ellipsoid(bone: String, centre: Vector3, size: Vector3, colour: String) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	_attach(bone, mesh, Transform3D(Basis.from_scale(size), centre), colour)


func _build_meshes() -> void:
	var hip := _rest("Hips").origin
	_ellipsoid("Hips", hip, Vector3(0.17, 0.12, 0.11), "pants")
	_segment("Hips", "Spine", 0.11, "shirt")
	_segment("Spine", "UpperChest", 0.12, "shirt")
	_ellipsoid("UpperChest", _rest("UpperChest").origin + Vector3(0, 0.06, 0), Vector3(0.20, 0.16, 0.10), "shirt")
	_segment("Neck", "Head", 0.04, "skin")
	var head := _rest("Head").origin + Vector3(0, 0.07, 0.015)
	_ellipsoid("Head", head, Vector3(0.105, 0.14, 0.11), "skin")
	_ellipsoid("Head", head + Vector3(0, -0.02, 0.11), Vector3(0.025, 0.025, 0.04), "skin")
	for side in ["Left", "Right"]:
		_segment(side + "Shoulder", side + "UpperArm", 0.055, "shirt")
		_segment(side + "UpperArm", side + "LowerArm", 0.055, "shirt")
		_segment(side + "LowerArm", side + "Hand", 0.042, "skin")
		# The hand runs on from the wrist along the forearm (palm-down rest pose): long toward the fingers, wide front to
		# back, thin top to bottom. (Before 5.4 it was centred on the wrist with its long axis across the arm.)
		var wrist := _rest(side + "Hand").origin
		var along := (wrist - _rest(side + "LowerArm").origin).normalized()
		_ellipsoid(side + "Hand", wrist + along * 0.085, Vector3(0.095, 0.022, 0.046), "skin")
		_segment(side + "UpperLeg", side + "LowerLeg", 0.075, "pants")
		_segment(side + "LowerLeg", side + "Foot", 0.058, "pants")
		var foot := _rest(side + "Foot").origin
		var toe := _rest(side + "Toes").origin
		var ankle := CapsuleMesh.new()
		ankle.radius = 0.035
		ankle.height = maxf(0.07, foot.y - 0.025)
		_attach(side + "Foot", ankle, Transform3D(Basis.IDENTITY, Vector3(foot.x, (foot.y + 0.025) * 0.5, foot.z)), "shoe")
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.105, 0.05, absf(toe.z - foot.z) + 0.04)
		var centre := Vector3(foot.x, 0.025, (foot.z + toe.z) * 0.5)
		_attach(side + "Foot", mesh, Transform3D(Basis.IDENTITY, centre), "shoe")
		var corners: Array[Vector3] = []
		for x in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				corners.append(_rest(side + "Foot").affine_inverse() * (centre + mesh.size * Vector3(x, -0.5, z)))
		sole_points[side] = corners
