## Extends a partial mapping to the remaining strips when the mapped strips follow a regular pattern
## (e.g. Mackie Control: knob CC 16+n, fader = pitch bend on channel n, buttons = notes base+n).
## Proposals are only made when >= 2 strips agree on one constant step, and they stay flagged "inferred"
## (unverified) until the real control is actuated.
extends RefCounted

const Catalog = preload("res://midi/control_catalog.gd")
const Events = preload("res://midi/midi_events.gd")

const STRIP_PARTS := ["knob", "fader", "mute", "solo", "rec", "select"]
## Mapping fields that must be identical across strips (everything but the signature).
const IGNORED_FIELDS := ["sig", "inferred"]


## Returns [{control_id, mapping, basis}] for unmapped strip controls. Pure: does not change `config`.
static func propose(config) -> Array:
	var out := []
	var taken := {}
	for id in config.mappings():
		taken[config.mappings()[id].sig] = true
	for part in STRIP_PARTS:
		var known := []   # [{strip, kind, channel, number, mapping}]
		for s in range(1, Catalog.STRIPS + 1):
			var id := "strip%d_%s" % [s, part]
			if config.is_mapped(id):
				var m: Dictionary = config.mapping_of(id)
				var p := _parse(m.sig)
				known.append({"strip": s, "kind": p[0], "channel": p[1], "number": p[2], "mapping": m, "id": id})
		if known.size() < 2:
			continue
		var step := _constant_step(known)
		if step.is_empty():
			continue
		var base: Dictionary = known[0]
		for s in range(1, Catalog.STRIPS + 1):
			var id := "strip%d_%s" % [s, part]
			if config.is_mapped(id):
				continue
			var ch: int = base.channel + step.channel * (s - base.strip)
			var num: int = base.number + step.number * (s - base.strip)
			if ch < 0 or ch > 15 or num < 0 or num > 127:
				continue
			var sig := Events.signature(base.kind, ch, num)
			if taken.has(sig):
				continue
			var mapping: Dictionary = (base.mapping as Dictionary).duplicate(true)
			mapping.sig = sig
			mapping.inferred = true
			taken[sig] = true
			out.append({"control_id": id, "mapping": mapping, "basis": known.map(func(k: Dictionary) -> String: return k.id)})
	return out


## Applies proposals through the config (signature ownership rules still hold). Returns the number applied.
static func apply(config, proposals: Array) -> int:
	var n := 0
	for p in proposals:
		config.set_mapping(p.control_id, p.mapping)
		n += 1
	return n


static func _parse(sig: String) -> Array:
	var parts := sig.split(":")
	return [parts[0], int(parts[1]), int(parts[2])]


## {channel, number} step per strip if every mapped strip agrees, else {}.
static func _constant_step(known: Array) -> Dictionary:
	var first: Dictionary = known[0]
	for k in known:
		if k.kind != first.kind or not _same_fields(k.mapping, first.mapping):
			return {}
	var step := {}
	for i in range(1, known.size()):
		var dn: int = known[i].strip - first.strip
		var dch: int = known[i].channel - first.channel
		var dnum: int = known[i].number - first.number
		if dch % dn != 0 or dnum % dn != 0:
			return {}
		var s := {"channel": dch / dn, "number": dnum / dn}
		if s.channel == 0 and s.number == 0:
			return {}
		if not step.is_empty() and step != s:
			return {}
		step = s
	return step


static func _same_fields(a: Dictionary, b: Dictionary) -> bool:
	for key in a:
		if not IGNORED_FIELDS.has(key) and a[key] != b.get(key):
			return false
	for key in b:
		if not IGNORED_FIELDS.has(key) and not a.has(key):
			return false
	return true
