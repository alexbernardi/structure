extends RefCounted

const Config = preload("res://midi/midi_config.gd")
const Catalog = preload("res://midi/control_catalog.gd")

const TMP := "user://test_midi_config.json"


func after_each() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + suffix))


func _write(text: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _valid_doc() -> Dictionary:
	return {"schema": 1, "ports": "auto", "active_profile": "daw", "profiles": {"daw": {"mappings": {
		"strip1_fader": {"sig": "pb:0:0", "behavior": "absolute", "raw_min": 0, "raw_max": 16256},
		"strip1_knob": {"sig": "cc:0:16", "behavior": "relative", "encoding": "sign_magnitude", "invert": true},
		"strip1_mute": {"sig": "note:0:16", "behavior": "momentary"}}}}}


func test_default_config_is_valid(t) -> void:
	t.eq(Config.validate(Config.default_data()), [], "no problems")


func test_roundtrip_keeps_integers_and_verification(t) -> void:
	var c := Config.new()
	c.set_mapping("strip1_fader", {"sig": "pb:0:0", "behavior": "absolute", "raw_min": 0, "raw_max": 16256, "invert": false})
	c.set_mapping("strip1_knob", {"sig": "cc:0:16", "behavior": "relative", "encoding": "fixed", "invert": false, "cw_values": [1], "ccw_values": [65]})
	c.mark_verified("strip1_fader")
	t.ok(c.save_file(TMP).ok, "saved")
	var d := Config.new()
	var r := d.load_file(TMP)
	t.ok(r.ok, "loaded: %s" % str(r.errors))
	t.eq(d.mapping_of("strip1_fader").raw_max, 16256, "range")
	t.eq(typeof(d.mapping_of("strip1_fader").raw_max), TYPE_INT, "ints, not floats")
	t.eq(d.mapping_of("strip1_knob").ccw_values, [65], "fixed lists survive")
	t.eq(typeof(d.mapping_of("strip1_knob").ccw_values[0]), TYPE_INT, "list items are ints")
	t.ok(d.is_verified("strip1_fader") and not d.is_verified("strip1_knob"), "verification persists")


func test_save_keeps_a_backup_of_the_previous_file(t) -> void:
	var c := Config.new()
	c.save_file(TMP)
	c.set_mapping("strip1_mute", {"sig": "note:0:16", "behavior": "momentary"})
	t.ok(c.save_file(TMP).ok, "second save")
	t.ok(FileAccess.file_exists(TMP + ".bak"), ".bak holds the previous version")
	t.ok(not FileAccess.file_exists(TMP + ".tmp"), "no temp file left")


func test_signature_belongs_to_one_control(t) -> void:
	var c := Config.new()
	c.set_mapping("strip1_mute", {"sig": "note:0:16", "behavior": "momentary"})
	c.mark_verified("strip1_mute")
	var replaced := c.set_mapping("strip2_mute", {"sig": "note:0:16", "behavior": "momentary"})
	t.eq(replaced, "strip1_mute", "previous owner reported")
	t.ok(not c.is_mapped("strip1_mute"), "and unmapped")
	t.eq(c.find_by_sig("note:0:16"), "strip2_mute", "lookup follows")
	t.ok(not c.is_verified("strip2_mute"), "new mapping starts unverified")


func test_remapping_clears_verification_and_unmapped_list(t) -> void:
	var c := Config.new()
	t.eq(c.unmapped_ids().size(), 59, "everything required starts unmapped")
	t.eq(c.unmapped_ids(true).size(), 61, "optional keys included on request")
	c.set_mapping("global_play", {"sig": "note:0:94", "behavior": "momentary"})
	c.mark_verified("global_play")
	c.set_mapping("global_play", {"sig": "note:0:95", "behavior": "momentary"})
	t.ok(not c.is_verified("global_play"), "re-learn clears the verified mark")
	t.eq(c.unmapped_ids().size(), 58, "one mapped")
	c.clear_mapping("global_play")
	t.eq(c.unmapped_ids().size(), 59, "cleared")


func test_hand_edited_file_loads(t) -> void:
	_write(JSON.stringify(_valid_doc()))
	var c := Config.new()
	var r := c.load_file(TMP)
	t.ok(r.ok, str(r.errors))
	t.eq(c.find_by_sig("cc:0:16"), "strip1_knob", "index built from the file")


func test_invalid_documents_are_rejected_with_reasons(t) -> void:
	var cases := {
		"wrong schema": func(d: Dictionary) -> void: d.schema = 99,
		"unknown control": func(d: Dictionary) -> void: d.profiles.daw.mappings["strip9_knob"] = {"sig": "cc:0:1", "behavior": "relative", "encoding": "fixed", "cw_values": [], "ccw_values": []},
		"bad signature": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip1_mute.sig = "note:16:1",
		"bad kind": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip1_mute.sig = "sysex:0:1",
		"button with analog behavior": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip1_mute.behavior = "absolute",
		"inverted range": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip1_fader.raw_min = 20000,
		"range above domain": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip1_fader.raw_max = 99999,
		"unknown encoding": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip1_knob.encoding = "gray_code",
		"duplicate signature": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip2_mute = {"sig": "note:0:16", "behavior": "momentary"},
		"missing active profile": func(d: Dictionary) -> void: d.active_profile = "nope",
		"invert not bool": func(d: Dictionary) -> void: d.profiles.daw.mappings.strip1_knob.invert = "yes",
		"bad ports": func(d: Dictionary) -> void: d.ports = 5,
	}
	for label in cases:
		var doc := _valid_doc()
		cases[label].call(doc)
		t.ok(not Config.validate(doc).is_empty(), "rejected: %s" % label)
	t.eq(Config.validate(_valid_doc()), [], "the unmodified document is valid")


func test_bad_files_do_not_replace_good_data(t) -> void:
	var c := Config.new()
	c.set_mapping("strip1_mute", {"sig": "note:0:16", "behavior": "momentary"})
	_write("{ not json")
	t.ok(not c.load_file(TMP).ok, "garbage rejected")
	var bad := _valid_doc()
	bad.schema = 2
	_write(JSON.stringify(bad))
	t.ok(not c.load_file(TMP).ok, "wrong schema rejected")
	t.ok(c.is_mapped("strip1_mute"), "existing data untouched")
	var missing := c.load_file("user://does_not_exist.json")
	t.ok(not missing.ok and missing.missing, "a missing file is reported as missing")


func test_save_refuses_invalid_data(t) -> void:
	var c := Config.new()
	c.profile().mappings["strip1_mute"] = {"sig": "bogus", "behavior": "momentary"}
	var r := c.save_file(TMP)
	t.ok(not r.ok, "invalid data is not written")
	t.ok(not FileAccess.file_exists(TMP), "no file created")


func test_profiles(t) -> void:
	var c := Config.new()
	c.set_mapping("strip1_mute", {"sig": "note:0:16", "behavior": "momentary"})
	t.ok(not c.set_active_profile("user"), "unknown profile needs create=true")
	t.ok(c.set_active_profile("user", true), "created")
	t.ok(not c.is_mapped("strip1_mute"), "profiles are independent")
	c.set_mapping("strip1_mute", {"sig": "cc:0:20", "behavior": "momentary"})
	c.set_active_profile("daw")
	t.eq(c.mapping_of("strip1_mute").sig, "note:0:16", "daw profile intact")
	t.eq(Config.validate(c.data), [], "still valid")
