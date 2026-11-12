## Animation adapter: plays authored clips imported with Godot's humanoid BoneMap and rest normalisation on the
## Vitruvian rig.
##
## Because the rig's rest orientations are the SkeletonProfileHumanoid reference orientations (the same ones the
## importer normalises every humanoid to), rotation tracks are copied unchanged. Only three things are adapted:
##   * track paths are renamed to this rig's Skeleton3D;
##   * the Hips position track is rewritten in metres: the hips keep the clip's displacement from the source rest,
##     scaled by the ratio of hip-joint heights (leg length), around this rig's own rest;
##   * tracks this rig does not own are dropped (fingers, eyes, leaf bones, position tracks of any bone other than
##     Hips, every scale track, the Root track). Bone lengths therefore come only from the rig's proportions.
##
## Root motion: the Root bone belongs to the character controller. In-place clips are used; a clip's Root track (root
## motion) is dropped and reported, never applied to the skeleton. See BONE-IK-ANIMATION.md.
extends RefCounted

const Humanoid = preload("res://systems/bone_ik/rig/humanoid.gd")
## Pinned, read-only CC0 sources shipped with movement_core 1.0.0 (its CONTRACT lists them as package assets).
const SOURCES := [
	"res://systems/movement_core/assets/quaternius/UAL1_Standard.glb",
	"res://systems/movement_core/assets/quaternius/UAL2_Climb.glb",
	"res://systems/movement_core/assets/quaternius/UAL2_Traversal.glb",
]

static var _cache := {}


## Loads (once) a humanoid-normalised GLB: its clips and its rest data.
## -> {path, ok, error, clips: {name: Animation}, motion_scale, hips_rest: Vector3, hip_joint_height,
##     rest_globals: {bone: Transform3D}, parents: {bone: parent name}}
static func load_source(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out := {"path": path, "ok": false, "error": "", "clips": {}}
	if not ResourceLoader.exists(path):
		out.error = "missing source %s" % path
		_cache[path] = out
		return out
	var scene: Node = (load(path) as PackedScene).instantiate()
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if skeletons.size() != 1 or players.size() != 1:
		out.error = "expected one Skeleton3D and one AnimationPlayer in %s" % path
		scene.free()
		_cache[path] = out
		return out
	var sk: Skeleton3D = skeletons[0]
	var ap: AnimationPlayer = players[0]
	if sk.find_bone("Hips") < 0 or sk.find_bone("LeftUpperLeg") < 0:
		out.error = "%s is not imported with the humanoid BoneMap" % path
		scene.free()
		_cache[path] = out
		return out
	out.motion_scale = sk.motion_scale
	out.hips_rest = sk.get_bone_global_rest(sk.find_bone("Hips")).origin
	out.hip_joint_height = 0.5 * (sk.get_bone_global_rest(sk.find_bone("LeftUpperLeg")).origin.y
		+ sk.get_bone_global_rest(sk.find_bone("RightUpperLeg")).origin.y)
	out.rest_globals = {}
	out.parents = {}
	for i in sk.get_bone_count():
		out.rest_globals[sk.get_bone_name(i)] = sk.get_bone_global_rest(i)
		var p := sk.get_bone_parent(i)
		out.parents[sk.get_bone_name(i)] = sk.get_bone_name(p) if p >= 0 else ""
	for name in ap.get_animation_list():
		out.clips[String(name)] = ap.get_animation(name).duplicate(true)
	out.ok = true
	scene.free()
	_cache[path] = out
	return out


## One clip retargeted to `definition` (rig_builder.build). -> [Animation, report]
static func retarget(source: Dictionary, clip_name: String, definition: Dictionary) -> Array:
	var clip: Animation = (source.clips[clip_name] as Animation).duplicate(true)
	var hips: Vector3 = definition.bones[definition.index.Hips].global.origin
	var scale: float = definition.measurements.hip_joint_height / source.hip_joint_height
	var report := {"clip": clip_name, "source": source.path, "length": clip.length, "loop": clip.loop_mode,
		"rotation_tracks": 0, "hips_position": false, "root_motion": false, "dropped_bones": [],
		"dropped_position": 0, "dropped_scale": 0, "dropped_other": 0, "leg_scale": scale}
	for t in range(clip.get_track_count() - 1, -1, -1):
		var path := clip.track_get_path(t)
		var bone := String(path.get_subname(0)) if path.get_subname_count() == 1 else ""
		var kind := clip.track_get_type(t)
		var keep := false
		if bone == "Root" and kind == Animation.TYPE_POSITION_3D:
			report.root_motion = true
		elif definition.index.has(bone) and not Humanoid.is_helper(bone):
			if kind == Animation.TYPE_ROTATION_3D and bone != "Root":
				keep = true
				report.rotation_tracks += 1
			elif kind == Animation.TYPE_POSITION_3D and bone == "Hips":
				keep = true
				report.hips_position = true
				for k in clip.track_get_key_count(t):
					var actual: Vector3 = clip.track_get_key_value(t, k) * source.motion_scale
					clip.track_set_key_value(t, k, hips + (actual - source.hips_rest) * scale)
			elif kind == Animation.TYPE_POSITION_3D:
				report.dropped_position += 1
			elif kind == Animation.TYPE_SCALE_3D:
				report.dropped_scale += 1
			else:
				report.dropped_other += 1
		elif bone != "" and not report.dropped_bones.has(bone):
			report.dropped_bones.append(bone)
		if keep:
			clip.track_set_path(t, NodePath("Skeleton3D:" + bone))
		else:
			clip.remove_track(t)
	return [clip, report]


## Every clip of every available source, retargeted. -> {library: AnimationLibrary, reports: {name: report},
## sources: {path: error or ""}}
static func build_library(definition: Dictionary, sources := SOURCES) -> Dictionary:
	var library := AnimationLibrary.new()
	var reports := {}
	var status := {}
	for path in sources:
		var source := load_source(path)
		status[path] = source.error
		if not source.ok:
			continue
		for name in source.clips:
			if library.has_animation(name):
				continue
			var result := retarget(source, name, definition)
			library.add_animation(name, result[0])
			reports[name] = result[1]
	return {"library": library, "reports": reports, "sources": status}
