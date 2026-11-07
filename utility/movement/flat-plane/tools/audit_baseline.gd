## Prints the baseline numbers (Phase 0) as JSON so they can be recorded in AGENT-WORKSHOP.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_baseline.gd
extends SceneTree

const Metrics = preload("res://tests/baseline_metrics.gd")


func _initialize() -> void:
	var m120 := Metrics.measure(120)
	var m60 := Metrics.measure(60)
	print("BASELINE120 ", JSON.stringify(m120))
	print("BASELINE60  ", JSON.stringify(m60))
	var diffs := {}
	for k in m120:
		if k != "hz" and m120[k] is float and m60[k] is float:
			diffs[k] = snappedf(m60[k] - m120[k], 0.0001)
	print("DELTA60-120 ", JSON.stringify(diffs))
	quit(0)
