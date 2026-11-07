## Regenerates the shipped treadmill-lab data from code so it cannot drift from the parameter definitions:
##   config/gait_bindings.json    (the five gait banks and the button actions)
##   presets_gait/*.json          ("default" plus a few starting points)
## Run:  godot --headless --path utility/movement/flat-plane --script res://tools/make_gait_files.gd
## Existing files are only overwritten with --force. The example values are starting points to tune from, not claims
## about how any of them looks or feels.
extends SceneTree

const Bindings = preload("res://tuning/tuning_bindings.gd")
const Presets = preload("res://tuning/preset_store.gd")
const GaitParams = preload("res://animation/gait_params.gd")
const RigParams = preload("res://animation/rig_params.gd")

const BINDINGS_PATH := "res://config/gait_bindings.json"
const PRESET_DIR := "res://presets_gait"

const EXAMPLES := {
	"first_defaults": {
		"note": "The factory defaults before the first tuning session (2026-11-07), with the original proportions. Kept for reference and comparison.",
		"values": {
			"walk_speed": 1.2, "step_length": 0.68, "stand_height": 0.93, "velocity_match": 1.0, "step_height": 0.07, "swing_peak": 0.5,
			"knee_min_flex": 12.0, "heel_strike_angle": 18.0, "toe_off_angle": 30.0, "heel_rise_at": 0.72, "pelvis_bob": 0.04,
			"loading_dip": 0.0, "pelvis_sway": 0.02, "pelvis_rotation": 5.0, "shoulder_counter": 8.0, "torso_lean": 2.0,
			"arm_swing": 24.0, "elbow_bend": 20.0, "arm_phase": 0.0, "view_zoom": 1.0,
		},
		"rig": "original",
	},
	"stroll": {
		"note": "Example: slow, relaxed walk: short steps, long stance, small arm swing.",
		"values": {"walk_speed": 0.8, "step_length": 0.6, "duty_factor": 0.64, "step_height": 0.05, "arm_swing": 14.0, "pelvis_bob": 0.03, "pelvis_rotation": 3.5, "shoulder_counter": 5.0},
	},
	"brisk": {
		"note": "Example: brisk walk: longer steps, more arm swing and body rotation.",
		"values": {"walk_speed": 1.8, "step_length": 0.72, "duty_factor": 0.57, "step_height": 0.09, "arm_swing": 34.0, "elbow_bend": 35.0, "pelvis_rotation": 7.0, "shoulder_counter": 12.0, "torso_lean": 4.0},
	},
	"stiff_robot": {
		"note": "Example: no foot roll and no body motion at all, to see what each effect adds.",
		"values": {"foot_roll": 0.0, "fx_pelvis_bob": 0.0, "fx_loading_dip": 0.0, "fx_pelvis_sway": 0.0, "fx_pelvis_rotation": 0.0, "fx_pelvic_tilt": 0.0, "fx_shoulder_counter": 0.0, "fx_elbow_bend": 0.0, "arm_swing": 10.0},
	},
	"shuffle": {
		"note": "Example: low foot clearance and little roll: a tired shuffle.",
		"values": {"walk_speed": 0.9, "step_length": 0.5, "step_height": 0.02, "heel_strike_angle": 6.0, "toe_off_angle": 12.0, "toe_clearance_angle": 2.0, "arm_swing": 8.0, "pelvis_bob": 0.02},
	},
}


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--add-missing-banks"):
		var bindings := Bindings.new()
		var loaded := bindings.load_file(BINDINGS_PATH)
		if not loaded.ok:
			push_error("Cannot append gait banks: %s" % loaded.errors)
			quit(1)
			return
		var names: Array[String] = []
		for bank in bindings.data.banks:
			names.append(bank.name)
		for bank in Bindings.gait_data().banks:
			if bank.name not in names:
				bindings.data.banks.append(bank)
		var saved := bindings.save_file(BINDINGS_PATH)
		if not saved.ok:
			push_error("Cannot save gait banks: %s" % saved.error)
		quit(0 if saved.ok else 1)
		return
	var force := OS.get_cmdline_user_args().has("--force")
	if force or not FileAccess.file_exists(BINDINGS_PATH):
		var b := Bindings.new()
		b.data = Bindings.gait_data()
		var r := b.save_file(BINDINGS_PATH)
		print("gait bindings: ", "written" if r.ok else r.error)
	else:
		print("gait bindings: exists (use --force to overwrite)")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIR))
	var store := Presets.new(PRESET_DIR)
	var plan := {"default": {"note": "Every gait and proportion parameter at the defaults saved on 2026-11-07 after the first tuning session.", "values": {}}}
	plan.merge(EXAMPLES)
	for name in plan:
		if store.exists(name) and not force:
			print("preset ", name, ": exists (use --force to overwrite)")
			continue
		var params = GaitParams.create()
		for id in plan[name].values:
			params.set_value(id, float(plan[name].values[id]))
		var targets := {"gait": params.snapshot()}
		if name == "default":
			targets["rig"] = RigParams.create().snapshot()   # the factory default also restores the proportions
		elif plan[name].get("rig", "") == "original":
			var rig = RigParams.create()
			for id in RigParams.ORIGINAL:
				rig.set_value(id, float(RigParams.ORIGINAL[id]))
			targets["rig"] = rig.snapshot()
		var r2 := store.save_preset(name, targets, String(plan[name].note))
		print("preset ", name, ": ", "written" if r2.ok else r2.error)
	quit(0)
