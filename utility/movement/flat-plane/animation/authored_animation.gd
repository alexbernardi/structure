## Sole normal-playback bone owner: native clip mixing, followed by bounded correction modifiers.
extends Node

const Model = preload("res://animation/locomotion_model.gd")
const FootOrientation = preload("res://animation/foot_orientation.gd")
const STATES := ["Idle", "Run", "Jump", "Fall", "Land", "Crouch"]
const MAX_FOOT_CORRECTION := 0.10

var visual
var params
var model
var tree := AnimationTree.new()
var machine := AnimationNodeStateMachine.new()
var playback: AnimationNodeStateMachinePlayback
var transitions: Array[AnimationNodeStateMachineTransition] = []
var max_correction := 0.0
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _ik: Array[TwoBoneIK3D] = []
var _previous_position := Vector3.ZERO
var _have_position := false
var measured_speed := 0.0
var _heading := 0.0
var final_feet := {}
var _orientation := FootOrientation.new()


func setup(target: Node3D, parameters) -> void:
	visual = target
	visual.player.stop()
	visual.player.active = false
	params = parameters
	model = Model.new(params, visual.proportion_scale)
	_build_graph()
	_build_ik()
	_orientation.modification_processed.connect(_capture_final_feet)


func _capture_final_feet() -> void:
	for side in ["Left", "Right"]:
		final_feet[side] = visual.skeleton.get_bone_global_pose(visual.bone_index[side + "Foot"])


func _clip(name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = name
	return node


func _build_graph() -> void:
	var run := AnimationNodeBlendTree.new()
	var gaits := AnimationNodeBlendSpace1D.new()
	gaits.min_space = 0.0
	gaits.max_space = 1.0
	gaits.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	gaits.add_blend_point(_clip("Jog_Fwd"), 0.0, -1, &"Jog")
	gaits.add_blend_point(_clip("Sprint"), 1.0, -1, &"Sprint")
	run.add_node("Gaits", gaits)
	run.add_node("Cadence", AnimationNodeTimeScale.new())
	run.add_node("Idle", _clip("Idle"))
	run.add_node("StartStop", AnimationNodeBlend2.new())
	run.connect_node("Cadence", 0, "Gaits")
	run.connect_node("StartStop", 0, "Idle")
	run.connect_node("StartStop", 1, "Cadence")
	run.connect_node("output", 0, "StartStop")
	machine.add_node("Idle", _clip("Idle"))
	machine.add_node("Run", run)
	machine.add_node("Jump", _clip("Jump_Start"))
	machine.add_node("Fall", _clip("Jump"))
	machine.add_node("Land", _clip("Jump_Land"))
	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = 2.0
	crouch.add_blend_point(_clip("Crouch_Idle"), 0.0, -1, &"Still")
	crouch.add_blend_point(_clip("Crouch_Fwd"), 2.0, -1, &"Moving")
	machine.add_node("Crouch", crouch)
	for from in STATES:
		for to in STATES:
			if from == to:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = params.get_value("transition_duration")
			machine.add_transition(from, to, transition)
			transitions.append(transition)
	tree.name = "AuthoredAnimationTree"
	visual.add_child(tree)
	tree.anim_player = ^"../AnimationPlayer"
	tree.tree_root = machine
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	playback = tree.get("parameters/playback")
	playback.start("Idle")
	tree.advance(0.0)


func _build_ik() -> void:
	visual.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	for side in ["Left", "Right"]:
		var target := Node3D.new()
		target.name = side + "FootTarget"
		visual.add_child(target)
		var pole := Node3D.new()
		pole.name = side + "KneePole"
		visual.add_child(pole)
		var ik := TwoBoneIK3D.new()
		ik.name = side + "FootCorrection"
		visual.skeleton.add_child(ik)
		ik.setting_count = 1
		ik.set_root_bone_name(0, side + "UpperLeg")
		ik.set_middle_bone_name(0, side + "LowerLeg")
		ik.set_end_bone_name(0, side + "Foot")
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		ik.active = false
		_targets.append(target)
		_poles.append(pole)
		_ik.append(ik)
	visual.skeleton.add_child(_orientation)


func follow(body: Node3D, offset: float, teleported: bool, dt: float) -> void:
	var position: Vector3 = body.get_global_transform_interpolated().origin
	measured_speed = 0.0
	if _have_position and not teleported and dt > 0.0:
		measured_speed = Vector2(position.x - _previous_position.x, position.z - _previous_position.z).length() / dt
	_previous_position = position
	_have_position = true
	visual.global_position = position + Vector3.UP * offset


func update(dt: float, state: Dictionary) -> void:
	var speed: float = state.speed
	var heading: float = state.get("heading", NAN)
	var teleported: bool = state.get("teleported", false)
	if is_finite(heading):
		_heading = heading if teleported else lerp_angle(_heading, heading, 1.0 - exp(-12.0 * dt))
	visual.rotation.y = _heading + PI
	model.update(dt, speed, state.grounded, state.vy, state.get("accel_forward", 0.0), teleported, state.get("crouching", false))
	for transition in transitions:
		transition.xfade_time = params.get_value("transition_duration")
	tree.set("parameters/Run/Gaits/blend_position", model.sprint_blend)
	tree.set("parameters/Run/Cadence/scale", model.cadence)
	tree.set("parameters/Run/StartStop/blend_amount", model.run_weight)
	tree.set("parameters/Crouch/blend_position", speed)
	if String(playback.get_current_node()) != model.state:
		playback.travel(model.state)
	tree.advance(dt)
	var chest: int = visual.bone_index.Chest
	visual.skeleton.set_bone_pose_rotation(chest, Quaternion(Vector3.RIGHT, model.lean) * visual.skeleton.get_bone_pose_rotation(chest))
	_correct_feet(state.grounded, dt)


func _correct_feet(grounded: bool, dt: float) -> void:
	max_correction = 0.0
	for index in 2:
		var side := "Left" if index == 0 else "Right"
		var skeleton: Skeleton3D = visual.skeleton
		var foot := skeleton.get_bone_global_pose(visual.bone_index[side + "Foot"])
		var knee := skeleton.get_bone_global_pose(visual.bone_index[side + "LowerLeg"]).origin
		var hip := skeleton.get_bone_global_pose(visual.bone_index[side + "UpperLeg"]).origin
		var desired := foot.origin
		desired.z = hip.z + (desired.z - hip.z) * model.stride
		var correction := desired - foot.origin
		_orientation.orientations[visual.bone_index[side + "Foot"]] = foot.basis
		if grounded and params.is_on("foot_ik"):
			var sole := Vector3(0, INF, 0)
			for point in visual.sole_points[side]:
				var corner: Vector3 = foot * point
				if corner.y < sole.y:
					sole = corner
			correction.y = clampf(-sole.y, 0.0, MAX_FOOT_CORRECTION)
			var horizontal := Vector2(correction.x, correction.z).limit_length(sqrt(maxf(0.0, MAX_FOOT_CORRECTION ** 2 - correction.y ** 2)))
			correction.x = horizontal.x
			correction.z = horizontal.y
		correction = correction.limit_length(MAX_FOOT_CORRECTION)
		max_correction = maxf(max_correction, correction.length())
		_targets[index].transform = Transform3D(foot.basis, foot.origin + correction)
		_poles[index].position = knee + (knee - (hip + foot.origin) * 0.5).normalized() * 0.5
		_ik[index].active = grounded and correction.length() > 0.0001
	visual.skeleton.advance(dt)


func set_enabled(enabled: bool) -> void:
	tree.active = enabled
	visual.visible = enabled
	if enabled:
		_have_position = false
