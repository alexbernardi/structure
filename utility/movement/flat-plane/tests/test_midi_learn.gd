extends RefCounted

const Learn = preload("res://midi/midi_learn.gd")
const Events = preload("res://midi/midi_events.gd")
const B = preload("res://midi/control_behavior.gd")
const Replay = preload("res://tests/capture_replay.gd")

var _l


func before_each() -> void:
	_l = Learn.new()


func _ev(kind: String, ch: int, num: int, val: int, off := false) -> Dictionary:
	return Events.from_input_event(Events.make_input_event(kind, ch, num, val, 0, off))


## Feeds a real-capture event list into the learner.
func _feed_all(events: Array) -> void:
	for ev in events:
		_l.feed(ev)


func _settle(seconds := 1.0) -> void:
	_l.tick(seconds)


func test_button_momentary_from_real_capture(t) -> void:
	_l.start("strip1_mute")
	for ev in Replay.events(0):
		if ev.sig == "note:0:16":
			_l.feed(ev)
	t.ok(_l.state == Learn.State.DONE, "mute button learned")
	t.eq(_l.status().mapping, {"sig": "note:0:16", "behavior": "momentary"}, "momentary note 16")


func test_button_trigger_when_no_release(t) -> void:
	_l.start("global_play")
	_l.feed(_ev("cc", 0, 20, 127))
	t.ok(_l.state == Learn.State.WAIT_RELEASE, "waiting for a release")
	_settle(1.0)
	t.ok(_l.state == Learn.State.WAIT_RELEASE, "a button held for a second is still waiting (it is not a trigger yet)")
	_settle(2.0)
	t.eq(_l.status().mapping, {"sig": "cc:0:20", "behavior": "trigger"}, "no release for 3 s -> trigger")


func test_button_held_a_while_is_still_momentary(t) -> void:
	_l.start("strip1_mute")
	_l.feed(_ev("note", 0, 16, 127))
	_settle(2.0)
	_l.feed(_ev("note", 0, 16, 0, true))
	t.eq(_l.status().mapping.behavior, "momentary", "held 2 s then released")


func test_button_ignores_analog_noise_until_a_press(t) -> void:
	_l.start("global_stop")
	_l.feed(_ev("pb", 0, 0, 5000))
	_l.feed(_ev("note", 0, 93, 0, true))
	t.ok(_l.state == Learn.State.LISTEN, "pitch bend and a stray release do not lock")
	_l.feed(_ev("note", 0, 93, 127))
	_l.feed(_ev("note", 0, 93, 0, true))
	t.eq(_l.status().mapping.sig, "note:0:93", "then the press locks")


func test_fader_absolute_from_real_capture(t) -> void:
	_l.start("strip1_fader")
	_feed_all(Replay.events(0).filter(func(ev: Dictionary) -> bool: return ev.sig == "pb:0:0"))
	_settle()
	var m: Dictionary = _l.status().mapping
	t.ok(_l.state == Learn.State.DONE, "learned after the user stops moving")
	t.eq([m.sig, m.behavior, m.raw_min, m.raw_max], ["pb:0:0", "absolute", 0, 16256], "full-travel range recorded")


func test_partial_sweep_falls_back_to_the_effective_domain(t) -> void:
	_l.start("strip2_fader")
	for v in range(2048, 6144, 128):
		_l.feed(_ev("pb", 1, 0, v))
	_settle()
	var m: Dictionary = _l.status().mapping
	t.eq([m.raw_min, m.raw_max], [0, 16256], "short sweep must not shrink the range; 7-bit quantisation is detected")


func test_full_resolution_pitch_bend_keeps_the_14_bit_range(t) -> void:
	_l.start("strip2_fader")
	for v in [3, 801, 1590, 2407, 3333, 4201, 5009, 5977, 6841, 7703, 8555, 9421, 10333, 11011, 12007, 13001, 14013, 15101, 16009, 16383]:
		_l.feed(_ev("pb", 1, 0, v))
	_settle()
	var m: Dictionary = _l.status().mapping
	t.eq([m.raw_min, m.raw_max], [3, 16383], "odd values -> no quantisation, observed full sweep used")


func test_knob_relative_two_stage_from_real_capture(t) -> void:
	_l.start("strip1_knob")
	var all_vals := Replay.events(0).filter(func(ev: Dictionary) -> bool: return ev.sig == "cc:0:16")
	var sixtyfives := all_vals.filter(func(ev: Dictionary) -> bool: return ev.value == 65)
	var ones := all_vals.filter(func(ev: Dictionary) -> bool: return ev.value == 1)
	_feed_all(sixtyfives)   # first direction as the user turned it in the capture
	_settle()
	t.ok(_l.state == Learn.State.NEED_REVERSE, "relative detected, asks for the other direction")
	_feed_all(ones)
	_settle()
	var m: Dictionary = _l.status().mapping
	t.ok(_l.state == Learn.State.DONE, "learned")
	t.eq([m.behavior, m.encoding, m.invert], ["relative", "sign_magnitude", true], "first direction sent 65 so it is inverted")
	t.eq(B.decode_relative(65, m), 1, "decoded as clockwise")
	t.eq(B.decode_relative(1, m), -1, "decoded as counter-clockwise")


func test_knob_absolute_in_user_mode_is_one_stage(t) -> void:
	_l.start("strip3_knob")
	for v in range(0, 128, 4):
		_l.feed(_ev("cc", 2, 18, v))
	_settle()
	var m: Dictionary = _l.status().mapping
	t.eq([m.behavior, m.sig, m.raw_min, m.raw_max], ["absolute", "cc:2:18", 0, 124], "absolute knob learned in one gesture")


func test_relative_reverse_with_same_values_is_rejected_then_retry(t) -> void:
	_l.start("strip4_knob")
	for i in 6:
		_l.feed(_ev("cc", 3, 19, 1))
	_settle()
	t.ok(_l.state == Learn.State.NEED_REVERSE, "asks for the other direction")
	for i in 4:
		_l.feed(_ev("cc", 3, 19, 1))   # user turned the same way again
	_settle()
	t.ok(_l.state == Learn.State.NEED_REVERSE, "stays in the reverse stage")
	t.ok(_l.prompt.contains("same value"), "explains why: %s" % _l.prompt)
	for i in 4:
		_l.feed(_ev("cc", 3, 19, 65))
	_settle()
	t.ok(_l.state == Learn.State.DONE, "retry succeeds")


func test_reverse_turn_right_after_the_prompt_is_not_ignored(t) -> void:
	_l.start("strip4_knob")
	for i in 6:
		_l.feed(_ev("cc", 3, 19, 1))
	_settle(0.7)   # the user stopped, so the prompt for the other direction appears
	_l.feed(_ev("cc", 3, 19, 65))   # and they turn back at once
	t.ok(_l.state == Learn.State.COLLECT_REVERSE, "collected immediately")


func test_other_signatures_are_ignored_while_collecting(t) -> void:
	_l.start("strip5_fader")
	_l.feed(_ev("pb", 4, 0, 1000))
	for v in range(1128, 9000, 256):
		_l.feed(_ev("pb", 4, 0, v))
		_l.feed(_ev("pb", 5, 0, 99))   # neighbour fader moving
	_settle()
	t.eq(_l.status().mapping.sig, "pb:4:0", "locked onto the first signature")


func test_too_few_messages_keeps_waiting(t) -> void:
	_l.start("strip6_fader")
	_l.feed(_ev("pb", 5, 0, 100))
	_l.feed(_ev("pb", 5, 0, 5000))
	_settle()
	t.ok(_l.state == Learn.State.COLLECT, "still collecting")
	t.ok(_l.prompt.contains("keep moving"), "tells the user")


func test_cancel_and_unknown_control(t) -> void:
	t.ok(not _l.start("strip9_knob"), "unknown id rejected")
	_l.start("strip1_knob")
	_l.cancel()
	t.ok(not _l.is_active(), "cancelled")
