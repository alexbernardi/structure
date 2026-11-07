## Saved, editable MIDI configuration: named profiles of control mappings. JSON on disk (hand-editable).
## Nothing here knows about gameplay: a mapping only says "this MIDI signature is that physical control".
extends RefCounted

const Catalog = preload("res://midi/control_catalog.gd")
const Behavior = preload("res://midi/control_behavior.gd")
const Events = preload("res://midi/midi_events.gd")

const SCHEMA := 1
const DEFAULT_PATH := "res://config/midi_mapping.json"
const BUTTON_BEHAVIORS := ["momentary", "trigger"]

var data: Dictionary = default_data()
var _index: Dictionary = {}  # sig -> control id for the active profile; rebuilt on demand


static func default_data() -> Dictionary:
	return {
		"schema": SCHEMA,
		"device_hint": "SMC-Mixer",
		"ports": "auto",
		"active_profile": "daw",
		"profiles": {"daw": {"label": "DAW mode (Mackie)", "mappings": {}, "verified": {}}},
	}


func profile_names() -> Array:
	return data.profiles.keys()


func active_profile_name() -> String:
	return data.active_profile


func set_active_profile(name: String, create := false) -> bool:
	if not data.profiles.has(name):
		if not create:
			return false
		data.profiles[name] = {"label": name, "mappings": {}, "verified": {}}
	data.active_profile = name
	_index.clear()
	return true


func profile() -> Dictionary:
	return data.profiles[data.active_profile]


func mappings() -> Dictionary:
	return profile().mappings


func mapping_of(control_id: String) -> Dictionary:
	return mappings().get(control_id, {})


func is_mapped(control_id: String) -> bool:
	return mappings().has(control_id)


func is_verified(control_id: String) -> bool:
	return profile().verified.has(control_id)


func mark_verified(control_id: String) -> void:
	if is_mapped(control_id) and not is_verified(control_id):
		profile().verified[control_id] = Time.get_datetime_string_from_system(true)
		mappings()[control_id].erase("inferred")


func is_inferred(control_id: String) -> bool:
	return mapping_of(control_id).get("inferred", false)


func find_by_sig(sig: String) -> String:
	if _index.is_empty() and not mappings().is_empty():
		for id in mappings():
			_index[mappings()[id].sig] = id
	return _index.get(sig, "")


## Stores a mapping. A signature belongs to one control: if another control used it, that mapping is
## removed and its id is returned (else ""). Re-mapping a control clears its verification.
func set_mapping(control_id: String, entry: Dictionary) -> String:
	var previous := ""
	for id in mappings().keys():
		if id != control_id and mappings()[id].sig == entry.sig:
			previous = id
			clear_mapping(id)
	mappings()[control_id] = entry
	profile().verified.erase(control_id)
	_index.clear()
	return previous


func clear_mapping(control_id: String) -> void:
	mappings().erase(control_id)
	profile().verified.erase(control_id)
	_index.clear()


func clear_all() -> void:
	profile().mappings = {}
	profile().verified = {}
	_index.clear()


func unmapped_ids(include_optional := false) -> Array[String]:
	var out: Array[String] = []
	for c in Catalog.all():
		if c.optional and not include_optional:
			continue
		if not is_mapped(c.id):
			out.append(c.id)
	return out


## Returns a list of problems (empty = valid). Never throws; used on load, save and by tests.
static func validate(d: Variant) -> Array[String]:
	var problems: Array[String] = []
	if typeof(d) != TYPE_DICTIONARY:
		return ["top level must be an object"]
	if int(d.get("schema", -1)) != SCHEMA:
		problems.append("unsupported schema %s (expected %d)" % [str(d.get("schema")), SCHEMA])
		return problems
	var ports: Variant = d.get("ports", "auto")
	if not (ports is Array or (ports is String and (ports == "auto" or ports == "all"))):
		problems.append("ports must be \"auto\", \"all\" or a list of port names")
	if typeof(d.get("profiles")) != TYPE_DICTIONARY or d.profiles.is_empty():
		problems.append("profiles must be a non-empty object")
		return problems
	if not d.profiles.has(d.get("active_profile", "")):
		problems.append("active_profile '%s' does not exist" % str(d.get("active_profile")))
	for pname in d.profiles:
		var p: Variant = d.profiles[pname]
		if typeof(p) != TYPE_DICTIONARY or typeof(p.get("mappings")) != TYPE_DICTIONARY:
			problems.append("profile '%s' needs a mappings object" % pname)
			continue
		var used := {}
		for id in p.mappings:
			for e in _validate_entry(String(id), p.mappings[id]):
				problems.append("%s/%s: %s" % [pname, id, e])
			var entry: Variant = p.mappings[id]
			if typeof(entry) == TYPE_DICTIONARY and entry.has("sig"):
				if used.has(entry.sig):
					problems.append("%s: signature %s used by both %s and %s" % [pname, entry.sig, used[entry.sig], id])
				used[entry.sig] = id
		if typeof(p.get("verified", {})) != TYPE_DICTIONARY:
			problems.append("profile '%s': verified must be an object" % pname)
	return problems


static func _validate_entry(id: String, e: Variant) -> Array[String]:
	var p: Array[String] = []
	if not Catalog.has(id):
		p.append("unknown control id")
		return p
	if typeof(e) != TYPE_DICTIONARY:
		p.append("mapping must be an object")
		return p
	var sig := String(e.get("sig", ""))
	var parts := sig.split(":")
	if parts.size() != 3 or not Events.DOMAIN_MAX.has(parts[0]) or not parts[1].is_valid_int() or not parts[2].is_valid_int() \
			or int(parts[1]) < 0 or int(parts[1]) > 15 or int(parts[2]) < 0 or int(parts[2]) > 127:
		p.append("bad signature '%s' (expected kind:channel0-15:number0-127)" % sig)
		return p
	var kind := Catalog.kind_of(id)
	var behavior := String(e.get("behavior", ""))
	if kind == Catalog.BUTTON:
		if not BUTTON_BEHAVIORS.has(behavior):
			p.append("button behavior must be one of %s" % str(BUTTON_BEHAVIORS))
	elif behavior == Behavior.ABSOLUTE:
		var hi: int = Events.DOMAIN_MAX[parts[0]]
		var lo_v: Variant = e.get("raw_min", 0)
		var hi_v: Variant = e.get("raw_max", hi)
		if not (lo_v is float or lo_v is int) or not (hi_v is float or hi_v is int) or int(lo_v) < 0 or int(hi_v) > hi or int(lo_v) >= int(hi_v):
			p.append("raw_min/raw_max must satisfy 0 <= raw_min < raw_max <= %d" % hi)
	elif behavior == Behavior.RELATIVE:
		var enc := String(e.get("encoding", ""))
		if not Behavior.ENCODINGS.has(enc):
			p.append("encoding must be one of %s" % str(Behavior.ENCODINGS))
		elif enc == Behavior.ENC_FIXED and (typeof(e.get("cw_values")) != TYPE_ARRAY or typeof(e.get("ccw_values")) != TYPE_ARRAY):
			p.append("fixed encoding needs cw_values and ccw_values lists")
	else:
		p.append("%s behavior must be absolute or relative" % kind)
	if e.has("invert") and typeof(e.invert) != TYPE_BOOL:
		p.append("invert must be true or false")
	if e.has("inferred") and typeof(e.inferred) != TYPE_BOOL:
		p.append("inferred must be true or false")
	return p


## Loads and validates. On any problem the current data is left untouched. Returns {ok, errors}.
func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["file not found: %s" % path], "missing": true}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "errors": ["not valid JSON (line %d: %s): %s" % [json.get_error_line(), json.get_error_message(), path]]}
	var parsed: Variant = json.data
	var problems := validate(parsed)
	if not problems.is_empty():
		return {"ok": false, "errors": problems}
	data = _normalised(parsed)
	_index.clear()
	return {"ok": true, "errors": []}


## JSON numbers load as floats; mappings use ints.
static func _normalised(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	for pname in out.profiles:
		var p: Dictionary = out.profiles[pname]
		if not p.has("verified"):
			p["verified"] = {}
		for id in p.mappings:
			var m: Dictionary = p.mappings[id]
			for key in ["raw_min", "raw_max"]:
				if m.has(key):
					m[key] = int(m[key])
			for key in ["cw_values", "ccw_values"]:
				if m.has(key):
					var ints := []
					for v in m[key]:
						ints.append(int(v))
					m[key] = ints
	return out


## Writes `<path>.tmp`, keeps the previous file as `<path>.bak`, then replaces. Returns {ok, error}.
func save_file(path: String) -> Dictionary:
	var problems := validate(data)
	if not problems.is_empty():
		return {"ok": false, "error": "refusing to save invalid config: %s" % problems[0]}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()]}
	f.store_string(JSON.stringify(data, "\t", true) + "\n")
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) != OK:
		return {"ok": false, "error": "could not replace %s" % path}
	return {"ok": true, "error": ""}
