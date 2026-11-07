## Named movement presets as JSON files (one per preset), validated on load and written atomically.
## Format:  {"schema": 1, "name": "...", "note": "...", "saved": "<UTC>", "targets": {"movement": {"<id>": <number>}}}
## Presets may be partial (only some ids): the rest keep their current values. Out-of-range values are clamped and
## reported; unknown ids are reported, never silently dropped. Deleting is explicit and never touches other files.
extends RefCounted

const SCHEMA := 1
const DEFAULT_DIR := "res://presets"
const MAX_NAME := 32

var dir := DEFAULT_DIR


func _init(directory := DEFAULT_DIR) -> void:
	dir = directory


## Lower-case letters, digits, '-' and '_' only; returns "" if nothing usable is left.
static func sanitize_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower().replace(" ", "_")
	var out := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	return out.left(MAX_NAME)


func path_of(name: String) -> String:
	return dir.path_join(name + ".json")


func names() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".json"):
			out.append(f.get_basename())
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func exists(name: String) -> bool:
	return FileAccess.file_exists(path_of(name))


## `targets` is {target: {id: value}} as produced by TunableRegistry.capture().
func save_preset(name: String, targets: Dictionary, note := "") -> Dictionary:
	var clean := sanitize_name(name)
	if clean == "":
		return {"ok": false, "error": "preset names need letters, digits, '-' or '_'", "name": ""}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return {"ok": false, "error": "cannot create %s" % dir, "name": clean}
	var doc := {"schema": SCHEMA, "name": clean, "note": note, "saved": Time.get_datetime_string_from_system(true), "targets": targets}
	var path := path_of(clean)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()], "name": clean}
	f.store_string(JSON.stringify(doc, "\t", true) + "\n")
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) != OK:
		return {"ok": false, "error": "could not replace %s" % path, "name": clean}
	return {"ok": true, "error": "", "name": clean}


## `registry` (optional) enables range/unknown checks. Returns {ok, targets, warnings, error, note}.
func load_preset(name: String, registry = null) -> Dictionary:
	var path := path_of(name)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "no preset named '%s'" % name, "targets": {}, "warnings": []}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"ok": false, "error": "'%s' is not valid JSON (line %d)" % [name, json.get_error_line()], "targets": {}, "warnings": []}
	return validate(json.data, name, registry)


static func validate(doc: Variant, name: String, registry = null) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": "preset '%s': %s" % [name, msg], "targets": {}, "warnings": []}
	if typeof(doc) != TYPE_DICTIONARY:
		return fail.call("top level must be an object")
	if int(doc.get("schema", -1)) != SCHEMA:
		return fail.call("unsupported schema %s (expected %d)" % [str(doc.get("schema")), SCHEMA])
	if typeof(doc.get("targets")) != TYPE_DICTIONARY:
		return fail.call("missing 'targets' object")
	var warnings: Array[String] = []
	var targets := {}
	for t in doc.targets:
		if typeof(doc.targets[t]) != TYPE_DICTIONARY:
			return fail.call("target '%s' must be an object" % t)
		var vals := {}
		for id in doc.targets[t]:
			var v: Variant = doc.targets[t][id]
			if not (v is float or v is int):
				return fail.call("%s.%s must be a number, got %s" % [t, id, type_string(typeof(v))])
			if is_nan(float(v)) or is_inf(float(v)):
				return fail.call("%s.%s is not a finite number" % [t, id])
			var key := "%s.%s" % [t, id]
			if registry != null:
				if not registry.has_key(key):
					warnings.append("unknown parameter %s (ignored)" % key)
					continue
				var d: Dictionary = registry.def_of(key)
				if float(v) < float(d.min) or float(v) > float(d.max):
					warnings.append("%s = %s is outside %s..%s and was clamped" % [key, str(v), str(d.min), str(d.max)])
			vals[id] = float(v)
		targets[t] = vals
	return {"ok": true, "error": "", "targets": targets, "warnings": warnings, "note": String(doc.get("note", ""))}


## Removes one preset file. Only called from an explicit user action.
func delete_preset(name: String) -> bool:
	var clean := sanitize_name(name)
	if clean == "" or not exists(clean):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path_of(clean))) == OK


func next_name(current: String, step: int) -> String:
	var all := names()
	if all.is_empty():
		return ""
	var i := all.find(current)
	if i < 0:
		return all[0] if step > 0 else all[all.size() - 1]
	return all[(i + step + all.size()) % all.size()]
