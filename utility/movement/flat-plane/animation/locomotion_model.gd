## Physical state in; bounded playback decisions out. No bones, input handling or physics writes.
extends RefCounted

const MIN_RATE := 0.8
const MAX_RATE := 1.45
const JOG_LENGTH := 28.0 / 30.0
const SPRINT_LENGTH := 20.0 / 30.0
const JOG_DISTANCE := 5.0
const SPRINT_DISTANCE := 5.5

var params
var proportion_scale := 1.0
var state := "Idle"
var cadence := 1.0
var sprint_blend := 0.0
var run_weight := 0.0
var stride := 1.0
var lean := 0.0
var _grounded := true
var _landing_time := 0.0


func _init(parameters, scale_ratio := 1.0) -> void:
	params = parameters
	proportion_scale = scale_ratio


func update(dt: float, speed: float, grounded: bool, vy: float, acceleration: float, teleported := false, crouching := false) -> void:
	if not is_finite(dt) or dt < 0.0 or not is_finite(speed) or speed < 0.0:
		push_error("Locomotion requires finite, non-negative elapsed time and measured speed")
		return
	if teleported:
		_grounded = grounded
		_landing_time = 0.0
		lean = 0.0
	if grounded and not _grounded:
		_landing_time = 0.20
	_grounded = grounded
	_landing_time = maxf(0.0, _landing_time - dt)
	state = "Jump" if not grounded and vy > 0.15 else "Fall" if not grounded else "Land" if _landing_time > 0.0 else "Run" if speed > 0.15 else "Idle"
	if grounded and crouching:
		state = "Crouch"
	var jog_speed := JOG_DISTANCE / JOG_LENGTH * proportion_scale
	var sprint_speed := SPRINT_DISTANCE / SPRINT_LENGTH * proportion_scale
	var blend_target := clampf((speed - jog_speed) / (sprint_speed - jog_speed), 0.0, 1.0)
	sprint_blend = move_toward(sprint_blend, blend_target, dt / params.get_value("transition_duration"))
	var length := lerpf(JOG_LENGTH, SPRINT_LENGTH, sprint_blend)
	var distance := lerpf(JOG_DISTANCE, SPRINT_DISTANCE, sprint_blend) * proportion_scale
	var nominal := distance / length
	cadence = clampf(speed / nominal * params.get_value("cadence_multiplier"), MIN_RATE, MAX_RATE)
	stride = clampf(speed / (nominal * cadence), 0.9, 1.1) * params.get_value("stride_scale")
	stride = clampf(stride, 0.9, 1.1)
	if state != "Run":
		stride = 1.0
	var weight := clampf(speed / (nominal * cadence * stride), 0.0, 1.0)
	run_weight = move_toward(run_weight, weight, dt / params.get_value("transition_duration"))
	var target_lean := clampf(acceleration * 0.006 * params.get_value("lean_intensity"), -0.10, 0.10) if grounded else 0.0
	lean = lerpf(lean, target_lean, 1.0 - exp(-10.0 * dt))
