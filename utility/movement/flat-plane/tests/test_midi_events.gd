extends RefCounted

const Events = preload("res://midi/midi_events.gd")
const Catalog = preload("res://midi/control_catalog.gd")
const Replay = preload("res://tests/capture_replay.gd")


func test_signature_and_note_on_off(t) -> void:
	var on := Events.from_input_event(Events.make_input_event(Events.KIND_NOTE, 2, 16, 127))
	t.eq(on.sig, "note:2:16", "note signature")
	var off := Events.from_input_event(Events.make_input_event(Events.KIND_NOTE, 2, 16, 0, 0, true))
	t.eq(off.sig, "note:2:16", "note off shares it")


func test_note_press_release_semantics(t) -> void:
	var on := Events.from_input_event(Events.make_input_event(Events.KIND_NOTE, 0, 94, 127))
	t.ok(on.pressed and not on.released, "note on vel 127 is a press")
	var on0 := Events.from_input_event(Events.make_input_event(Events.KIND_NOTE, 0, 94, 0))
	t.ok(on0.released and not on0.pressed, "note on with velocity 0 is a release")
	var off := Events.from_input_event(Events.make_input_event(Events.KIND_NOTE, 0, 94, 0, 0, true))
	t.ok(off.released and not off.pressed, "note off is a release")
	t.eq(on.sig, off.sig, "on and off share a signature")


func test_cc_pitch_bend_pressure(t) -> void:
	var cc := Events.from_input_event(Events.make_input_event(Events.KIND_CC, 3, 16, 65))
	t.eq([cc.kind, cc.channel, cc.number, cc.value], ["cc", 3, 16, 65], "cc fields")
	var pb := Events.from_input_event(Events.make_input_event(Events.KIND_PITCH_BEND, 1, 0, 12800))
	t.eq([pb.sig, pb.value], ["pb:1:0", 12800], "pitch bend has no number")
	var pr := Events.from_input_event(Events.make_input_event(Events.KIND_PRESSURE, 0, 0, 44))
	t.eq([pr.sig, pr.value], ["pressure:0:0", 44], "channel pressure")


func test_unsupported_messages_are_ignored(t) -> void:
	var e := InputEventMIDI.new()
	e.message = MIDI_MESSAGE_TIMING_CLOCK
	t.ok(Events.from_input_event(e).is_empty(), "timing clock ignored")
	e.message = MIDI_MESSAGE_SYSTEM_EXCLUSIVE
	t.ok(Events.from_input_event(e).is_empty(), "sysex ignored")


func test_real_capture_decodes_to_known_signatures(t) -> void:
	var sigs := {}
	for ev in Replay.events(0):
		sigs[ev.sig] = int(sigs.get(ev.sig, 0)) + 1
	t.eq(sigs.keys().size(), 4, "fader, knob, mute button, play button")
	for s in ["pb:0:0", "cc:0:16", "note:0:16", "note:0:94"]:
		t.ok(sigs.has(s), "capture contains %s" % s)


func test_catalog_matches_the_hardware(t) -> void:
	var counts := {Catalog.BUTTON: 0, Catalog.KNOB: 0, Catalog.FADER: 0}
	var optional := 0
	var seen := {}
	for c in Catalog.all():
		t.ok(not seen.has(c.id), "unique id %s" % c.id)
		seen[c.id] = true
		if c.optional:
			optional += 1
		else:
			counts[c.kind] += 1
	t.eq(counts[Catalog.BUTTON], 43, "43 buttons (manufacturer spec)")
	t.eq(counts[Catalog.KNOB], 8, "8 knobs")
	t.eq(counts[Catalog.FADER], 8, "8 faders")
	t.eq(optional, 2, "BT and SHIFT are optional")
	t.eq(Catalog.required_ids().size(), 59, "59 required controls")
