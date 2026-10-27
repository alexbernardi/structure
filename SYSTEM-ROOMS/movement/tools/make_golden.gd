## Regenerates fixtures/golden_trajectory.json. Only run when the model is changed ON PURPOSE,
## and record the reason in the room README changelog.
##   godot --headless --path SYSTEM-ROOMS/movement --script res://tools/make_golden.gd
extends SceneTree

const Model = preload("../src/movement_model.gd")
const Sim = preload("../tests/trajectory_sim.gd")


func _initialize() -> void:
	var info := Engine.get_version_info()
	var data := {
		"model_version": Model.VERSION,
		"params": Model.default_params(),
		"generated_on": "%s %s" % [OS.get_name(), info.string],
		"rows": Sim.simulate(Model.default_params()),
	}
	var f := FileAccess.open("res://fixtures/golden_trajectory.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", true, true))
	f.close()
	print("wrote res://fixtures/golden_trajectory.json (%d rows)" % data.rows.size())
	quit(0)
