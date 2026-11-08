## Parameters of the procedural walk and run (treadmill lab). VISUAL ONLY: none is read by the movement simulation.
## Angles are in degrees and distances in metres here (as they are easiest to judge on a controller); the model converts.
## Booleans are switches (a fader at or above half = on).
extends RefCounted

const ParamSet = preload("res://animation/param_set.gd")

const GROUPS := ["playback", "cycle", "feet", "pelvis", "upper", "running", "switches", "view"]
const RUN_OVERRIDES := ["step_length", "duty_factor", "step_height", "swing_peak", "swing_forward", "midstance_at",
	"pelvis_bob", "torso_lean", "arm_swing", "elbow_bend"]


static func profile_id(id: String, running: bool) -> String:
	if not running:
		return id
	if id == "walk_speed":
		return "run_speed"
	return "run_" + id if id in RUN_OVERRIDES else id


static func _d(id: String, label: String, group: String, unit: String, lo: float, hi: float, default: float, step: float, extra := {}) -> Dictionary:
	var d := {"id": id, "label": label, "group": group, "unit": unit, "min": lo, "max": hi, "default": default, "step": step, "affects": "visual"}
	d.merge(extra, true)
	return d


static func _flag(id: String, label: String, group: String, hint: String, default := 1.0) -> Dictionary:
	return _d(id, label, group, "on/off", 0.0, 1.0, default, 1.0, {"type": "bool", "hint": hint})


static func definitions() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		# ---- playback
		_d("walk_speed", "Walk speed (belt)", "playback", "m/s", 0.0, 3.0, 1.55, 0.05, {"hint": "the treadmill belt and the pace of the gait"}),
		_d("time_scale", "Playback speed", "playback", "x", 0.05, 2.0, 1.0, 0.05, {"curve": "log", "hint": "slow motion for studying a pose; physics of the walk is unchanged"}),
		_flag("freeze", "Freeze the cycle", "playback", "hold the walk at the 'cycle position' below", 0.0),
		_d("scrub", "Cycle position (frozen)", "playback", "0..1", 0.0, 1.0, 0.0, 0.005, {"hint": "0 = left heel strike, 0.5 = right heel strike"}),
		# ---- cycle
		_d("step_length", "Step length", "cycle", "m", 0.3, 1.0, 0.80, 0.01, {"hint": "heel strike to the opposite heel strike; with auto step length this is the length at 1.4 m/s"}),
		_flag("auto_step_length", "Step length grows with speed", "cycle", "off = the step length stays fixed and only the cadence changes"),
		_d("duty_factor", "Stance fraction", "cycle", "ratio", 0.5, 0.75, 0.62, 0.01, {"hint": "share of the cycle a foot is on the ground; double support = 2 x this - 1"}),
		_d("step_height", "Foot clearance", "cycle", "m", 0.0, 0.2, 0.065, 0.005, {"hint": "peak height of the ankle's swing above its path"}),
		_d("swing_peak", "Clearance peak timing", "cycle", "ratio", 0.3, 0.7, 0.34, 0.01, {"hint": "the Passing landmark within swing; the reference reaches it earlier than halfway"}),
		_d("reference_fit", "Reference walk fit", "cycle", "0..1", 0.0, 1.0, 1.0, 0.05, {"hint": "1 = swing through the measured Passing/Up landmarks, reference hip timing and arms; 0 = the former single-arc procedural model"}),
		_d("swing_forward", "Swing arc forward offset", "cycle", "m", -0.2, 0.2, 0.0, 0.005, {"hint": "bows the airborne ankle path forward or back; zero effect on planted feet or the landing/push-off handovers"}),
		_d("velocity_match", "Swing blends into stance", "cycle", "0..1", 0.0, 1.0, 1.0, 0.05, {"hint": "1 = the swing foot leaves and lands moving exactly like the stance foot (smooth); 0 = it stops at both ends"}),
		_d("stand_height", "Hip height", "cycle", "x leg", 0.85, 1.0, 0.95, 0.005, {"hint": "wanted hip height at double support as a fraction of the leg length; higher lets the stance knee extend, lower keeps it bent"}),
		_d("knee_min_flex", "Knee never straighter than", "cycle", "deg", 0.0, 30.0, 13.0, 1.0, {"hint": "the hips are lowered just enough that no knee has to lock straight: smooth and human; 0 allows a fully straight leg"}),
		# ---- feet
		_flag("foot_roll", "Heel-to-toe foot roll", "feet", "off = the foot stays flat on the ground and swings flat"),
		_d("heel_strike_angle", "Heel strike angle", "feet", "deg", 0.0, 30.0, 15.0, 1.0, {"hint": "toe-up angle of the foot at the moment of landing"}),
		_d("toe_off_angle", "Toe-off angle", "feet", "deg", 0.0, 80.0, 75.0, 1.0, {"hint": "toe-down angle when the foot leaves the ground; also scales the reference swing's toe-down pose"}),
		_d("toe_clearance_angle", "Toe lift in swing", "feet", "deg", 0.0, 25.0, 0.0, 1.0, {"hint": "extra toe-up angle at mid swing"}),
		_d("foot_flat_at", "Foot flat at", "feet", "x stance", 0.05, 0.4, 0.16, 0.01, {"hint": "fraction of the stance at which the heel-strike roll ends"}),
		_d("heel_rise_at", "Heel rise at", "feet", "x stance", 0.4, 0.95, 0.42, 0.01, {"hint": "fraction of the stance at which the heel leaves the ground; earlier = a longer, smoother push-off and a higher rear heel at the other foot's heel strike"}),
		_d("midstance_at", "Ankle under the hip at", "feet", "x stance", 0.3, 0.6, 0.34, 0.01, {"hint": "fraction of the stance at which the ankle passes under the hip; lower = the feet land closer and push off further behind, so the legs straddle the hips (0.5 = centred on the planted foot)"}),
		_d("roll_flow", "Foot roll flow", "feet", "0..1", 0.0, 1.0, 1.0, 0.05, {"hint": "1 = the toe starts dropping the instant the heel lands and the foot is still turning at toe-off; 0 = the foot holds its angle around heel strike and toe-off"}),
		# ---- pelvis
		_d("pelvis_bob", "Vertical bob", "pelvis", "m", 0.0, 0.16, 0.08, 0.002, {"hint": "hip height peak-to-peak; the reference peaks near Up, not Passing"}),
		_flag("fx_pelvis_bob", "Fx: vertical bob", "switches", "hips rise over each stance leg"),
		_d("loading_dip", "Loading-response dip", "pelvis", "m", 0.0, 0.04, 0.0, 0.002, {"hint": "extra dip after heel strike; the reference hip wave already includes its Down pose"}),
		_flag("fx_loading_dip", "Fx: loading dip", "switches", "hips sink just after each heel strike"),
		_d("pelvis_sway", "Side-to-side sway", "pelvis", "m", 0.0, 0.08, 0.018, 0.002, {"hint": "hips shift over the stance foot"}),
		_flag("fx_pelvis_sway", "Fx: side sway", "switches", "hips shift over the stance foot"),
		_d("pelvis_rotation", "Pelvis rotation", "pelvis", "deg", 0.0, 15.0, 4.5, 0.5, {"hint": "hips turn with the forward leg"}),
		_flag("fx_pelvis_rotation", "Fx: pelvis rotation", "switches", "hips turn with the forward leg"),
		_d("pelvic_tilt", "Pelvic tilt", "pelvis", "deg", 0.0, 12.0, 3.0, 0.5, {"hint": "the swing-side hip drops"}),
		_flag("fx_pelvic_tilt", "Fx: pelvic tilt", "switches", "the swing-side hip drops"),
		# ---- upper body
		_d("torso_lean", "Torso lean", "upper", "deg", -10.0, 20.0, 4.0, 0.5, {"hint": "forward lean of the whole (straight) trunk from the waist, on top of the speed lean"}),
		_d("spine_curve", "Upper back curve", "upper", "deg", -10.0, 35.0, 0.0, 0.5, {"hint": "forward curl of the chest and neck (a hunched back); 0 = a straight spine, negative = chest up and back"}),
		_d("head_level", "Head kept level", "upper", "0..1", 0.0, 1.0, 1.0, 0.05, {"hint": "1 = the head stays upright however the trunk leans or curls; 0 = it follows the trunk"}),
		_d("shoulder_counter", "Shoulder counter-rotation", "upper", "deg", 0.0, 25.0, 7.5, 0.5, {"hint": "shoulders turn against the hips"}),
		_flag("fx_shoulder_counter", "Fx: shoulder counter-rotation", "switches", "shoulders turn against the hips"),
		_d("arm_swing", "Arm swing", "upper", "deg", 0.0, 70.0, 38.0, 1.0, {"hint": "each arm swings against its opposite leg"}),
		_flag("fx_arm_swing", "Fx: arm swing", "switches", "each arm swings against its opposite leg"),
		_d("elbow_bend", "Elbow bend", "upper", "deg", 0.0, 90.0, 20.0, 1.0, {"hint": "scales the elbow flexion; reference arms relax near Passing rather than holding the forearms forward"}),
		_flag("fx_elbow_bend", "Fx: elbow bend", "switches", "elbows bend and deepen with the swing"),
		_d("arm_phase", "Arm timing offset", "upper", "deg", -45.0, 45.0, 0.0, 1.0, {"hint": "arm swing early (+) or late (-) relative to the legs"}),
		# ---- running (independent tuning, shared rig, foot rockers and effect switches)
		_flag("run_mode", "Running mode", "running", "treadmill: off = reference walk, on = running with flight. The playground always uses running", 0.0),
		_d("run_speed", "Run speed (belt)", "playback", "m/s", 0.0, 15.0, 7.0, 0.05, {"hint": "running treadmill speed (7 m/s = 15.7 mph); walk speed is remembered separately"}),
		_d("run_step_length", "Run step length", "running", "m", 0.6, 2.0, 1.65, 0.01, {"hint": "one step at 4.5 m/s; auto length scales with speed^0.65 (about 2.20 m at 7 m/s)"}),
		_d("run_duty_factor", "Run stance fraction", "running", "ratio", 0.18, 0.48, 0.18, 0.01, {"hint": "below 0.5 creates flight; total airborne share = 1 - 2 x stance"}),
		_d("run_step_height", "Run heel recovery", "running", "m", 0.05, 0.55, 0.30, 0.005, {"hint": "raises the recovering heel; moderate lift keeps the trailing leg long through flight"}),
		_d("run_knee_drive", "Run knee drive", "running", "m", 0.0, 0.5, 0.26, 0.005, {"hint": "height of the leading ankle at the knee-drive landmark; lower values keep the forward thigh below horizontal"}),
		_d("run_swing_peak", "Run recovery timing", "running", "x swing", 0.2, 0.45, 0.28, 0.01, {"hint": "where the heel reaches its recovery landmark within the airborne swing"}),
		_d("run_swing_forward", "Run swing forward offset", "running", "m", -0.2, 0.2, 0.0, 0.005, {"hint": "airborne path shaping, independent of the walking path"}),
		_d("run_midstance_at", "Run ankle under hip at", "running", "x stance", 0.3, 0.6, 0.30, 0.01, {"hint": "landing/push-off placement; brings the contact leg under the body"}),
		_d("run_pelvis_bob", "Run hip compression / rise", "running", "m", 0.02, 0.2, 0.12, 0.002, {"hint": "early supported loading followed by leg extension into takeoff and flight; this is a visual cycle, not ballistic physics"}),
		_d("run_flight_lift", "Run flight lift", "running", "m", 0.0, 0.2, 0.10, 0.005, {"hint": "extra rise of the whole body, both feet included, while no foot touches the belt; 0 = feet skim the belt in flight"}),
		_d("run_torso_lean", "Run torso lean", "running", "deg", 0.0, 25.0, 15.0, 0.5, {"hint": "forward inclination of the straight trunk; default is matched to the side-view sprint reference"}),
		_d("run_arm_swing", "Run arm swing", "running", "deg", 0.0, 70.0, 50.0, 1.0, {"hint": "counter-swing against the driving knee"}),
		_d("run_elbow_bend", "Run elbow bend", "running", "deg", 0.0, 110.0, 90.0, 1.0, {"hint": "bent elbows, with a small cyclic flexion instead of the walking arm pose"}),
		# ---- master
		_flag("gait_model", "Gait model (master)", "switches", "off = the original simple walk, for comparison"),
		# ---- view (what the lab draws; no effect on the walk)
		_flag("view_belt", "View: moving belt", "view", "stripes on the treadmill move at the walking speed"),
		_flag("view_guides", "View: guide lines", "view", "ground, hip height and plumb line"),
		_flag("view_paths", "View: foot paths", "view", "the planned ankle path of each foot"),
		_flag("view_joints", "View: joints", "view", "hip, knee, ankle and toe markers"),
		_flag("view_diagram", "View: gait diagram", "view", "stance and swing bars with the cycle position"),
		_flag("view_ortho", "View: orthographic camera", "view", "off = perspective (default); turn on only for orthographic measurements", 0.0),
		_flag("edit_rig", "Edit proportions by dragging", "view", "handles on every joint and limb: drag to change lengths, widths and thickness (the walk freezes while you edit)", 0.0),
		_flag("edit_path", "Edit ankle path by dragging", "view", "P: drag landing, push-off, swing arc and hip height in either side view; Space previews, F5 saves a preset", 0.0),
		_d("view_zoom", "View: zoom", "view", "x", 0.5, 3.0, 0.8, 0.05, {"curve": "log"}),
	]
	return out


static func create():
	return ParamSet.new(definitions())
