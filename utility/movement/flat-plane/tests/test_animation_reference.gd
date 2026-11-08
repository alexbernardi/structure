extends RefCounted

const Scene = preload("res://scenes/animation_reference.tscn")
const Source = preload("res://assets/quaternius/UAL1_Standard.glb")
const RootMotion = preload("res://assets/quaternius/UAL1_Standard_RM.glb")
const TraversalSource = preload("res://assets/quaternius/UAL2_Traversal.glb")
const TraversalRootMotion = preload("res://assets/quaternius/UAL2_Traversal_RM.glb")
const Mannequin = preload("res://character/authored_mannequin.gd")


func test_authentic_reference_has_valid_tracks_and_plays_all_clips(t) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var scene := Scene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	scene.set_process(false)
	scene.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	t.eq(scene.skeleton.get_bone_count(), 65, "original source skeleton, not the procedural mannequin")
	t.eq(scene.player.get_animation_list().size(), 43, "inventory of the actual Standard package")
	for clip in scene.CLIPS:
		scene.play_clip(scene.CLIPS.find(clip))
		scene.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		t.eq(scene.skeleton.get_bone_count(), 65, "%s plays on an original Quaternius character" % clip)
		var animation_root: Node = scene.player.get_node(scene.player.root_node)
		var animation: Animation = scene.player.get_animation(clip)
		t.ok(animation != null and animation.length > 0.0, "%s has duration" % clip)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var node := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			t.ok(node != null, "%s resolves %s" % [clip, path])
			if node is Skeleton3D and path.get_subname_count() > 0:
				t.ok(node.find_bone(path.get_subname(0)) >= 0, "%s maps an existing bone" % path)
		var before: Quaternion = scene.skeleton.get_bone_pose_rotation(scene.skeleton.find_bone("LeftUpperLeg"))
		scene.player.advance(animation.length * 0.3)
		var after: Quaternion = scene.skeleton.get_bone_pose_rotation(scene.skeleton.find_bone("LeftUpperLeg"))
		t.ok(not before.is_equal_approx(after), "%s actually poses the original skeleton" % clip)
		t.eq(scene.source.position, Vector3.ZERO, "animation never translates a gameplay body")
		t.eq(scene.traversal_source.position, Vector3.ZERO, "traversal reference stays in place too")
	t.ok(scene.traversal_source.visible and not scene.source.visible, "vault shows the UAL2 source character")
	scene.queue_free()
	await tree.process_frame


func test_paid_ual2_safety_vault_source_is_authentic_and_measured(t) -> void:
	for resource in [TraversalSource, TraversalRootMotion]:
		var source: Node = resource.instantiate()
		var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
		var skeleton: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
		t.eq(player.get_animation_list().size(), 1, "subset holds only the selected authored clip")
		var animation := player.get_animation("SafetyVault")
		t.near(animation.length, 22.0 / 30.0, 0.001, "authored 22-frame vault")
		t.eq(animation.loop_mode, Animation.LOOP_NONE, "vault is a one-shot")
		var displacement := Vector3.ZERO
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and path.get_subname_count() > 0 and path.get_subname(0) == "Root":
				displacement = animation.position_track_interpolate(track, animation.length) - animation.position_track_interpolate(track, 0.0)
		var distance := Vector2(displacement.x, displacement.z).length() * skeleton.motion_scale
		t.near(distance, 2.901 if resource == TraversalRootMotion else 0.0, 0.005, "authored vault root displacement")
		source.free()


func test_authored_in_place_and_root_motion_reference_displacements(t) -> void:
	for resource in [Source, RootMotion]:
		var source: Node = resource.instantiate()
		var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
		var skeleton: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
		for data in [["Jog_Fwd", 5.0, 5.357143], ["Sprint", 5.5, 8.25]]:
			var animation := player.get_animation(data[0])
			var displacement := Vector3.ZERO
			for track in animation.get_track_count():
				var path := animation.track_get_path(track)
				if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and path.get_subname_count() > 0 and path.get_subname(0) == "Root":
					displacement = animation.position_track_interpolate(track, animation.length) - animation.position_track_interpolate(track, 0.0)
			var distance := Vector2(displacement.x, displacement.z).length() * skeleton.motion_scale
			t.near(distance, data[1] if resource == RootMotion else 0.0, 0.001, "authored displacement of %s" % data[0])
			if resource == RootMotion:
				t.near(distance / animation.length, data[2], 0.001, "measured nominal speed, not an assumed constant")
		source.free()


func test_native_primitive_target_preserves_authored_joint_motion_and_bone_lengths(t) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var target := Mannequin.new()
	tree.root.add_child(target)
	var source: Node = Source.instantiate()
	tree.root.add_child(source)
	await tree.process_frame
	var source_player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
	var source_skeleton: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	target.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var worst := 0.0
	for clip in target.CLIPS:
		target.player.play(clip)
		source_player.play(clip)
		for i in 48:
			var time: float = i / 48.0 * target.player.get_animation(clip).length
			target.player.seek(time, true)
			source_player.seek(time, true)
			for bone in target.BONES:
				var index: int = target.bone_index[bone]
				var actual := target.skeleton.get_bone_global_pose(index).origin
				var expected := source_skeleton.get_bone_global_pose(source_skeleton.find_bone(bone)).origin * target.proportion_scale
				worst = maxf(worst, expected.distance_to(actual))
				if bone not in ["Root", "Hips"]:
					t.near(target.skeleton.get_bone_pose_position(index).length(), target.skeleton.get_bone_rest(index).origin.length(),
						1e-5, "%s length is not animated or stretched" % bone)
	t.ok(worst < 0.001, "native normalized tracks preserve the source performance within 1 mm: %.6f m" % worst)
	t.eq(target.skeleton.get_bone_count(), 23, "minimal compatible rig without unused finger bones")
	target.queue_free()
	source.queue_free()
	await tree.process_frame


func test_authored_jog_and_sprint_begin_on_compatible_footstep_phases(t) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var target := Mannequin.new()
	tree.root.add_child(target)
	await tree.process_frame
	target.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var samples := []
	for clip in ["Jog_Fwd", "Sprint"]:
		var values := []
		target.player.play(clip)
		for i in 48:
			target.player.seek(i / 48.0 * target.player.get_animation(clip).length, true)
			var left: Vector3 = target.skeleton.get_bone_global_pose(target.bone_index.LeftFoot).origin
			var right: Vector3 = target.skeleton.get_bone_global_pose(target.bone_index.RightFoot).origin
			values.append(left.z - right.z)
		samples.append(values)
	var correlation := 0.0
	var magnitude_a := 0.0
	var magnitude_b := 0.0
	for i in 48:
		correlation += samples[0][i] * samples[1][i]
		magnitude_a += samples[0][i] ** 2
		magnitude_b += samples[1][i] ** 2
	correlation /= sqrt(magnitude_a * magnitude_b)
	t.ok(correlation > 0.75, "native cyclic mixing keeps the same leg forward; normalized cycle correlation %.3f" % correlation)
	target.queue_free()
	await tree.process_frame
