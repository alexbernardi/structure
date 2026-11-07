## Which parameter or action each *logical* control drives. Physical MIDI -> logical control is the MIDI config
## (learned); this is the second layer: logical control -> parameter / action. Both are data, both editable.
## Banks give every strip a fader and a knob slot, so one controller can tune many things.
extends RefCounted

const Catalog = preload("res://midi/control_catalog.gd")
const Registry = preload("res://tuning/tunable_registry.gd")

const SCHEMA := 1
const DEFAULT_PATH := "res://config/tuning_bindings.json"
const MAX_BANK_NAME := 24
const STRIP_PARTS := ["mute", "solo", "rec", "select"]

## id -> label. "strip" actions need a strip's parameter, so they are only valid on the per-strip buttons.
const ACTIONS := {
	"none": "(nothing)",
	"reset_param": "Reset parameter to default",
	"lock_param": "Lock / unlock parameter",
	"revert_param": "Revert to preset value",
	"select_param": "Select parameter (show details)",
	"toggle_param": "Toggle on/off parameter",
	"reset_all": "Reset ALL parameters",
	"respawn": "Respawn",
	"teleport_prev": "Teleport to previous landmark",
	"teleport_next": "Teleport to next landmark",
	"bank_prev": "Previous bank",
	"bank_next": "Next bank",
	"preset_prev": "Previous preset",
	"preset_next": "Next preset",
	"preset_save": "Save current preset",
	"hud_cycle": "Cycle HUD (full / compact / off)",
	"record_toggle": "Start / stop input recording",
}
const STRIP_ONLY := ["reset_param", "lock_param", "revert_param", "select_param", "toggle_param"]

var data: Dictionary = default_data()


static func default_data() -> Dictionary:
	var m := "movement."
	var ground: Array = ["max_ground_speed", "ground_accel", "ground_friction", "braking", "stop_speed", "sprint_multiplier", "crouch_speed", ""]
	var jump: Array = ["jump_impulse", "gravity", "max_fall_speed", "coyote_time", "jump_buffer_time", "air_accel", "air_speed_cap", "air_control"]
	var body: Array = ["max_walkable_slope", "slope_speed_penalty", "step_height", "stand_height", "crouch_height", "auto_jump", "", ""]
	var banks: Array = [_bank("Ground", ground, m), _bank("Jump & Air", jump, m), _bank("Slope & Body", body, m)]
	banks.append_array(body_banks())
	return {
		"schema": SCHEMA,
		"knob_scale": 1.0,
		"banks": banks,
		"strip_actions": {"mute": "reset_param", "solo": "lock_param", "rec": "revert_param", "select": "select_param"},
		"global_actions": {
			"global_play": "respawn", "global_stop": "reset_all", "global_record": "record_toggle",
			"global_rewind": "preset_prev", "global_forward": "preset_next",
			"global_bank_prev": "bank_prev", "global_bank_next": "bank_next",
			"global_nav_up": "preset_save", "global_nav_down": "hud_cycle",
			"global_nav_left": "teleport_prev", "global_nav_right": "teleport_next",
		},
	}


## Procedural body banks (visual only). Faders carry the amplitudes and knobs the spring frequency and damping of each
## group; the second bank puts every effect switch on a fader so each one can be isolated; the third holds the gains
## and limits behind the amplitudes.
static func body_banks() -> Array:
	var b := "body."
	var springs: Array = ["torso_lean_amp", "hip_sway_amp", "rotation_lag", "landing_compression", "landing_rebound", "follow_through", "head_stabilization", "arm_swing_amp"]
	var spring_knobs: Array = ["torso_freq", "torso_damping", "hip_freq", "hip_damping", "rotation_freq", "rotation_damping", "landing_freq", "landing_damping"]
	var effects: Array = ["fx_torso_lean", "fx_torso_lateral", "fx_anticipation", "fx_pelvis_shift", "fx_pelvis_gait", "fx_landing", "fx_head", "fx_arms"]
	var effect_knobs: Array = ["body_dynamics", "", "", "", "", "", "", "fx_facing_lag"]
	var detail_faders: Array = ["lean_accel_gain", "lean_speed_gain", "lateral_lean_gain", "anticipation_lead", "sway_distance", "bob_height", "weight_shift_gain", "landing_gain"]
	var detail_knobs: Array = ["lean_max_deg", "lateral_lean_max_deg", "shoulder_counter_amp", "head_freq", "head_max_yaw_deg", "", "weight_shift_max", "landing_max"]
	var s1 := {}
	var s2 := {}
	var s3 := {}
	for i in 8:
		s3[str(i + 1)] = {"fader": b + String(detail_faders[i])}
		if detail_knobs[i] != "":
			s3[str(i + 1)]["knob"] = b + String(detail_knobs[i])
		s1[str(i + 1)] = {"fader": b + String(springs[i]), "knob": b + String(spring_knobs[i])}
		s2[str(i + 1)] = {"fader": b + String(effects[i])}
		if effect_knobs[i] != "":
			s2[str(i + 1)]["knob"] = b + String(effect_knobs[i])
	return [{"name": "Body Springs", "strips": s1}, {"name": "Body Effects", "strips": s2}, {"name": "Body Detail", "strips": s3}]


## Banks for the treadmill gait lab (target "gait"); the buttons keep the same meaning as everywhere else.
static func gait_data() -> Dictionary:
	var d := default_data()
	var g := "gait."
	var cycle: Array = ["walk_speed", "step_length", "duty_factor", "step_height", "swing_peak", "stand_height", "velocity_match", "time_scale"]
	var pelvis: Array = ["pelvis_bob", "loading_dip", "pelvis_sway", "pelvis_rotation", "pelvic_tilt", "shoulder_counter", "torso_lean", ""]
	var feet: Array = ["heel_strike_angle", "toe_off_angle", "toe_clearance_angle", "foot_flat_at", "heel_rise_at", "arm_swing", "elbow_bend", "arm_phase"]
	var toggle_faders: Array = ["gait_model", "auto_step_length", "foot_roll", "fx_pelvis_bob", "fx_loading_dip", "fx_pelvis_sway", "fx_pelvis_rotation", "fx_pelvic_tilt"]
	var toggle_knobs: Array = ["fx_shoulder_counter", "fx_arm_swing", "fx_elbow_bend", "freeze", "view_belt", "view_paths", "view_joints", "view_diagram"]
	var view_faders: Array = ["scrub", "view_zoom", "time_scale", "", "", "", "", ""]
	var view_knobs: Array = ["scrub", "view_zoom", "view_guides", "view_ortho", "", "", "", ""]
	var toggles := {}
	var view := {}
	for i in 8:
		var t := {}
		if toggle_faders[i] != "":
			t["fader"] = g + String(toggle_faders[i])
		if toggle_knobs[i] != "":
			t["knob"] = g + String(toggle_knobs[i])
		toggles[str(i + 1)] = t
		var v := {}
		if view_faders[i] != "":
			v["fader"] = g + String(view_faders[i])
		if view_knobs[i] != "":
			v["knob"] = g + String(view_knobs[i])
		if not v.is_empty():
			view[str(i + 1)] = v
	d.banks = [_bank("Walk Cycle", cycle, g), _bank("Pelvis & Torso", pelvis, g), _bank("Feet & Arms", feet, g), {"name": "Toggles", "strips": toggles}, {"name": "View & Playback", "strips": view}]
	return d


## Each strip's knob fine-adjusts the same parameter its fader sets coarsely.
static func _bank(name: String, ids: Array, prefix: String) -> Dictionary:
	var strips := {}
	for i in ids.size():
		if ids[i] != "":
			strips[str(i + 1)] = {"fader": prefix + String(ids[i]), "knob": prefix + String(ids[i])}
	return {"name": name, "strips": strips}


# ------------------------------------------------------------------ queries

func bank_count() -> int:
	return data.banks.size()


func bank_name(i: int) -> String:
	return String(data.banks[i].name)


func slot_key(bank: int, strip: int, kind: String) -> String:
	if bank < 0 or bank >= bank_count():
		return ""
	var s: Dictionary = data.banks[bank].strips.get(str(strip), {})
	return String(s.get(kind, ""))


func strip_action(part: String) -> String:
	return String(data.strip_actions.get(part, "none"))


func global_action(control_id: String) -> String:
	return String(data.global_actions.get(control_id, "none"))


func knob_scale() -> float:
	return float(data.get("knob_scale", 1.0))


## Every parameter key referenced by any bank (to warn about ones that do not resolve).
func referenced_keys() -> Array[String]:
	var out: Array[String] = []
	for b in data.banks:
		for s in b.strips.values():
			for kind in ["fader", "knob"]:
				var k: Variant = s.get(kind)
				if k != null and String(k) != "" and not out.has(String(k)):
					out.append(String(k))
	return out


func unresolved(registry) -> Array[String]:
	var out: Array[String] = []
	for k in referenced_keys():
		if not registry.has_key(k):
			out.append(k)
	return out


# ------------------------------------------------------------------ editing

## Assigns (or with key == "" clears) a slot. Returns false for an invalid bank/strip/kind/key.
func assign(bank: int, strip: int, kind: String, key: String) -> bool:
	if bank < 0 or bank >= bank_count() or strip < 1 or strip > Catalog.STRIPS or not ["fader", "knob"].has(kind):
		return false
	if key != "" and not Registry.is_valid_key(key):
		return false
	var strips: Dictionary = data.banks[bank].strips
	var s: Dictionary = strips.get(str(strip), {})
	if key == "":
		s.erase(kind)
	else:
		s[kind] = key
	if s.is_empty():
		strips.erase(str(strip))
	else:
		strips[str(strip)] = s
	return true


func set_strip_action(part: String, action: String) -> bool:
	if not STRIP_PARTS.has(part) or not ACTIONS.has(action):
		return false
	data.strip_actions[part] = action
	return true


func set_global_action(control_id: String, action: String) -> bool:
	var c := Catalog.get_control(control_id)
	if c.is_empty() or c.strip != 0 or not ACTIONS.has(action) or STRIP_ONLY.has(action):
		return false
	data.global_actions[control_id] = action
	return true


func add_bank(name: String) -> int:
	var n := name.strip_edges().left(MAX_BANK_NAME)
	if n == "":
		n = "Bank %d" % (bank_count() + 1)
	data.banks.append({"name": n, "strips": {}})
	return bank_count() - 1


func rename_bank(i: int, name: String) -> bool:
	var n := name.strip_edges().left(MAX_BANK_NAME)
	if i < 0 or i >= bank_count() or n == "":
		return false
	data.banks[i].name = n
	return true


## The last bank cannot be removed.
func remove_bank(i: int) -> bool:
	if i < 0 or i >= bank_count() or bank_count() <= 1:
		return false
	data.banks.remove_at(i)
	return true


# ------------------------------------------------------------------ validation and files

static func validate(d: Variant) -> Array[String]:
	var p: Array[String] = []
	if typeof(d) != TYPE_DICTIONARY:
		return ["top level must be an object"]
	if int(d.get("schema", -1)) != SCHEMA:
		return ["unsupported schema %s (expected %d)" % [str(d.get("schema")), SCHEMA]]
	var ks: Variant = d.get("knob_scale", 1.0)
	if not (ks is float or ks is int) or float(ks) < 0.1 or float(ks) > 10.0:
		p.append("knob_scale must be a number between 0.1 and 10")
	if typeof(d.get("banks")) != TYPE_ARRAY or (d.banks as Array).is_empty():
		p.append("banks must be a non-empty list")
	else:
		for i in (d.banks as Array).size():
			p.append_array(_validate_bank(i, d.banks[i]))
	if typeof(d.get("strip_actions")) != TYPE_DICTIONARY:
		p.append("strip_actions must be an object")
	else:
		for part in d.strip_actions:
			if not STRIP_PARTS.has(String(part)):
				p.append("strip_actions: unknown button '%s' (use %s)" % [part, str(STRIP_PARTS)])
			elif not ACTIONS.has(String(d.strip_actions[part])):
				p.append("strip_actions.%s: unknown action '%s'" % [part, str(d.strip_actions[part])])
	if typeof(d.get("global_actions")) != TYPE_DICTIONARY:
		p.append("global_actions must be an object")
	else:
		for id in d.global_actions:
			var c := Catalog.get_control(String(id))
			var action := String(d.global_actions[id])
			if c.is_empty() or c.strip != 0:
				p.append("global_actions: '%s' is not a global button" % id)
			elif not ACTIONS.has(action):
				p.append("global_actions.%s: unknown action '%s'" % [id, action])
			elif STRIP_ONLY.has(action):
				p.append("global_actions.%s: '%s' only works on the per-strip buttons" % [id, action])
	return p


static func _validate_bank(i: int, b: Variant) -> Array[String]:
	var p: Array[String] = []
	if typeof(b) != TYPE_DICTIONARY:
		return ["banks[%d] must be an object" % i]
	var name: Variant = b.get("name")
	if not (name is String) or String(name).strip_edges() == "" or String(name).length() > MAX_BANK_NAME:
		p.append("banks[%d].name must be 1-%d characters" % [i, MAX_BANK_NAME])
	if typeof(b.get("strips")) != TYPE_DICTIONARY:
		p.append("banks[%d].strips must be an object" % i)
		return p
	for sk in b.strips:
		if not String(sk).is_valid_int() or int(String(sk)) < 1 or int(String(sk)) > Catalog.STRIPS:
			p.append("banks[%d]: strip '%s' must be 1-%d" % [i, sk, Catalog.STRIPS])
			continue
		var s: Variant = b.strips[sk]
		if typeof(s) != TYPE_DICTIONARY:
			p.append("banks[%d].strips.%s must be an object" % [i, sk])
			continue
		for kind in s:
			if not ["fader", "knob"].has(String(kind)):
				p.append("banks[%d].strips.%s: unknown slot '%s'" % [i, sk, kind])
			elif not (s[kind] is String) or not Registry.is_valid_key(String(s[kind])):
				p.append("banks[%d].strips.%s.%s: '%s' is not a valid target.parameter key" % [i, sk, kind, str(s[kind])])
	return p


## Loads and validates; on any problem the current data stays untouched. Returns {ok, errors, missing}.
func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["file not found: %s" % path], "missing": true}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"ok": false, "errors": ["not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]]}
	var problems := validate(json.data)
	if not problems.is_empty():
		return {"ok": false, "errors": problems}
	data = json.data
	data.knob_scale = float(data.get("knob_scale", 1.0))
	return {"ok": true, "errors": []}


func save_file(path: String) -> Dictionary:
	var problems := validate(data)
	if not problems.is_empty():
		return {"ok": false, "error": "refusing to save invalid bindings: %s" % problems[0]}
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
