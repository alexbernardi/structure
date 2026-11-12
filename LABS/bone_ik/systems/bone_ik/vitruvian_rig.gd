## The Vitruvian rig: the public entry point of the bone_ik system (CONTRACT.md).
##
## Builds a Skeleton3D from Proportions, plays retargeted authored clips, and runs one ordered modifier chain:
##
##   [AnimationPlayer | PoseSource]  -> Probe "animation"
##   -> (phase 2: IK modifiers are inserted here) -> Probe "ik"
##   -> AxialAlignModifier (lossless elbow / knee / forearm cleanup) -> JointLimitModifier (anatomical hard limits) -> TwistHelperModifier -> Probe "final"
##   -> (phase 3: PhysicalBoneSimulator3D goes last)
##
## The rig owns no character movement: the Root bone stays at the origin; a controller moves this node.
extends Node3D

signal rebuilt

const VERSION := "0.1.0"
const Proportions = preload("res://systems/bone_ik/rig/proportions.gd")
const RigBuilder = preload("res://systems/bone_ik/rig/rig_builder.gd")
const JointProfile = preload("res://systems/bone_ik/rig/joint_profile.gd")
const Humanoid = preload("res://systems/bone_ik/rig/humanoid.gd")
const ClipAdapter = preload("res://systems/bone_ik/animation/humanoid_clip_adapter.gd")
const PoseProbe = preload("res://systems/bone_ik/runtime/pose_probe_modifier.gd")
const PoseSource = preload("res://systems/bone_ik/runtime/pose_source_modifier.gd")
const LimitModifier = preload("res://systems/bone_ik/runtime/joint_limit_modifier.gd")
const TwistModifier = preload("res://systems/bone_ik/runtime/twist_helper_modifier.gd")
const AxialModifier = preload("res://systems/bone_ik/runtime/axial_align_modifier.gd")

enum Mode { REST, NEUTRAL, ANIMATION, MANUAL }
const MODE_NAMES := ["T-pose (rest)", "Neutral standing", "Imported animation", "Manual joints"]
## Neutral standing pose, degrees (anatomical angles; everything else at neutral). Arms hang (shoulder neutral),
## elbows and knees slightly flexed, palms toward the thighs.
const NEUTRAL_POSE := {
	"LeftUpperArm": Vector3(4, 6, 0), "RightUpperArm": Vector3(4, 6, 0),
	"LeftLowerArm": Vector3(12, 0, 0), "RightLowerArm": Vector3(12, 0, 0),
	"LeftUpperLeg": Vector3(2, 3, 0), "RightUpperLeg": Vector3(2, 3, 0),
	"LeftLowerLeg": Vector3(4, 0, 0), "RightLowerLeg": Vector3(4, 0, 0),
	"LeftFoot": Vector3(2, 0, 0), "RightFoot": Vector3(2, 0, 0),
}
## Limit policy. Authored clips concentrate motion in single bones (see BONE-IK-ANIMATION.md), so clamping them by
## default would change working animation: PROCEDURAL enforces the hard limits on rest / neutral / manual (and,
## later, IK) poses and only measures authored playback. ALWAYS also clamps authored clips; MEASURE never clamps.
enum LimitPolicy { PROCEDURAL, ALWAYS, MEASURE }
## Response states (phase 3+ defines their physics; only "animated" exists now).
const RESPONSE_STATES := ["animated", "partial_ragdoll", "full_ragdoll", "recovering"]

var proportions
var definition := {}
var profile                       ## JointProfile bound to `definition`
var skeleton: Skeleton3D
var player: AnimationPlayer
var pose_source
var probe_animation
var probe_ik
var probe_final
var hinge_modifier
var limit_modifier
var twist_modifier
var mode := Mode.REST
var limit_policy := LimitPolicy.PROCEDURAL
var clip := ""
var manual_angles := {}           ## bone -> Vector3 degrees (manual mode)
var animation_reports := {}
var animation_sources := {}
var response_state := "animated"
var ik_requests := {}             ## effector -> {target, influence} (stored; solved in phase 2)


func _init(p = null) -> void:
	proportions = p if p != null else Proportions.new()
	_create_nodes()


func _ready() -> void:
	if definition.is_empty():
		build()


func _create_nodes() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	pose_source = PoseSource.new()
	pose_source.name = "PoseSource"
	probe_animation = PoseProbe.new()
	probe_animation.name = "ProbeAnimation"
	probe_animation.stage = "animation"
	probe_ik = PoseProbe.new()
	probe_ik.name = "ProbeIK"
	probe_ik.stage = "ik"
	hinge_modifier = AxialModifier.new()
	hinge_modifier.name = "AxialAlign"
	limit_modifier = LimitModifier.new()
	limit_modifier.name = "JointLimits"
	twist_modifier = TwistModifier.new()
	twist_modifier.name = "TwistHelpers"
	probe_final = PoseProbe.new()
	probe_final.name = "ProbeFinal"
	probe_final.stage = "final"
	for m in [pose_source, probe_animation, probe_ik, hinge_modifier, limit_modifier, twist_modifier, probe_final]:
		skeleton.add_child(m)
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)


## (Re)builds the skeleton from `p` (or the current proportions). Keeps the mode, the clip and its time.
func build(p = null) -> void:
	if p != null:
		proportions = p
	var time := player.current_animation_position if player.assigned_animation != "" else 0.0   # playing or paused
	definition = RigBuilder.build(proportions)
	RigBuilder.apply_to(skeleton, definition)
	profile = JointProfile.new(definition)
	hinge_modifier.profile = profile
	limit_modifier.profile = profile
	twist_modifier.setup(definition, profile)
	_load_animations()
	_apply_mode(time)
	rebuilt.emit()


func _load_animations() -> void:
	var result := ClipAdapter.build_library(definition)
	animation_reports = result.reports
	animation_sources = result.sources
	if player.has_animation_library(""):
		player.remove_animation_library("")
	player.add_animation_library("", result.library)


func clips() -> PackedStringArray:
	var out := PackedStringArray(animation_reports.keys())
	out.sort()
	return out


func set_mode(m: Mode) -> void:
	mode = m
	_apply_mode(0.0)


func play(name: String, from := 0.0) -> bool:
	if not player.has_animation(name):
		push_warning("no clip %s" % name)
		return false
	clip = name
	mode = Mode.ANIMATION
	_apply_mode(from)
	return true


func _apply_mode(time: float) -> void:
	pose_source.active = mode != Mode.ANIMATION
	_apply_limit_policy()
	if mode == Mode.ANIMATION and clip != "" and player.has_animation(clip):
		player.play(clip)
		player.seek(time, true)
	else:
		player.stop()
		_refresh_pose_source()


func _refresh_pose_source() -> void:
	var rotations := {}
	var angles := {}
	if mode == Mode.NEUTRAL:
		angles = NEUTRAL_POSE
	elif mode == Mode.MANUAL:
		angles = manual_angles
	if mode != Mode.REST:
		for j in profile.joints:
			# Neutral, not rest: the shoulder's anatomical zero is the hanging arm.
			var deg: Vector3 = angles.get(j.bone, Vector3.ZERO)
			rotations[j.bone_index] = JointProfile.local_from_angles(j, deg * (PI / 180.0))
	pose_source.rotations = rotations


## Manual pose: anatomical angles in degrees (flex, abd, twist). Switches to manual mode.
func set_joint_angles(bone: String, degrees: Vector3) -> bool:
	if profile.joint(bone).is_empty():
		return false
	manual_angles[bone] = degrees
	if mode != Mode.MANUAL:
		# Start manual editing from the neutral stance, not from the T-pose.
		for b in NEUTRAL_POSE:
			if not manual_angles.has(b):
				manual_angles[b] = NEUTRAL_POSE[b]
		mode = Mode.MANUAL
		_apply_mode(0.0)
	else:
		_refresh_pose_source()
	return true


func reset_manual() -> void:
	manual_angles.clear()
	_refresh_pose_source()


func set_limit_policy(policy: LimitPolicy) -> void:
	limit_policy = policy
	_apply_limit_policy()


## Shortcut used by tools: true = ALWAYS, false = MEASURE.
func set_limits_enforced(on: bool) -> void:
	set_limit_policy(LimitPolicy.ALWAYS if on else LimitPolicy.MEASURE)


func _apply_limit_policy() -> void:
	match limit_policy:
		LimitPolicy.ALWAYS: limit_modifier.enforce = true
		LimitPolicy.MEASURE: limit_modifier.enforce = false
		_: limit_modifier.enforce = mode != Mode.ANIMATION


func set_hinge_align(on: bool) -> void:
	hinge_modifier.active = on


## Anatomical angles of a joint in degrees at a stage ("animation", "ik" or "final"; final after the limits).
func get_joint_angles(bone: String, stage := "final") -> Vector3:
	var j: Dictionary = profile.joint(bone)
	var probe = _probe(stage)
	if j.is_empty() or not probe.has_snapshot():
		return Vector3.ZERO
	return JointProfile.angles(j, probe.rotations[j.bone_index]) * (180.0 / PI)


func _probe(stage: String):
	return {"animation": probe_animation, "ik": probe_ik}.get(stage, probe_final)


## Model-space transforms of every bone: "rest", "animation", "ik" or "final".
func stage_globals(stage: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if stage == "rest":
		for bone in definition.bones:
			out.append(bone.global)
		return out
	var probe = _probe(stage)
	if not probe.has_snapshot():
		return stage_globals("rest")
	return probe.globals(skeleton)


## Read-only pose state for tools, tests, networking studies and later controllers.
func pose_state() -> Dictionary:
	var joints := {}
	for j in profile.joints:
		var s: Dictionary = limit_modifier.states.get(j.bone, {})
		joints[j.bone] = {
			"final_deg": get_joint_angles(j.bone, "final"),
			"animation_deg": get_joint_angles(j.bone, "animation"),
			"incoming_beyond_hard_deg": rad_to_deg(s.get("hard", 0.0)),
			"soft_load": s.get("soft", 0.0),
		}
	return {"version": VERSION, "mode": MODE_NAMES[mode], "clip": clip,
		"time": player.current_animation_position if player.assigned_animation != "" else 0.0,
		"response_state": response_state, "limits_enforced": limit_modifier.enforce,
		"limit_policy": ["procedural", "always", "measure"][limit_policy],
		"hinge_align": hinge_modifier.active, "hinge_transfer_deg": _transfer_deg(),
		"violating_joints": limit_modifier.violating, "worst_violation_deg": limit_modifier.worst_deg,
		"worst_violation_bone": limit_modifier.worst_bone, "joints": joints,
		"measurements": definition.measurements, "ik_layer": "none (phase 2)"}


func _transfer_deg() -> Dictionary:
	var out := {}
	for k in hinge_modifier.transferred:
		out[k] = rad_to_deg(hinge_modifier.transferred[k])
	return out


## Phase 2 interface, reserved. Stores the request; nothing solves it yet. Returns ERR_UNAVAILABLE.
## effector: "left_hand" | "right_hand" | "left_foot" | "right_foot"; target in this node's space.
func request_ik_target(effector: String, target: Transform3D, influence := 1.0, pole := Vector3.ZERO) -> int:
	ik_requests[effector] = {"target": target, "influence": clampf(influence, 0.0, 1.0), "pole": pole}
	return ERR_UNAVAILABLE


func clear_ik_target(effector: String) -> void:
	ik_requests.erase(effector)


## Phase 3+ interface, reserved: an impulse (N*s) at a world point on a bone. Returns ERR_UNAVAILABLE.
func apply_impact(_bone: String, _impulse: Vector3, _world_point: Vector3) -> int:
	return ERR_UNAVAILABLE


## Phase 3+ interface: only "animated" is implemented. Returns OK or ERR_UNAVAILABLE.
func set_response_state(state: String) -> int:
	if state == "animated":
		response_state = state
		return OK
	return ERR_UNAVAILABLE
