## Phase 0 audit probe: what this Godot build offers for skeletons / IK / animation, and whether the primitive
## humanoid's skeleton really drives what is drawn. Prints facts; assertions live in the tests.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit.gd
extends SceneTree

const Scene = preload("res://scenes/flat_plane.tscn")


func _initialize() -> void:
	var v := Engine.get_version_info()
	print("ENGINE %s (hash %s)" % [v.string, str(v.get("hash", "?")).left(9)])
	_apis()
	await _skeleton()
	quit(0)


func _apis() -> void:
	for c in ["Skeleton3D", "SkeletonModifier3D", "SkeletonProfile", "BoneAttachment3D", "AnimationTree", "AnimationPlayer",
			"SkeletonIK3D", "TwoBoneIK3D", "IKModifier3D", "ChainIK3D", "LookAtModifier3D", "BoneConstraint3D", "CopyTransformModifier3D",
			"ConvertTransformModifier3D", "AimModifier3D", "RetargetModifier3D", "SpringBoneSimulator3D", "XRBodyModifier3D", "PhysicalBoneSimulator3D"]:
		print("API %-26s %s" % [c, "present" if ClassDB.class_exists(c) else "MISSING"])
	print("SkeletonModifier3D subclasses: ", ", ".join(ClassDB.get_inheriters_from_class("SkeletonModifier3D")))
	if ClassDB.class_exists("TwoBoneIK3D"):
		var names: Array[String] = []
		for p in ClassDB.class_get_property_list("TwoBoneIK3D", true):
			names.append("%s:%s" % [p.name, type_string(p.type)])
		print("TwoBoneIK3D own properties: ", ", ".join(names))
		var methods: Array[String] = []
		for m in ClassDB.class_get_method_list("TwoBoneIK3D", true):
			methods.append(m.name)
		print("TwoBoneIK3D own methods: ", ", ".join(methods))
		print("TwoBoneIK3D parents: ", ClassDB.get_parent_class("TwoBoneIK3D"), " <- ", ClassDB.get_parent_class(ClassDB.get_parent_class("TwoBoneIK3D")))
	print("Skeleton3D modifier_callback_mode_process default: ", Skeleton3D.new().modifier_callback_mode_process)


func _skeleton() -> void:
	var s: Node = Scene.instantiate()
	s.options = {"no-capture": "true", "no-hardware": "true", "no-tuning": "true", "no-window-state": "true"}
	root.add_child(s)
	await process_frame   # _ready (which switches the scene's _process on) has not run yet during _initialize
	s.set_physics_process(false)
	s.set_process(false)   # the scene re-poses the skeleton every frame; stop that so this probe's changes are the only ones
	await process_frame
	await process_frame
	var vis: Node = s.visual
	var sk: Skeleton3D = vis.skeleton
	print("SKELETON class=%s bones=%d parent_of_skeleton=%s top_level_visual=%s interp_mode=%s" % [sk.get_class(), sk.get_bone_count(), vis.name, vis.top_level, str(vis.physics_interpolation_mode)])
	var roots := 0
	for i in sk.get_bone_count():
		if sk.get_bone_parent(i) == -1:
			roots += 1
	print("SKELETON roots=%d  has Skin resources: %s  modifiers (children of Skeleton3D that are SkeletonModifier3D): %d" % [roots, str(_has_skin(sk)), _count_modifiers(sk)])
	var attach := 0
	var meshes := 0
	var skinned := 0
	for n in sk.get_children():
		if n is BoneAttachment3D:
			attach += 1
			for m in n.get_children():
				if m is MeshInstance3D:
					meshes += 1
					if (m as MeshInstance3D).skin != null:
						skinned += 1
	print("PRESENTATION BoneAttachment3D=%d  MeshInstance3D under them=%d  of which skinned=%d  (0 skinned = rigid segments riding bones)" % [attach, meshes, skinned])

	# Does moving a bone move what is drawn? Compare the skeleton's own result with the mesh the renderer draws,
	# frame by frame, to see whether the attachments follow immediately or lag.
	var node: BoneAttachment3D = sk.get_node("Attach_forearm_l")
	var mesh: MeshInstance3D = node.get_child(0)
	var head: MeshInstance3D = sk.get_node("Attach_head").get_child(0)
	sk.reset_bone_poses()
	for i in 6:
		await process_frame
	var base_forearm: Vector3 = mesh.global_position
	var base_head: float = head.global_position.y
	var base_bone: Vector3 = sk.global_transform * sk.get_bone_global_pose(vis.bone_index.forearm_l).origin
	print("INFLUENCE at rest: forearm mesh %s, forearm bone joint %s, head mesh y %.3f" % [base_forearm, base_bone, base_head])
	sk.set_bone_pose_rotation(vis.bone_index.upper_arm_l, Quaternion(Vector3.RIGHT, 1.2))
	sk.set_bone_pose_position(vis.bone_index.pelvis, Vector3(0, 0.5, 0))
	for frame in 8:
		await process_frame
		var bone_now: Vector3 = sk.global_transform * sk.get_bone_global_pose(vis.bone_index.forearm_l).origin
		print("INFLUENCE frame %d: forearm joint moved %.3f m (skeleton) / forearm mesh moved %.3f m (drawn); head mesh dropped %.3f m" % [
			frame + 1, base_bone.distance_to(bone_now), base_forearm.distance_to(mesh.global_position), base_head - head.global_position.y])
	# Does the presentation leak into the physics body?
	var body: CharacterBody3D = s.body
	var shape: Shape3D = body.get_child(0).shape
	print("PHYSICS body=%s collider=%s visual_is_collider=%s body_children=%s" % [body.get_class(), shape.get_class(), str(vis is CollisionObject3D), ", ".join(body.get_children().map(func(c: Node) -> String: return c.name))])
	print("PHYSICS ticks/s=%d interpolation=%s" % [Engine.physics_ticks_per_second, str(ProjectSettings.get_setting("physics/common/physics_interpolation"))])
	s.queue_free()


func _has_skin(sk: Skeleton3D) -> bool:
	for n in sk.get_children():
		for m in n.get_children():
			if m is MeshInstance3D and (m as MeshInstance3D).skin != null:
				return true
	return false


func _count_modifiers(sk: Skeleton3D) -> int:
	var n := 0
	for c in sk.get_children():
		if c is SkeletonModifier3D:
			n += 1
	return n
