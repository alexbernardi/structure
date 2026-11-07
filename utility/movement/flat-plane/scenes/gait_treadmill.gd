## Treadmill gait lab: the humanoid walks in place on a belt, seen from the side, with every variable of the walk on the
## MIDI controller (banks Walk Cycle / Pelvis & Torso / Feet & Arms / Toggles / View & Playback) and a measurement overlay.
## Presentation only: no physics body, no input to a simulation. The belt moves at exactly the walking speed, so a planted
## foot must stay still on it; the lab measures that on the real skeleton.
##
## Launch: godot --path utility/movement/flat-plane res://scenes/gait_treadmill.tscn
## Options: --no-tuning, --no-hardware, --no-window-state, --midi-config=<path>, --tuning-bindings=<path>,
##   --preset-dir=<path>, --tuning-state=<path>, --view=side|side-left|front|back|three-quarter,
##   --gait.<parameter>=<value> (e.g. --gait.freeze=1 --gait.scrub=0.25), --screenshot=<png> [--screenshot-frame=N],
##   --quit-after=<seconds>.
## Keys: Space freeze/resume, , and . step the frozen cycle, 1-5 camera views, +/- or wheel zoom, T belt, B body dynamics,
##   E edit the proportions by dragging handles (Backspace resets them), Ctrl+wheel resizes the character,
##   F3 HUD, F4 bindings editor, PgUp/PgDn bank, [ ] preset, F5 save preset, Home reset all, F6/F7/F8/F11 window.
extends Node3D

const Visual = preload("res://character/character_visual.gd")
const GaitParams = preload("res://animation/gait_params.gd")
const GaitModel = preload("res://animation/gait_model.gd")
const RigParams = preload("res://animation/rig_params.gd")
const RigEditor = preload("res://ui/rig_editor.gd")
const BodyParams = preload("res://animation/body_params.gd")
const BodyDynamics = preload("res://animation/body_dynamics.gd")
const Params = preload("res://movement/movement_params.gd")
const Actions = preload("res://movement/input_actions.gd")
const Midi = preload("res://midi/midi_manager.gd")
const Tuning = preload("res://tuning/tuning_system.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")
const Hud = preload("res://ui/tuning_hud.gd")
const Overlay = preload("res://ui/gait_overlay.gd")
const WindowState = preload("res://scenes/window_state.gd")

const BINDINGS_PATH := "res://config/gait_bindings.json"
const PRESET_DIR := "res://presets_gait"
const STATE_PATH := "user://tuning_state_gait.json"
const WINDOW_STATE_PATH := "user://window_state_gait.json"
const SPEED_ACCEL := 3.0          ## m/s^2: how fast the belt follows the walk speed setting (so changes are never a pop)
const BELT_LENGTH := 4.0
const STRIPE_SPACING := 0.25
const SCRUB_STEP := 1.0 / 48.0
const VIEWS := {
	"side": Vector3(5.0, 0.95, 0.0), "side-left": Vector3(-5.0, 0.95, 0.0),
	"front": Vector3(0.0, 0.95, -5.0), "back": Vector3(0.0, 0.95, 5.0),
	"three-quarter": Vector3(3.2, 1.3, -3.6),
}
const VIEW_KEYS := {KEY_1: "side", KEY_2: "side-left", KEY_3: "front", KEY_4: "back", KEY_5: "three-quarter"}

var gait_params = GaitParams.create()
var rig_params = RigParams.create()   ## proportions of the humanoid (limb lengths, widths, thickness)
var body_params = BodyParams.create()
var model
var dynamics
var visual
var cam: Camera3D
var midi
var tuning
var overlay
var rig_editor
var options := {}   ## overrides command-line options (used by tests)
var view := "side"
var speed := 0.0    ## the belt's (smoothed) speed
var belt_offset := 0.0
var slip_l := 0.0   ## measured foot slip on the belt, m/s (worst of the last second)
var slip_r := 0.0

var _args := {}
var _stripes: Array[Node3D] = []
var _rig_dirty := true
var _was_editing := false
var _froze_for_edit := false
var _prev_speed := 0.0
var _first := true
var _frames := 0
var _sole_prev := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # heel and toe of each foot
var _sole_valid := [false, false, false, false]
var _slip_peak := [0.0, 0.0]
var _slip_clock := 0.0


func _ready() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_args.merge(options, true)
	Actions.register()   # the tuning shortcuts (F3 F4 F5 PgUp PgDn [ ] Home) are input actions
	for k in _args:
		if String(k).begins_with("gait."):
			gait_params.set_value(String(k).substr(5), float(_args[k]))
		elif String(k).begins_with("body."):
			body_params.set_value(String(k).substr(5), float(_args[k]))
		elif String(k).begins_with("rig."):
			rig_params.set_value(String(k).substr(4), float(_args[k]))
	view = String(_args.get("view", "side"))
	if not VIEWS.has(view):
		view = "side"
	speed = float(gait_params.get_value("walk_speed"))
	_prev_speed = speed
	model = GaitModel.new(gait_params, rig_params)
	rig_params.changed.connect(func(_id: String, _v: float) -> void: _rig_dirty = true)
	dynamics = BodyDynamics.new(body_params)
	_build_world()
	visual = get_node("Visual")
	visual.apply_rig(rig_params)
	visual.walk_animation.setup(visual, model)
	cam = Camera3D.new()
	cam.name = "Camera"
	add_child(cam)
	cam.current = true
	_build_overlay()
	_apply_camera()
	_build_tuning()
	if DisplayServer.get_name() != "headless" and not _args.has("no-window-state"):
		var ws := WindowState.new()
		ws.name = "WindowState"
		add_child(ws)
		ws.attach(get_window(), String(_args.get("side", "left")), WINDOW_STATE_PATH)


# ------------------------------------------------------------------ world: a treadmill made of primitives

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 60.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)
	# belt surface at y = 0 (the character's feet), frame and rails below and beside it
	_box(Vector3(1.0, 0.12, BELT_LENGTH), Vector3(0, -0.06, 0), Color(0.17, 0.18, 0.2))
	_box(Vector3(1.3, 0.1, BELT_LENGTH + 0.2), Vector3(0, -0.17, 0), Color(0.28, 0.3, 0.34))
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.1, 0.16, BELT_LENGTH + 0.2), Vector3(sx * 0.6, -0.03, 0), Color(0.32, 0.34, 0.4))
	var n := int(BELT_LENGTH / STRIPE_SPACING)
	for i in n:
		var major := i % 2 == 0
		# a stripe across the belt, plus a mark on each rail so the belt's motion also reads when seen edge-on from the side
		var group := Node3D.new()
		add_child(group)
		var col := Color(0.8, 0.83, 0.9) if major else Color(0.45, 0.48, 0.55)
		_box(Vector3(0.9, 0.004, 0.025 if major else 0.012), Vector3(0, 0.002, 0), col, group)
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.012, 0.1 if major else 0.05, 0.03 if major else 0.016), Vector3(sx * 0.653, -0.03, 0), col, group)
		_stripes.append(group)
	_move_stripes()


func _move_stripes() -> void:
	for i in _stripes.size():
		var z := fposmod(float(i) * STRIPE_SPACING + belt_offset + BELT_LENGTH * 0.5, BELT_LENGTH) - BELT_LENGTH * 0.5
		_stripes[i].position.z = z
		_stripes[i].visible = gait_params.is_on("view_belt") or i == 0


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	overlay = Overlay.new()
	overlay.scene = self
	layer.add_child(overlay)
	rig_editor = RigEditor.new()
	rig_editor.scene = self
	layer.add_child(rig_editor)


# ------------------------------------------------------------------ camera

func _hud_width() -> float:
	if tuning == null or tuning.hud == null or not tuning.hud.visible:
		return 0.0
	return Hud.WIDTH + 30.0


func _apply_camera() -> void:
	var zoom: float = gait_params.get_value("view_zoom")
	var target := Vector3(0.0, 0.92 * float(rig_params.get_value("scale")), 0.0)
	var from: Vector3 = VIEWS[view]
	cam.global_position = from
	cam.look_at(target, Vector3.UP)
	var h_px := maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	if gait_params.is_on("view_ortho"):
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.3 / zoom
		cam.h_offset = _hud_width() * 0.5 * cam.size / h_px   # keep the character in the free part of the window
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 28.0 / zoom
		cam.h_offset = 0.0
	cam.near = 0.05
	cam.far = 40.0


func set_view(name: String) -> void:
	if VIEWS.has(name):
		view = name
		_apply_camera()
		if tuning != null:
			tuning.toast.emit("View: %s" % name, "info")


# ------------------------------------------------------------------ tuning

func _build_tuning() -> void:
	if _args.has("no-tuning"):
		return
	midi = Midi.new()
	midi.name = "Midi"
	add_child(midi)
	var hardware := not _args.has("no-hardware") and DisplayServer.get_name() != "headless"
	midi.autosave = not _args.has("midi-config")
	midi.start(String(_args.get("midi-config", "res://config/midi_mapping.json")), hardware)
	tuning = Tuning.new()
	tuning.name = "Tuning"
	add_child(tuning)
	var opts := {
		"no_ui": _args.has("no-tuning-ui") or DisplayServer.get_name() == "headless" and not _args.has("tuning-ui"),
		"no_movement": true, "default_bindings": Bindings.gait_data(),
		"bindings_path": String(_args.get("tuning-bindings", BINDINGS_PATH)),
		"preset_dir": String(_args.get("preset-dir", PRESET_DIR)),
		"state_path": String(_args.get("tuning-state", STATE_PATH)),
		"extra_targets": [["gait", "Gait (visual)", gait_params], ["rig", "Proportions (visual)", rig_params], ["body", "Body (visual)", body_params],
			["graph", "Animation graph", visual.walk_animation.params]],
	}
	tuning.setup(Params.new(), midi, opts)
	tuning.scene_action.connect(_on_tuning_action)
	tuning.editor_toggled.connect(func(_open: bool) -> void: _apply_camera())


func _on_tuning_action(action: String, _ctx: Dictionary) -> void:
	match action:
		"respawn":
			model.phase = 0.0
			_first = true
			tuning.toast.emit("Cycle restarted", "info")
		"teleport_next":
			set_view(_next_view(1))
		"teleport_prev":
			set_view(_next_view(-1))
		"record_toggle":
			tuning.toast.emit("Input recording is not available yet", "warn")


func _next_view(step: int) -> String:
	var names := VIEWS.keys()
	return String(names[(names.find(view) + step + names.size()) % names.size()])


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if rig_editor != null and rig_editor.handle_input(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if tuning != null and tuning.editor != null and tuning.editor.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var wheel := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0.0)
		if wheel != 0.0:
			if event.ctrl_pressed:   # Ctrl + wheel resizes the character itself
				rig_params.set_value("scale", float(rig_params.get_value("scale")) * pow(1.02, wheel))
			else:
				_nudge("view_zoom", pow(1.1, wheel))
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if VIEW_KEYS.has(event.keycode):
		set_view(VIEW_KEYS[event.keycode])
		return
	match event.keycode:
		KEY_SPACE:
			_toggle("freeze")
		KEY_COMMA:
			_step_scrub(-SCRUB_STEP)
		KEY_PERIOD:
			_step_scrub(SCRUB_STEP)
		KEY_EQUAL, KEY_KP_ADD:
			_nudge("view_zoom", 1.1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_nudge("view_zoom", 1.0 / 1.1)
		KEY_T:
			_toggle("view_belt")
		KEY_E:
			_toggle("edit_rig")
		KEY_B:
			_toggle("body_dynamics", true)


func _toggle(id: String, body := false) -> void:
	var ps = body_params if body else gait_params
	ps.set_value(id, 0.0 if ps.is_on(id) else 1.0)
	if tuning != null:
		tuning.toast.emit("%s %s" % [ps.def(id).label, "ON" if ps.is_on(id) else "off"], "info")


func _nudge(id: String, factor: float) -> void:
	gait_params.set_value(id, float(gait_params.get_value(id)) * factor)
	_apply_camera()


func _step_scrub(delta: float) -> void:
	if not gait_params.is_on("freeze"):
		gait_params.set_value("freeze", 1.0)
		gait_params.set_value("scrub", model.phase)
	gait_params.set_value("scrub", fposmod(float(gait_params.get_value("scrub")) + delta, 1.0))


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_frames += 1
	advance(delta)
	_apply_camera_if_changed()
	_measure_slip(delta)
	if _args.has("screenshot") and _frames == int(_args.get("screenshot-frame", 60)):
		get_viewport().get_texture().get_image().save_png(String(_args.screenshot))
		get_tree().quit()
	if _args.has("quit-after") and Time.get_ticks_msec() / 1000.0 > float(_args["quit-after"]):
		get_tree().quit()


var _last_cam_key := ""


func _apply_camera_if_changed() -> void:
	var key := "%s|%s|%s|%s" % [view, gait_params.get_value("view_zoom"), gait_params.is_on("view_ortho"), _hud_width()]
	if key != _last_cam_key:
		_last_cam_key = key
		_apply_camera()


## One rendered frame: the belt follows the speed setting, the model advances, the body model and the skeleton follow.
func advance(delta: float) -> void:
	visual.walk_animation.sync_parameters()
	_update_edit_mode()
	if _rig_dirty:
		_rig_dirty = false
		visual.apply_rig(rig_params)
	var target: float = gait_params.get_value("walk_speed")
	speed = target if _first else move_toward(speed, target, SPEED_ACCEL * delta)
	var graph_speed: float = visual.walk_animation.params.get_value("playback_speed")
	var scaled := delta * float(gait_params.get_value("time_scale")) * graph_speed
	var frozen: bool = gait_params.is_on("freeze")
	var pose: Dictionary = model.update(0.0 if frozen else delta * graph_speed, speed)
	if not frozen:
		belt_offset += speed * scaled
	_move_stripes()
	var accel := (speed - _prev_speed) / maxf(delta, 1e-4)
	_prev_speed = speed
	var kin := {"velocity": Vector3(0.0, 0.0, -speed), "accel": Vector3(0.0, 0.0, -accel), "heading": 0.0 if speed > 0.01 else NAN,
		"grounded": true, "gait_phase": float(pose.get("phase", 0.0)) * TAU, "gait_amount": float(pose.get("gait_amount", 0.0)), "teleported": _first}
	_first = false
	var state := {"speed": speed, "vy": 0.0, "grounded": true, "crouching": false, "accel_forward": accel,
		"heading": 0.0 if speed > 0.01 else NAN, "dyn": dynamics.update(delta, kin), "gait": pose}
	visual.global_position = Vector3.ZERO
	visual.update_pose(state, delta)


## Editing the proportions freezes the walk (a moving target is hard to drag) and resumes it afterwards, unless it was frozen already.
func _update_edit_mode() -> void:
	var editing: bool = gait_params.is_on("edit_rig")
	if editing and not _was_editing:
		_froze_for_edit = not gait_params.is_on("freeze")
		if _froze_for_edit:
			gait_params.set_value("scrub", model.phase)
			gait_params.set_value("freeze", 1.0)
	elif _was_editing and not editing and _froze_for_edit:
		gait_params.set_value("freeze", 0.0)
		_froze_for_edit = false
	_was_editing = editing


## Foot slip measured on the posed skeleton, not on the model: any heel or toe that is on the ground must travel with the belt.
func _measure_slip(delta: float) -> void:
	var pose: Dictionary = model.pose
	if not pose.get("active", false) or delta <= 0.0 or gait_params.is_on("freeze"):
		_sole_valid = [false, false, false, false]
		return
	var scaled := delta * float(gait_params.get_value("time_scale")) * float(visual.walk_animation.params.get_value("playback_speed"))
	for side in 2:
		var s := "l" if side == 0 else "r"
		var contact: bool = pose.contact_l if side == 0 else pose.contact_r
		var fp: Transform3D = visual.skeleton.get_bone_global_pose(visual.bone_index["foot_" + s])
		var points: Array[Vector3] = [
			visual.to_global(fp * Vector3(0.0, -model.cycle.ankle_h, -model.cycle.heel.x)),
			visual.to_global(fp * Vector3(0.0, -model.cycle.ankle_h, -model.cycle.toe.x))]
		for k in 2:
			var idx := side * 2 + k
			var planted: bool = contact and points[k].y < 0.002
			if planted and _sole_valid[idx]:
				# a planted point is carried backwards by the belt: in this frame it moves with +z at the belt speed
				var slip := absf((points[k].z - _sole_prev[idx].z) / scaled - speed)
				_slip_peak[side] = maxf(_slip_peak[side], slip)
			_sole_valid[idx] = planted
			_sole_prev[idx] = points[k]
	_slip_clock += delta
	if _slip_clock >= 1.0:
		slip_l = _slip_peak[0]
		slip_r = _slip_peak[1]
		_slip_peak = [0.0, 0.0]
		_slip_clock = 0.0
