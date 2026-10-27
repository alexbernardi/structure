## Version identity of the running build. Values come from project.godot ([structure] section and
## application/config/version) plus res://build_manifest.json, which the tooling generates for each build.
extends RefCounted

const MANIFEST_PATH := "res://build_manifest.json"

static var _manifest_cache: Variant = null


static func build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func protocol_version() -> int:
	return int(ProjectSettings.get_setting("structure/network/protocol_version", 0))


static func world_schema_version() -> int:
	return int(ProjectSettings.get_setting("structure/persistence/world_schema_version", 0))


static func min_world_schema_version() -> int:
	return int(ProjectSettings.get_setting("structure/persistence/min_world_schema_version", 0))


static func engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d-%s" % [info.major, info.minor, info.patch, info.status]


static func manifest() -> Dictionary:
	if _manifest_cache == null:
		_manifest_cache = {}
		if FileAccess.file_exists(MANIFEST_PATH):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) == OK and json.data is Dictionary:
				_manifest_cache = json.data
	return _manifest_cache


static func summary() -> Dictionary:
	var m := manifest()
	return {
		"build": build_version(),
		"commit": m.get("git_commit", "unknown"),
		"dirty": m.get("git_dirty", null),
		"image": m.get("image", ""),
		"engine": engine_version(),
		"protocol": protocol_version(),
		"world_schema": world_schema_version(),
	}
