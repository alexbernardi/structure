## World persistence: one JSON document per world directory, atomically replaced on every save.
## Safety rules (AGENT-WORKSHOP/PROTOCOLS/VERSIONING.md):
##   * never overwrite a file it cannot read, or one written by a newer schema;
##   * never create a fresh world while recoverable data (world.json.bak) is present;
##   * migrations keep a copy of the original document (world.v<N>.json);
##   * an interrupted save is recovered from world.json.tmp (it is only renamed after a complete write).
extends RefCounted

const WorldState = preload("res://world/world_state.gd")
const BuildInfo = preload("res://core/build_info.gd")
const FILE_NAME := "world.json"

var dir: String


func _init(world_dir: String) -> void:
	dir = world_dir


func file_path() -> String:
	return dir.path_join(FILE_NAME)


## -> {ok, state, created, recovered, migrated_from, error}
func load_or_create(world_id: String, world_seed: int) -> Dictionary:
	var result := {"ok": false, "state": null, "created": false, "recovered": false, "migrated_from": 0, "error": ""}
	DirAccess.make_dir_recursive_absolute(dir)
	if not DirAccess.dir_exists_absolute(dir):
		result.error = "cannot create world directory %s" % dir
		return result
	var path := file_path()
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".tmp") and _read_doc(path + ".tmp").ok:
			DirAccess.rename_absolute(path + ".tmp", path)
			result.recovered = true
		elif FileAccess.file_exists(path + ".bak"):
			result.error = "found %s.bak but no %s; refusing to create a new world over recoverable data (restore or move it)" % [FILE_NAME, FILE_NAME]
			return result
		else:
			var fresh := WorldState.new()
			fresh.init_new(world_id, world_seed)
			result.ok = true
			result.state = fresh
			result.created = true
			return result
	var doc := _read_doc(path)
	if not doc.ok:
		result.error = "%s: %s (file left untouched; restore world.json.bak or a snapshot)" % [path, doc.error]
		return result
	var data: Dictionary = doc.data
	var version := int(data.get("schema_version", -1))
	var current := BuildInfo.world_schema_version()
	var minimum := BuildInfo.min_world_schema_version()
	if version > current:
		result.error = "world schema v%d is newer than this server supports (v%d); run a newer build" % [version, current]
		return result
	if version < minimum:
		result.error = "world schema v%d is older than the oldest migratable schema (v%d)" % [version, minimum]
		return result
	if str(data.get("world_id", "")) != world_id:
		result.error = "data directory holds world '%s' but the server is configured for '%s'" % [data.get("world_id", ""), world_id]
		return result
	if version < current:
		DirAccess.copy_absolute(path, dir.path_join("world.v%d.json" % version))
		var migrated := migrate(data, version, current)
		if not migrated.ok:
			result.error = migrated.error
			return result
		data = migrated.data
		result.migrated_from = version
	var state := WorldState.new()
	var problem := state.load_save_dict(data)
	if problem != "":
		result.error = "%s: %s" % [path, problem]
		return result
	result.ok = true
	result.state = state
	return result


func save(state: WorldState) -> Error:
	var doc := state.to_save_dict()
	doc["schema_version"] = BuildInfo.world_schema_version()
	doc["saved_at"] = Time.get_datetime_string_from_system(true) + "Z"
	doc["server_build"] = BuildInfo.summary()
	var path := file_path()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, "  ", true))
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		return write_error
	if FileAccess.file_exists(path):
		var err := DirAccess.rename_absolute(path, path + ".bak")
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp, path)


## Schema migrations. When bumping structure/persistence/world_schema_version, add a branch that
## upgrades v -> v+1, a fixture of the old schema under TESTING/fixtures/worlds, and a test.
static func migrate(data: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var doc := data.duplicate(true)
	for v in range(from_version, to_version):
		match v:
			_:
				return {"ok": false, "error": "no migration from schema v%d to v%d" % [v, v + 1]}
	doc["schema_version"] = to_version
	return {"ok": true, "data": doc}


static func _read_doc(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "unreadable (error %d)" % FileAccess.get_open_error()}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if text.strip_edges() == "" or json.parse(text) != OK:
		return {"ok": false, "error": "invalid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]}
	if not json.data is Dictionary:
		return {"ok": false, "error": "top level is not an object"}
	return {"ok": true, "data": json.data}
