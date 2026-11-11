## Prints the movement parameters and the default MIDI bank layout as Markdown, straight from the code.
##   godot --headless --path utility/movement/flat-plane --script res://tools/audit_tables.gd
extends SceneTree

const Params = preload("res://systems/movement_core/movement/movement_params.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")
const Registry = preload("res://tuning/tunable_registry.gd")


func _initialize() -> void:
	print("TABLE-PARAMS")
	print("| Parameter | Unit | Min | Max | Default | Step | Group |")
	print("|---|---|---|---|---|---|---|")
	for d in Params.definitions():
		print("| `%s` | %s | %s | %s | %s | %s | %s |" % [d.id, d.unit, str(d.min), str(d.max), str(d.default), str(d.step), d.group])
	var reg := Registry.new()
	reg.register("movement", "Movement", Params.new())
	var b := Bindings.new()
	for i in b.bank_count():
		print("TABLE-BANK %d %s" % [i + 1, b.bank_name(i)])
		print("| Strip | Fader (coarse) | Knob (fine) |")
		print("|---|---|---|")
		for s in range(1, 9):
			var f := b.slot_key(i, s, "fader")
			var k := b.slot_key(i, s, "knob")
			print("| %d | %s | %s |" % [s, reg.label_of(f) if f != "" else "-", reg.label_of(k) if k != "" else "-"])
	print("TABLE-BUTTONS")
	for part in Bindings.STRIP_PARTS:
		print("strip %s -> %s" % [part, Bindings.ACTIONS[b.strip_action(part)]])
	for id in b.data.global_actions:
		print("%s -> %s" % [id, Bindings.ACTIONS[b.data.global_actions[id]]])
	quit(0)
