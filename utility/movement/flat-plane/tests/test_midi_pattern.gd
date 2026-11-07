extends RefCounted

const Pattern = preload("res://midi/midi_pattern.gd")
const Config = preload("res://midi/midi_config.gd")


## The Mackie layout observed on the real unit for strips 1-3 (checkpoint 2).
func _mackie_config(strips := [1, 2, 3]):
	var c := Config.new()
	for n in strips:
		c.set_mapping("strip%d_knob" % n, {"sig": "cc:0:%d" % (15 + n), "behavior": "relative", "encoding": "sign_magnitude", "invert": false})
		c.set_mapping("strip%d_fader" % n, {"sig": "pb:%d:0" % (n - 1), "behavior": "absolute", "raw_min": 0, "raw_max": 16256, "invert": false})
		c.set_mapping("strip%d_rec" % n, {"sig": "note:0:%d" % (n - 1), "behavior": "momentary"})
		c.set_mapping("strip%d_solo" % n, {"sig": "note:0:%d" % (7 + n), "behavior": "momentary"})
		c.set_mapping("strip%d_mute" % n, {"sig": "note:0:%d" % (15 + n), "behavior": "momentary"})
		c.set_mapping("strip%d_select" % n, {"sig": "note:0:%d" % (23 + n), "behavior": "momentary"})
	return c


func _sigs(proposals: Array) -> Dictionary:
	var out := {}
	for p in proposals:
		out[p.control_id] = p.mapping.sig
	return out


func test_mackie_pattern_fills_strips_4_to_8(t) -> void:
	var c = _mackie_config()
	var props := Pattern.propose(c)
	t.eq(props.size(), 30, "5 strips x 6 controls")
	var s := _sigs(props)
	t.eq(s.strip4_knob, "cc:0:19", "knob CC advances by one")
	t.eq(s.strip8_knob, "cc:0:23", "to strip 8")
	t.eq(s.strip4_fader, "pb:3:0", "fader MIDI channel advances")
	t.eq(s.strip8_fader, "pb:7:0", "to channel 8")
	t.eq(s.strip5_rec, "note:0:4", "rec = note 0..7")
	t.eq(s.strip5_solo, "note:0:12", "solo = note 8..15")
	t.eq(s.strip5_mute, "note:0:20", "mute = note 16..23")
	t.eq(s.strip8_select, "note:0:31", "select = note 24..31")


func test_proposals_copy_the_learned_behaviour_and_are_flagged(t) -> void:
	var c = _mackie_config()
	var by_id := {}
	for p in Pattern.propose(c):
		by_id[p.control_id] = p.mapping
	t.eq(by_id.strip6_fader.raw_max, 16256, "range copied")
	t.eq(by_id.strip6_knob.encoding, "sign_magnitude", "encoding copied")
	t.eq(by_id.strip6_mute.behavior, "momentary", "button behaviour copied")
	t.ok(by_id.strip6_mute.inferred, "flagged as inferred")


func test_apply_stores_and_leaves_them_unverified(t) -> void:
	var c = _mackie_config()
	t.eq(Pattern.apply(c, Pattern.propose(c)), 30, "applied")
	t.ok(c.is_mapped("strip8_knob") and c.is_inferred("strip8_knob"), "mapped but inferred")
	t.ok(not c.is_verified("strip8_knob"), "not verified")
	t.eq(Config.validate(c.data), [], "still a valid config")
	c.mark_verified("strip8_knob")
	t.ok(c.is_verified("strip8_knob") and not c.is_inferred("strip8_knob"), "a real actuation verifies it and drops the flag")
	t.eq(Pattern.propose(c).size(), 0, "nothing left to propose")


func test_needs_two_strips(t) -> void:
	t.eq(Pattern.propose(_mackie_config([1])).size(), 0, "one strip is not a pattern")
	t.eq(Pattern.propose(Config.new()).size(), 0, "nothing mapped")


func test_non_adjacent_strips_work(t) -> void:
	var c = _mackie_config([2, 5])
	var s := _sigs(Pattern.propose(c))
	t.eq(s.strip1_knob, "cc:0:16", "extrapolates backwards")
	t.eq(s.strip8_knob, "cc:0:23", "and forwards")
	t.eq(s.strip3_fader, "pb:2:0", "faders too")


func test_inconsistent_step_is_not_extrapolated(t) -> void:
	var c = _mackie_config([1, 2])
	c.set_mapping("strip3_knob", {"sig": "cc:0:20", "behavior": "relative", "encoding": "sign_magnitude", "invert": false})
	var s := _sigs(Pattern.propose(c))
	t.ok(not s.has("strip4_knob"), "CC 16, 17, 20 is not a constant step")
	t.ok(s.has("strip3_fader"), "other controls with a clean pattern still are")


func test_different_behaviour_blocks_inference(t) -> void:
	var c = _mackie_config([1, 2])
	c.mappings()["strip2_mute"].behavior = "trigger"
	var s := _sigs(Pattern.propose(c))
	t.ok(not s.has("strip3_mute"), "momentary vs trigger: not the same kind of button")
	var c2 = _mackie_config([1, 2])
	c2.mappings()["strip2_knob"].invert = true
	t.ok(not _sigs(Pattern.propose(c2)).has("strip3_knob"), "a different invert flag blocks it too")


func test_out_of_range_extrapolation_is_skipped(t) -> void:
	var c := Config.new()
	c.set_mapping("strip1_fader", {"sig": "pb:13:0", "behavior": "absolute", "raw_min": 0, "raw_max": 16256, "invert": false})
	c.set_mapping("strip2_fader", {"sig": "pb:14:0", "behavior": "absolute", "raw_min": 0, "raw_max": 16256, "invert": false})
	var s := _sigs(Pattern.propose(c))
	t.ok(s.has("strip3_fader") and s.strip3_fader == "pb:15:0", "channel 16 is the last valid one")
	t.ok(not s.has("strip4_fader"), "channel 17 does not exist")


func test_signatures_already_in_use_are_not_stolen(t) -> void:
	var c = _mackie_config([1, 2])
	c.set_mapping("global_play", {"sig": "note:0:18", "behavior": "momentary"})  # would be strip3 mute
	var s := _sigs(Pattern.propose(c))
	t.ok(not s.has("strip3_mute"), "taken by another control")
	t.ok(s.has("strip4_mute") and s.strip4_mute == "note:0:19", "the rest of the pattern continues")
