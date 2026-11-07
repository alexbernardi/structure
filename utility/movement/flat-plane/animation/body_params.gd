## Parameters of the procedural body model (torso, pelvis, landing, rotation, head, shoulders and arms).
## Every one is VISUAL ONLY: none of them is read by the movement simulation. Units are physical or conceptual
## ("x" = a dimensionless multiplier, 0 = effect off, 1 = nominal). Frequencies use a log curve so each octave of a
## controller travels equally; the effect flags are booleans (a fader at or above half = on).
extends RefCounted

const ParamSet = preload("res://animation/param_set.gd")

const GROUPS := ["switches", "torso", "pelvis", "landing", "rotation", "head", "arms"]


static func _d(id: String, label: String, group: String, unit: String, lo: float, hi: float, default: float, step: float, extra := {}) -> Dictionary:
	var d := {"id": id, "label": label, "group": group, "unit": unit, "min": lo, "max": hi, "default": default, "step": step, "affects": "visual"}
	d.merge(extra, true)
	return d


static func _flag(id: String, label: String, hint: String) -> Dictionary:
	return _d(id, label, "switches", "on/off", 0.0, 1.0, 1.0, 1.0, {"type": "bool", "hint": hint})


static func definitions() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		# ---- switches: every effect can be disabled on its own; the master turns the whole model off
		_flag("body_dynamics", "Body dynamics (master)", "off = the original simple pose, no spring model at all"),
		_flag("fx_torso_lean", "Fx: torso lean", "forward/back lean from acceleration and speed"),
		_flag("fx_torso_lateral", "Fx: lean into turns", "roll toward the inside of a turn"),
		_flag("fx_anticipation", "Fx: turn anticipation", "torso (and head) turn ahead of the body"),
		_flag("fx_pelvis_shift", "Fx: pelvis weight shift", "hips shift against acceleration"),
		_flag("fx_pelvis_gait", "Fx: pelvis bob and sway", "vertical bob and side sway while walking/running"),
		_flag("fx_landing", "Fx: landing compression", "hips compress on landing and rebound"),
		_flag("fx_head", "Fx: head stabilisation", "head stays level against torso lean, leads turns"),
		_flag("fx_arms", "Fx: shoulders and arms", "shoulder counter-rotation and arm follow-through"),
		_flag("fx_facing_lag", "Fx: rotation lag", "the body turns toward its heading through a spring"),
		# ---- torso
		_d("torso_lean_amp", "Torso lean amplitude", "torso", "x", 0.0, 2.0, 1.0, 0.05, {"hint": "scales every torso angle"}),
		_d("lean_accel_gain", "Lean per acceleration", "torso", "rad/(m/s^2)", 0.0, 0.03, 0.008, 0.0005, {"hint": "lean forward when speeding up, back when braking"}),
		_d("lean_speed_gain", "Lean per speed", "torso", "rad/(m/s)", 0.0, 0.06, 0.015, 0.001, {"hint": "steady forward lean while running"}),
		_d("lean_max_deg", "Maximum forward/back lean", "torso", "deg", 0.0, 40.0, 18.0, 1.0),
		_d("lateral_lean_gain", "Lean into turns", "torso", "rad/(m/s^2)", 0.0, 0.04, 0.012, 0.0005, {"hint": "roll per sideways acceleration"}),
		_d("lateral_lean_max_deg", "Maximum sideways lean", "torso", "deg", 0.0, 25.0, 10.0, 1.0),
		_d("anticipation_lead", "Turn anticipation lead", "torso", "s", 0.0, 0.4, 0.12, 0.01, {"hint": "torso yaw = turn rate x lead"}),
		_d("torso_freq", "Torso spring frequency", "torso", "Hz", 0.5, 12.0, 3.0, 0.1, {"curve": "log"}),
		_d("torso_damping", "Torso damping ratio", "torso", "ratio", 0.05, 2.0, 0.55, 0.01, {"hint": "<1 springy follow-through, 1 critical, >1 sluggish"}),
		# ---- pelvis
		_d("hip_sway_amp", "Hip sway amplitude", "pelvis", "x", 0.0, 2.0, 1.0, 0.05, {"hint": "scales side sway and bob"}),
		_d("sway_distance", "Hip sway distance", "pelvis", "m", 0.0, 0.08, 0.025, 0.001),
		_d("bob_height", "Vertical bob", "pelvis", "m", 0.0, 0.08, 0.03, 0.001),
		_d("weight_shift_gain", "Weight shift per acceleration", "pelvis", "m/(m/s^2)", 0.0, 0.004, 0.0012, 0.0001),
		_d("weight_shift_max", "Maximum weight shift", "pelvis", "m", 0.0, 0.1, 0.05, 0.005),
		_d("hip_freq", "Hip spring frequency", "pelvis", "Hz", 0.5, 12.0, 2.5, 0.1, {"curve": "log"}),
		_d("hip_damping", "Hip damping ratio", "pelvis", "ratio", 0.05, 2.0, 0.5, 0.01),
		# ---- landing
		_d("landing_compression", "Landing compression", "landing", "x", 0.0, 2.0, 1.0, 0.05, {"hint": "how deep the hips drop on impact"}),
		_d("landing_gain", "Compression per impact speed", "landing", "m/(m/s)", 0.0, 0.03, 0.012, 0.0005),
		_d("landing_max", "Maximum compression", "landing", "m", 0.0, 0.35, 0.2, 0.01),
		_d("landing_rebound", "Landing rebound", "landing", "x", 0.0, 2.0, 0.35, 0.05, {"hint": "energy returned when the hips bottom out"}),
		_d("landing_freq", "Landing spring frequency", "landing", "Hz", 1.0, 15.0, 5.0, 0.1, {"curve": "log"}),
		_d("landing_damping", "Landing damping ratio", "landing", "ratio", 0.05, 2.0, 0.45, 0.01),
		# ---- rotation
		_d("rotation_lag", "Rotational lag", "rotation", "x", 0.1, 4.0, 1.0, 0.05, {"curve": "log", "hint": "divides every rotation spring frequency: more lag = slower to turn"}),
		_d("rotation_freq", "Rotation spring frequency", "rotation", "Hz", 0.5, 15.0, 6.0, 0.1, {"curve": "log"}),
		_d("rotation_damping", "Rotation damping ratio", "rotation", "ratio", 0.1, 2.0, 0.8, 0.01),
		# ---- head
		_d("head_stabilization", "Head stabilisation", "head", "0..1", 0.0, 1.0, 0.6, 0.01, {"hint": "1 = the head stays level however the torso leans"}),
		_d("head_freq", "Head spring frequency", "head", "Hz", 1.0, 15.0, 6.0, 0.1, {"curve": "log"}),
		_d("head_max_yaw_deg", "Maximum head turn", "head", "deg", 0.0, 90.0, 60.0, 1.0),
		# ---- shoulders and arms
		_d("shoulder_counter_amp", "Shoulder counter-rotation", "arms", "x", 0.0, 2.0, 1.0, 0.05),
		_d("arm_swing_amp", "Arm swing amplitude", "arms", "x", 0.0, 2.0, 1.0, 0.05),
		_d("follow_through", "Body follow-through", "arms", "x", 0.0, 2.0, 1.0, 0.05, {"hint": "arms and shoulders lag and overshoot sudden changes"}),
	]
	return out


static func create():
	return ParamSet.new(definitions())
