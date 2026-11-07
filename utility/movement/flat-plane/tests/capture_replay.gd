## Test helper: replays the real SMC-Mixer capture (tests/fixtures/smc_mixer_daw_capture.json).
extends RefCounted

const Events = preload("res://midi/midi_events.gd")
const PATH := "res://tests/fixtures/smc_mixer_daw_capture.json"


static func load_capture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


## Columns: device, message, channel, pitch, velocity, controller_number, controller_value, t_usec.
static func input_events(device := -1) -> Array[InputEventMIDI]:
	var out: Array[InputEventMIDI] = []
	for row in load_capture().events:
		if device >= 0 and int(row[0]) != device:
			continue
		var e := InputEventMIDI.new()
		e.device = int(row[0])
		e.message = int(row[1])
		e.channel = int(row[2])
		e.pitch = int(row[3])
		e.velocity = int(row[4])
		e.controller_number = int(row[5])
		e.controller_value = int(row[6])
		out.append(e)
	return out


## Normalised events of one port.
static func events(device := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in input_events(device):
		out.append(Events.from_input_event(e))
	return out


## Raw values of every event with the given signature on one port.
static func values_of(sig: String, device := 0) -> Array[int]:
	var out: Array[int] = []
	for ev in events(device):
		if ev.sig == sig:
			out.append(int(ev.value))
	return out
