## Composes the tuning pieces for a running scene: registry + bindings + engine + presets + UI, wired to a MIDI
## manager. The scene provides what only it can do (respawn, teleport, recording) by listening to `scene_action`.
extends Node

const Engine_ = preload("res://tuning/tuning_engine.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")
const Registry = preload("res://tuning/tunable_registry.gd")
const Presets = preload("res://tuning/preset_store.gd")
const Hud = preload("res://ui/tuning_hud.gd")
const Editor = preload("res://ui/binding_editor.gd")
const Events = preload("res://midi/midi_events.gd")
const Catalog = preload("res://midi/control_catalog.gd")

signal scene_action(action: String, context: Dictionary)
signal editor_toggled(open: bool)
signal toast(text: String, level: String)

const DEFAULT_STATE_PATH := "user://tuning_state.json"
const PROTECTED_PRESET := "default"

var registry = Registry.new()
var bindings = Bindings.new()
var engine
var presets
var midi
var hud
var editor
var load_errors: Array[String] = []
var bindings_path := Bindings.DEFAULT_PATH
var state_path := DEFAULT_STATE_PATH
var last_midi_text := ""

var _ui_layer: CanvasLayer


## `opts`: bindings_path, preset_dir, state_path ("" = do not remember), no_ui (tests), extra_targets (Array of
## [name, label, source]) registered before the bindings are checked so other systems' parameters can be bound,
## no_movement (do not register the movement parameters), default_bindings (data used when the bindings file is missing).
func setup(params, midi_manager: Node, opts := {}) -> void:
	midi = midi_manager
	bindings_path = String(opts.get("bindings_path", Bindings.DEFAULT_PATH))
	state_path = String(opts.get("state_path", DEFAULT_STATE_PATH))
	presets = Presets.new(String(opts.get("preset_dir", Presets.DEFAULT_DIR)))
	if not opts.get("no_movement", false):
		registry.register("movement", "Movement", params)
	if opts.has("default_bindings"):
		bindings.data = opts.default_bindings.duplicate(true)
	for t in opts.get("extra_targets", []):
		registry.register(String(t[0]), String(t[1]), t[2])
	var r: Dictionary = bindings.load_file(bindings_path)
	if not r.ok and not r.get("missing", false):
		load_errors = r.errors   # keep the defaults in memory; the bad file is not overwritten until the user saves
	engine = Engine_.new(registry, bindings)
	midi.control_changed.connect(engine.on_control)
	midi.raw_event.connect(_on_raw_event)
	engine.action_requested.connect(_on_action)
	if not opts.get("no_ui", false):
		_build_ui()
	_restore_state()
	for k in bindings.unresolved(registry):
		_say("Binding to unknown parameter %s is inactive" % k, "warn")
	if not load_errors.is_empty():
		_say("tuning_bindings.json rejected: %s" % load_errors[0], "error")


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	hud = Hud.new()
	hud.bind(self)
	_ui_layer.add_child(hud)
	editor = Editor.new()
	editor.visible = false
	_ui_layer.add_child(editor)
	editor.build(self)


func _on_raw_event(ev: Dictionary, accepted: bool, _port: String) -> void:
	if accepted:
		var id: String = midi.config.find_by_sig(ev.sig)
		last_midi_text = "%s%s" % [Events.describe(ev).strip_edges(), "  ->  " + Catalog.get_control(id).label if id != "" else "  (unmapped)"]


func _say(text: String, level := "info") -> void:
	toast.emit(text, level)
	if hud != null:
		hud.notify(text, level)


# ------------------------------------------------------------------ keyboard parity with the controller buttons

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action("toggle_editor"):
		toggle_editor()
	elif editor != null and editor.visible:
		return   # typing into the editor must not trigger shortcuts
	elif event.is_action("bank_next"):
		engine.run_action("bank_next")
	elif event.is_action("bank_prev"):
		engine.run_action("bank_prev")
	elif event.is_action("reset_all_params"):
		engine.run_action("reset_all")
	elif event.is_action("preset_next"):
		engine.run_action("preset_next")
	elif event.is_action("preset_prev"):
		engine.run_action("preset_prev")
	elif event.is_action("preset_save"):
		engine.run_action("preset_save")
	elif event.is_action("toggle_hud"):
		engine.run_action("hud_cycle")


func toggle_editor() -> void:
	if editor == null:
		return
	editor.visible = not editor.visible
	if editor.visible:
		editor.refresh()
	editor_toggled.emit(editor.visible)


# ------------------------------------------------------------------ actions

func _on_action(action: String, ctx: Dictionary) -> void:
	match action:
		"preset_next":
			cycle_preset(1)
		"preset_prev":
			cycle_preset(-1)
		"preset_save":
			save_current_preset()
		"hud_cycle":
			if hud != null:
				hud.cycle()
		_:
			scene_action.emit(action, ctx)


func cycle_preset(step: int) -> void:
	var name: String = presets.next_name(engine.preset_name, step)
	if name == "":
		_say("No presets saved yet", "warn")
		return
	load_preset(name)


func load_preset(name: String) -> bool:
	var r: Dictionary = presets.load_preset(name, registry)
	if not r.ok:
		_say(r.error, "error")
		return false
	var res: Dictionary = engine.apply_values(r.targets, name)
	var extra := ""
	if not res.skipped_locked.is_empty():
		extra += "  (%d locked kept)" % res.skipped_locked.size()
	if not r.warnings.is_empty():
		extra += "  (%d value(s) clamped or ignored)" % r.warnings.size()
	_say("Preset '%s' loaded%s" % [name, extra], "warn" if extra != "" else "ok")
	save_state()
	return true


func save_current_preset() -> void:
	var name: String = engine.preset_name
	if name == "" or name == PROTECTED_PRESET:
		name = "tuned_%s" % Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	save_preset_as(name)


func save_preset_as(raw_name: String) -> Dictionary:
	if Presets.sanitize_name(raw_name) == PROTECTED_PRESET:
		_say("'%s' is the factory default and cannot be overwritten; choose another name" % PROTECTED_PRESET, "error")
		return {"ok": false, "error": "protected name"}
	var r: Dictionary = presets.save_preset(raw_name, registry.capture())
	if r.ok:
		engine.mark_saved(r.name)
		_say("Saved preset '%s'" % r.name, "ok")
		save_state()
	else:
		_say(r.error, "error")
	return r


func delete_preset(name: String) -> bool:
	if Presets.sanitize_name(name) == PROTECTED_PRESET:
		_say("The factory default preset cannot be deleted", "error")
		return false
	var ok: bool = presets.delete_preset(name)
	if ok and engine.preset_name == name:
		engine.preset_name = ""
		engine.state_changed.emit()
	_say("Deleted preset '%s'" % name if ok else "No preset '%s'" % name, "ok" if ok else "warn")
	return ok


func save_bindings() -> Dictionary:
	var r: Dictionary = bindings.save_file(bindings_path)
	_say("Bindings saved" if r.ok else r.error, "ok" if r.ok else "error")
	return r


func reload_bindings() -> Dictionary:
	var r: Dictionary = bindings.load_file(bindings_path)
	if r.ok:
		engine.bank = clampi(engine.bank, 0, bindings.bank_count() - 1)
		engine.rearm_all()
		engine.state_changed.emit()
	_say("Bindings reloaded" if r.ok else "Reload failed: %s" % r.errors[0], "ok" if r.ok else "error")
	return r


# ------------------------------------------------------------------ remembered session

func save_state() -> void:
	if state_path == "":
		return
	var f := FileAccess.open(state_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"preset": engine.preset_name, "bank": engine.bank}))
		f.close()


func _restore_state() -> void:
	if state_path == "" or not FileAccess.file_exists(state_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(state_path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var name := String(json.data.get("preset", ""))
	if name != "" and presets.exists(name):
		load_preset(name)
	var b := int(json.data.get("bank", 0))
	if b > 0 and b < bindings.bank_count():
		engine.switch_bank(b)


func _exit_tree() -> void:
	if engine != null:
		save_state()
