extends RefCounted

const GaitParams = preload("res://animation/gait_params.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")
const Registry = preload("res://tuning/tunable_registry.gd")
const RigParams = preload("res://animation/rig_params.gd")
const GraphParams = preload("res://animation/graph_params.gd")


func test_definitions_are_consistent(t) -> void:
	var p = GaitParams.create()
	t.eq(p.check_definitions(), [], "ids unique, ranges ordered, defaults inside, log curves positive, booleans 0..1")
	t.ok(p.definitions().size() >= 40, "a full set of variables: %d" % p.definitions().size())


func test_every_parameter_has_units_and_a_group_and_is_visual_only(t) -> void:
	var p = GaitParams.create()
	for d in p.definitions():
		t.ok(String(d.unit) != "", "%s has a unit" % d.id)
		t.ok(GaitParams.GROUPS.has(d.group), "%s is in a known group" % d.id)
		t.eq(d.affects, "visual", "%s does not touch the simulation" % d.id)


func test_values_are_clamped_snapped_and_nan_safe(t) -> void:
	var p = GaitParams.create()
	t.eq(p.set_value("step_length", 9.0), 1.0, "clamped to the maximum")
	t.eq(p.set_value("step_length", -1.0), 0.3, "clamped to the minimum")
	t.eq(p.set_value("duty_factor", 0.6049), 0.6, "snapped to the step")
	t.eq(p.set_value("walk_speed", NAN), p.def("walk_speed").default, "NaN falls back to the default")
	t.eq(p.set_value("freeze", 0.7), 1.0, "a boolean above half is on")
	t.ok(p.is_on("freeze"), "and reads as on")
	p.reset_all()
	t.ok(not p.is_on("freeze") and p.get_value("walk_speed") == p.def("walk_speed").default, "reset restores the defaults")


func test_the_gait_banks_are_valid_and_reach_every_parameter(t) -> void:
	var data := Bindings.gait_data()
	t.eq(Bindings.validate(data), [], "valid bindings")
	var b := Bindings.new()
	b.data = data
	t.eq(b.bank_count(), 8, "seven original banks plus the animation graph")
	t.eq([b.bank_name(0), b.bank_name(1), b.bank_name(2), b.bank_name(3), b.bank_name(4), b.bank_name(5), b.bank_name(6)], ["Walk Cycle", "Pelvis & Torso", "Feet & Arms", "Toggles", "View & Playback", "Proportions 1", "Proportions 2"], "names")
	var reg := Registry.new()
	reg.register("gait", "Gait (visual)", GaitParams.create())
	reg.register("rig", "Proportions (visual)", RigParams.create())
	reg.register("graph", "Animation graph", GraphParams.create())
	t.eq(b.unresolved(reg), [], "every bound parameter exists")
	var bound := b.referenced_keys()
	var missing := []
	for key in reg.keys():
		if not bound.has(key):
			missing.append(key)
	t.eq(missing, [], "every gait and proportion parameter is reachable from some bank")


func test_toggles_sit_together_on_their_own_bank(t) -> void:
	var b := Bindings.new()
	b.data = Bindings.gait_data()
	var reg := Registry.new()
	reg.register("gait", "Gait (visual)", GaitParams.create())
	for strip in range(1, 9):
		for kind in ["fader", "knob"]:
			var key := b.slot_key(3, strip, kind)
			t.ok(key != "" and reg.is_bool(key), "toggles bank strip %d %s is a switch: %s" % [strip, kind, key])
	for bank in [0, 1, 2]:
		for strip in range(1, 9):
			var key := b.slot_key(bank, strip, "fader")
			if key != "":
				t.ok(not reg.is_bool(key), "%s is a value, not a switch" % key)
