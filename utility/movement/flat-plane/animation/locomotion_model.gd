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
var steer := 1.0         ## cadence multiplier the presentation applies on top of `cadence` (vault anticipation)
var lean := 0.0
var _grounded := true
var _landing_time := 0.0


func _init(parameters, scale_ratio := 1.0) -> void:
	params = parameters
	proportion_scale = scale_ratio


func update(dt: float, speed: float, grounded: bool, vy: float, acceleration: float, teleported := false, crouching := false, vaulting := false) -> void:
	if not is_finite(dt) or dt < 0.0 or not is_finite(speed) or speed < 0.0:
		push_error("Locomotion requires finite, non-negative elapsed time and measured speed")
		return
	var supported := grounded or vaulting   # a vault lands inside its own clip: no separate landing reaction
	if teleported:
		_grounded = supported
		_landing_time = 0.0
		lean = 0.0
	if supported and not _grounded:
		_landing_time = 0.20
	_grounded = supported
	_landing_time = maxf(0.0, _landing_time - dt)
	state = "Jump" if not grounded and vy > 0.15 else "Fall" if not grounded else "Land" if _landing_time > 0.0 else "Run" if speed > 0.15 else "Idle"
	if grounded and crouching:
		state = "Crouch"
	if vaulting:
		state = "Vault"
	sprint_blend = move_toward(sprint_blend, blend_target(speed), dt / params.get_value("transition_duration"))
	var nominal := _nominal_speed(sprint_blend)
	cadence = cadence_at(speed, sprint_blend)
	stride = clampf(speed / (nominal * cadence), 0.9, 1.1) * params.get_value("stride_scale")
	stride = clampf(stride, 0.9, 1.1)
	if state != "Run":
		stride = 1.0
	var weight := clampf(speed / (nominal * cadence * stride), 0.0, 1.0)
	run_weight = move_toward(run_weight, weight, dt / params.get_value("transition_duration"))
	if state == "Run":
		stride = clampf(stride / steer, 0.9, 1.1)   # a steered cadence keeps the feet with the ground, within limits
	var target_lean := clampf(acceleration * 0.006 * params.get_value("lean_intensity"), -0.10, 0.10) if grounded and not vaulting else 0.0
	lean = lerpf(lean, target_lean, 1.0 - exp(-10.0 * dt))


## Jog-to-sprint blend the model settles at for a ground speed.
func blend_target(speed: float) -> float:
	var jog_speed := JOG_DISTANCE / JOG_LENGTH * proportion_scale
	var sprint_speed := SPRINT_DISTANCE / SPRINT_LENGTH * proportion_scale
	return clampf((speed - jog_speed) / (sprint_speed - jog_speed), 0.0, 1.0)


## Playback rate of the running loops at a ground speed and blend (before any steering).
func cadence_at(speed: float, blend: float) -> float:
	return clampf(speed / _nominal_speed(blend) * params.get_value("cadence_multiplier"), MIN_RATE, MAX_RATE)


## Loop cycles per second at a ground speed and blend (before any steering).
func cycle_rate(speed: float, blend: float) -> float:
	return cadence_at(speed, blend) / lerpf(JOG_LENGTH, SPRINT_LENGTH, blend)


## Ground speed the blended loop covers at its authored rate.
func _nominal_speed(blend: float) -> float:
	return lerpf(JOG_DISTANCE, SPRINT_DISTANCE, blend) * proportion_scale / lerpf(JOG_LENGTH, SPRINT_LENGTH, blend)
