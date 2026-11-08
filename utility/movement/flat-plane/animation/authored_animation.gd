## Sole normal-playback bone owner: native clip mixing, followed by bounded correction modifiers.
extends Node

const Model = preload("res://animation/locomotion_model.gd")
const FootOrientation = preload("res://animation/foot_orientation.gd")
const TwoBoneCorrection = preload("res://animation/two_bone_correction.gd")
const VaultClip = preload("res://traversal/vault_clip.gd")
const STATES := ["Idle", "Run", "Jump", "Fall", "Land", "Crouch"]
const MAX_FOOT_CORRECTION := 0.10
const LEG_REACH := 0.995           ## share of the leg's length a corrected foot may be from the hip (never locks the knee)
const PHASE_STEER := [0.8, 1.25]   ## cadence multiplier range used to arrive at the vault on its authored foot

var visual
var params
var model
var tree := AnimationTree.new()
var machine := AnimationNodeStateMachine.new()
var playback: AnimationNodeStateMachinePlayback
var transitions: Array[AnimationNodeStateMachineTransition] = []
var vault_transitions: Array[AnimationNodeStateMachineTransition] = []
var traversal_params
var vault_profile
var has_vault := false
var max_correction := 0.0
var hand_error := 0.0           ## m between the support hand and its contact point after correction (telemetry)
var phase_steer := 1.0
var takeoff_eta := INF          ## s until the vault takeoff the steering is aiming at (telemetry)
var run_phase := 0.0            ## shared phase (0..1) of the jog and sprint loops; the graph is seeked to it every frame
var _correction := TwoBoneCorrection.new()
var _feet: Array = []        ## TwoBoneCorrection.Chain per side (Left, Right)
var _arm                     ## TwoBoneCorrection.Chain of the vault support hand
var _hand_world := Vector3.ZERO
var _was_vaulting := false
var _spine_base := Quaternion.IDENTITY   ## Spine pose before this frame's support lean (no clip animates the Spine)
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
	_spine_base = visual.skeleton.get_bone_pose_rotation(visual.bone_index.Spine)
	_orientation.modification_processed.connect(_capture_final_feet)


func _capture_final_feet() -> void:
	for side in ["Left", "Right"]:
		final_feet[side] = visual.skeleton.get_bone_global_pose(visual.bone_index[side + "Foot"])
	hand_error = 0.0
	if _arm.active:
		var wrist: Vector3 = visual.skeleton.get_bone_global_pose(visual.bone_index.RightHand).origin
		hand_error = (visual.skeleton.global_transform * wrist).distance_to(_hand_world)


func _clip(name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = name
	return node


## A loop played at a time chosen by the script (a seek on a synced blend space would set every gait to one time,
## and Godot 4.7 does not advance seekable sub-trees inside a synced blend space at all).
func _seekable(name: String) -> AnimationNodeBlendTree:
	var node := AnimationNodeBlendTree.new()
	node.add_node("Clip", _clip(name))
	node.add_node("Seek", AnimationNodeTimeSeek.new())
	node.connect_node("Seek", 0, "Clip")
	node.connect_node("output", 0, "Seek")
	return node


func _build_graph() -> void:
	var run := AnimationNodeBlendTree.new()
	var gaits := AnimationNodeBlendSpace1D.new()
	gaits.min_space = 0.0
	gaits.max_space = 1.0
	# Phase sync is done by the script clock (run_phase), which reproduces SYNC_MODE_CYCLIC_MUTABLE: one shared
	# phase advancing at cadence / the blended loop length.
	gaits.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_NONE
	gaits.add_blend_point(_seekable("Jog_Fwd"), 0.0, -1, &"Jog")
	gaits.add_blend_point(_seekable("Sprint"), 1.0, -1, &"Sprint")
	run.add_node("Gaits", gaits)
	run.add_node("Idle", _clip("Idle"))
	run.add_node("StartStop", AnimationNodeBlend2.new())
	run.connect_node("StartStop", 0, "Idle")
	run.connect_node("StartStop", 1, "Gaits")
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
	# The authored vault is played by clip time (the traversal action owns its timing), never by its own clock.
	has_vault = visual.traversal_clips.has(VaultClip.CLIP)
	if has_vault:
		var vault := AnimationNodeBlendTree.new()
		vault.add_node("Clip", _clip(VaultClip.CLIP))
		vault.add_node("Seek", AnimationNodeTimeSeek.new())
		vault.connect_node("Seek", 0, "Clip")
		vault.connect_node("output", 0, "Seek")
		machine.add_node("Vault", vault)
		for other in STATES:
			for pair in [[other, "Vault"], ["Vault", other]]:
				var transition := AnimationNodeStateMachineTransition.new()
				transition.xfade_time = 0.12
				machine.add_transition(pair[0], pair[1], transition)
				vault_transitions.append(transition)
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
	var skeleton: Skeleton3D = visual.skeleton
	var bones: Dictionary = visual.bone_index
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_correction.name = "ContactCorrection"
	skeleton.add_child(_correction)
	for side in ["Left", "Right"]:
		_feet.append(_correction.add_chain(skeleton, bones[side + "UpperLeg"], bones[side + "LowerLeg"], bones[side + "Foot"]))
	# Support hand of the vault: planted on the obstacle top while the clip says the hand bears weight.
	_arm = _correction.add_chain(skeleton, bones.RightUpperArm, bones.RightLowerArm, bones.RightHand)
	skeleton.add_child(_orientation)


## Traversal presentation inputs: the transition response and contact correction controls, and the measured vault.
func setup_traversal(parameters, profile) -> void:
	traversal_params = parameters
	vault_profile = profile


func follow(body: Node3D, offset: Vector3, teleported: bool, dt: float) -> void:
	var position: Vector3 = body.get_global_transform_interpolated().origin
	measured_speed = 0.0
	if _have_position and not teleported and dt > 0.0:
		measured_speed = Vector2(position.x - _previous_position.x, position.z - _previous_position.z).length() / dt
	_previous_position = position
	_have_position = true
	visual.global_position = position + offset


func update(dt: float, state: Dictionary) -> void:
	var speed: float = state.speed
	var heading: float = state.get("heading", NAN)
	var teleported: bool = state.get("teleported", false)
	var vault: Dictionary = state.get("vault", {})
	var response: float = traversal_params.get_value("transition_response") if traversal_params != null else 0.12
	var vaulting := has_vault and _vault_showing(vault, response)
	if vaulting:
		heading = vault.heading
	if is_finite(heading):
		var turn := 20.0 if vaulting else 12.0
		_heading = heading if teleported else lerp_angle(_heading, heading, 1.0 - exp(-turn * dt))
	visual.rotation.y = _heading + PI
	model.steer = phase_steer
	model.update(dt, speed, state.grounded, state.vy, state.get("accel_forward", 0.0), teleported, state.get("crouching", false), vaulting)
	for transition in transitions:
		transition.xfade_time = params.get_value("transition_duration")
	for transition in vault_transitions:
		transition.xfade_time = response
	_steer_phase(vault, dt)
	tree.set("parameters/Run/Gaits/blend_position", model.sprint_blend)
	tree.set("parameters/Run/StartStop/blend_amount", model.run_weight)
	tree.set("parameters/Crouch/blend_position", speed)
	if has_vault and vault.get("vault", false):
		tree.set("parameters/Vault/Seek/seek_request", clampf(vault.time, 0.0, VaultClip.LENGTH - 0.0005))
	_advance_run_phase(vault, vaulting, response, dt)
	_was_vaulting = vaulting
	if String(playback.get_current_node()) != model.state:
		playback.travel(model.state)
	var spine: int = visual.bone_index.Spine
	visual.skeleton.set_bone_pose_rotation(spine, _spine_base)   # undo last frame's support lean before mixing
	tree.advance(dt)
	_spine_base = visual.skeleton.get_bone_pose_rotation(spine)
	var chest: int = visual.bone_index.Chest
	visual.skeleton.set_bone_pose_rotation(chest, Quaternion(Vector3.RIGHT, model.lean) * visual.skeleton.get_bone_pose_rotation(chest))
	_support(vault)
	_correct_feet(state.grounded and not vaulting, dt)


## The vault shows until the crossfade back to running would finish with the clip, so the run picks up mid-landing
## at the phase that continues the vault's last steps instead of freezing on its final frame.
func _vault_showing(vault: Dictionary, response: float) -> bool:
	if not vault.get("vault", false):
		return false
	var rate: float = vault.get("rate", 1.0)
	return vault.time < maxf(VaultClip.LANDING, VaultClip.LENGTH - response * rate)


func _gait_length() -> float:
	return lerpf(Model.JOG_LENGTH, Model.SPRINT_LENGTH, model.sprint_blend)


## Current phase (0..1) of the running loop.
func gait_phase() -> float:
	return run_phase


## The running loops' clock. It advances at the cadence (times the anticipation steer) over the blended loop length,
## restarts with the Run state like a fresh clip, and after a vault resumes at the phase that continues the vault's
## last steps, less the part of the vault still to play during the fade back.
func _advance_run_phase(vault: Dictionary, vaulting: bool, response: float, dt: float) -> void:
	var rate: float = model.cadence * phase_steer / _gait_length()
	if _was_vaulting and not vaulting and model.state == "Run" and vault_profile != null:
		var remaining := 0.0
		if vault.get("vault", false):
			remaining = maxf(0.0, VaultClip.LENGTH - float(vault.time)) / float(vault.get("rate", 1.0))
		run_phase = vault_profile.exit_phase - remaining * rate
	elif model.state == "Run" and String(playback.get_current_node()) != "Run":
		run_phase = 0.0
	else:
		run_phase += dt * rate
	run_phase = fposmod(run_phase, 1.0)
	tree.set("parameters/Run/Gaits/Jog/Seek/seek_request", run_phase * Model.JOG_LENGTH)
	tree.set("parameters/Run/Gaits/Sprint/Seek/seek_request", run_phase * Model.SPRINT_LENGTH)


## Anticipation: while a vault lies ahead, scales the run cadence (within PHASE_STEER) so the gait reaches the vault's
## entry pose at takeoff, then eases back. Of the entry poses just before and just after where the unsteered gait would
## arrive, it aims for the one it can reach (the gentler steer if both). Presentation only; the body is untouched.
func _steer_phase(vault: Dictionary, dt: float) -> void:
	var target := 1.0
	takeoff_eta = INF
	if vault.has("approach") and model.state == "Run" and vault_profile != null and vault_profile.valid:
		var natural := _natural_advance(vault.approach)
		takeoff_eta = natural.y
		var advance := maxf(natural.x, 0.001)
		var phase := gait_phase()
		var aim: float = vault.entry_phase
		var below := aim + floorf(phase + advance - aim)
		var best_miss := INF
		for goal in [below, below + 1.0]:
			var steer := clampf((goal - phase) / advance, PHASE_STEER[0], PHASE_STEER[1])
			var miss := absf(phase + advance * steer - goal)
			if miss < best_miss - 0.002 or (miss <= best_miss + 0.002 and absf(log(steer)) < absf(log(target))):
				best_miss = minf(best_miss, miss)
				target = steer
	phase_steer = lerpf(phase_steer, target, 1.0 - exp(-10.0 * dt))


## Gait cycles (x) and seconds (y) the unsteered run takes to cover a vault approach: constant speed until the
## anticipation easing starts, then speed linear in the remaining distance down to the vault's travel speed (as the
## traversal action eases it), with the jog/sprint blend lagging the speed as the model's does.
func _natural_advance(approach: Dictionary) -> Vector2:
	var distance: float = maxf(approach.distance, 0.0)
	var speed: float = maxf(approach.speed, 0.1)
	var travel: float = maxf(approach.travel_speed, 0.1)
	var ease: float = clampf(approach.ease, 0.0, distance)
	var blend: float = model.sprint_blend
	var blend_rate: float = 1.0 / params.get_value("transition_duration")
	var cycles := 0.0
	var time := 0.0
	var run_in := (distance - ease) / speed
	if run_in > 0.0:
		var target: float = model.blend_target(speed)
		for i in 6:
			var dt := run_in / 6.0
			var mid := move_toward(blend, target, 0.5 * dt * blend_rate)
			cycles += dt * model.cycle_rate(speed, mid)
			blend = move_toward(blend, target, dt * blend_rate)
		time = run_in
	if ease > 0.0:
		var step := ease / 12.0
		for i in 12:
			var from := travel + (speed - travel) * (ease - i * step) / ease
			var to := travel + (speed - travel) * (ease - (i + 1) * step) / ease
			var dt := step / from if absf(from - to) < 0.0001 else step * log(from / to) / (from - to)
			var v := 0.5 * (from + to)
			var target: float = model.blend_target(v)
			var mid := move_toward(blend, target, 0.5 * dt * blend_rate)
			cycles += dt * model.cycle_rate(v, mid)
			blend = move_toward(blend, target, dt * blend_rate)
			time += dt
	return Vector2(cycles, time)


## Support hand and torso: the planned lean toward the support arm, and the hand pinned to its contact point while it
## bears weight (both scaled by contact correction). Applied to the authored pose before the correction modifiers.
func _support(vault: Dictionary) -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var hand_bone: int = visual.bone_index.RightHand
	var correction: float = traversal_params.get_value("contact_correction") if traversal_params != null else 1.0
	var weight: float = float(vault.get("hand_weight", 0.0)) * correction
	var lean: float = float(vault.get("lean", 0.0)) * correction
	if absf(lean) > 0.0001:
		var spine: int = visual.bone_index.Spine
		var parent_basis := skeleton.get_bone_global_pose(skeleton.get_bone_parent(spine)).basis
		var leaned := Basis(Vector3.BACK, lean) * skeleton.get_bone_global_pose(spine).basis
		skeleton.set_bone_pose_rotation(spine, (parent_basis.inverse() * leaned).get_rotation_quaternion())
	_arm.active = weight > 0.001
	_hand_world = vault.get("hand", Vector3.ZERO)
	if not _arm.active:
		_orientation.orientations.erase(hand_bone)
		return
	var hand := skeleton.get_bone_global_pose(hand_bone)
	var elbow := skeleton.get_bone_global_pose(visual.bone_index.RightLowerArm).origin
	var shoulder := skeleton.get_bone_global_pose(visual.bone_index.RightUpperArm).origin
	_arm.influence = minf(weight, 1.0)
	_arm.target = skeleton.global_transform.affine_inverse() * _hand_world
	_arm.pole = elbow + (elbow - (shoulder + hand.origin) * 0.5).normalized() * 0.5
	_orientation.orientations[hand_bone] = hand.basis


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
		# A stride-stretched foot near full extension stays within the leg's reach (as far as the authored foot at least).
		var reach := maxf((hip.distance_to(knee) + knee.distance_to(foot.origin)) * LEG_REACH, hip.distance_to(foot.origin))
		correction = hip + (foot.origin + correction - hip).limit_length(reach) - foot.origin
		max_correction = maxf(max_correction, correction.length())
		_feet[index].target = foot.origin + correction
		_feet[index].pole = knee + (knee - (hip + foot.origin) * 0.5).normalized() * 0.5
		_feet[index].active = grounded and correction.length() > 0.0001
	visual.skeleton.advance(dt)


func set_enabled(enabled: bool) -> void:
	tree.active = enabled
	visual.visible = enabled
	if enabled:
		_have_position = false
