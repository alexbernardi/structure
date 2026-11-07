## Parameters of the procedural walk (treadmill lab). VISUAL ONLY: none of them is read by the movement simulation.
## Angles are in degrees and distances in metres here (as they are easiest to judge on a controller); the model converts.
## Booleans are switches (a fader at or above half = on).
extends RefCounted

const ParamSet = preload("res://animation/param_set.gd")

const GROUPS := ["playback", "cycle", "feet", "pelvis", "upper", "switches", "view"]


static func _d(id: String, label: String, group: String, unit: String, lo: float, hi: float, default: float, step: float, extra := {}) -> Dictionary:
	var d := {"id": id, "label": label, "group": group, "unit": unit, "min": lo, "max": hi, "default": default, "step": step, "affects": "visual"}
	d.merge(extra, true)
	return d


static func _flag(id: String, label: String, group: String, hint: String, default := 1.0) -> Dictionary:
	return _d(id, label, group, "on/off", 0.0, 1.0, default, 1.0, {"type": "bool", "hint": hint})


static func definitions() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		# ---- playback
		_d("walk_speed", "Walk speed (belt)", "playback", "m/s", 0.0, 3.0, 1.2, 0.05, {"hint": "the treadmill belt and the pace of the gait"}),
		_d("time_scale", "Playback speed", "playback", "x", 0.05, 2.0, 1.0, 0.05, {"curve": "log", "hint": "slow motion for studying a pose; physics of the walk is unchanged"}),
		_flag("freeze", "Freeze the cycle", "playback", "hold the walk at the 'cycle position' below", 0.0),
		_d("scrub", "Cycle position (frozen)", "playback", "0..1", 0.0, 1.0, 0.0, 0.005, {"hint": "0 = left heel strike, 0.5 = right heel strike"}),
		# ---- cycle
		_d("step_length", "Step length", "cycle", "m", 0.3, 1.0, 0.68, 0.01, {"hint": "heel strike to the opposite heel strike; with auto step length this is the length at 1.4 m/s"}),
		_flag("auto_step_length", "Step length grows with speed", "cycle", "off = the step length stays fixed and only the cadence changes"),
		_d("duty_factor", "Stance fraction", "cycle", "ratio", 0.5, 0.75, 0.6, 0.01, {"hint": "share of the cycle a foot is on the ground; double support = 2 x this - 1"}),
		_d("step_height", "Foot clearance", "cycle", "m", 0.0, 0.2, 0.07, 0.005, {"hint": "peak height of the ankle's swing above its path"}),
		_d("swing_peak", "Clearance peak timing", "cycle", "ratio", 0.3, 0.7, 0.5, 0.01, {"hint": "where in the swing the foot is highest (0.5 = midway)"}),
		_d("velocity_match", "Swing blends into stance", "cycle", "0..1", 0.0, 1.0, 1.0, 0.05, {"hint": "1 = the swing foot leaves and lands moving exactly like the stance foot (smooth); 0 = it stops at both ends"}),
		_d("stand_height", "Hip height", "cycle", "x leg", 0.85, 1.0, 0.93, 0.005, {"hint": "hip height at double support as a fraction of the leg length; lower = more knee bend"}),
		# ---- feet
		_flag("foot_roll", "Heel-to-toe foot roll", "feet", "off = the foot stays flat on the ground and swings flat"),
		_d("heel_strike_angle", "Heel strike angle", "feet", "deg", 0.0, 30.0, 18.0, 1.0, {"hint": "toe-up angle of the foot at the moment of landing"}),
		_d("toe_off_angle", "Toe-off angle", "feet", "deg", 0.0, 50.0, 30.0, 1.0, {"hint": "toe-down angle when the foot leaves the ground"}),
		_d("toe_clearance_angle", "Toe lift in swing", "feet", "deg", 0.0, 25.0, 8.0, 1.0, {"hint": "extra toe-up angle at mid swing"}),
		_d("foot_flat_at", "Foot flat at", "feet", "x stance", 0.05, 0.4, 0.16, 0.01, {"hint": "fraction of the stance at which the heel-strike roll ends"}),
		_d("heel_rise_at", "Heel rise at", "feet", "x stance", 0.4, 0.95, 0.72, 0.01, {"hint": "fraction of the stance at which the heel leaves the ground"}),
		# ---- pelvis
		_d("pelvis_bob", "Vertical bob", "pelvis", "m", 0.0, 0.08, 0.04, 0.002, {"hint": "hips rise over each stance leg"}),
		_flag("fx_pelvis_bob", "Fx: vertical bob", "switches", "hips rise over each stance leg"),
		_d("loading_dip", "Loading-response dip", "pelvis", "m", 0.0, 0.04, 0.01, 0.002, {"hint": "hips sink slightly just after each heel strike"}),
		_flag("fx_loading_dip", "Fx: loading dip", "switches", "hips sink just after each heel strike"),
		_d("pelvis_sway", "Side-to-side sway", "pelvis", "m", 0.0, 0.08, 0.02, 0.002, {"hint": "hips shift over the stance foot"}),
		_flag("fx_pelvis_sway", "Fx: side sway", "switches", "hips shift over the stance foot"),
		_d("pelvis_rotation", "Pelvis rotation", "pelvis", "deg", 0.0, 15.0, 5.0, 0.5, {"hint": "hips turn with the forward leg"}),
		_flag("fx_pelvis_rotation", "Fx: pelvis rotation", "switches", "hips turn with the forward leg"),
		_d("pelvic_tilt", "Pelvic tilt", "pelvis", "deg", 0.0, 12.0, 3.0, 0.5, {"hint": "the swing-side hip drops"}),
		_flag("fx_pelvic_tilt", "Fx: pelvic tilt", "switches", "the swing-side hip drops"),
		# ---- upper body
		_d("torso_lean", "Torso lean", "upper", "deg", -10.0, 20.0, 2.0, 0.5, {"hint": "forward lean of the trunk on top of the speed lean"}),
		_d("shoulder_counter", "Shoulder counter-rotation", "upper", "deg", 0.0, 25.0, 8.0, 0.5, {"hint": "shoulders turn against the hips"}),
		_flag("fx_shoulder_counter", "Fx: shoulder counter-rotation", "switches", "shoulders turn against the hips"),
		_d("arm_swing", "Arm swing", "upper", "deg", 0.0, 70.0, 24.0, 1.0, {"hint": "each arm swings against its opposite leg"}),
		_flag("fx_arm_swing", "Fx: arm swing", "switches", "each arm swings against its opposite leg"),
		_d("elbow_bend", "Elbow bend", "upper", "deg", 0.0, 90.0, 20.0, 1.0, {"hint": "resting elbow flexion; it deepens as the arm swings forward"}),
		_flag("fx_elbow_bend", "Fx: elbow bend", "switches", "elbows bend and deepen with the swing"),
		_d("arm_phase", "Arm timing offset", "upper", "deg", -45.0, 45.0, 0.0, 1.0, {"hint": "arm swing early (+) or late (-) relative to the legs"}),
		# ---- master
		_flag("gait_model", "Gait model (master)", "switches", "off = the original simple walk, for comparison"),
		# ---- view (what the lab draws; no effect on the walk)
		_flag("view_belt", "View: moving belt", "view", "stripes on the treadmill move at the walking speed"),
		_flag("view_guides", "View: guide lines", "view", "ground, hip height and plumb line"),
		_flag("view_paths", "View: foot paths", "view", "the planned ankle path of each foot"),
		_flag("view_joints", "View: joints", "view", "hip, knee, ankle and toe markers"),
		_flag("view_diagram", "View: gait diagram", "view", "stance and swing bars with the cycle position"),
		_flag("view_ortho", "View: orthographic camera", "view", "off = perspective"),
		_d("view_zoom", "View: zoom", "view", "x", 0.5, 3.0, 1.0, 0.05, {"curve": "log"}),
	]
	return out


static func create():
	return ParamSet.new(definitions())
