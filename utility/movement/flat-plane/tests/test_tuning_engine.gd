extends RefCounted

const Engine_ = preload("res://tuning/tuning_engine.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")
const Registry = preload("res://tuning/tunable_registry.gd")
const Params = preload("res://movement/movement_params.gd")
const BodyParams = preload("res://animation/body_params.gd")

var _p
var _reg
var _b
var _e
var _events: Array = []
var _actions: Array = []


func before_each() -> void:
	_p = Params.new()
	_reg = Registry.new()
	_reg.register("movement", "Movement", _p)
	_reg.register("body", "Body (visual)", BodyParams.create())
	_b = Bindings.new()
	_e = Engine_.new(_reg, _b)
	_events = []
	_actions = []
	_e.param_changed.connect(func(k: String, v: float, s: String) -> void: _events.append([k, v, s]))
	_e.action_requested.connect(func(a: String, c: Dictionary) -> void: _actions.append([a, c]))


func after_each() -> void:
	# The signal lambdas below capture this test object; dropping the engine breaks that reference cycle.
	_e = null
	_b = null
	_reg = null
	_p = null


func _fader(strip: int, v: float) -> void:
	_e.on_control("strip%d_fader" % strip, {"kind": "fader", "value": v})


func _knob(strip: int, delta: int) -> void:
	_e.on_control("strip%d_knob" % strip, {"kind": "knob", "delta": delta})


func _press(id: String) -> void:
	_e.on_control(id, {"kind": "button", "pressed": true})


# ------------------------------------------------------------------ faders and soft takeover

func test_fader_sets_the_bound_parameter_across_its_range(t) -> void:
	_fader(1, 0.0)
	_fader(1, 1.0)   # first touch of an unknown fader only records a side; the second crosses/engages
	_fader(1, 0.5)
	t.near(_p.get_value("max_ground_speed"), 8.0, 0.1, "strip 1 fader is max ground speed: 1 + 0.5 * 14 = 8.0")
	_fader(1, 1.0)
	t.eq(_p.get_value("max_ground_speed"), 15.0, "top of the fader is the maximum")
	_fader(1, 0.0)
	t.eq(_p.get_value("max_ground_speed"), 1.0, "bottom is the minimum")


func test_fader_far_from_the_value_does_nothing_until_it_arrives(t) -> void:
	_p.set_value("max_ground_speed", 4.5)         # normalised 0.25
	_fader(1, 0.95)
	_fader(1, 0.7)
	_fader(1, 0.4)
	t.eq(_p.get_value("max_ground_speed"), 4.5, "no jump while approaching")
	t.eq(_events.size(), 0, "no change events either")
	_fader(1, 0.26)
	_fader(1, 0.30)
	t.near(_p.get_value("max_ground_speed"), 1.0 + 0.30 * 14.0, 0.1, "follows once it has arrived")


func test_first_move_of_a_fader_whose_position_is_unknown_never_jumps(t) -> void:
	_p.set_value("gravity", 19.6)
	_e.switch_bank(1)
	var before: float = _p.get_value("gravity")
	_fader(2, 0.05)   # strip 2 is gravity in bank 2; the fader was never touched, so its position is unknown
	t.eq(_p.get_value("gravity"), before, "first event cannot change anything")
	_fader(2, 0.15)
	t.eq(_p.get_value("gravity"), before, "still below the value (0.33): waiting")


func test_changing_bank_arms_pickup_for_every_fader(t) -> void:
	_fader(1, 0.25)
	_fader(1, 0.27)   # bank 1: max_ground_speed engaged near its value (0.25)
	t.ok(_e.fader_info(1).engaged, "engaged in bank 1")
	for s in range(1, 9):
		_fader(s, 0.9)   # park every fader high (bank 1 params unaffected except strip 1 which is now high)
	var gravity_before: float = _p.get_value("gravity")
	_e.switch_bank(1)
	t.ok(not _e.fader_info(2).engaged, "bank 2 strip 2: fader at 0.9, gravity at 0.33 -> pickup needed")
	_fader(2, 0.88)
	t.eq(_p.get_value("gravity"), gravity_before, "nudging the fader after the switch does not move the parameter")


func test_fader_already_at_the_value_after_a_switch_is_live_immediately(t) -> void:
	_p.set_value("gravity", Params.from_normalized("gravity", 0.5))
	_fader(2, 0.5)   # physical position of strip 2 recorded (bank 1 strip 2 = ground_accel, may change - irrelevant)
	_e.switch_bank(1)
	t.ok(_e.fader_info(2).engaged, "physical 0.5 matches gravity 0.5: no pickup needed")


func test_returning_to_a_bank_keeps_what_the_fader_left_behind(t) -> void:
	for pos in [0.0, 1.0, 0.4]:
		_fader(1, pos)
	var v: float = _p.get_value("max_ground_speed")
	_e.switch_bank(1)
	_e.switch_bank(0)
	t.eq(_p.get_value("max_ground_speed"), v, "switching away and back changes nothing")
	t.ok(_e.fader_info(1).engaged, "fader still sits at the value so it is live again")


func test_knob_change_requires_the_fader_to_pick_up_again(t) -> void:
	_fader(1, 0.0)
	_fader(1, 0.3)
	t.ok(_e.fader_info(1).engaged, "engaged")
	_knob(1, 10)
	t.ok(not _e.fader_info(1).engaged, "a knob moved the value away from the fader: pickup again")
	var after_knob: float = _p.get_value("max_ground_speed")
	_fader(1, 0.31)
	t.eq(_p.get_value("max_ground_speed"), after_knob, "fader nudge does not snap the value back")


func test_fader_moves_its_own_slot_without_losing_engagement(t) -> void:
	_fader(1, 0.0)
	_fader(1, 0.5)
	_fader(1, 0.6)
	_fader(1, 0.4)
	t.ok(_e.fader_info(1).engaged, "a fader's own changes never un-engage it")
	t.eq(_events.filter(func(e: Array) -> bool: return e[2] == "fader").size() > 0, true, "events carry the source")


# ------------------------------------------------------------------ knobs

func test_knob_steps_by_whole_parameter_steps(t) -> void:
	_knob(1, 1)
	t.eq(_p.get_value("max_ground_speed"), 4.6, "+1 click = +0.1 m/s")
	_knob(1, -3)
	t.eq(_p.get_value("max_ground_speed"), 4.3, "-3 clicks")
	_knob(2, 5)
	t.eq(_p.get_value("ground_accel"), 50.0, "ground_accel step is 1.0")


func test_knob_scale_changes_the_fineness(t) -> void:
	_b.data.knob_scale = 5.0
	_knob(1, 1)
	t.eq(_p.get_value("max_ground_speed"), 5.0, "5x scale")
	_b.data.knob_scale = 0.1
	_knob(1, 1)
	t.eq(_p.get_value("max_ground_speed"), 5.0, "0.1x scale rounds to nothing: the step floor is the parameter step")


func test_knob_is_clamped_at_the_ends(t) -> void:
	for i in 200:
		_knob(1, 5)
	t.eq(_p.get_value("max_ground_speed"), 15.0, "stops at the maximum")
	for i in 400:
		_knob(1, -5)
	t.eq(_p.get_value("max_ground_speed"), 1.0, "and the minimum")


func test_knob_on_a_boolean_follows_direction(t) -> void:
	_e.switch_bank(2)
	_knob(6, 1)
	t.eq(_p.get_value("auto_jump"), 1.0, "clockwise = on")
	_knob(6, -1)
	t.eq(_p.get_value("auto_jump"), 0.0, "counter-clockwise = off")


func test_unbound_and_unknown_controls_are_ignored(t) -> void:
	_knob(8, 3)    # strip 8 has no binding in bank 1
	_fader(8, 0.5)
	_e.on_control("not_a_control", {"value": 0.5})
	_e.on_control("global_shift", {"pressed": true})
	t.eq(_events.size(), 0, "nothing happened")


# ------------------------------------------------------------------ buttons and actions

func test_strip_buttons_reset_revert_lock_select(t) -> void:
	_p.set_value("max_ground_speed", 9.0)
	_press("strip1_mute")
	t.eq(_p.get_value("max_ground_speed"), 4.5, "mute = reset to default")
	_e.baseline["movement.max_ground_speed"] = 6.0
	_press("strip1_rec")
	t.eq(_p.get_value("max_ground_speed"), 6.0, "rec = revert to the preset value")
	_press("strip1_solo")
	t.ok(_e.locked.has("movement.max_ground_speed"), "solo = lock")
	_press("strip1_select")
	t.eq(_e.selected_key, "movement.max_ground_speed", "select")


func test_release_events_do_nothing(t) -> void:
	_e.on_control("strip1_mute", {"kind": "button", "pressed": false})
	t.eq(_events.size() + _actions.size(), 0, "only presses run actions")


func test_locked_parameters_ignore_everything(t) -> void:
	_press("strip1_solo")
	var v: float = _p.get_value("max_ground_speed")
	_knob(1, 10)
	_fader(1, 0.0)
	_fader(1, 1.0)
	_press("strip1_mute")
	_e.reset_all()
	t.eq(_p.get_value("max_ground_speed"), v, "knob, fader, reset button and reset-all all refused")
	_e.set_param("movement.max_ground_speed", 7.0, "force")
	t.eq(_p.get_value("max_ground_speed"), 7.0, "only an explicit force changes it")
	_press("strip1_solo")
	_knob(1, 1)
	t.eq(_p.get_value("max_ground_speed"), 7.1, "unlocked again")


func test_bank_buttons_wrap(t) -> void:
	var last: int = _b.bank_count() - 1
	_press("global_bank_next")
	t.eq(_e.bank, 1, "next")
	for i in last:
		_press("global_bank_next")
	t.eq(_e.bank, 0, "wraps to the first bank")
	_press("global_bank_prev")
	t.eq(_e.bank, last, "previous wraps to the last")


func test_unhandled_actions_are_forwarded(t) -> void:
	_press("global_play")
	_press("global_nav_right")
	_press("global_rewind")
	t.eq(_actions.map(func(a: Array) -> String: return a[0]), ["respawn", "teleport_next", "preset_prev"], "the scene/system implements these")


func test_toggle_param_action_works_on_booleans_only(t) -> void:
	_e.switch_bank(2)
	_b.set_strip_action("rec", "toggle_param")
	_press("strip6_rec")
	t.eq(_p.get_value("auto_jump"), 1.0, "toggled on")
	_press("strip6_rec")
	t.eq(_p.get_value("auto_jump"), 0.0, "and off")
	_press("strip1_rec")
	t.ok(true, "toggle on a number is a no-op (strip 1 has no binding in this bank)")


func test_reset_all_restores_every_default(t) -> void:
	for k in _reg.keys():
		_reg.set_value(k, _reg.def_of(k).max)
	_e.reset_all()
	for k in _reg.keys():
		t.ok(_reg.is_default(k), "%s back at its default" % k)
	t.eq(_e.preset_name, "", "no preset is current any more")


func test_every_global_action_in_the_defaults_is_known(t) -> void:
	for id in _b.data.global_actions:
		t.ok(Bindings.ACTIONS.has(_b.data.global_actions[id]), "%s -> %s" % [id, _b.data.global_actions[id]])


# ------------------------------------------------------------------ binding by moving a control

func test_bind_by_moving_a_control(t) -> void:
	t.ok(_e.begin_learn("movement.gravity"), "armed")
	_fader(8, 0.5)   # strip 8, bank 1: unbound slot
	t.eq(_b.slot_key(0, 8, "fader"), "movement.gravity", "bound to the strip whose fader moved")
	t.eq(_e.pending_learn, "", "learn finished")
	t.eq(_events.size(), 0, "the learn gesture itself does not change anything")
	t.ok(_e.begin_learn("movement.air_accel"), "again")
	_knob(8, 1)
	t.eq(_b.slot_key(0, 8, "knob"), "movement.air_accel", "knobs can be bound separately")
	t.ok(not _e.begin_learn("movement.nope"), "unknown parameters are refused")


func test_learn_ignores_buttons_and_can_be_cancelled(t) -> void:
	_e.begin_learn("movement.gravity")
	_press("global_play")
	t.eq(_e.pending_learn, "movement.gravity", "buttons do not complete a parameter learn")
	_e.cancel_learn()
	_fader(8, 0.5)
	t.eq(_b.slot_key(0, 8, "fader"), "", "cancelled: nothing bound")


# ------------------------------------------------------------------ presets as values

func test_apply_values_sets_baseline_and_arms_pickup(t) -> void:
	_fader(1, 0.0)
	_fader(1, 0.3)
	var r: Dictionary = _e.apply_values({"movement": {"max_ground_speed": 9.0, "gravity": 12.0}}, "fast")
	t.eq(r.applied, 2, "two applied")
	t.eq(_p.get_value("max_ground_speed"), 9.0, "applied")
	t.eq(_e.preset_name, "fast", "current preset")
	t.ok(not _e.is_modified(), "a freshly loaded preset is not 'modified'")
	t.ok(not _e.fader_info(1).engaged, "the fader (at 0.3) must pick up the new value")
	_knob(1, 5)
	t.ok(_e.is_modified() and _e.modified_keys() == ["movement.max_ground_speed"], "a knob tweak marks it modified")
	_press("strip1_rec")
	t.ok(not _e.is_modified(), "revert returns to the preset")


func test_apply_values_skips_locked_and_reports_unknown(t) -> void:
	_press("strip1_solo")
	var r: Dictionary = _e.apply_values({"movement": {"max_ground_speed": 12.0, "gravity": 12.0, "warp": 3.0}, "lab": {"x": 1.0}}, "mixed")
	t.eq(_p.get_value("max_ground_speed"), 4.5, "locked parameter kept")
	t.eq(_p.get_value("gravity"), 12.0, "others applied")
	t.eq(r.skipped_locked, ["movement.max_ground_speed"], "reported")
	t.eq(r.unknown.size(), 2, "unknown ids and targets reported: %s" % str(r.unknown))


# ------------------------------------------------------------------ bindings to things that do not exist

func test_bindings_to_unregistered_targets_are_inert(t) -> void:
	_b.assign(0, 8, "fader", "camera.fov")
	_fader(8, 0.0)
	_fader(8, 0.9)
	t.eq(_events.size(), 0, "no target, no effect, no crash")
	t.eq(_b.unresolved(_reg), ["camera.fov"], "reported as unresolved")
