## Normalises raw MIDI into plain dictionaries and builds synthetic events for tests and replay.
## Pure functions: no nodes, no engine state besides the InputEventMIDI type.
extends RefCounted

const KIND_CC := "cc"
const KIND_NOTE := "note"
const KIND_PITCH_BEND := "pb"
const KIND_PRESSURE := "pressure"
const KIND_AFTERTOUCH := "aftertouch"
const KIND_PROGRAM := "program"

## Value domain (inclusive) per kind, used for normalisation.
const DOMAIN_MAX := {KIND_CC: 127, KIND_NOTE: 127, KIND_PITCH_BEND: 16383, KIND_PRESSURE: 127, KIND_AFTERTOUCH: 127, KIND_PROGRAM: 127}


## Signature of the control a message belongs to: "<kind>:<channel 0-15>:<number>".
## Pitch bend and channel pressure carry no number (always 0). Note On and Note Off share a signature.
static func signature(kind: String, channel: int, number: int) -> String:
	return "%s:%d:%d" % [kind, channel, number]


## Returns {} for messages the lab ignores (system realtime, SysEx, ...).
static func from_input_event(e: InputEventMIDI) -> Dictionary:
	var kind := ""
	var number := 0
	var value := 0
	var pressed := false
	var released := false
	match e.message:
		MIDI_MESSAGE_NOTE_ON:
			kind = KIND_NOTE
			number = e.pitch
			value = e.velocity
			pressed = e.velocity > 0
			released = e.velocity == 0
		MIDI_MESSAGE_NOTE_OFF:
			kind = KIND_NOTE
			number = e.pitch
			value = e.velocity
			released = true
		MIDI_MESSAGE_CONTROL_CHANGE:
			kind = KIND_CC
			number = e.controller_number
			value = e.controller_value
			pressed = value > 0
			released = value == 0
		MIDI_MESSAGE_PITCH_BEND:
			kind = KIND_PITCH_BEND
			value = e.pitch
		MIDI_MESSAGE_CHANNEL_PRESSURE:
			kind = KIND_PRESSURE
			value = e.pressure
		MIDI_MESSAGE_AFTERTOUCH:
			kind = KIND_AFTERTOUCH
			number = e.pitch
			value = e.pressure
		MIDI_MESSAGE_PROGRAM_CHANGE:
			kind = KIND_PROGRAM
			value = e.instrument
		_:
			return {}
	return {
		"kind": kind, "channel": e.channel, "number": number, "value": value,
		"pressed": pressed, "released": released, "device": e.device,
		"sig": signature(kind, e.channel, number), "usec": Time.get_ticks_usec(),
	}


## Builds a synthetic event for tests/replay. `value` means: velocity (note), controller value (cc),
## 14-bit bend (pb), pressure (pressure/aftertouch), program (program). `note_off` selects Note Off for notes.
static func make_input_event(kind: String, channel: int, number: int, value: int, device := 0, note_off := false) -> InputEventMIDI:
	var e := InputEventMIDI.new()
	e.channel = channel
	e.device = device
	match kind:
		KIND_NOTE:
			e.message = MIDI_MESSAGE_NOTE_OFF if note_off else MIDI_MESSAGE_NOTE_ON
			e.pitch = number
			e.velocity = value
		KIND_CC:
			e.message = MIDI_MESSAGE_CONTROL_CHANGE
			e.controller_number = number
			e.controller_value = value
		KIND_PITCH_BEND:
			e.message = MIDI_MESSAGE_PITCH_BEND
			e.pitch = value
		KIND_PRESSURE:
			e.message = MIDI_MESSAGE_CHANNEL_PRESSURE
			e.pressure = value
		KIND_AFTERTOUCH:
			e.message = MIDI_MESSAGE_AFTERTOUCH
			e.pitch = number
			e.pressure = value
		KIND_PROGRAM:
			e.message = MIDI_MESSAGE_PROGRAM_CHANGE
			e.instrument = value
	return e


## One-line human description, e.g. "CC  ch1 #16 = 65".
static func describe(ev: Dictionary) -> String:
	var ch: int = int(ev.channel) + 1
	match ev.kind:
		KIND_NOTE:
			return "NOTE %s ch%d #%d vel %d" % ["on " if ev.pressed else "off", ch, ev.number, ev.value]
		KIND_CC:
			return "CC       ch%d #%d = %d" % [ch, ev.number, ev.value]
		KIND_PITCH_BEND:
			return "PITCH    ch%d = %d" % [ch, ev.value]
		KIND_PRESSURE:
			return "PRESSURE ch%d = %d" % [ch, ev.value]
		KIND_AFTERTOUCH:
			return "POLYAT   ch%d #%d = %d" % [ch, ev.number, ev.value]
		KIND_PROGRAM:
			return "PROGRAM  ch%d = %d" % [ch, ev.value]
	return str(ev)
