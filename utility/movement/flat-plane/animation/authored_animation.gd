## Sole normal-playback bone owner: native clip mixing, followed by bounded correction modifiers.
extends Node

const Model = preload("res://animation/locomotion_model.gd")
const FootOrientation = preload("res://animation/foot_orientation.gd")
const TwoBoneCorrection = preload("res://animation/two_bone_correction.gd")
const VaultClip = preload("res://traversal/vault_clip.gd")
const MantleClip = preload("res://traversal/mantle_clip.gd")
const PullupClip = preload("res://traversal/pullup_clip.gd")
const FlipClip = preload("res://traversal/flip_clip.gd")
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
# Movement Lab 5.4: the hang (no authored hang exists: the pull-up's grip frame, placed and corrected procedurally)
const HANG_ARM := 0.97             ## share of the arm's length from shoulder to wrist while hanging (straight, not locked)
const HANG_SHOULDER_OFF := 0.22    ## m the shoulders hang out from the wall (the head and chest clear the face)
const WRIST_OUT := 0.045           ## m the wrist sits out from the face: the forearm clears the edge
const WRIST_UP := 0.024            ## m the wrist sits above the top: the palm rests on it, the fingers lie over it
const STEP_TRIGGER := 0.10         ## m a hand trails its place before it moves (shimmying)
const STEP_SETTLE := 0.03          ## m left over once the shimmy stops: the hands re-centre
const STEP_TIME := 0.22            ## s per hand move
const STEP_LIFT := 0.07            ## m a moving hand lifts off the top
const STEP_OVERSHOOT := 0.05       ## m a moving hand reaches past its place in the direction of travel
const SWING_LENGTH := 1.3          ## m from the hands to the body's centre of mass (pendulum)
const SWING_OMEGA2 := 7.5          ## (rad/s)^2: g / L for a compound pendulum hanging from the hands (about 0.37 Hz)
const SWING_DAMP := 1.4            ## 1/s
const LEG_STIFF := 60.0            ## the legs follow the body's swing through a soft hip (secondary motion)
const LEG_DAMP := 5.0
const FOOT_WALL_CLEAR := 0.12      ## m the dangling feet stay off the wall
const FOOT_GROUND_CLEAR := 0.06    ## m above the ground (a low hang braces the legs instead)
const HANG_BLEND := 0.15           ## s the drawn body takes to settle into the hang and to leave it
const FOOT_BRACE_OFF := 0.08      ## m from the wall to the braced ankle (the ball of the foot presses on the wall)
const BRACE_BELOW_HIP := 0.65     ## m below the hip the braced feet press on the wall (knees up and bent: a climber's brace)
const FOOT_STEP_TRIGGER := 0.16    ## m a braced foot trails its place before it moves (shimmying, corners)
const FOOT_STEP_TIME := 0.2        ## s per foot move
const BRACE_RATE := 6.0            ## 1/s the feet come up onto the wall after a catch (and leave it where it ends)
const BRACE_SHOULDER_OFF := 0.08   ## m further out the shoulders hang when the feet push off the wall
const TERRAIN_REACH := 0.45        ## m of ground height difference under a foot that the foot IK follows
const TERRAIN_RATE := 25.0         ## 1/s the ground under each foot is followed (no pops on step edges)
const PELVIS_RATE := 12.0          ## 1/s the pelvis drops to let the lower foot reach its ground
const FOOT_TILT_MAX := deg_to_rad(35.0)   ## steepest surface a planted foot tilts to
const ROLL_TILT := 0.35            ## share of the sideways swing the torso tilts (two hands make it a parallelogram: the arms
                                   ## swing sideways together and the shoulders stay nearly level)

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
var has_flip := false
var flip_drop := 0.0            ## m the drawn character is lowered this frame during a flip (telemetry)
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
var final_knees := {}               ## side -> world knee position after every correction (tests)
var final_hands := {}               ## side -> world transform of the hand after every correction (tests)
var _orientation := FootOrientation.new()
var ray_exclude: Array[RID] = []   ## the character's own collider (hang probes)
var hanging_shown := false
var hang_swing := Vector2.ZERO     ## rad: (pitch of the body out from the wall, roll toward its right) (telemetry)
var hand_steps := 0                ## hand moves made while shimmying (telemetry)
var two_hands_moving := 0          ## frames with both hands off the ledge (telemetry: must stay 0)
var hang_lift := 0.0               ## m the drawn body is pulled up by spread hands this frame (telemetry)
var head_clearance := 0.0          ## m the drawn head and chest would clear the face before the lean (telemetry)
var _swing_v := Vector2.ZERO
var _legs := Vector2.ZERO
var _legs_v := Vector2.ZERO
var _hang_weight := 0.0
var _hang_shift := Vector3.ZERO
var _hang_basis := Basis.IDENTITY
var _hang_legs := false
var _plants := {}                  ## side -> world wrist target while the hand is on the ledge
var _step := {}                    ## side -> {from, to, t} while that hand moves
var _prev_shimmy := 0.0
var _plant_d := {}                 ## side -> the wall direction under that hand (a corner grip has two)
var _brace := 0.0                  ## 0 dangling .. 1 both feet pushing on the wall
var _foot_plants := {}             ## side -> {at: world ankle target on the wall, n: wall normal}
var _foot_step := {}               ## side -> {from, to, t} while that foot moves along the wall
var foot_steps := 0                ## braced foot moves (telemetry)
var braced_feet := 0               ## feet on the wall this frame (telemetry)
var debug_contacts := {}           ## hand / foot IK targets, wall normals, the lip path (debug overlay, tests)
var _ground := {"Left": 0.0, "Right": 0.0}       ## ground height under each foot relative to the drawn floor (smoothed)
var _ground_normal := {"Left": Vector3.UP, "Right": Vector3.UP}
var _pelvis := 0.0                 ## m the drawn body is lowered so the lower foot reaches its ground
var mantle_hand_error := 0.0       ## m between the mantle's planted hand and its contact after correction (telemetry)
var _mantle_plant := {}            ## the quick mantle's planted left hand: {at, wrist_y, target}
var terrain_correction := 0.0      ## m largest terrain offset applied to a foot this frame (telemetry)


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
		final_hands[side] = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.bone_index[side + "Hand"])
		final_knees[side] = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.bone_index[side + "LowerLeg"]).origin
	hand_error = 0.0
	grip_error = 0.0
	if _gripping:
		for side in _grip_targets:
			var chain = _arm_left if side == "Left" else _arm_right
			if chain.active and chain.influence > 0.99:
				var final: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.bone_index[side + "Hand"]).origin
				grip_error = maxf(grip_error, final.distance_to(_grip_targets[side]))
	if not _mantle_plant.is_empty() and _arm_left.active and _arm_left.influence > 0.99:
		var planted: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.bone_index.LeftHand).origin
		mantle_hand_error = maxf(mantle_hand_error, planted.distance_to(_mantle_plant.target))
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
	has_flip = visual.traversal_clips.has(FlipClip.CLIP)
	for entry in [["Mantle", MantleClip.CLIP, has_mantle], ["AirJump", AIR_JUMP_CLIP, has_air_jump], ["Pullup", PullupClip.CLIP, has_pullup],
			["SlideStart", "Slide_Start", has_slide], ["SlideLoop", "Slide", has_slide], ["SlideExit", "Slide_Exit", has_slide],
			["Flip", FlipClip.CLIP, has_flip]]:
		if not entry[2]:
			continue
		var node := AnimationNodeBlendTree.new()
		node.add_node("Clip", _clip(entry[1]))
		node.add_node("Seek", AnimationNodeTimeSeek.new())
		node.connect_node("Seek", 0, "Clip")
		node.connect_node("output", 0, "Seek")
		machine.add_node(entry[0], node)
	var names: Array = STATES.duplicate()
	for extra in ["Vault", "VaultMirror", "Mantle", "AirJump", "Pullup", "SlideStart", "SlideLoop", "SlideExit", "Flip"]:
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
	var flip: Dictionary = vault.get("flip", {})
	var flipping: bool = has_flip and not flip.is_empty() and not mantling and not vaulting
	if flipping:
		sliding = false
		heading = flip.heading       # the flip keeps the direction it was taken in (air control steers the body, not the turn)
	if mantling:
		heading = climb.heading
	var air_jumping: bool = has_air_jump and not mantling and not vaulting and not flipping and not state.grounded and float(vault.get("air_jump", INF)) < AIR_JUMP_SHOWN
	if is_finite(heading):
		var turn := 20.0 if vaulting else 12.0
		_heading = heading if teleported else lerp_angle(_heading, heading, 1.0 - exp(-turn * dt))
	visual.rotation = Vector3(0.0, _heading + PI, 0.0)   # a hang's swing tilts the drawn body; anything else is upright
	model.steer = phase_steer
	var was_running: bool = model.state == "Run"
	model.update(dt, speed, state.grounded, state.vy, state.get("accel_forward", 0.0), teleported, state.get("crouching", false), vaulting or mantling or flipping)
	if mantling:
		model.state = "Pullup" if pulling else "Mantle"
	elif flipping:
		model.state = "Flip"
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
	if flipping:
		tree.set("parameters/Flip/Seek/seek_request", clampf(float(flip.time), 0.0, FlipClip.END))
	_advance_run_phase(vault, vaulting, starting_run, dt)
	_was_vaulting = vaulting
	if String(playback.get_current_node()) != model.state:
		playback.travel(model.state)
	var spine: int = visual.bone_index.Spine
	visual.skeleton.set_bone_pose_rotation(spine, _spine_base)   # undo last frame's support lean before mixing
	tree.advance(dt)
	_spine_base = visual.skeleton.get_bone_pose_rotation(spine)
	flip_drop = 0.0
	if flipping and flip.airborne:
		# The clip's own rise, by the flip pose's blend weight, and never so low that the pose actually drawn (a crouch or
		# slide still fading out, or the blend between them) puts a foot, hand or the head below the ground under the body.
		var lowest := INF
		for bone in ["LeftToes", "RightToes", "LeftFoot", "RightFoot", "Head", "LeftHand", "RightHand"]:
			var p: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.bone_index[bone]).origin
			lowest = minf(lowest, p.y - visual.global_position.y)
		flip_drop = minf(float(flip.get("drop", 0.0)) * _state_weight("Flip"), float(flip.get("height", 0.0)) + lowest)
	visual.global_position.y -= flip_drop
	var chest: int = visual.bone_index.Chest
	# A fast vault is taken leaning into it, a slow one upright (speed-linked pitch while over the obstacle).
	vault_pitch = clampf((float(vault.get("speed", 0.0)) - 4.0) / 5.0, 0.0, 1.0) * SPEED_PITCH * shape if vaulting else 0.0
	visual.skeleton.set_bone_pose_rotation(chest, Quaternion(Vector3.RIGHT, model.lean + vault_pitch) * visual.skeleton.get_bone_pose_rotation(chest))
	_support(vault)
	_hang(climb if mantling and climb.get("hang", false) else {}, dt)
	_grip(climb if mantling and pulling else {})
	_mantle_hand(climb if mantling and not pulling and not climb.get("hang", false) else {})
	_correct_feet(state.grounded and not vaulting and not mantling and not sliding and not flipping, dt)


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


## Blend weight of a state machine node after this frame's advance (1 when it is the settled current node).
func _state_weight(node: String) -> float:
	var current := String(playback.get_current_node())
	var from := String(playback.get_fading_from_node())
	var length := playback.get_fading_length()
	var progress := clampf(playback.get_fading_position() / length, 0.0, 1.0) if from != "" and length > 0.0 else 1.0
	if current == node:
		return progress
	return 1.0 - progress if from == node else 0.0


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
	if climb.get("hang", false):
		return                     # the hang places the hands itself (_hang)
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
		# Hands still on the edge keep the grip's orientation (palm on the top, fingers over it) as the pull-up begins.
		_orientation.orientations[hand_bone] = hand.basis.slerp(_grip_basis(d, skeleton), weight) if _plants.size() > 0 else hand.basis


## The hang, drawn: both hands on the lip (each found by rays at that hand: the top just past the face and the face),
## the body hanging from them at arm's length, swinging as a damped pendulum (out from the wall and back, bouncing off
## it; rolling sideways as the shimmy speeds up and slows down; set going by the catch), and the legs following through
## a soft hip, kept off the wall and the ground. Procedural secondary motion on the authored grip frame, not a physics
## ragdoll: presentation only. While shimmying the hands move one at a time, the leading hand first.
func _hang(climb: Dictionary, dt: float) -> void:
	var skeleton: Skeleton3D = visual.skeleton
	if climb.is_empty():
		hanging_shown = false
		_hang_legs = false
		if _hang_weight > 0.0:
			_hang_weight = maxf(0.0, _hang_weight - dt / HANG_BLEND)
			var w := smoothstep(0.0, 1.0, _hang_weight)
			var now: Transform3D = visual.global_transform
			visual.global_transform = Transform3D(now.basis.slerp(_hang_basis, w), now.origin + _hang_shift * w)
		else:
			_plants.clear()
			_step.clear()
			_foot_plants.clear()
			_foot_step.clear()
		debug_contacts = {}
		return
	var d: Vector3 = climb.direction
	var r: Vector3 = climb.right
	if not hanging_shown:
		_start_hang(climb)
	hanging_shown = true
	_hang_weight = minf(1.0, _hang_weight + dt / HANG_BLEND)
	var w := smoothstep(0.0, 1.0, _hang_weight)
	var space: PhysicsDirectSpaceState3D = visual.get_world_3d().direct_space_state
	_move_hands(climb, space, dt)
	var grip_mid := (_hand_target("Left", d) + _hand_target("Right", d)) * 0.5
	# Pendulum about the hands: x = out from the wall (it cannot swing into it), y = toward the right. Feet pushing on
	# the wall stiffen and damp the swing out from it.
	var accel := (float(climb.shimmy) - _prev_shimmy) / maxf(dt, 1e-4)
	_prev_shimmy = climb.shimmy
	_swing_v.x += (-(SWING_OMEGA2 + 25.0 * _brace) * hang_swing.x - (SWING_DAMP + 4.0 * _brace) * _swing_v.x) * dt
	_swing_v.y += (-SWING_OMEGA2 * hang_swing.y - SWING_DAMP * _swing_v.y - accel / SWING_LENGTH) * dt
	hang_swing += _swing_v * dt
	if hang_swing.x < 0.0:
		hang_swing.x = 0.0
		_swing_v.x = -_swing_v.x * 0.3        # the body meets the wall and bounces off it a little
	_legs_v += (LEG_STIFF * (hang_swing - _legs) - LEG_DAMP * _legs_v) * dt
	_legs += _legs_v * dt
	# Place the drawn body: shoulders below the hands at arm's length, out from the wall, swung about the hands (out from
	# the wall the whole body pitches; sideways both arms swing together and the torso tilts only a little).
	var pitch := Basis(r, -hang_swing.x)
	var swing := Basis(d, -hang_swing.y) * pitch
	var basis := Basis(d, -hang_swing.y * ROLL_TILT) * pitch * Basis(Vector3.UP, atan2(-d.x, -d.z) + PI)
	var bones: Dictionary = visual.bone_index
	var local: Transform3D = visual.global_transform.affine_inverse() * skeleton.global_transform
	var shoulders: Vector3 = (skeleton.get_bone_global_pose(bones.LeftUpperArm).origin + skeleton.get_bone_global_pose(bones.RightUpperArm).origin) * 0.5
	var arm := HANG_ARM * _arm_length()
	var off := HANG_SHOULDER_OFF + BRACE_SHOULDER_OFF * _brace
	var down := sqrt(maxf(arm * arm - off * off, 0.01))
	var desired := grip_mid + swing * (Vector3.DOWN * down - d * off)
	var target_origin: Vector3 = desired - basis * (local * shoulders)
	# The authored grip frame leans the upper body into the wall: pitch the drawn body out about the hands until the
	# head and the chest clear the face (a fixed rest angle for this pose, applied under the swing).
	var placed := Transform3D(basis, target_origin)
	var lean_into := -INF
	for part in [["Head", 0.07, 0.14], ["UpperChest", 0.06, 0.13]]:
		var centre: Vector3 = placed * local * (skeleton.get_bone_global_pose(bones[part[0]]).origin + Vector3.UP * float(part[1]))
		lean_into = maxf(lean_into, (centre - (climb.edge as Vector3)).dot(d) + float(part[2]))
	if lean_into > 0.0:
		var lean := Basis(r, -lean_into / maxf(0.3, grip_mid.distance_to(placed * local * skeleton.get_bone_global_pose(bones.Head).origin)))
		placed = Transform3D(lean * placed.basis, grip_mid + lean * (placed.origin - grip_mid))
	head_clearance = -lean_into
	var now: Transform3D = visual.global_transform
	visual.global_transform = Transform3D(now.basis.slerp(placed.basis, w), now.origin.lerp(placed.origin, w))
	_hang_shift = visual.global_transform.origin - now.origin
	_hang_basis = visual.global_transform.basis
	# A planted hand further than its nearly straight arm reaches (hands spread during a shimmy, the sideways swing, the
	# trailing hand on the old wall round a corner) pulls the body toward it: up where it can, sideways where it must.
	var pull := Vector3.ZERO
	var reach_limit := _arm_length() * 0.985
	for side in ["Left", "Right"]:
		if _step.has(side):
			continue
		var gap: Vector3 = _hand_target(side, d) - skeleton.global_transform * skeleton.get_bone_global_pose(bones[side + "UpperArm"]).origin
		var across := Vector2(gap.x, gap.z).length()
		if gap.length() <= reach_limit:
			continue
		if across < reach_limit:
			pull.y = maxf(pull.y, gap.y - sqrt(reach_limit * reach_limit - across * across))
		else:
			pull += gap.normalized() * (gap.length() - reach_limit)
	if pull != Vector3.ZERO:
		visual.global_position += pull * w
		_hang_shift += pull * w
	hang_lift = pull.length()
	var to_skeleton := skeleton.global_transform.affine_inverse()
	# Arms: wrists on their grip points, elbows out to the sides and back from the wall; hands palm-down on the top.
	_gripping = true
	var full_arm := _arm_length()
	for side in ["Left", "Right"]:
		var chain = _arm_left if side == "Left" else _arm_right
		var wrist := _hand_target(side, d)
		var shoulder := skeleton.get_bone_global_pose(bones[side + "UpperArm"]).origin
		# A moving hand lifts off and reaches ahead only as far as its (nearly straight) arm allows.
		var shoulder_world: Vector3 = skeleton.global_transform * shoulder
		if _step.has(side) and wrist.distance_to(shoulder_world) > full_arm * 0.985:
			wrist = shoulder_world + (wrist - shoulder_world).normalized() * full_arm * 0.985
		var out := r if side == "Right" else -r
		chain.active = true
		chain.influence = w
		chain.target = to_skeleton * wrist
		chain.pole = shoulder + to_skeleton.basis * (out * 0.4 - d * 0.3 + Vector3.DOWN * 0.1)
		_grip_targets[side] = wrist
		var hand: int = bones[side + "Hand"]
		var hand_d: Vector3 = _step[side].get("d", d) if _step.has(side) else _plant_d.get(side, d)
		_orientation.orientations[hand] = skeleton.get_bone_global_pose(hand).basis.slerp(_grip_basis(hand_d, skeleton), w)
	# Legs: braced on the wall like a climber where there is wall within reach (the authored grip frame's bent legs, each
	# foot on a real contact found at its own height), else dangling from the hips along the lagging swing.
	_hang_legs = true
	var ground := -INF
	var below := _probe(space, grip_mid, grip_mid + Vector3.DOWN * 6.0)
	if not below.is_empty():
		ground = (below.position as Vector3).y
	var hang_dir := Basis(d, -_legs.y) * Basis(r, -_legs.x) * Vector3.DOWN
	var contacts := _brace_feet(climb, space, d, r, dt)
	braced_feet = contacts.size()
	var settled := float(climb.get("hang_time", 1.0)) > 0.08
	_brace = move_toward(_brace, 1.0 if settled and contacts.size() == 2 else 0.0, BRACE_RATE * dt)
	var feet_debug := []
	for index in 2:
		var side := "Left" if index == 0 else "Right"
		var hip: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bones[side + "UpperLeg"]).origin
		var knee: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bones[side + "LowerLeg"]).origin
		var foot := hip + hang_dir * _leg_length(side) * 0.95
		var into: float = (foot - climb.edge).dot(d)
		if into > -FOOT_WALL_CLEAR:
			foot -= d * (into + FOOT_WALL_CLEAR)
		foot.y = maxf(foot.y, ground + FOOT_GROUND_CLEAR)
		if contacts.has(side):
			foot = foot.lerp(contacts[side], _brace)
			feet_debug.append([contacts[side], _foot_plants[side].n])
		_feet[index].target = to_skeleton * foot
		# Braced, the knees come up toward the chest (a climber's brace, feet below them on the wall); dangling, they bend
		# slightly toward the wall.
		_feet[index].pole = to_skeleton * (knee + (d * 0.4 + Vector3.UP * 0.1).lerp(Vector3.UP * 0.6 + d * 0.1, _brace))
		_feet[index].influence = w
		_feet[index].active = true
		var foot_bone: int = bones[side + "Foot"]
		_orientation.orientations[foot_bone] = skeleton.get_bone_global_pose(foot_bone).basis
	var hands_debug := []
	for side in ["Left", "Right"]:
		hands_debug.append([_hand_target(side, d), _plant_d.get(side, d)])
	debug_contacts = {"hands": hands_debug, "feet": feet_debug, "path": _lip_path(climb), "brace": _brace}


## Braced feet: each foot's place on the wall, found by a ray at the authored foot's height (the grip frame is a braced
## pose); kept while the body moves, moved one at a time once it trails by FOOT_STEP_TRIGGER or the wall turns (a
## corner). A foot with no wall within its leg's reach is not braced. Returns side -> ankle target (world).
func _brace_feet(climb: Dictionary, space: PhysicsDirectSpaceState3D, d: Vector3, r: Vector3, dt: float) -> Dictionary:
	var skeleton: Skeleton3D = visual.skeleton
	var bones: Dictionary = visual.bone_index
	var wanted := {}
	for side in ["Left", "Right"]:
		var foot: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bones[side + "Foot"]).origin
		var hip: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bones[side + "UpperLeg"]).origin
		# Feet come up toward the hips: the contact is at least BRACE_BELOW_HIP above the authored foot's drop.
		var probe := Vector3(foot.x, maxf(foot.y, hip.y - BRACE_BELOW_HIP), foot.z)
		var hit := _probe(space, probe - d * 0.3, probe + d * 1.0)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.35:
			continue
		var n := Vector3((hit.normal as Vector3).x, 0.0, (hit.normal as Vector3).z).normalized()
		var at: Vector3 = (hit.position as Vector3) + n * FOOT_BRACE_OFF
		if at.distance_to(hip) > _leg_length(side) * 0.97:
			continue
		wanted[side] = {"at": at, "n": n}
	for side in _foot_step.keys():
		var step: Dictionary = _foot_step[side]
		step.t = float(step.t) + dt / FOOT_STEP_TIME
		if step.t >= 1.0:
			_foot_plants[side] = {"at": step.to, "n": step.n}
			_foot_step.erase(side)
			foot_steps += 1
	for side in _foot_plants.keys():
		if not wanted.has(side) and not _foot_step.has(side):
			_foot_plants.erase(side)
	if _foot_step.is_empty():
		for side in wanted:
			if not _foot_plants.has(side):
				_foot_plants[side] = wanted[side]
				continue
			var plant: Dictionary = _foot_plants[side]
			var trail: float = absf(((wanted[side].at as Vector3) - (plant.at as Vector3)).dot(r))
			if trail > FOOT_STEP_TRIGGER or (plant.n as Vector3).dot(wanted[side].n) < 0.9:
				_foot_step[side] = {"from": plant.at, "to": wanted[side].at, "n": wanted[side].n, "t": 0.0}
				break
	var out := {}
	for side in _foot_plants:
		var plant: Dictionary = _foot_plants[side]
		var at: Vector3 = plant.at
		if _foot_step.has(side):
			var step: Dictionary = _foot_step[side]
			var u := clampf(float(step.t), 0.0, 1.0)
			at = (step.from as Vector3).lerp(step.to, smoothstep(0.0, 1.0, u)) + (plant.n as Vector3) * 0.1 * sin(PI * u)
		out[side] = at
	return out


## The lip the hands work along, as points for the debug overlay: one segment, or two meeting at a corner.
func _lip_path(climb: Dictionary) -> Array:
	var c: Dictionary = climb.get("corner", {})
	if c.is_empty():
		var e: Vector3 = climb.edge
		return [e - (climb.right as Vector3) * 0.6, e + (climb.right as Vector3) * 0.6]
	var r_old: Vector3 = (c.d_old as Vector3).cross(Vector3.UP)
	var r_new: Vector3 = (c.d_new as Vector3).cross(Vector3.UP)
	var at: Vector3 = c.at
	var side: float = c.side
	return [at - r_old * side * 0.6, at, at + r_new * side * 0.6]


## A new hang: the hands start on the authored grip places, and the catch sets the body swinging (moving into the wall
## it swings out off it; falling, it swings out a little; moving along the wall, it rolls the other way).
func _start_hang(climb: Dictionary) -> void:
	_plants.clear()
	_step.clear()
	_plant_d.clear()
	_foot_plants.clear()
	_foot_step.clear()
	_brace = 0.0
	_hang_weight = 0.0
	hang_swing = Vector2.ZERO
	_legs = Vector2.ZERO
	_legs_v = Vector2.ZERO
	_prev_shimmy = 0.0
	var v: Vector3 = climb.get("catch_velocity", Vector3.ZERO)
	var into := maxf(0.0, v.dot(climb.direction))
	var falling := maxf(0.0, -v.y)
	_swing_v = Vector2(clampf(0.25 + 0.25 * into + 0.12 * falling, 0.0, 1.6), clampf(-v.dot(climb.right) / SWING_LENGTH, -1.2, 1.2))


## Each hand's place on the ledge follows the hang point; one hand moves at a time (the one furthest behind, which is
## the leading hand when the shimmy sets off), lifting off and reaching a little past its place.
func _move_hands(climb: Dictionary, space: PhysicsDirectSpaceState3D, dt: float) -> void:
	var lip: float = climb.lip_y
	var slots := {}
	for side in ["Left", "Right"]:
		slots[side] = _hand_slot(climb, side)
		if not _plants.has(side):
			_plants[side] = _snap_hand(space, slots[side].at, slots[side].d, lip)
			_plant_d[side] = slots[side].d
	if _step.size() > 1:
		two_hands_moving += 1
	for side in _step.keys():
		var step: Dictionary = _step[side]
		step.t = float(step.t) + dt / STEP_TIME
		if step.t >= 1.0:
			_plants[side] = step.to
			_plant_d[side] = step.d
			_step.erase(side)
			hand_steps += 1
	if not _step.is_empty():
		return
	var shimmying := absf(float(climb.shimmy)) > 0.05 or float(climb.get("turning", -1.0)) >= 0.0
	var best := ""
	var worst := 0.0
	for side in ["Left", "Right"]:
		var drift: float = float(slots[side].x) - _path_x(climb, _plants[side])
		if absf(drift) > (STEP_TRIGGER if shimmying else STEP_SETTLE) and absf(drift) > worst:
			best = side
			worst = absf(drift)
	if best != "":
		var ahead: float = signf(float(slots[best].x) - _path_x(climb, _plants[best])) * (STEP_OVERSHOOT if shimmying else 0.0)
		var to := _path_point(climb, float(slots[best].x) + ahead)
		_step[best] = {"from": _plants[best], "to": _snap_hand(space, to.at, to.d, lip), "d": to.d, "t": 0.0}


## Where a hand belongs on the ledge now: the authored grip's sideways place either side of the hang point, along the
## lip - straight, or around a corner (then each hand has its own wall: an asymmetric grip). {at, d, x}.
func _hand_slot(climb: Dictionary, side: String) -> Dictionary:
	var scale: float = visual.skeleton.global_transform.basis.get_scale().x
	var c: Dictionary = climb.get("corner", {})
	var x: float = (float(c.x) if not c.is_empty() else 0.0) - _grip_hand_x(side) * scale
	var p := _path_point(climb, x)
	p["x"] = x
	return p


## A point of the lip at path coordinate `x` (metres toward the character's right): {at, d}. Around a corner the path
## is the old wall up to the corner, then the new wall.
func _path_point(climb: Dictionary, x: float) -> Dictionary:
	var c: Dictionary = climb.get("corner", {})
	if c.is_empty():
		return {"at": (climb.edge as Vector3) + (climb.right as Vector3) * x, "d": climb.direction}
	var on_new: bool = x * float(c.side) > 0.0
	var d: Vector3 = c.d_new if on_new else c.d_old
	return {"at": (c.at as Vector3) + d.cross(Vector3.UP) * x, "d": d}


## Path coordinate of a point near the lip (the inverse of _path_point; the nearer wall around a corner).
func _path_x(climb: Dictionary, point: Vector3) -> float:
	var c: Dictionary = climb.get("corner", {})
	if c.is_empty():
		return (point - (climb.edge as Vector3)).dot(climb.right)
	var side: float = c.side
	var x_old: float = (point - (c.at as Vector3)).dot((c.d_old as Vector3).cross(Vector3.UP))
	var x_new: float = (point - (c.at as Vector3)).dot((c.d_new as Vector3).cross(Vector3.UP))
	var old_ok: bool = x_old * side <= 0.0
	var new_ok: bool = x_new * side > 0.0
	if old_ok and not new_ok:
		return x_old
	if new_ok and not old_ok:
		return x_new
	var at_old: Vector3 = (c.at as Vector3) + (c.d_old as Vector3).cross(Vector3.UP) * x_old
	var at_new: Vector3 = (c.at as Vector3) + (c.d_new as Vector3).cross(Vector3.UP) * x_new
	return x_old if Vector2(point.x - at_old.x, point.z - at_old.z).length() <= Vector2(point.x - at_new.x, point.z - at_new.z).length() else x_new


## The wrist's grip point for a hand at `at` (on the face, at the lip): the real top just past the face and the real
## face there, then the wrist just out from the face and just above the top.
func _snap_hand(space: PhysicsDirectSpaceState3D, at: Vector3, d: Vector3, lip: float) -> Vector3:
	var top_y := lip
	var column := at + d * 0.06
	var top := _probe(space, Vector3(column.x, lip + 0.25, column.z), Vector3(column.x, lip - 0.25, column.z))
	if not top.is_empty():
		top_y = (top.position as Vector3).y
	var face := at
	var from := Vector3(at.x, top_y - 0.06, at.z) - d * 0.3
	var hit := _probe(space, from, from + d * 0.5)
	if not hit.is_empty():
		face = hit.position
	return Vector3(face.x, top_y, face.z) - d * WRIST_OUT + Vector3.UP * WRIST_UP


func _hand_target(side: String, d: Vector3) -> Vector3:
	if _step.has(side):
		var step: Dictionary = _step[side]
		var u := clampf(float(step.t), 0.0, 1.0)
		var arc := sin(PI * u)
		return (step.from as Vector3).lerp(step.to, smoothstep(0.0, 1.0, u)) + Vector3.UP * STEP_LIFT * arc - d * 0.04 * arc
	return _plants.get(side, Vector3.ZERO)


## Gripping hand orientation in skeleton space: fingers (bone +Y) over the top into the wall, palm (bone +Z) down on it.
func _grip_basis(d: Vector3, skeleton: Skeleton3D) -> Basis:
	var fingers := Vector3(d.x, 0.0, d.z).normalized()
	var palm := Vector3.DOWN
	var world := Basis(fingers.cross(palm), fingers, palm)
	return (skeleton.global_transform.basis.inverse() * world).orthonormalized()


func _probe(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = ray_exclude
	return space.intersect_ray(query)


func _arm_length() -> float:
	var sk: Skeleton3D = visual.skeleton
	var b: Dictionary = visual.bone_index
	var a := sk.get_bone_global_rest(b.LeftUpperArm).origin
	var e := sk.get_bone_global_rest(b.LeftLowerArm).origin
	var h := sk.get_bone_global_rest(b.LeftHand).origin
	return (a.distance_to(e) + e.distance_to(h)) * sk.global_transform.basis.get_scale().x


func _leg_length(side: String) -> float:
	var sk: Skeleton3D = visual.skeleton
	var b: Dictionary = visual.bone_index
	var hip := sk.get_bone_global_rest(b[side + "UpperLeg"]).origin
	var knee := sk.get_bone_global_rest(b[side + "LowerLeg"]).origin
	var ankle := sk.get_bone_global_rest(b[side + "Foot"]).origin
	return (hip.distance_to(knee) + knee.distance_to(ankle)) * sk.global_transform.basis.get_scale().x


## The quick mantle (ClimbUp_1m): its left hand plants on the top. From the clip's planted frame the hand is held where
## it landed along the ledge, with the palm on the real top surface; the authored wrist rise as the arm pushes is kept.
func _mantle_hand(climb: Dictionary) -> void:
	var t: float = climb.get("time", -1.0)
	var w := smoothstep(MantleClip.HAND_PLANTED - 0.02, MantleClip.HAND_PLANTED, t) * (1.0 - smoothstep(MantleClip.HAND_OFF, MantleClip.HAND_OFF + 0.03, t))
	if climb.is_empty() or w <= 0.0:
		if not _mantle_plant.is_empty():
			_arm_left.active = false
			_mantle_plant = {}
		return
	var skeleton: Skeleton3D = visual.skeleton
	var bones: Dictionary = visual.bone_index
	var wrist: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bones.LeftHand).origin
	if _mantle_plant.is_empty():
		var top := wrist.y
		var space: PhysicsDirectSpaceState3D = visual.get_world_3d().direct_space_state
		var hit := _probe(space, wrist + Vector3.UP * 0.3, wrist + Vector3.DOWN * 0.4)
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.7:
			top = (hit.position as Vector3).y
		_mantle_plant = {"at": Vector3(wrist.x, top + WRIST_UP, wrist.z), "wrist_y": wrist.y, "target": wrist, "top": top}
		mantle_hand_error = 0.0
	var target: Vector3 = (_mantle_plant.at as Vector3) + Vector3.UP * (wrist.y - float(_mantle_plant.wrist_y))
	_mantle_plant.target = target
	# A hand stays planted only while its arm reaches it: as the body rises past, the straightening arm lets it go.
	var shoulder_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bones.LeftUpperArm).origin
	w *= 1.0 - smoothstep(0.97, 1.0, shoulder_world.distance_to(target) / _arm_length())
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var elbow := skeleton.get_bone_global_pose(bones.LeftLowerArm).origin
	var shoulder := skeleton.get_bone_global_pose(bones.LeftUpperArm).origin
	_arm_left.active = true
	_arm_left.influence = w
	_arm_left.target = to_skeleton * target
	_arm_left.pole = elbow + (elbow - (shoulder + skeleton.get_bone_global_pose(bones.LeftHand).origin) * 0.5).normalized() * 0.5
	_orientation.orientations[bones.LeftHand] = skeleton.get_bone_global_pose(bones.LeftHand).basis


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
	terrain_correction = 0.0
	var skeleton: Skeleton3D = visual.skeleton
	var terrain: bool = grounded and params.is_on("foot_ik") and not _hang_legs and visual.is_inside_tree()
	_terrain(terrain, dt)
	for index in (0 if _hang_legs else 2):   # hanging: the legs are the hang's (_hang)
		var side := "Left" if index == 0 else "Right"
		var foot := skeleton.get_bone_global_pose(visual.bone_index[side + "Foot"])
		var knee := skeleton.get_bone_global_pose(visual.bone_index[side + "LowerLeg"]).origin
		var hip := skeleton.get_bone_global_pose(visual.bone_index[side + "UpperLeg"]).origin
		var desired := foot.origin
		desired.z = hip.z + (desired.z - hip.z) * model.stride
		var correction := desired - foot.origin
		_orientation.orientations[visual.bone_index[side + "Foot"]] = foot.basis
		var lift := 0.0
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
			lift = sole.y
		correction = correction.limit_length(MAX_FOOT_CORRECTION)
		if terrain:
			# The real ground under this foot (relative to the drawn floor, less the pelvis drop): the authored swing height
			# is kept above it, and a planted foot tilts to the surface (stance-weighted).
			var offset: float = clampf(float(_ground[side]) - _pelvis, -TERRAIN_REACH, TERRAIN_REACH)
			correction.y += offset
			# No sole corner below its own ground: where the sole straddles a step edge, the higher tread holds it.
			var sink := 0.0
			var space: PhysicsDirectSpaceState3D = visual.get_world_3d().direct_space_state
			for point in visual.sole_points[side]:
				var corner: Vector3 = skeleton.global_transform * (foot * point + correction)
				var hit := _probe(space, corner + Vector3.UP * 0.4, corner + Vector3.DOWN * 0.1)
				if not hit.is_empty() and (hit.normal as Vector3).y > 0.5:
					sink = maxf(sink, (hit.position as Vector3).y - corner.y)
			correction.y += minf(sink, TERRAIN_REACH)
			offset += minf(sink, TERRAIN_REACH)
			terrain_correction = maxf(terrain_correction, absf(offset))
			var stance := 1.0 - smoothstep(0.02, 0.10, lift)
			var n: Vector3 = (skeleton.global_transform.basis.inverse() * (_ground_normal[side] as Vector3)).normalized()
			var tilt := Quaternion(Vector3.UP, n)
			var angle := tilt.get_angle()
			if angle > 0.001:
				tilt = Quaternion.IDENTITY.slerp(tilt, minf(1.0, FOOT_TILT_MAX / angle) * stance)
				_orientation.orientations[visual.bone_index[side + "Foot"]] = Basis(tilt) * foot.basis
		# A stride-stretched foot near full extension stays within the leg's reach (as far as the authored foot at least).
		var reach := maxf((hip.distance_to(knee) + knee.distance_to(foot.origin)) * LEG_REACH, hip.distance_to(foot.origin))
		correction = hip + (foot.origin + correction - hip).limit_length(reach) - foot.origin
		max_correction = maxf(max_correction, (correction - Vector3.UP * (float(_ground[side]) - _pelvis if terrain else 0.0)).length())
		_feet[index].target = foot.origin + correction
		_feet[index].pole = knee + (knee - (hip + foot.origin) * 0.5).normalized() * 0.5
		_feet[index].active = grounded and correction.length() > 0.0001
	visual.skeleton.advance(dt)


## Ground under each foot: a ray from above the foot finds the real surface (steps, slopes, uneven ground); heights are
## relative to the drawn floor and followed smoothly; the pelvis drops so the lower foot can reach its ground (the body
## stands on its higher support). Off the ground everything eases back to the flat floor.
func _terrain(active: bool, dt: float) -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var floor_y: float = skeleton.global_transform.origin.y
	var space: PhysicsDirectSpaceState3D = visual.get_world_3d().direct_space_state if active else null
	var lowest := 0.0
	var marks := []
	for side in ["Left", "Right"]:
		var target := 0.0
		var normal := Vector3.UP
		if active:
			# Under the heel and under the toes: the higher ground holds the foot (a toe over the next tread lifts it).
			var foot_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(visual.bone_index[side + "Foot"])
			var toe: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(visual.bone_index[side + "Toes"]).origin
			var best := -INF
			var forward := Vector3(toe.x - foot_pose.origin.x, 0.0, toe.z - foot_pose.origin.z).normalized()
			var lift := INF
			for point in visual.sole_points[side]:
				lift = minf(lift, (skeleton.get_bone_global_pose(visual.bone_index[side + "Foot"]) * point).y)
			var samples := [foot_pose.origin, toe + forward * 0.05]
			if lift > 0.03:
				samples.append(toe + forward * 0.18)   # a swinging foot clears the ground just ahead of its toes (a riser)
			for at in samples:
				var hit := _probe(space, Vector3(at.x, floor_y + TERRAIN_REACH, at.z), Vector3(at.x, floor_y - TERRAIN_REACH - 0.1, at.z))
				if not hit.is_empty() and (hit.normal as Vector3).y > 0.5 and (hit.position as Vector3).y > best:
					best = (hit.position as Vector3).y
					normal = hit.normal
					marks.append([hit.position, normal])
			if best > -INF:
				target = clampf(best - floor_y, -TERRAIN_REACH, TERRAIN_REACH)
		# Rising ground is taken quickly (a foot must not sink into a step), falling ground eased.
		var k := 1.0 - exp(-(TERRAIN_RATE * 3.0 if target > float(_ground[side]) else TERRAIN_RATE) * dt)
		_ground[side] = lerpf(float(_ground[side]), target, k)
		_ground_normal[side] = (_ground_normal[side] as Vector3).lerp(normal, k).normalized()
		lowest = minf(lowest, float(_ground[side]))
	_pelvis = lerpf(_pelvis, lowest if active else 0.0, 1.0 - exp(-PELVIS_RATE * dt))
	if absf(_pelvis) > 1e-5:
		visual.global_position += Vector3.UP * _pelvis
	if active:
		debug_contacts = {"ground": marks, "pelvis": _pelvis}


func set_enabled(enabled: bool) -> void:
	tree.active = enabled
	visual.visible = enabled
	if enabled:
		_have_position = false
