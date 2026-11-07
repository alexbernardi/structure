## Procedural body inertia. A pure model: kinematics in (velocity, acceleration, heading, ground state, landing impacts,
## gait phase), a pose of offsets out. No nodes, no physics access, nothing here can influence the simulation.
##
## Every effect is a spring (springs.gd) driven by a quantity the SIMULATION produced, never by key presses:
##   torso    pitch <- forward acceleration and speed;  roll <- sideways acceleration;  yaw <- turn rate (anticipation)
##   pelvis   weight shift <- acceleration;  bob and sway <- gait phase;  compression <- landing impact speed
##   facing   the body's yaw follows the heading through a spring (rotational lag)
##   head     counter-rotates the torso (stabilisation) and leads turns
##   shoulders counter-rotate the pelvis; arms lag and overshoot accelerations and turns (follow-through)
## Each effect has its own on/off flag; the master flag turns the whole model off (`active` = false and the visual
## falls back to its original pose). Every joint has a hard angular limit that no parameter can exceed.
##
## Conventions (character-local, facing -Z): pitch + = lean forward; roll + = toward the character's right;
## yaw + = turn to the character's right; pelvis_shift.x + = right, .z + = backward; heading / facing_yaw use Godot's
## rotation.y (positive = counter-clockwise from above = turning left).
extends RefCounted

const Springs = preload("res://animation/springs.gd")
const Math = preload("res://animation/spring_math.gd")

# hard joint limits (radians): parameters can shrink these, never exceed them
const TORSO_PITCH_HARD := 0.6
const TORSO_ROLL_HARD := 0.45
const TORSO_YAW_HARD := 0.7
const HEAD_PITCH_HARD := 0.5
const HEAD_ROLL_HARD := 0.35
const ARM_PITCH_HARD := 0.9
const ARM_ROLL_HARD := 0.9
const ANTICIPATION_YAW_MAX := 0.61
const MAX_TURN_RATE := 15.0          ## rad/s
const OVERSHOOT_ALLOWANCE := 1.3     ## springs may swing this far past their configured maximum before the joint limit

# fixed constants of the secondary springs (not part of the tuned set)
const GAIT_SMOOTH_FREQ := 8.0
const GAIT_SMOOTH_DAMPING := 0.9
const HEAD_DAMPING := 0.7
const ARM_FREQ := 4.0
const ARM_DAMPING := 0.35
const PELVIS_TWIST := 0.10
const SHOULDER_TWIST := 0.12
const ARM_ACCEL_GAIN := 0.02
const ARM_TURN_GAIN := 0.08

var p                                  ## ParamSet of body parameters (values are read live every update)

var torso := Springs.Vector.new(3.0, 0.55)         ## (pitch, yaw, roll)
var pelvis_spring := Springs.Vector.new(2.5, 0.5)  ## weight shift (x right, y unused, z back)
var drop := Springs.Scalar.new(5.0, 0.45)          ## landing compression (negative = hips lowered)
var sway := Springs.Scalar.new(GAIT_SMOOTH_FREQ, GAIT_SMOOTH_DAMPING)
var bob := Springs.Scalar.new(GAIT_SMOOTH_FREQ, GAIT_SMOOTH_DAMPING)
var facing := Springs.Scalar.new(6.0, 0.8)         ## unwrapped yaw, rotation.y convention
var head := Springs.Vector.new(6.0, HEAD_DAMPING)  ## (pitch, yaw, roll) relative to the chest
var arm_l := Springs.Vector.new(ARM_FREQ, ARM_DAMPING)  ## (swing pitch offset, unused, outward roll)
var arm_r := Springs.Vector.new(ARM_FREQ, ARM_DAMPING)

var turn_rate := 0.0                   ## smoothed heading rate (rad/s, positive = turning left)
var pose: Dictionary = {}
var debug: Dictionary = {}             ## targets and derived quantities, for the debug visualisation (Phase 8)

var _heading_prev := NAN
var _initialized := false          ## false until the first update (or after the master switch was off): the body then snaps to its heading
var _drop_v_prev := 0.0


func _init(params) -> void:
	p = params
	reset(0.0)
	pose = neutral_pose(0.0)


## The pose with every effect at rest.
static func neutral_pose(facing_yaw: float) -> Dictionary:
	return {
		"active": false, "facing_yaw": facing_yaw,
		"torso_pitch": 0.0, "torso_yaw": 0.0, "torso_roll": 0.0,
		"pelvis_shift": Vector3.ZERO, "pelvis_drop": 0.0, "bob": 0.0, "sway": 0.0, "pelvis_twist": 0.0, "shoulder_twist": 0.0,
		"head_pitch": 0.0, "head_yaw": 0.0, "head_roll": 0.0,
		"arm_pitch_l": 0.0, "arm_roll_l": 0.0, "arm_pitch_r": 0.0, "arm_roll_r": 0.0, "arm_scale": 1.0,
	}


## Back to rest (respawn, teleport, switching the model on). `facing_yaw` is where the body already points.
func reset(facing_yaw := 0.0) -> void:
	torso.reset()
	torso.target = Vector3.ZERO
	pelvis_spring.reset()
	pelvis_spring.target = Vector3.ZERO
	drop.reset()
	drop.target = 0.0
	sway.reset()
	sway.target = 0.0
	bob.reset()
	bob.target = 0.0
	head.reset()
	head.target = Vector3.ZERO
	for a in [arm_l, arm_r]:
		a.reset()
		a.target = Vector3.ZERO
	facing.reset(facing_yaw, 0.0)
	facing.target = facing_yaw
	turn_rate = 0.0
	_heading_prev = NAN
	_drop_v_prev = 0.0
	_initialized = true
	pose = neutral_pose(facing_yaw)


## One update. `k`: velocity (Vector3), accel (Vector3, horizontal m/s^2), heading (rad or NAN when standing),
## grounded, gait_phase, gait_amount (0..1), landed_impact (m/s, once), teleported (bool). Returns the pose.
func update(dt: float, k: Dictionary) -> Dictionary:
	if not (dt > 0.0) or is_inf(dt):
		return pose
	var master: bool = p.is_on("body_dynamics")
	var heading: float = k.get("heading", NAN)
	if not master:
		_initialized = false   # switching back on starts from rest, aligned with the heading
		pose = neutral_pose(heading if not is_nan(heading) else facing.x)
		return pose
	if k.get("teleported", false) or not _initialized:
		reset(heading if not is_nan(heading) else facing.x)
	dt = minf(dt, Springs.MAX_DT)

	var velocity: Vector3 = k.get("velocity", Vector3.ZERO)
	var accel: Vector3 = k.get("accel", Vector3.ZERO)
	var grounded: bool = k.get("grounded", true)
	var speed := Vector2(velocity.x, velocity.z).length()
	var amp: float = p.get_value("torso_lean_amp")

	_update_facing(dt, heading, speed)
	var f: float = facing.x
	var fwd := Vector3(-sin(f), 0.0, -cos(f))
	var right := Vector3(cos(f), 0.0, -sin(f))
	var a_fwd := accel.dot(fwd)
	var a_lat := accel.dot(right)
	var v_fwd := velocity.dot(fwd)
	var turn_right := -turn_rate

	# ---- torso
	var lean_max: float = minf(deg_to_rad(p.get_value("lean_max_deg")), TORSO_PITCH_HARD / OVERSHOOT_ALLOWANCE)
	var roll_max: float = minf(deg_to_rad(p.get_value("lateral_lean_max_deg")), TORSO_ROLL_HARD / OVERSHOOT_ALLOWANCE)
	var pitch_t := 0.0
	var roll_t := 0.0
	var yaw_t := 0.0
	if p.is_on("fx_torso_lean"):
		pitch_t = clampf((a_fwd * p.get_value("lean_accel_gain") + v_fwd * p.get_value("lean_speed_gain")) * amp, -lean_max, lean_max)
	if p.is_on("fx_torso_lateral"):
		roll_t = clampf(a_lat * p.get_value("lateral_lean_gain") * amp, -roll_max, roll_max)
	if p.is_on("fx_anticipation"):
		yaw_t = clampf(turn_right * p.get_value("anticipation_lead") * amp, -ANTICIPATION_YAW_MAX, ANTICIPATION_YAW_MAX)
	torso.frequency_hz = p.get_value("torso_freq")
	torso.damping_ratio = p.get_value("torso_damping")
	torso.set_target(Vector3(pitch_t, yaw_t, roll_t))
	torso.step(dt)
	_limit_axes(torso, Vector3(lean_max * OVERSHOOT_ALLOWANCE, TORSO_YAW_HARD, roll_max * OVERSHOOT_ALLOWANCE))

	# ---- pelvis: weight shift
	var shift_t := Vector3.ZERO
	if p.is_on("fx_pelvis_shift"):
		var g: float = p.get_value("weight_shift_gain")
		shift_t = Vector3(-a_lat * g, 0.0, a_fwd * g)
	pelvis_spring.frequency_hz = p.get_value("hip_freq")
	pelvis_spring.damping_ratio = p.get_value("hip_damping")
	pelvis_spring.limit_length = p.get_value("weight_shift_max")
	pelvis_spring.set_target(shift_t)
	pelvis_spring.step(dt)

	# ---- pelvis: gait bob and sway, shoulder counter-rotation (all locked to the gait phase)
	var phase: float = k.get("gait_phase", 0.0)
	var gait: float = clampf(k.get("gait_amount", 0.0), 0.0, 1.0) * (1.0 if grounded else 0.0)
	var gait_on: bool = p.is_on("fx_pelvis_gait")
	var sway_amp: float = p.get_value("hip_sway_amp")
	sway.set_target(sin(phase) * p.get_value("sway_distance") * sway_amp * gait if gait_on else 0.0)
	bob.set_target(absf(cos(phase)) * p.get_value("bob_height") * sway_amp * gait if gait_on else 0.0)
	sway.step(dt)
	bob.step(dt)
	var shoulder_amp: float = p.get_value("shoulder_counter_amp")
	var arms_on: bool = p.is_on("fx_arms")
	var pelvis_twist: float = sin(phase) * PELVIS_TWIST * gait * shoulder_amp if arms_on else 0.0
	var shoulder_twist: float = -sin(phase) * SHOULDER_TWIST * gait * shoulder_amp if arms_on else 0.0

	# ---- landing compression and rebound
	_update_landing(dt, float(k.get("landed_impact", 0.0)))

	# ---- head
	var stab: float = p.get_value("head_stabilization") if p.is_on("fx_head") else 0.0
	var head_yaw_max: float = deg_to_rad(p.get_value("head_max_yaw_deg"))
	var lead_yaw: float = turn_right * p.get_value("anticipation_lead") * 1.5 if p.is_on("fx_head") else 0.0
	head.frequency_hz = p.get_value("head_freq")
	head.damping_ratio = HEAD_DAMPING
	head.set_target(Vector3(-stab * torso.x.x, clampf(-stab * torso.x.y + lead_yaw, -head_yaw_max, head_yaw_max), -stab * torso.x.z))
	head.step(dt)
	_limit_axes(head, Vector3(HEAD_PITCH_HARD, head_yaw_max, HEAD_ROLL_HARD))

	# ---- arms: lag and overshoot accelerations and turns
	var follow: float = p.get_value("follow_through") if arms_on else 0.0
	var pitch_arm := clampf(-a_fwd * ARM_ACCEL_GAIN * follow, -ARM_PITCH_HARD, ARM_PITCH_HARD)
	var roll_out := clampf(turn_right * ARM_TURN_GAIN * follow, -ARM_ROLL_HARD, ARM_ROLL_HARD)
	arm_l.set_target(Vector3(pitch_arm, 0.0, roll_out))     # turning right swings the (outer) left arm out
	arm_r.set_target(Vector3(pitch_arm, 0.0, -roll_out))
	arm_l.step(dt)
	arm_r.step(dt)
	_limit_axes(arm_l, Vector3(ARM_PITCH_HARD, 1.0, ARM_ROLL_HARD))
	_limit_axes(arm_r, Vector3(ARM_PITCH_HARD, 1.0, ARM_ROLL_HARD))

	pose = {
		"active": true, "facing_yaw": facing.x,
		"torso_pitch": torso.x.x, "torso_yaw": torso.x.y, "torso_roll": torso.x.z,
		"pelvis_shift": pelvis_spring.x, "pelvis_drop": drop.x, "bob": bob.x, "sway": sway.x,
		"pelvis_twist": pelvis_twist, "shoulder_twist": shoulder_twist,
		"head_pitch": head.x.x, "head_yaw": head.x.y, "head_roll": head.x.z,
		"arm_pitch_l": arm_l.x.x, "arm_roll_l": arm_l.x.z, "arm_pitch_r": arm_r.x.x, "arm_roll_r": arm_r.x.z,
		"arm_scale": p.get_value("arm_swing_amp"),
	}
	debug = {"a_fwd": a_fwd, "a_lat": a_lat, "v_fwd": v_fwd, "turn_rate": turn_rate, "torso_target": Vector3(pitch_t, yaw_t, roll_t),
		"shift_target": shift_t, "facing_target": facing.target}
	return pose


func _update_facing(dt: float, heading: float, speed: float) -> void:
	var rate_raw := 0.0
	if not is_nan(heading) and not is_nan(_heading_prev) and speed > 0.4:
		rate_raw = clampf(angle_difference(_heading_prev, heading) / dt, -MAX_TURN_RATE, MAX_TURN_RATE) * minf(speed / 1.5, 1.0)
	turn_rate = Math.damp_scalar(turn_rate, rate_raw, 0.04 if speed > 0.4 else 0.08, dt)
	_heading_prev = heading if (not is_nan(heading) and speed > 0.4) else NAN
	var lag: float = maxf(p.get_value("rotation_lag"), 0.1)
	if p.is_on("fx_facing_lag"):
		facing.frequency_hz = p.get_value("rotation_freq") / lag
		facing.damping_ratio = p.get_value("rotation_damping")
		if not is_nan(heading) and speed > 0.4:
			facing.target = facing.x + angle_difference(facing.x, heading)   # nearest equivalent angle: never the long way round
		facing.step(dt)
		# the spring chases a target that is re-derived every frame, so keep the stored target on the same branch
		facing.target = facing.x if (is_nan(heading) or speed <= 0.4) else facing.target
	else:
		if not is_nan(heading) and speed > 0.4:
			facing.x = Math.damp_scalar(facing.x, facing.x + angle_difference(facing.x, heading), 0.03, dt)
		facing.v = 0.0
		facing.target = facing.x


func _update_landing(dt: float, impact: float) -> void:
	var on: bool = p.is_on("fx_landing")
	drop.frequency_hz = p.get_value("landing_freq")
	drop.damping_ratio = p.get_value("landing_damping")
	drop.min_value = -p.get_value("landing_max")
	drop.max_value = 0.04
	drop.target = 0.0
	if not on:
		drop.reset()
		_drop_v_prev = 0.0
		return
	if impact > 1.0:
		var depth: float = minf(impact * p.get_value("landing_gain") * p.get_value("landing_compression"), p.get_value("landing_max"))
		var w := TAU * drop.frequency_hz
		drop.v += -depth * w / Math.impulse_peak_factor(drop.damping_ratio)
		_drop_v_prev = drop.v
	drop.step(dt)
	# rebound: the moment the hips bottom out and start rising, return extra energy
	if _drop_v_prev < 0.0 and drop.v > 0.0 and drop.x < -1e-4:
		drop.v *= 1.0 + p.get_value("landing_rebound")
	_drop_v_prev = drop.v


## Clamp each component of a Vector spring to +-limit and drop velocity that pushes into the limit (no wind-up).
func _limit_axes(sp, limit: Vector3) -> void:
	for a in 3:
		var l: float = limit[a]
		if sp.x[a] > l:
			sp.x[a] = l
			if sp.v[a] > 0.0:
				sp.v[a] = 0.0
		elif sp.x[a] < -l:
			sp.x[a] = -l
			if sp.v[a] < 0.0:
				sp.v[a] = 0.0


## Angular limits actually in force for the current parameters (radians), for tests and the debug view.
func joint_limits() -> Dictionary:
	var lean_max: float = minf(deg_to_rad(p.get_value("lean_max_deg")), TORSO_PITCH_HARD / OVERSHOOT_ALLOWANCE) * OVERSHOOT_ALLOWANCE
	var roll_max: float = minf(deg_to_rad(p.get_value("lateral_lean_max_deg")), TORSO_ROLL_HARD / OVERSHOOT_ALLOWANCE) * OVERSHOOT_ALLOWANCE
	return {"torso_pitch": lean_max, "torso_roll": roll_max, "torso_yaw": TORSO_YAW_HARD, "head_pitch": HEAD_PITCH_HARD,
		"head_roll": HEAD_ROLL_HARD, "head_yaw": deg_to_rad(p.get_value("head_max_yaw_deg")), "arm_pitch": ARM_PITCH_HARD, "arm_roll": ARM_ROLL_HARD}
