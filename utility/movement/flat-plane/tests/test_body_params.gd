extends RefCounted

const BodyParams = preload("res://animation/body_params.gd")
const ParamSet = preload("res://animation/param_set.gd")
const Registry = preload("res://tuning/tunable_registry.gd")


func test_definitions_are_consistent(t) -> void:
	var p = BodyParams.create()
	t.eq(p.check_definitions(), [], "ids, ranges, defaults, curves, tags")
	t.ok(p.definitions().size() >= 38, "the model is fully parameterised: %d parameters" % p.definitions().size())
	for d in p.definitions():
		t.ok(String(d.unit) != "" and String(d.label) != "", "%s has a label and a unit" % d.id)
		t.ok(BodyParams.GROUPS.has(d.group), "%s group %s known" % [d.id, d.group])


func test_every_body_parameter_is_visual_only(t) -> void:
	var p = BodyParams.create()
	for d in p.definitions():
		t.eq(p.affects(d.id), "visual", "%s is tagged visual-only" % d.id)


func test_every_effect_has_its_own_switch(t) -> void:
	var p = BodyParams.create()
	for id in ["body_dynamics", "fx_torso_lean", "fx_torso_lateral", "fx_anticipation", "fx_pelvis_shift", "fx_pelvis_gait", "fx_landing", "fx_head", "fx_arms", "fx_facing_lag"]:
		t.ok(not p.def(id).is_empty() and p.def(id).type == "bool", "%s is a boolean switch" % id)
		t.ok(p.is_on(id), "%s defaults to on" % id)


func test_values_are_clamped_snapped_and_nan_safe(t) -> void:
	var p = BodyParams.create()
	t.eq(p.set_value("torso_lean_amp", 99.0), 2.0, "above max")
	t.eq(p.set_value("torso_lean_amp", -1.0), 0.0, "below min")
	t.eq(p.set_value("torso_lean_amp", 0.337), 0.35, "snapped to the 0.05 step")
	t.eq(p.set_value("torso_freq", NAN), 3.0, "NaN falls back to the default")
	t.eq(p.set_value("fx_head", 0.4), 0.0, "booleans snap down")
	t.eq(p.set_value("fx_head", 0.6), 1.0, "and up")
	t.eq(p.set_value("nonexistent", 5.0), 5.0, "unknown ids are not stored")
	t.ok(not p.values.has("nonexistent"), "and leave no trace")


func test_changed_signal_and_reset(t) -> void:
	var p = BodyParams.create()
	var seen := []
	p.changed.connect(func(id: String, v: float) -> void: seen.append([id, v]))
	p.set_value("head_stabilization", 0.8)
	p.set_value("head_stabilization", 0.8)
	t.eq(seen, [["head_stabilization", 0.8]], "only real changes are announced")
	p.reset("head_stabilization")
	t.ok(p.is_default("head_stabilization"), "reset")
	p.set_value("torso_freq", 9.0)
	p.set_value("hip_damping", 1.5)
	p.reset_all()
	t.ok(p.is_default("torso_freq") and p.is_default("hip_damping"), "reset all")


func test_apply_reports_unknown_ids(t) -> void:
	var p = BodyParams.create()
	var unknown: Array[String] = p.apply({"torso_freq": 6.0, "warp": 1.0, "hip_freq": "fast"})
	t.eq(unknown, ["warp"], "unknown reported, not dropped silently")
	t.eq(p.get_value("torso_freq"), 6.0, "valid applied")
	t.ok(p.is_default("hip_freq"), "wrong type ignored")


func test_curves_roundtrip_and_shape(t) -> void:
	var p = BodyParams.create()
	for d in p.definitions():
		if d.get("type", "") == "bool":
			continue
		t.eq(p.from_normalized(d.id, 0.0), float(d.min), "%s bottom" % d.id)
		t.eq(p.from_normalized(d.id, 1.0), float(d.max), "%s top" % d.id)
		t.near(p.to_normalized(d.id, p.from_normalized(d.id, 0.37)), 0.37, 1e-9, "%s %s curve roundtrip" % [d.id, d.get("curve", "linear")])
	# log curve: the middle of a frequency control is the geometric mean, so each octave gets equal travel
	t.near(p.from_normalized("torso_freq", 0.5), sqrt(0.5 * 12.0), 1e-9, "log curve midpoint")
	var lin := ParamSet.new([{"id": "a", "label": "A", "group": "g", "unit": "u", "min": 0.0, "max": 10.0, "default": 5.0, "step": 0.1},
		{"id": "q", "label": "Q", "group": "g", "unit": "u", "min": 0.0, "max": 10.0, "default": 5.0, "step": 0.1, "curve": "quad"},
		{"id": "s", "label": "S", "group": "g", "unit": "u", "min": 0.0, "max": 10.0, "default": 5.0, "step": 0.1, "curve": "sqrt"}])
	t.eq(lin.from_normalized("a", 0.5), 5.0, "linear")
	t.eq(lin.from_normalized("q", 0.5), 2.5, "quad: finer at the low end")
	t.near(lin.from_normalized("s", 0.25), 5.0, 1e-9, "sqrt: finer at the high end")
	t.eq(lin.from_normalized("a", 7.0), 10.0, "out-of-range control positions clamp")


func test_bad_definitions_are_detected(t) -> void:
	var bad := ParamSet.new([
		{"id": "a", "label": "A", "group": "g", "unit": "u", "min": 5.0, "max": 1.0, "default": 2.0, "step": 1.0},
		{"id": "a", "label": "A", "group": "g", "unit": "u", "min": 0.0, "max": 1.0, "default": 9.0, "step": 1.0},
		{"id": "l", "label": "L", "group": "g", "unit": "u", "min": 0.0, "max": 1.0, "default": 0.5, "step": 0.1, "curve": "log"},
		{"id": "c", "label": "C", "group": "g", "unit": "u", "min": 0.0, "max": 1.0, "default": 0.5, "step": 0.1, "curve": "zigzag"},
		{"id": "v", "label": "V", "group": "g", "unit": "u", "min": 0.0, "max": 1.0, "default": 0.5, "step": 0.1, "affects": "audio"},
	])
	t.ok(bad.check_definitions().size() >= 6, "each mistake is reported: %s" % str(bad.check_definitions()))


func test_works_as_a_tuning_target(t) -> void:
	var reg := Registry.new()
	var p = BodyParams.create()
	reg.register("body", "Body dynamics", p)
	t.ok(reg.has_key("body.torso_freq") and reg.has_key("body.fx_head"), "addressable by key")
	t.eq(reg.label_of("body.torso_freq"), "Torso spring frequency", "label")
	t.eq(reg.set_value("body.torso_freq", 7.77), 7.8, "set through the registry snaps")
	t.eq(p.get_value("torso_freq"), 7.8, "reaches the object")
	t.near(reg.norm("body.torso_freq"), p.to_normalized("torso_freq", 7.8), 1e-12, "uses the parameter's own curve")
	t.eq(reg.from_norm("body.torso_freq", 0.0), 0.5, "bottom of a log control")
	t.eq(reg.format_value("body.fx_head", 1.0), "ON", "booleans read ON/off")
	t.eq(reg.format_value("body.torso_freq", 3.0), "3.0 Hz", "units shown")
	t.eq(reg.def_of("body.torso_freq").affects, "visual", "the tag is reachable for the HUD")
