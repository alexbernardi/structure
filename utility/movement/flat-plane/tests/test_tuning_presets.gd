extends RefCounted

const Bindings = preload("res://tuning/tuning_bindings.gd")
const Presets = preload("res://tuning/preset_store.gd")
const Registry = preload("res://tuning/tunable_registry.gd")
const Params = preload("res://movement/movement_params.gd")
const BodyParams = preload("res://animation/body_params.gd")

const BIND_TMP := "user://test_tuning_bindings.json"
const PRESET_DIR := "user://test_presets"


func after_each() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BIND_TMP + suffix))
	var d := DirAccess.open(PRESET_DIR)
	if d:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PRESET_DIR))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _reg():
	var r := Registry.new()
	r.register("movement", "Movement", Params.new())
	r.register("body", "Body (visual)", BodyParams.create())
	return r


# ------------------------------------------------------------------ bindings

func test_default_bindings_are_valid_and_cover_the_parameters(t) -> void:
	var b := Bindings.new()
	t.eq(Bindings.validate(b.data), [], "valid")
	t.eq(b.unresolved(_reg()), [], "every bound parameter exists")
	var bound := b.referenced_keys()
	for key in _reg().keys():
		t.ok(bound.has(key), "%s is reachable from some bank" % key)


func test_default_layout(t) -> void:
	var b := Bindings.new()
	t.eq(b.bank_count(), 6, "movement banks plus the three body banks")
	t.eq(b.bank_name(3), "Body Springs", "body bank names")
	t.eq(b.bank_name(4), "Body Effects", "body bank names")
	t.eq(b.bank_name(0), "Ground", "names")
	t.eq(b.slot_key(0, 1, "fader"), "movement.max_ground_speed", "strip 1 fader")
	t.eq(b.slot_key(0, 1, "knob"), "movement.max_ground_speed", "the knob fine-adjusts the same parameter")
	t.eq(b.slot_key(0, 8, "fader"), "", "spare strips are empty")
	t.eq(b.slot_key(9, 1, "fader"), "", "out of range banks are safe")
	t.eq(b.strip_action("mute"), "reset_param", "defaults for the strip buttons")
	t.eq(b.global_action("global_bank_next"), "bank_next", "bank buttons")


func test_shipped_bindings_file_loads(t) -> void:
	var b := Bindings.new()
	var r := b.load_file(Bindings.DEFAULT_PATH)
	t.ok(r.ok, "config/tuning_bindings.json is valid: %s" % str(r.errors))


func test_roundtrip_and_backup(t) -> void:
	var b := Bindings.new()
	b.assign(0, 8, "fader", "movement.gravity")
	b.add_bank("Experiments")
	t.ok(b.save_file(BIND_TMP).ok, "saved")
	b.assign(0, 8, "fader", "")
	t.ok(b.save_file(BIND_TMP).ok, "saved again")
	t.ok(FileAccess.file_exists(BIND_TMP + ".bak"), "previous version kept")
	var c := Bindings.new()
	t.ok(c.load_file(BIND_TMP).ok, "loaded")
	t.eq(c.bank_count(), 7, "added bank persisted")
	t.eq(c.slot_key(0, 8, "fader"), "", "latest edit persisted")


func test_assign_clear_and_validation_of_edits(t) -> void:
	var b := Bindings.new()
	t.ok(b.assign(0, 8, "fader", "movement.gravity"), "assign")
	t.eq(b.slot_key(0, 8, "fader"), "movement.gravity", "stored")
	t.ok(b.assign(0, 8, "fader", ""), "clear")
	t.ok(not b.data.banks[0].strips.has("8"), "empty strips are removed")
	t.ok(not b.assign(0, 9, "fader", "movement.gravity"), "no strip 9")
	t.ok(not b.assign(b.bank_count(), 1, "fader", "movement.gravity"), "no bank past the last")
	t.ok(not b.assign(0, 1, "slider", "movement.gravity"), "no such slot kind")
	t.ok(not b.assign(0, 1, "fader", "gravity"), "key must be target.id")
	t.eq(Bindings.validate(b.data), [], "the data stayed valid through all of that")


func test_bank_management(t) -> void:
	var b := Bindings.new()
	var i := b.add_bank("  My Bank  ")
	t.eq(b.bank_name(i), "My Bank", "trimmed")
	t.ok(b.rename_bank(i, "x".repeat(50)), "rename")
	t.eq(b.bank_name(i).length(), Bindings.MAX_BANK_NAME, "long names are cut")
	t.ok(not b.rename_bank(i, "   "), "blank names refused")
	t.ok(b.remove_bank(i), "remove")
	var lone := Bindings.new()
	lone.data.banks = [lone.data.banks[0]]
	t.ok(not lone.remove_bank(0), "the last bank cannot be removed")
	t.eq(b.add_bank(""), b.bank_count() - 1, "blank name gets a generated one")
	t.ok(b.bank_name(b.bank_count() - 1).begins_with("Bank"), "generated")


func test_action_assignment_rules(t) -> void:
	var b := Bindings.new()
	t.ok(b.set_strip_action("solo", "toggle_param"), "strip buttons accept strip actions")
	t.ok(not b.set_strip_action("solo", "fly"), "unknown action")
	t.ok(not b.set_strip_action("shift", "none"), "not a strip button")
	t.ok(b.set_global_action("global_play", "bank_next"), "global buttons accept global actions")
	t.ok(not b.set_global_action("global_play", "reset_param"), "strip-only actions are refused on global buttons")
	t.ok(not b.set_global_action("strip1_mute", "respawn"), "strip buttons are not global")
	t.ok(b.set_global_action("global_shift", "hud_cycle"), "optional keys can be bound too")


func test_invalid_files_are_rejected_with_reasons(t) -> void:
	var cases := {
		"wrong schema": func(d: Dictionary) -> void: d.schema = 3,
		"no banks": func(d: Dictionary) -> void: d.banks = [],
		"bank without name": func(d: Dictionary) -> void: d.banks[0].name = "",
		"strip 9": func(d: Dictionary) -> void: d.banks[0].strips["9"] = {"fader": "movement.gravity"},
		"bad key": func(d: Dictionary) -> void: d.banks[0].strips["1"].fader = "Movement Gravity",
		"unknown slot": func(d: Dictionary) -> void: d.banks[0].strips["1"].slider = "movement.gravity",
		"unknown strip action": func(d: Dictionary) -> void: d.strip_actions.mute = "explode",
		"unknown strip button": func(d: Dictionary) -> void: d.strip_actions.volume = "reset_param",
		"global action that needs a strip": func(d: Dictionary) -> void: d.global_actions.global_play = "reset_param",
		"not a global button": func(d: Dictionary) -> void: d.global_actions.strip1_mute = "respawn",
		"knob scale out of range": func(d: Dictionary) -> void: d.knob_scale = 100.0,
		"banks not a list": func(d: Dictionary) -> void: d.banks = {},
	}
	for label in cases:
		var d: Dictionary = Bindings.default_data()
		cases[label].call(d)
		t.ok(not Bindings.validate(d).is_empty(), "rejected: %s" % label)
	t.eq(Bindings.validate(Bindings.default_data()), [], "the untouched default is valid")
	t.ok(not Bindings.validate([1, 2]).is_empty(), "not an object")


func test_bad_files_leave_current_data_alone(t) -> void:
	var b := Bindings.new()
	b.assign(0, 8, "fader", "movement.gravity")
	_write(BIND_TMP, "{ nope")
	t.ok(not b.load_file(BIND_TMP).ok, "garbage")
	_write(BIND_TMP, JSON.stringify({"schema": 9}))
	t.ok(not b.load_file(BIND_TMP).ok, "wrong schema")
	t.eq(b.slot_key(0, 8, "fader"), "movement.gravity", "data untouched")
	var missing := b.load_file("user://nothing_here.json")
	t.ok(not missing.ok and missing.missing, "missing file is flagged as missing")


func test_save_refuses_invalid_data(t) -> void:
	var b := Bindings.new()
	b.data.banks[0].name = ""
	t.ok(not b.save_file(BIND_TMP).ok, "refused")
	t.ok(not FileAccess.file_exists(BIND_TMP), "nothing written")


# ------------------------------------------------------------------ presets

func test_name_sanitising(t) -> void:
	t.eq(Presets.sanitize_name("  Moon Jump! "), "moon_jump", "spaces and punctuation")
	t.eq(Presets.sanitize_name("../../evil"), "evil", "no path traversal")
	t.eq(Presets.sanitize_name("a\\b/c"), "abc", "no separators")
	t.eq(Presets.sanitize_name("***"), "", "nothing usable")
	t.eq(Presets.sanitize_name("x".repeat(80)).length(), Presets.MAX_NAME, "length limit")


func test_save_load_roundtrip_is_exact(t) -> void:
	var store := Presets.new(PRESET_DIR)
	var reg = _reg()
	reg.set_value("movement.max_ground_speed", 7.3)
	reg.set_value("movement.gravity", 12.4)
	reg.set_value("movement.auto_jump", 1.0)
	var r := store.save_preset("My Test", reg.capture(), "a note")
	t.ok(r.ok and r.name == "my_test", "saved under a clean name")
	var loaded := store.load_preset("my_test", reg)
	t.ok(loaded.ok and loaded.warnings.is_empty(), str(loaded))
	t.eq(loaded.targets.movement.max_ground_speed, 7.3, "exact float")
	t.eq(loaded.targets.movement.auto_jump, 1.0, "bool stored as number")
	t.eq(loaded.note, "a note", "note kept")
	t.eq(loaded.targets.movement.size(), Params.definitions().size(), "all parameters stored")


func test_listing_cycling_and_delete(t) -> void:
	var store := Presets.new(PRESET_DIR)
	var reg = _reg()
	for n in ["b_preset", "a_preset", "c_preset"]:
		store.save_preset(n, reg.capture())
	t.eq(store.names(), ["a_preset", "b_preset", "c_preset"], "sorted")
	t.eq(store.next_name("a_preset", 1), "b_preset", "next")
	t.eq(store.next_name("c_preset", 1), "a_preset", "wraps forward")
	t.eq(store.next_name("a_preset", -1), "c_preset", "wraps back")
	t.eq(store.next_name("", 1), "a_preset", "no current preset: first")
	t.eq(store.next_name("gone", -1), "c_preset", "unknown current: last when going back")
	t.ok(store.delete_preset("b_preset"), "deleted")
	t.eq(store.names(), ["a_preset", "c_preset"], "only that one")
	t.ok(not store.delete_preset("b_preset"), "deleting a missing preset is a harmless no")
	t.ok(not store.delete_preset("../x"), "no traversal on delete")
	t.eq(Presets.new(PRESET_DIR + "_none").names(), [], "a missing folder lists nothing")
	t.eq(Presets.new(PRESET_DIR + "_none").next_name("", 1), "", "and cycles nowhere")


func test_overwrite_is_atomic_and_leaves_no_temp_file(t) -> void:
	var store := Presets.new(PRESET_DIR)
	var reg = _reg()
	store.save_preset("x", reg.capture())
	reg.set_value("movement.gravity", 25.0)
	t.ok(store.save_preset("x", reg.capture()).ok, "overwritten")
	t.ok(not FileAccess.file_exists(store.path_of("x") + ".tmp"), "no temp file")
	t.eq(store.load_preset("x", reg).targets.movement.gravity, 25.0, "new content")
	t.eq(store.names(), ["x"], "still one preset")


func test_bad_names_are_refused(t) -> void:
	var store := Presets.new(PRESET_DIR)
	var r := store.save_preset("???", {})
	t.ok(not r.ok, "refused: %s" % r.error)


func test_out_of_range_values_are_clamped_and_reported(t) -> void:
	var store := Presets.new(PRESET_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIR))
	_write(store.path_of("wild"), JSON.stringify({"schema": 1, "targets": {"movement": {"max_ground_speed": 400, "gravity": 0.01, "jump_impulse": 6.0, "warp": 1.0}, "camera": {"fov": 60}}}))
	var r := store.load_preset("wild", _reg())
	t.ok(r.ok, "loads")
	t.eq(r.warnings.size(), 4, "two clamped, two unknown: %s" % str(r.warnings))
	var reg = _reg()
	reg.set_value("movement.max_ground_speed", r.targets.movement.max_ground_speed)
	t.eq(reg.value("movement.max_ground_speed"), 15.0, "applying clamps to the legal range")
	t.ok(not r.targets.movement.has("warp"), "unknown ids are not passed on")


func test_partial_presets_are_allowed(t) -> void:
	var store := Presets.new(PRESET_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIR))
	_write(store.path_of("tiny"), JSON.stringify({"schema": 1, "targets": {"movement": {"gravity": 9.8}}}))
	var r := store.load_preset("tiny", _reg())
	t.ok(r.ok and r.targets.movement.size() == 1, "one value is fine")


func test_corrupt_and_invalid_presets_are_rejected_without_engine_errors(t) -> void:
	var store := Presets.new(PRESET_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIR))
	var bad := {
		"not json": "{ nope",
		"array": "[1,2]",
		"wrong schema": JSON.stringify({"schema": 2, "targets": {}}),
		"no targets": JSON.stringify({"schema": 1}),
		"target not object": JSON.stringify({"schema": 1, "targets": {"movement": 5}}),
		"string value": JSON.stringify({"schema": 1, "targets": {"movement": {"gravity": "heavy"}}}),
	}
	for label in bad:
		_write(store.path_of("t"), bad[label])
		var r := store.load_preset("t", _reg())
		t.ok(not r.ok and r.error != "", "rejected: %s (%s)" % [label, r.error])
	t.ok(not store.load_preset("nonexistent").ok, "missing preset")


func test_shipped_presets_are_valid_and_in_range(t) -> void:
	var store := Presets.new()
	var names := store.names()
	t.ok(names.size() >= 3, "example presets ship with the lab: %s" % str(names))
	for n in names:
		var r := store.load_preset(n, _reg())
		t.ok(r.ok, "%s loads: %s" % [n, r.error])
		t.eq(r.warnings, [], "%s: no clamping or unknown ids needed" % n)


func test_default_preset_equals_the_parameter_defaults(t) -> void:
	var r := Presets.new().load_preset("default", _reg())
	t.ok(r.ok, "a 'default' preset exists")
	for d in Params.definitions():
		t.eq(r.targets.movement.get(d.id), float(d.default), "default.%s" % d.id)
