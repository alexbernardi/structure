## Logical controls of the SMC-Mixer (what the lab can map). Identifiers are lab-internal names, never MIDI numbers.
## Layout source: AGENT-WORKSHOP/DOCUMENTATION/SMC-MIXER-HARDWARE.md (official photo + manual).
extends RefCounted

const KNOB := "knob"
const FADER := "fader"
const BUTTON := "button"

const STRIPS := 8
const STRIP_BUTTONS := [["mute", "M"], ["solo", "S"], ["rec", "R"], ["select", "Select"]]
## Left to right as printed on the unit.
const GLOBAL_BUTTONS := [
	["play", "Play"], ["stop", "Stop"], ["record", "Record"], ["rewind", "Rewind"], ["forward", "Fast fwd"],
	["bank_prev", "Prev 8 tracks"], ["bank_next", "Next 8 tracks"],
	["nav_up", "Up"], ["nav_down", "Down"], ["nav_left", "Left"], ["nav_right", "Right"],
]
## Firmware-handled keys; mapping them is optional (they may not emit MIDI).
const OPTIONAL_BUTTONS := [["shift", "Shift"], ["bt", "BT"]]

static var _cache: Array[Dictionary] = []


## Ordered list: per strip knob, fader, M, S, R, select; then the global row; then optional keys.
static func all() -> Array[Dictionary]:
	if not _cache.is_empty():
		return _cache
	for s in range(1, STRIPS + 1):
		_cache.append({"id": "strip%d_knob" % s, "label": "Strip %d knob" % s, "kind": KNOB, "strip": s, "optional": false})
		_cache.append({"id": "strip%d_fader" % s, "label": "Strip %d fader" % s, "kind": FADER, "strip": s, "optional": false})
		for b in STRIP_BUTTONS:
			_cache.append({"id": "strip%d_%s" % [s, b[0]], "label": "Strip %d %s" % [s, b[1]], "kind": BUTTON, "strip": s, "optional": false})
	for b in GLOBAL_BUTTONS:
		_cache.append({"id": "global_%s" % b[0], "label": b[1], "kind": BUTTON, "strip": 0, "optional": false})
	for b in OPTIONAL_BUTTONS:
		_cache.append({"id": "global_%s" % b[0], "label": b[1], "kind": BUTTON, "strip": 0, "optional": true})
	return _cache


static func ids() -> Array[String]:
	var out: Array[String] = []
	for c in all():
		out.append(c.id)
	return out


static func required_ids() -> Array[String]:
	var out: Array[String] = []
	for c in all():
		if not c.optional:
			out.append(c.id)
	return out


static func has(id: String) -> bool:
	return ids().has(id)


static func get_control(id: String) -> Dictionary:
	for c in all():
		if c.id == id:
			return c
	return {}


static func kind_of(id: String) -> String:
	return String(get_control(id).get("kind", ""))
