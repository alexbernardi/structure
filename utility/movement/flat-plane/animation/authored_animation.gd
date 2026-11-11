## Sole normal-playback bone owner: native clip mixing, followed by bounded correction modifiers.
extends Node

const Model = preload("res://animation/locomotion_model.gd")
const FootOrientation = preload("res://animation/foot_orientation.gd")
const TwoBoneCorrection = preload("res://animation/two_bone_correction.gd")
const VaultClip = preload("res://traversal/vault_clip.gd")
const MantleClip = preload("res://traversal/mantle_clip.gd")
const PullupClip = preload("res://traversal/pullup_clip.gd")
const ClipPose = preload("res://traversal/clip_pose.gd")
const SLIDE_START_SHOWN := 0.55    ## s of Slide_Start (the drop into the slide) before the slide loop
const SLIDE_LOOP_LENGTH := 2.0
const SLIDE_EXIT_LENGTH := 0.5
const SLIDE_LOOP_SPEED := 4.5      ## m/s the authored slide loop travels (its root motion)
const AIR_JUMP_CLIP := "DoubleJump"
const AIR_JUMP_SHOWN := 0.45       ## s of the authored double jump shown before the air loop takes over
const MIRROR_VAULT := "SafetyVault_Mirror"
const SPEED_PITCH := 0.14          ## rad of extra forward torso pitch on a vault at 9 m/s and above (none at 4 m/s)
const TURN_RATE := 20.0            ## 1/s heading response while vaulting
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
var has_mantle := false
var has_air_jump := false
var max_correction := 0.0
var hand_error := 0.0           ## m between the support hand and its contact point after correction (telemetry)
var phase_steer := 1.0
var takeoff_eta := INF          ## s until the vault takeoff the steering is aiming at (telemetry)
var run_phase := 0.0            ## shared phase (0..1) of the jog and sprint loops; the graph is seeked to it every frame
var _correction := TwoBoneCorrection.new()
var _feet: Array = []        ## TwoBoneCorrection.Chain per side (Left, Right)
var _arm                     ## TwoBoneCorrection.Chain of the current vault's support hand (right or left)
var _arm_right
var _arm_left
var has_vault_mirror := false
var has_pullup := false
var has_slide := false
var grip_error := 0.0           ## m: the larger hand distance from its edge target while both hands grip (telemetry)
var _gripping := false
var _grip_targets := {}
var _grip_hand := {}
var vault_mirrored := false     ## the vault showing now is the mirrored (left-hand, right-foot) variant
var vault_variants := {"right": 0, "left": 0}   ## variants shown (telemetry, tests)
var vault_pitch := 0.0          ## the speed-linked torso pitch applied this frame (telemetry)
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
	grip_error = 0.0
	if _gripping:
		for side in _grip_targets:
			var chain = _arm_left if side == "Left" else _arm_right
			if chain.active and chain.influence > 0.99:
				var final: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.bone_index[side + "Hand"]).origin
				grip_error = maxf(grip_error, final.distance_to(_grip_targets[side]))
	if _arm.active and not _gripping:
		var wrist: Vector3 = visual.skeleton.get_bone_global_pose(visual.bone_index.LeftHand if vault_mirrored else visual.bone_index.RightHand).origin
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
		# Movement Lab 5.1: the exact mirror of the authored vault (left-hand support, right-foot entry).
		has_vault_mirror = visual.traversal_clips.has(MIRROR_VAULT)
		if has_vault_mirror:
			var mirror := AnimationNodeBlendTree.new()
			mirror.add_node("Clip", _clip(MIRROR_VAULT))
			mirror.add_node("Seek", AnimationNodeTimeSeek.new())
			mirror.connect_node("Seek", 0, "Clip")
			mirror.connect_node("output", 0, "Seek")
			machine.add_node("VaultMirror", mirror)
			for other in STATES + ["Vault"]:
				for pair in [[other, "VaultMirror"], ["VaultMirror", other]]:
					var transition := AnimationNodeStateMachineTransition.new()
					transition.xfade_time = 0.12
					machine.add_transition(pair[0], pair[1], transition)
					vault_transitions.append(transition)
	# Movement Lab 5.0-5.2 moves, each played by the clock of the action that owns it: the mantle and the pull-up by
	# the climb's clip time (the hang holds the pull-up's grip frame), the air jump by the time since it, the slide by
	# the slide's own time.
	has_mantle = visual.traversal_clips.has(MantleClip.CLIP)
	has_air_jump = visual.traversal_clips.has(AIR_JUMP_CLIP)
	has_pullup = visual.traversal_clips.has(PullupClip.CLIP)
	has_slide = visual.traversal_clips.has("Slide") and visual.traversal_clips.has("Slide_Start") and visual.traversal_clips.has("Slide_Exit")
	for entry in [["Mantle", MantleClip.CLIP, has_mantle], ["AirJump", AIR_JUMP_CLIP, has_air_jump], ["Pullup", PullupClip.CLIP, has_pullup],
			["SlideStart", "Slide_Start", has_slide], ["SlideLoop", "Slide", has_slide], ["SlideExit", "Slide_Exit", has_slide]]:
		if not entry[2]:
			continue
		var node := AnimationNodeBlendTree.new()
		node.add_node("Clip", _clip(entry[1]))
		node.add_node("Seek", AnimationNodeTimeSeek.new())
		node.connect_node("Seek", 0, "Clip")
		node.connect_node("output", 0, "Seek")
		machine.add_node(entry[0], node)
	var names: Array = STATES.duplicate()
	for extra in ["Vault", "VaultMirror", "Mantle", "AirJump", "Pullup", "SlideStart", "SlideLoop", "SlideExit"]:
		if machine.has_node(extra):
			names.append(extra)
	for a in names:
		for b in names:
			if a != b and not machine.has_transition(a, b):
				var transition := AnimationNodeStateMachineTransition.new()
				transition.xfade_time = 0.12
				machine.add_transition(a, b, transition)
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
	_arm_right = _correction.add_chain(skeleton, bones.RightUpperArm, bones.RightLowerArm, bones.RightHand)
	_arm_left = _correction.add_chain(skeleton, bones.LeftUpperArm, bones.LeftLowerArm, bones.LeftHand)
	_arm = _arm_right
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
	if vaulting and not _was_vaulting:
		_start_vault_variant(vault)
	var shape := 0.0                 # 0..1: the body is over the obstacle (hand planted until the legs come through)
	if vaulting:
		var t: float = vault.time
		shape = smoothstep(VaultClip.TAKEOFF, VaultClip.HAND_PLANT, t) * (1.0 - smoothstep(0.45, VaultClip.LANDING, t))
		# An angled face turns the body toward its normal as the hand releases and the legs swing through (not while the
		# hand bears weight, which would pull the shoulder off the planted hand); travel stays on the planned line.
		var swing := smoothstep(VaultClip.HAND_PLANT, VaultClip.HAND_RELEASE + 0.05, t) * (1.0 - smoothstep(0.5, VaultClip.LANDING, t))
		heading = vault.heading + float(vault.get("turn", 0.0)) * swing
	var climb: Dictionary = vault.get("mantle", {})
	var pulling: bool = has_pullup and not climb.is_empty() and climb.get("clip", "climb") == "pullup"
	var mantling: bool = (has_mantle or pulling) and not climb.is_empty() and (climb.get("hang", false) or climb.time < float(climb.get("length", MantleClip.LENGTH)) - response * float(climb.rate))
	var slide: Dictionary = vault.get("slide", {})
	var sliding: bool = has_slide and not slide.is_empty() and not mantling and not vaulting
	if mantling:
		heading = climb.heading
	var air_jumping: bool = has_air_jump and not mantling and not vaulting and not state.grounded and float(vault.get("air_jump", INF)) < AIR_JUMP_SHOWN
	if is_finite(heading):
		var turn := 20.0 if vaulting else 12.0
		_heading = heading if teleported else lerp_angle(_heading, heading, 1.0 - exp(-turn * dt))
	visual.rotation.y = _heading + PI
	model.steer = phase_steer
	var was_running: bool = model.state == "Run"
	model.update(dt, speed, state.grounded, state.vy, state.get("accel_forward", 0.0), teleported, state.get("crouching", false), vaulting or mantling)
	if mantling:
		model.state = "Pullup" if pulling else "Mantle"
	elif sliding:
		model.state = _slide_state(slide)
	elif air_jumping:
		model.state = "AirJump"
	elif vaulting and vault_mirrored:
		model.state = "VaultMirror"
	var starting_run: bool = model.state == "Run" and not was_running
	if starting_run and not _was_vaulting:
		run_phase = 0.0
		if vault.has("approach") and vault_profile != null and vault_profile.valid:
			# Choose a support foot during the entry crossfade, not by jumping an already-running loop.
			var advance := _natural_advance(vault.approach).x
			run_phase = vault_profile.entry_phase
			if absf(wrapf(advance + 0.5, -0.5, 0.5)) < absf(wrapf(advance, -0.5, 0.5)):
				run_phase += 0.5
	for transition in transitions:
		transition.xfade_time = params.get_value("transition_duration")
	for transition in vault_transitions:
		transition.xfade_time = response
	_steer_phase(vault, dt)
	tree.set("parameters/Run/Gaits/blend_position", model.sprint_blend)
	tree.set("parameters/Run/StartStop/blend_amount", model.run_weight)
	tree.set("parameters/Crouch/blend_position", speed)
	if has_vault and vault.get("vault", false):
		var node := "VaultMirror" if vault_mirrored else "Vault"
		tree.set("parameters/%s/Seek/seek_request" % node, clampf(vault.time, 0.0, VaultClip.LENGTH - 0.0005))
	if mantling:
		var node := "Pullup" if pulling else "Mantle"
		tree.set("parameters/%s/Seek/seek_request" % node, clampf(float(climb.time), 0.0, float(climb.get("length", MantleClip.LENGTH)) - 0.0005))
	if sliding:
		_seek_slide(slide)
	if air_jumping:
		tree.set("parameters/AirJump/Seek/seek_request", clampf(float(vault.air_jump), 0.0, AIR_JUMP_SHOWN))
	_advance_run_phase(vault, vaulting, starting_run, dt)
	_was_vaulting = vaulting
	if String(playback.get_current_node()) != model.state:
		playback.travel(model.state)
	var spine: int = visual.bone_index.Spine
	visual.skeleton.set_bone_pose_rotation(spine, _spine_base)   # undo last frame's support lean before mixing
	tree.advance(dt)
	_spine_base = visual.skeleton.get_bone_pose_rotation(spine)
	var chest: int = visual.bone_index.Chest
	# A fast vault is taken leaning into it, a slow one upright (speed-linked pitch while over the obstacle).
	vault_pitch = clampf((float(vault.get("speed", 0.0)) - 4.0) / 5.0, 0.0, 1.0) * SPEED_PITCH * shape if vaulting else 0.0
	visual.skeleton.set_bone_pose_rotation(chest, Quaternion(Vector3.RIGHT, model.lean + vault_pitch) * visual.skeleton.get_bone_pose_rotation(chest))
	_support(vault)
	_grip(climb if mantling and pulling else {})
	_correct_feet(state.grounded and not vaulting and not mantling and not sliding, dt)


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
func _advance_run_phase(vault: Dictionary, vaulting: bool, starting_run: bool, dt: float) -> void:
	var rate: float = model.cadence * phase_steer / _gait_length()
	if _was_vaulting and not vaulting and model.state == "Run" and vault_profile != null:
		var remaining := 0.0
		if vault.get("vault", false):
			remaining = maxf(0.0, VaultClip.LENGTH - float(vault.time)) / float(vault.get("rate", 1.0))
		run_phase = (vault_profile.mirror_exit_phase if vault_mirrored else vault_profile.exit_phase) - remaining * rate
	elif not starting_run:
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
		var best_miss := INF
		for aim in _entry_aims(vault):
			var below: float = aim + floorf(phase + advance - aim)
			for goal in [below, below + 1.0]:
				var steer := clampf((goal - phase) / advance, PHASE_STEER[0], PHASE_STEER[1])
				var miss := absf(phase + advance * steer - goal)
				if miss < best_miss - 0.002 or (miss <= best_miss + 0.002 and absf(log(steer)) < absf(log(target))):
					best_miss = minf(best_miss, miss)
					target = steer
	phase_steer = lerpf(phase_steer, target, 1.0 - exp(-10.0 * dt))


## Gait cycles (x) and seconds (y) to takeoff. Predict the core's acceleration toward input speed, then the action's
## distance-based easing; integrate cadence with the same lagging jog/sprint blend as the locomotion model.
func _natural_advance(approach: Dictionary) -> Vector2:
	var distance: float = maxf(approach.distance, 0.0)
	var speed: float = maxf(approach.speed, 0.1)
	var travel: float = maxf(approach.travel_speed, 0.1)
	var ease: float = clampf(approach.ease, 0.0, distance)
	var blend: float = model.sprint_blend
	var blend_rate: float = 1.0 / params.get_value("transition_duration")
	var cycles := 0.0
	var time := 0.0
	var run_in := distance - ease
	if run_in > 0.0:
		var target_speed: float = maxf(speed, approach.get("target_speed", speed))
		var acceleration: float = maxf(0.0, approach.get("acceleration", 0.0))
		var step := run_in / 12.0
		for i in 12:
			var dt := step / speed
			if acceleration > 0.0 and speed < target_speed:
				var accelerated := minf(step, (target_speed * target_speed - speed * speed) / (2.0 * acceleration))
				var next_speed := sqrt(speed * speed + 2.0 * acceleration * accelerated)
				dt = (next_speed - speed) / acceleration + (step - accelerated) / next_speed
				speed = next_speed
			var average_speed := step / dt
			var target: float = model.blend_target(average_speed)
			var mid := move_toward(blend, target, 0.5 * dt * blend_rate)
			cycles += dt * model.cycle_rate(average_speed, mid)
			blend = move_toward(blend, target, dt * blend_rate)
			time += dt
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


## Entry phases the approach may steer toward: the planned support side's, or both variants' when the face is square
## (the stride then decides which foot - and so which hand - leads).
func _entry_aims(vault: Dictionary) -> Array:
	var side: int = int(vault.get("side", 0))
	var authored: float = vault.get("entry_phase", vault_profile.entry_phase)
	var mirrored: float = vault.get("mirror_entry_phase", vault_profile.mirror_entry_phase)
	if not has_vault_mirror or side > 0:
		return [authored]
	if side < 0:
		return [mirrored]
	return [authored, mirrored]


## Picks the variant at takeoff: an angled face fixed the support side in the plan; a square face takes the variant
## whose entry foot is nearest the stride the runner is actually on (so consecutive vaults follow the gait instead of
## resetting to one pose). Locked until the vault has finished showing.
func _start_vault_variant(vault: Dictionary) -> void:
	var side: int = int(vault.get("side", 0))
	vault_mirrored = false
	if has_vault_mirror and side < 0:
		vault_mirrored = true
	elif has_vault_mirror and side == 0:
		var phase := gait_phase()
		var to_authored := absf(wrapf(phase - vault_profile.entry_phase, -0.5, 0.5))
		var to_mirrored := absf(wrapf(phase - vault_profile.mirror_entry_phase, -0.5, 0.5))
		vault_mirrored = to_mirrored < to_authored
	_arm_right.active = false
	_arm_left.active = false
	_orientation.orientations.erase(visual.bone_index.RightHand)
	_orientation.orientations.erase(visual.bone_index.LeftHand)
	_arm = _arm_left if vault_mirrored else _arm_right
	vault_variants["left" if vault_mirrored else "right"] += 1


## The slide's authored states: the drop into it, the loop while momentum lasts, the recovery.
func _slide_state(slide: Dictionary) -> String:
	if float(slide.get("exit", -1.0)) >= 0.0:
		return "SlideExit"
	return "SlideStart" if float(slide.time) < SLIDE_START_SHOWN / _slide_rate(slide) else "SlideLoop"


## Playback follows the slide speed: the authored loop travels 4.5 m/s, so a faster slide drags faster.
func _slide_rate(slide: Dictionary) -> float:
	return clampf(float(slide.get("speed", SLIDE_LOOP_SPEED)) / SLIDE_LOOP_SPEED, 0.6, 1.6)


func _seek_slide(slide: Dictionary) -> void:
	var rate := _slide_rate(slide)
	var t: float = slide.time
	tree.set("parameters/SlideStart/Seek/seek_request", clampf(t * rate, 0.0, SLIDE_START_SHOWN))
	tree.set("parameters/SlideLoop/Seek/seek_request", fposmod(maxf(t - SLIDE_START_SHOWN / rate, 0.0) * rate, SLIDE_LOOP_LENGTH))
	var exit: float = slide.get("exit", -1.0)
	if exit >= 0.0:
		tree.set("parameters/SlideExit/Seek/seek_request", clampf(exit, 0.0, SLIDE_EXIT_LENGTH - 0.0005))


## Two-handed grip on the edge while hanging and pulling up: each hand is pinned where the authored pose puts it along
## the edge, on the lip (LIP below the top, at the face), until the authored release of that hand. Keeps the hands on
## the wall while the body hangs and the root motion's linear approximation drifts during the pull.
func _grip(climb: Dictionary) -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var active := not climb.is_empty() and climb.has("edge") and float(climb.time) < PullupClip.LEFT_RELEASE + 0.06
	if not active:
		if _gripping:
			for chain in [_arm_left, _arm_right]:
				chain.active = false
			_orientation.orientations.erase(visual.bone_index.LeftHand)
			_orientation.orientations.erase(visual.bone_index.RightHand)
			_grip_targets.clear()
		_gripping = false
		return
	_gripping = true
	var edge: Vector3 = climb.edge
	var d: Vector3 = climb.direction
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for side in ["Left", "Right"]:
		var chain = _arm_left if side == "Left" else _arm_right
		var release: float = PullupClip.LEFT_RELEASE if side == "Left" else PullupClip.RIGHT_RELEASE
		var weight := 1.0 - smoothstep(release - 0.06, release, float(climb.time))
		var hand_bone: int = visual.bone_index[side + "Hand"]
		var hand := skeleton.get_bone_global_pose(hand_bone)
		if not _grip_targets.has(side):
			# The authored hand's sideways place on the edge in the grip frame itself (clip x = the character's left),
			# mapped onto the wall: independent of the crossfade the drawn body is in on the first frame.
			var scale: float = skeleton.global_transform.basis.get_scale().x   # skeleton space is scaled to the mannequin
			_grip_targets[side] = edge - d.cross(Vector3.UP) * _grip_hand_x(side) * scale + d * 0.02 + Vector3.DOWN * PullupClip.LIP
		var target: Vector3 = _grip_targets[side]
		var elbow := skeleton.get_bone_global_pose(visual.bone_index[side + "LowerArm"]).origin
		var shoulder := skeleton.get_bone_global_pose(visual.bone_index[side + "UpperArm"]).origin
		chain.active = weight > 0.001
		chain.influence = weight
		chain.target = to_skeleton * target
		chain.pole = elbow + (elbow - (shoulder + hand.origin) * 0.5).normalized() * 0.5
		_orientation.orientations[hand_bone] = hand.basis


## Sideways (clip x) position of a hand in the authored pull-up's grip frame, sampled from the clip once.
func _grip_hand_x(side: String) -> float:
	if _grip_hand.is_empty():
		var clip: Animation = visual.player.get_animation(PullupClip.CLIP)
		var pose := ClipPose.sample(clip, visual.skeleton, PullupClip.GRIP)
		for name in ["Left", "Right"]:
			_grip_hand[name] = pose[visual.bone_index[name + "Hand"]].origin.x
	return _grip_hand[side]


## Support hand and torso: the planned lean toward the support arm, and the hand pinned to its contact point while it
## bears weight (both scaled by contact correction). Applied to the authored pose before the correction modifiers.
func _support(vault: Dictionary) -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var side_name := "Left" if vault_mirrored else "Right"
	var hand_bone: int = visual.bone_index[side_name + "Hand"]
	var correction: float = traversal_params.get_value("contact_correction") if traversal_params != null else 1.0
	var weight: float = float(vault.get("hand_weight", 0.0)) * correction
	var lean: float = float(vault.get("lean", 0.0)) * correction * (-1.0 if vault_mirrored else 1.0)
	if absf(lean) > 0.0001:
		var spine: int = visual.bone_index.Spine
		var parent_basis := skeleton.get_bone_global_pose(skeleton.get_bone_parent(spine)).basis
		var leaned := Basis(Vector3.BACK, lean) * skeleton.get_bone_global_pose(spine).basis
		skeleton.set_bone_pose_rotation(spine, (parent_basis.inverse() * leaned).get_rotation_quaternion())
	_arm.active = weight > 0.001
	_hand_world = vault.get("hand_left" if vault_mirrored else "hand", Vector3.ZERO)
	if not _arm.active:
		_orientation.orientations.erase(hand_bone)
		return
	var hand := skeleton.get_bone_global_pose(hand_bone)
	var elbow := skeleton.get_bone_global_pose(visual.bone_index[side_name + "LowerArm"]).origin
	var shoulder := skeleton.get_bone_global_pose(visual.bone_index[side_name + "UpperArm"]).origin
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
