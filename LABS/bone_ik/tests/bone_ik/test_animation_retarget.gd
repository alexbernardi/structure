## Authored animation on the Vitruvian rig: imported Quaternius clips (CC0, pinned movement_core 1.0.0 assets)
## retargeted through the humanoid profile. Compares against the same clip on the original imported skeleton.
extends RefCounted

const Rig = preload("res://systems/bone_ik/vitruvian_rig.gd")
const ClipAdapter = preload("res://systems/bone_ik/animation/humanoid_clip_adapter.gd")
const Measure = preload("res://tests/bone_ik/anim_measure.gd")
const LOCOMOTION := ["Idle", "Walk", "Jog_Fwd", "Sprint"]

var _tree: SceneTree
var rig
var source: Node


func before_each() -> void:
	_tree = Engine.get_main_loop()
	rig = Rig.new()
	_tree.root.add_child(rig)
	source = (load(ClipAdapter.SOURCES[0]) as PackedScene).instantiate()
	_tree.root.add_child(source)
	source.visible = false
	await _tree.process_frame   # the rig builds itself in _ready


func after_each() -> void:
	rig.queue_free()
	source.queue_free()
	await _tree.process_frame


func test_library_contents_and_track_policy(t) -> void:
	for path in ClipAdapter.SOURCES:
		t.eq(rig.animation_sources.get(path, "not attempted"), "", "source loads: %s" % path)
	for name in LOCOMOTION + ["Roll", "Jump_Start", "ClimbUp_2m"]:
		t.ok(rig.animation_reports.has(name), "clip %s available" % name)
	for name in rig.animation_reports:
		var r: Dictionary = rig.animation_reports[name]
		var clip: Animation = rig.player.get_animation(name)
		var scale_tracks := 0
		var positions := []
		for i in clip.get_track_count():
			if clip.track_get_type(i) == Animation.TYPE_SCALE_3D:
				scale_tracks += 1
			if clip.track_get_type(i) == Animation.TYPE_POSITION_3D:
				positions.append(String(clip.track_get_path(i)))
			t.ok(String(clip.track_get_path(i)).begins_with("Skeleton3D:"), "%s track targets this rig" % name)
		t.eq(scale_tracks, 0, "%s: no scale tracks (no unintended scaling)" % name)
		t.ok(positions.is_empty() or positions == ["Skeleton3D:Hips"], "%s: only the hips translate (%s)" % [name, positions])
		t.ok(r.rotation_tracks >= 15, "%s keeps the body's rotation tracks (%d)" % [name, r.rotation_tracks])


func test_idle_retargets_without_distortion(t) -> void:
	var m := Measure.measure(rig, source, "Idle")
	print("    Idle: %s" % [m])
	t.ok(m.rotation_error_deg < 0.01, "every bone's world orientation equals the source (worst %.5f deg)" % m.rotation_error_deg)
	t.ok(m.length_error_m < 1e-5, "no bone changes length (worst %.7f m)" % m.length_error_m)
	t.ok(m.stance_toe_error_m < 0.02, "planted toes stay planted within 2 cm (worst %.4f m)" % m.stance_toe_error_m)
	t.ok(m.min_sole_m > -0.02 and m.min_sole_m < 0.03, "feet stay on the ground (lowest sole point %.4f m)" % m.min_sole_m)
	t.ok(m.hinge_position_change_m < 1e-4, "hinge alignment moves no joint (%.7f m)" % m.hinge_position_change_m)


func test_locomotion_clips_retarget(t) -> void:
	for clip in LOCOMOTION:
		var m := Measure.measure(rig, source, clip)
		print("    %s: %s" % [clip, m])
		t.ok(m.rotation_error_deg < 0.01, "%s: orientations equal the source (%.5f deg)" % [clip, m.rotation_error_deg])
		t.ok(m.length_error_m < 1e-5, "%s: constant bone lengths" % clip)
		# Our ankle is anatomical (0.039 x stature); the source's sits about 3 cm higher, so a strongly pitched foot
		# lifts our toe joint differently. Phase 2 foot IK removes the residue; 4 cm is the phase 1 bound.
		t.ok(m.stance_toe_error_m < 0.04, "%s: planted toes stay planted within 4 cm (%.4f m)" % [clip, m.stance_toe_error_m])
		t.ok(m.violations.is_empty(), "%s: within the hard limits after hinge alignment (%s; raw %s)" % [clip, m.violations, m.raw_violations])
		t.ok(absf(m.min_sole_m - m.src_min_sole_m) < 0.03, "%s: lowest sole point matches the source within 3 cm (%.4f vs %.4f m)" % [clip, m.min_sole_m, m.src_min_sole_m])
		t.ok(m.hinge_position_change_m < 1e-4, "%s: hinge alignment moves no joint (%.7f m)" % [clip, m.hinge_position_change_m])


func test_axial_alignment_on_awkward_clips(t) -> void:
	# Push: the source splits a straight arm's roll between upper arm and forearm with a full extra turn; Roll and
	# Punch_Cross bend elbows far. Alignment must stay lossless and leave no arm joint beyond its hard limit.
	for clip in ["Push", "Punch_Cross", "Roll"]:
		var m := Measure.measure(rig, source, clip, 30)
		t.ok(m.hinge_position_change_m < 1e-4, "%s: alignment moves no joint (%.7f m)" % [clip, m.hinge_position_change_m])
		var arms := []
		for bone in m.violations:
			if bone.ends_with("UpperArm") or bone.ends_with("LowerArm"):
				arms.append(bone)
		if clip != "Roll":   # Roll keeps a genuine left-hand / hip excess (see BONE-IK-ANIMATION.md)
			t.ok(arms.is_empty(), "%s: shoulders and elbows within limits after alignment (raw %s)" % [clip, m.raw_violations])
