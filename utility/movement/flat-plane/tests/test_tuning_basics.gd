extends RefCounted

const Takeover = preload("res://tuning/soft_takeover.gd")
const Registry = preload("res://tuning/tunable_registry.gd")
const Params = preload("res://movement/movement_params.gd")


func test_arm_engages_when_already_aligned(t) -> void:
	t.ok(Takeover.arm(0.50, 0.51).engaged, "within tolerance: engaged immediately")
	t.ok(not Takeover.arm(0.90, 0.30).engaged, "far away: needs pickup")
	t.eq(Takeover.arm(0.90, 0.30).side, 1, "fader above the value")
	t.eq(Takeover.arm(0.10, 0.30).side, -1, "fader below the value")
	t.ok(not Takeover.arm(-1.0, 0.30).engaged and Takeover.arm(-1.0, 0.30).side == 0, "never-touched fader: unknown side")


func test_no_jump_before_the_fader_reaches_the_value(t) -> void:
	var s := Takeover.arm(0.90, 0.30)
	for pos in [0.88, 0.7, 0.5, 0.35]:
		s = Takeover.update(s, pos, 0.30)
		t.ok(not s.engaged, "still waiting at %.2f" % pos)
	s = Takeover.update(s, 0.31, 0.30)
	t.ok(s.engaged, "engages on arrival")


func test_crossing_engages_even_if_the_fader_skips_the_tolerance_band(t) -> void:
	var s := Takeover.arm(0.90, 0.30)
	s = Takeover.update(s, 0.60, 0.30)
	s = Takeover.update(s, 0.05, 0.30)   # a fast flick straight past
	t.ok(s.engaged, "crossing the value counts")


func test_first_touch_of_an_unknown_fader_records_a_side_then_waits(t) -> void:
	var s := Takeover.arm(-1.0, 0.30)
	s = Takeover.update(s, 0.8, 0.30)
	t.ok(not s.engaged and s.side == 1, "first event only records the side")
	s = Takeover.update(s, 0.2, 0.30)
	t.ok(s.engaged, "then crossing engages")


func test_engaged_state_is_sticky(t) -> void:
	var s := Takeover.update(Takeover.arm(0.5, 0.5), 0.9, 0.1)
	t.ok(s.engaged, "once engaged, the fader owns the value until the value changes elsewhere")


func test_tolerance_is_about_three_fader_steps(t) -> void:
	t.ok(Takeover.TOLERANCE >= 3.0 / 127.0 and Takeover.TOLERANCE <= 0.05, "tolerance %.3f" % Takeover.TOLERANCE)


func test_registry_resolves_keys_and_formats(t) -> void:
	var reg := Registry.new()
	var p := Params.new()
	reg.register("movement", "Movement", p)
	t.ok(reg.has_key("movement.gravity") and not reg.has_key("movement.warp") and not reg.has_key("camera.fov"), "known / unknown / unregistered")
	t.eq(reg.label_of("movement.gravity"), "Gravity", "label")
	t.eq(reg.unit_of("movement.gravity"), "m/s^2", "unit")
	t.eq(reg.format_value("movement.gravity", 19.6), "19.6 m/s^2", "one decimal for 0.2 steps")
	t.eq(reg.format_value("movement.coyote_time", 0.1), "0.10 s", "two decimals for 0.01 steps")
	t.eq(reg.format_value("movement.ground_accel", 45.0), "45 m/s^2", "integers for step 1")
	t.eq(reg.format_value("movement.auto_jump", 1.0), "ON", "booleans")
	t.eq(reg.keys().size(), Params.definitions().size(), "every parameter is addressable")


func test_registry_set_clamps_and_snaps(t) -> void:
	var reg := Registry.new()
	reg.register("movement", "Movement", Params.new())
	t.eq(reg.set_value("movement.max_ground_speed", 4.537), 4.5, "snapped to the 0.1 step")
	t.eq(reg.set_value("movement.max_ground_speed", 99.0), 15.0, "clamped to max")
	t.eq(reg.set_value("movement.coyote_time", 0.123), 0.12, "0.01 step")
	t.near(reg.norm("movement.max_ground_speed"), 1.0, 0.0001, "normalised position")
	t.eq(reg.from_norm("movement.max_ground_speed", 0.0), 1.0, "bottom of the range")


func test_registry_key_validation(t) -> void:
	for ok in ["movement.gravity", "camera.fov", "a1.b_2"]:
		t.ok(Registry.is_valid_key(ok), ok)
	for bad in ["gravity", "movement.", ".gravity", "a.b.c", "Movement.Gravity", "movement.gra vity", ""]:
		t.ok(not Registry.is_valid_key(bad), "rejects '%s'" % bad)


func test_extra_targets_share_the_registry(t) -> void:
	var reg := Registry.new()
	reg.register("movement", "Movement", Params.new())
	var extra := Params.new()
	reg.register("lab", "Another system", extra)
	t.eq(reg.keys().size(), Params.definitions().size() * 2, "both targets listed")
	reg.set_value("lab.gravity", 10.0)
	t.eq(extra.get_value("gravity"), 10.0, "routed to the right object")
	t.eq(reg.value("movement.gravity"), 19.6, "without touching the other")
	reg.unregister("lab")
	t.ok(not reg.has_key("lab.gravity"), "unregistered")


func test_snap_helper(t) -> void:
	t.eq(Params.snap("gravity", 19.64), 19.6, "nearest step")
	t.eq(Params.snap("gravity", 0.0), 1.0, "clamped after snapping")
	t.eq(Params.snap("auto_jump", 0.6), 1.0, "bool")
	t.eq(Params.snap("unknown", 3.3), 3.3, "unknown ids pass through")
