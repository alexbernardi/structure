extends Node

const GraphParams = preload("res://animation/graph_params.gd")
const SAMPLES := 96

var params = GraphParams.create()
var model
var visual
var player: AnimationPlayer
var tree: AnimationTree
var generation := 0
var bake_usec := 0
var _key := -1
var _last_phase := 0.0
var _seek := true


func setup(target: Node3D, gait_model) -> void:
	visual = target
	model = gait_model
	player = visual.get_node("AnimationPlayer")
	tree = visual.get_node("AnimationTree")
	# Each character owns its clips; changing one rig must not rewrite another character's library.
	var original := player.get_animation_library("")
	var library := AnimationLibrary.new()
	for name in original.get_animation_list():
		library.add_animation(name, original.get_animation(name).duplicate(true))
	player.remove_animation_library("")
	player.add_animation_library("", library)
	tree.tree_root = tree.tree_root.duplicate(true)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	params.changed.connect(func(id: String, value: float) -> void: tree.set(GraphParams.PATHS[id], value))
	sync_parameters()


func sync_parameters() -> void:
	for id in GraphParams.PATHS:
		var value: float = tree.get(GraphParams.PATHS[id])
		if not is_finite(value):
			push_error("Non-finite walk graph parameter: %s" % id)
			value = params.get_value(id)
		var clamped: float = params.set_value(id, value)
		if not is_equal_approx(value, clamped):
			tree.set(GraphParams.PATHS[id], clamped)


func regenerate() -> void:
	if model.cycle.is_empty():
		model.cycle = model.cycle_for(0.0)
	var pose_values: Array[float] = []
	for d in model.p.definitions():
		if d.group not in ["view", "playback"]:
			pose_values.append(model.p.get_value(d.id))
	var key := hash([pose_values, model.rig.values.hash() if model.rig != null else 0, model.cycle.v])
	if key == _key:
		return
	var start := Time.get_ticks_usec()
	var reset := player.get_animation("RESET")
	reset.track_set_key_value(visual.bone_index.size(), 0,
		visual.skeleton.get_bone_rest(visual.bone_index.pelvis).origin)
	var clip := player.get_animation("walk")
	clip.clear()
	clip.length = 1.0
	clip.loop_mode = Animation.LOOP_LINEAR
	for bone in visual.bone_index:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:" + bone))
	var pelvis_track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(pelvis_track, ^"Skeleton3D:pelvis")
	for i in SAMPLES + 1:
		var q := float(i) / SAMPLES
		var frame := walk_frame(model.pose_at(fposmod(q, 1.0)))
		var track := 0
		for bone in visual.bone_index:
			clip.rotation_track_insert_key(track, q, frame.rotations[bone])
			track += 1
		clip.position_track_insert_key(pelvis_track, q, frame.positions.pelvis)
	_key = key
	_seek = true
	generation += 1
	bake_usec = Time.get_ticks_usec() - start


static func walk_frame(g: Dictionary) -> Dictionary:
	var undo: Quaternion = g.pelvis_q.inverse()
	var pitch: float = -g.torso_lean
	var rotations := {
		"pelvis": g.pelvis_q,
		"spine": undo * Quaternion(Vector3.RIGHT, pitch * 0.4),
		"chest": Quaternion(Vector3.UP, g.chest_yaw) * Quaternion(Vector3.RIGHT, pitch * 0.6),
		"neck": Quaternion.IDENTITY, "head": Quaternion.IDENTITY,
	}
	for side in ["l", "r"]:
		var roll := 0.1 if side == "l" else -0.1
		rotations["thigh_" + side] = undo * Quaternion(Vector3.RIGHT, g["thigh_" + side])
		rotations["shin_" + side] = Quaternion(Vector3.RIGHT, -float(g["knee_" + side]))
		rotations["foot_" + side] = Quaternion(Vector3.RIGHT, g["foot_" + side])
		rotations["upper_arm_" + side] = Quaternion(Vector3.RIGHT, g["arm_" + side]) * Quaternion(Vector3.FORWARD, roll)
		rotations["forearm_" + side] = Quaternion(Vector3.RIGHT, g["elbow_" + side])
	return {"rotations": rotations, "positions": {"pelvis": g.pelvis}}


func _write_static(clip: Animation, pose: Dictionary) -> void:
	var track := 0
	for bone in visual.bone_index:
		clip.track_set_key_value(track, 0, pose.rotations[bone])
		track += 1
	clip.track_set_key_value(track, 0, pose.positions.pelvis)


func apply_pose(full: Dictionary, legacy: Dictionary, weight: float) -> void:
	regenerate()
	var q: float = model.phase
	var clip := player.get_animation("walk")
	var body := {"rotations": {}, "positions": {}}
	var manual: float = params.get_value("walk_blend")
	var track := 0
	for bone in visual.bone_index:
		var sampled := clip.rotation_track_interpolate(track, q)
		var base: Quaternion = legacy.rotations[bone].slerp(sampled, weight)
		# Add2 composes a rest-relative rotation AFTER the incoming pose. Gate this layer with the manual walk blend,
		# so choosing the fallback really chooses it rather than having the body layer restore the walk.
		body.rotations[bone] = Quaternion.IDENTITY.slerp(base.inverse() * full.rotations[bone], manual)
		track += 1
	var base_position: Vector3 = legacy.positions.pelvis.lerp(clip.position_track_interpolate(track, q), weight)
	var rest: Vector3 = visual.skeleton.get_bone_rest(visual.bone_index.pelvis).origin
	body.positions.pelvis = rest + (full.positions.pelvis - base_position) * manual
	_write_static(player.get_animation("legacy"), legacy)
	_write_static(player.get_animation("body"), body)
	# The planner and tree share a normalized stride clock. Only resampling a clip or scrubbing seeks; normal playback
	# actually advances through WalkSpeed, rather than overwriting its pose from outside the animation mixer.
	tree.set("parameters/Locomotion/blend_amount", weight)
	if _seek or model.p.is_on("freeze") or not model.pose.get("active", false):
		tree.set("parameters/WalkSeek/seek_request", q)
		tree.advance(0.0)
	else:
		var step := fposmod(q - _last_phase, 1.0)
		tree.advance(step / params.get_value("playback_speed"))
	_seek = false
	_last_phase = q


static func static_clip(target: Node3D) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0
	for bone in target.bone_index:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:" + bone))
		clip.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	var position := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(position, ^"Skeleton3D:pelvis")
	clip.position_track_insert_key(position, 0.0, target.skeleton.get_bone_rest(target.bone_index.pelvis).origin)
	return clip
