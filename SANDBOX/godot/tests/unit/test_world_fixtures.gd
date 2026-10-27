## Compatibility guarantee: every world fixture of a released schema (TESTING/fixtures/worlds/world-v<N>.json)
## must keep loading (directly or through migrations) as long as N >= min_world_schema_version.
extends RefCounted

const WorldStore = preload("res://world/world_store.gd")
const BuildInfo = preload("res://core/build_info.gd")

var dir := ""


func before_each() -> void:
	dir = OS.get_user_data_dir().path_join("test_fixtures_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _fixtures_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../TESTING/fixtures/worlds").simplify_path()


func test_released_world_schemas_still_load(t) -> void:
	var fixtures := Array(DirAccess.get_files_at(_fixtures_dir())).filter(func(f: String) -> bool: return f.begins_with("world-v"))
	t.ok(not fixtures.is_empty(), "fixtures found in %s" % _fixtures_dir())
	for name in fixtures:
		var text := FileAccess.get_file_as_string(_fixtures_dir().path_join(name))
		var doc: Dictionary = JSON.parse_string(text)
		if int(doc.schema_version) < BuildInfo.min_world_schema_version():
			continue  # migration path deliberately dropped; the fixture documents history only
		var f := FileAccess.open(dir.path_join("world.json"), FileAccess.WRITE)
		f.store_string(text)
		f.close()
		var loaded := WorldStore.new(dir).load_or_create(doc.world_id, int(doc.seed))
		t.ok(loaded.ok, "%s loads: %s" % [name, loaded.error])
		if loaded.ok:
			t.eq(loaded.state.sites["site_0"].deposited, int(doc.sites[0].deposited), "%s progress preserved" % name)
			t.eq(loaded.state.resources.size(), doc.resources.size(), "%s resources preserved" % name)
