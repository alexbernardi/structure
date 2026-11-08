## Regenerates the shipped tuning data from code so it cannot drift from the parameter definitions:
##   config/tuning_bindings.json   (the default banks and button actions)
##   presets/*.json                (a "default" preset plus a few example starting points)
## Run:  godot --headless --path utility/movement/flat-plane --script res://tools/make_tuning_files.gd
## Existing files are only overwritten with --force; --add-missing-banks appends banks that are new in code to the
## existing bindings file and changes nothing else. The example values are starting points to tune from, not
## claims about how any of them feels.
extends SceneTree

const Bindings = preload("res://tuning/tuning_bindings.gd")
const Presets = preload("res://tuning/preset_store.gd")
const Registry = preload("res://tuning/tunable_registry.gd")
const Params = preload("res://movement/movement_params.gd")

const EXAMPLES := {
	"floaty": {
		"note": "Example: low gravity, long hang time, lots of air steering.",
		"values": {"gravity": 9.8, "jump_impulse": 6.0, "max_fall_speed": 20.0, "air_control": 0.6, "air_speed_cap": 2.0, "air_accel": 20.0},
	},
	"snappy": {
		"note": "Example: fast, tight ground control and a heavier jump.",
		"values": {"max_ground_speed": 6.0, "ground_accel": 80.0, "ground_friction": 10.0, "braking": 40.0, "jump_impulse": 6.5, "gravity": 28.0, "air_control": 0.2, "coyote_time": 0.08, "jump_buffer_time": 0.08},
	},
	"strafe_lab": {
		"note": "Example: low ground friction, hop-friendly (auto-jump), strong air acceleration with a low air cap: air strafing builds speed.",
		"values": {"max_ground_speed": 5.0, "ground_friction": 4.0, "air_accel": 70.0, "air_speed_cap": 0.9, "air_control": 0.0, "auto_jump": 1.0, "jump_impulse": 5.0, "gravity": 18.0},
	},
	"slippery": {
		"note": "Example: ice. Slow to start, slow to stop.",
		"values": {"ground_friction": 1.5, "braking": 3.0, "ground_accel": 15.0},
	},
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var force := args.has("--force")
	var made := 0
	if args.has("--add-missing-banks") and FileAccess.file_exists(Bindings.DEFAULT_PATH):
		# Appends default banks the shipped file does not have yet, without touching anything already there.
		var existing := Bindings.new()
		var loaded := existing.load_file(Bindings.DEFAULT_PATH)
		if not loaded.ok:
			print("bindings: not changed, current file is invalid: ", loaded.errors[0])
			quit(1)
			return
		var names: Array = []
		for bank in existing.data.banks:
			names.append(bank.name)
		var added: Array = []
		for bank in Bindings.default_data().banks:
			if not names.has(bank.name):
				existing.data.banks.append(bank)
				added.append(bank.name)
		if not added.is_empty():
			var saved := existing.save_file(Bindings.DEFAULT_PATH)
			print("bindings: added banks ", added, " -> ", "written" if saved.ok else saved.error)
		else:
			print("bindings: no banks missing")
		quit(0)
		return
	if force or not FileAccess.file_exists(Bindings.DEFAULT_PATH):
		var b := Bindings.new()
		var r := b.save_file(Bindings.DEFAULT_PATH)
		print("bindings: ", "written" if r.ok else r.error)
		made += 1
	var locomotion_path := "res://config/locomotion_bindings.json"
	if force or not FileAccess.file_exists(locomotion_path):
		var b := Bindings.new()
		b.data = Bindings.locomotion_data()
		var result := b.save_file(locomotion_path)
		if not result.ok:
			push_error("Cannot save authored-animation bindings: %s" % result.error)
			quit(1)
			return
		print("authored animation bindings: written")
	var store := Presets.new()
	var reg := Registry.new()
	reg.register("movement", "Movement", Params.new())
	var plan := {"default": {"note": "Every parameter at its documented default.", "values": {}}}
	plan.merge(EXAMPLES)
	for name in plan:
		if store.exists(name) and not force:
			print("preset ", name, ": exists (use --force to overwrite)")
			continue
		var params := Params.new()
		for id in plan[name].values:
			params.set_value(id, float(plan[name].values[id]))
		var r2 := store.save_preset(name, {"movement": params.snapshot()}, String(plan[name].note))
		print("preset ", name, ": ", "written" if r2.ok else r2.error)
		made += 1
	quit(0)
