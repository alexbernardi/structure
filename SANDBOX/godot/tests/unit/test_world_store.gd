extends RefCounted

const WorldState = preload("res://world/world_state.gd")
const WorldStore = preload("res://world/world_store.gd")

var dir := ""


func before_each() -> void:
	dir = OS.get_user_data_dir().path_join("test_store_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _write(name: String, text: String) -> void:
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _doc(schema: int, world_id := "w") -> String:
	var s := WorldState.new()
	s.init_new(world_id, 7)
	var d := s.to_save_dict()
	d["schema_version"] = schema
	return JSON.stringify(d)


func test_creates_then_reloads_world(t) -> void:
	var store := WorldStore.new(dir)
	var first := store.load_or_create("w", 7)
	t.ok(first.ok and first.created, "new world created")
	first.state.sites["site_0"].deposited = 5
	t.eq(store.save(first.state), OK, "saved")
	var second := WorldStore.new(dir).load_or_create("w", 999)
	t.ok(second.ok and not second.created, "existing world loaded: %s" % second.error)
	t.eq(second.state.sites["site_0"].deposited, 5, "progress persisted")
	t.eq(second.state.world_seed, 7, "an existing world keeps its seed")


func test_save_keeps_previous_version_as_backup(t) -> void:
	var store := WorldStore.new(dir)
	var w: WorldState = store.load_or_create("w", 7).state
	store.save(w)
	w.sites["site_0"].deposited = 1
	store.save(w)
	t.ok(FileAccess.file_exists(store.file_path() + ".bak"), "backup written")
	t.ok(not FileAccess.file_exists(store.file_path() + ".tmp"), "no temp file left")
	var bak: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.file_path() + ".bak"))
	t.eq(int(bak.sites[0].deposited), 0, "backup holds the previous revision")


func test_refuses_newer_schema_and_leaves_file_untouched(t) -> void:
	var text := _doc(99)
	_write("world.json", text)
	var r := WorldStore.new(dir).load_or_create("w", 7)
	t.ok(not r.ok, "refused")
	t.ok(r.error.contains("newer"), "explains why: %s" % r.error)
	t.eq(FileAccess.get_file_as_string(dir.path_join("world.json")), text, "file untouched")


func test_refuses_schema_older_than_minimum(t) -> void:
	_write("world.json", _doc(0))
	var r := WorldStore.new(dir).load_or_create("w", 7)
	t.ok(not r.ok and r.error.contains("older"), "refused: %s" % r.error)


func test_refuses_other_world(t) -> void:
	_write("world.json", _doc(1, "other"))
	var r := WorldStore.new(dir).load_or_create("w", 7)
	t.ok(not r.ok and r.error.contains("other"), "refused: %s" % r.error)


func test_refuses_corrupt_file(t) -> void:
	_write("world.json", "{ this is not json")
	var r := WorldStore.new(dir).load_or_create("w", 7)
	t.ok(not r.ok and r.error.contains("invalid JSON"), "refused: %s" % r.error)
	t.eq(FileAccess.get_file_as_string(dir.path_join("world.json")), "{ this is not json", "file untouched")


func test_recovers_interrupted_save_from_tmp(t) -> void:
	_write("world.json.tmp", _doc(1))
	_write("world.json.bak", _doc(1))
	var r := WorldStore.new(dir).load_or_create("w", 7)
	t.ok(r.ok and r.recovered, "recovered: %s" % r.error)


func test_refuses_to_start_fresh_over_backup(t) -> void:
	_write("world.json.bak", _doc(1))
	var r := WorldStore.new(dir).load_or_create("w", 7)
	t.ok(not r.ok and r.error.contains(".bak"), "refused: %s" % r.error)


func test_migration_without_path_fails_cleanly(t) -> void:
	var m := WorldStore.migrate({"schema_version": 1}, 1, 2)
	t.ok(not m.ok, "no v1->v2 migration exists yet")
	var same := WorldStore.migrate({"schema_version": 1}, 1, 1)
	t.ok(same.ok, "no-op migration succeeds")
