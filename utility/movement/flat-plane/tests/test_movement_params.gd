extends RefCounted

const Params = preload("res://systems/movement_core/movement/movement_params.gd")


func test_definitions_are_consistent(t) -> void:
	t.eq(Params.check_definitions(), [], "every parameter has a label, unit, min < default < max, known group")
	t.ok(Params.definitions().size() >= 19, "all requested parameters exist")


func test_all_requested_parameters_are_present(t) -> void:
	for id in ["max_ground_speed", "ground_accel", "ground_friction", "braking", "jump_impulse", "gravity", "air_accel",
			"air_speed_cap", "air_control", "sprint_multiplier", "crouch_speed", "max_walkable_slope", "coyote_time", "jump_buffer_time"]:
		t.ok(not Params.def(id).is_empty(), "defined: %s" % id)


func test_defaults_and_units(t) -> void:
	var p := Params.new()
	for d in Params.definitions():
		t.eq(p.get_value(d.id), float(d.default), "default of %s" % d.id)
		t.ok(String(d.unit) != "", "unit of %s" % d.id)
	t.ok(p.is_default("gravity"), "fresh params are at their defaults")


func test_values_are_clamped_to_their_range(t) -> void:
	var p := Params.new()
	t.eq(p.set_value("max_ground_speed", 999.0), 15.0, "above max")
	t.eq(p.set_value("max_ground_speed", -5.0), 1.0, "below min")
	t.eq(p.set_value("coyote_time", 0.25), 0.25, "inside the range is untouched")
	t.eq(p.set_value("auto_jump", 0.7), 1.0, "bool snaps to 1")
	t.eq(p.set_value("auto_jump", 0.2), 0.0, "bool snaps to 0")
	t.eq(p.get_value("max_ground_speed"), 1.0, "stored value is the clamped one")


func test_changed_signal_fires_only_on_real_change(t) -> void:
	var p := Params.new()
	var seen := []
	p.changed.connect(func(id: String, v: float) -> void: seen.append([id, v]))
	p.set_value("gravity", 25.0)
	p.set_value("gravity", 25.0)
	p.set_value("gravity", 9999.0)
	t.eq(seen, [["gravity", 25.0], ["gravity", 60.0]], "twice: the repeat is not a change")


func test_reset_one_and_all(t) -> void:
	var p := Params.new()
	p.set_value("gravity", 30.0)
	p.set_value("ground_accel", 10.0)
	p.reset("gravity")
	t.ok(p.is_default("gravity") and not p.is_default("ground_accel"), "single reset")
	p.reset_all()
	t.ok(p.is_default("ground_accel"), "reset all")


func test_normalized_mapping_roundtrip(t) -> void:
	for d in Params.definitions():
		if d.get("type", "") == "bool":
			continue
		t.near(Params.to_normalized(d.id, Params.from_normalized(d.id, 0.5)), 0.5, 0.0001, "%s mid" % d.id)
		t.eq(Params.from_normalized(d.id, 0.0), float(d.min), "%s bottom" % d.id)
		t.eq(Params.from_normalized(d.id, 1.0), float(d.max), "%s top" % d.id)
	t.eq(Params.from_normalized("gravity", 5.0), 60.0, "out-of-range control values clamp")


func test_apply_reports_unknown_ids_and_ignores_bad_types(t) -> void:
	var p := Params.new()
	var unknown := p.apply({"gravity": 22.0, "warp_drive": 9.0, "jump_impulse": "high"})
	t.eq(unknown, ["warp_drive"], "unknown ids are reported, not dropped silently")
	t.eq(p.get_value("gravity"), 22.0, "valid entries applied")
	t.ok(p.is_default("jump_impulse"), "wrong type ignored")
