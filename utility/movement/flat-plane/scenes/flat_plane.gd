## Flat-plane movement lab: composes the independent modules (world, collision body, humanoid visual, orbit camera,
## input source, movement parameters) into one launchable scene.
##   godot --path utility/movement/flat-plane res://scenes/flat_plane.tscn
## Options after `--`: --no-capture (keep the mouse free)  --no-animation (physics only)  --screenshot=<abs.png>  --quit-after=<seconds>
extends Node3D

const World = preload("res://world/flat_plane_world.gd")
const Body = preload("res://character/character_body.gd")
const Visual = preload("res://character/character_visual.gd")
const OrbitCamera = preload("res://character/orbit_camera.gd")
const Params = preload("res://movement/movement_params.gd")
const Actions = preload("res://movement/input_actions.gd")
const InputSource = preload("res://movement/input_source.gd")
const WindowState = preload("res://scenes/window_state.gd")
const Midi = preload("res://midi/midi_manager.gd")
const Tuning = preload("res://tuning/tuning_system.gd")
const BodyParams = preload("res://animation/body_params.gd")
const BodyDynamics = preload("res://animation/body_dynamics.gd")
const GaitParams = preload("res://animation/gait_params.gd")
const GaitModel = preload("res://animation/gait_model.gd")

var params: Params = Params.new()
var world
var body
var visual
var cam
var live = InputSource.Live.new()
var midi
var tuning
var body_params = BodyParams.create()   ## visual-only parameters, tuned like the movement ones (target "body")
var dynamics   ## BodyDynamics: the spring model that drives the torso, pelvis, head and arms
var gait_params = GaitParams.create()
var gait_model
## Procedural presentation on/off. The physical controller never reads it: with animation off the body moves identically.
var animation_enabled := true
var options := {}   ## overrides command-line options (used by tests)

var _args := {}
var _pending_impact := 0.0
var _accel_sum := Vector3.ZERO   # physics acceleration summed since the last rendered frame
var _accel_ticks := 0
var _teleported := false
var _frames := 0
var _readout: Label
var _landmark_index := 0


func _ready() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_args.merge(options, true)
	animation_enabled = not _args.has("no-animation")
	Actions.register()

	world = World.new()
	world.name = "World"
	add_child(world)
	world.build()

	body = Body.new()
	body.name = "Character"
	add_child(body)
	body.setup(params)
	body.spawn_transform = world.spawn_transform
	body.global_transform = world.spawn_transform
	body.landed.connect(func(impact: float) -> void: _pending_impact = impact)
	body.respawned.connect(func() -> void:
		cam.snap()
		_teleported = true)

	visual = get_node("Visual")
	visual.reparent(body)
	visual.apply_rig(null)   # sandbox collision and original visual proportions remain unchanged
	gait_model = GaitModel.new(gait_params)
	visual.walk_animation.setup(visual, gait_model)
	dynamics = BodyDynamics.new(body_params)

	cam = OrbitCamera.new()
	cam.name = "OrbitCamera"
	cam.target = body
	if _args.has("cam-yaw"):
		cam.yaw = deg_to_rad(float(_args["cam-yaw"]))
	if _args.has("cam-pitch"):
		cam.pitch = deg_to_rad(float(_args["cam-pitch"]))
	if _args.has("cam-distance"):
		cam.distance = float(_args["cam-distance"])
	add_child(cam)

	_build_readout()
	_build_tuning()
	if DisplayServer.get_name() != "headless" and not _args.has("no-window-state"):
		var ws := WindowState.new()
		ws.name = "WindowState"
		add_child(ws)
		ws.attach(get_window(), String(_args.get("side", "left")))
	if not _args.has("no-capture") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## MIDI controller + live tuning. Options: --no-tuning, --no-hardware (do not open MIDI inputs),
## --midi-config=<path> (mapping file; default config/midi_mapping.json), --tuning-bindings=<path>, --preset-dir=<path>.
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
	var opts := {"no_ui": _args.has("no-tuning-ui") or DisplayServer.get_name() == "headless" and not _args.has("tuning-ui")}
	for pair in [["tuning-bindings", "bindings_path"], ["preset-dir", "preset_dir"], ["tuning-state", "state_path"]]:
		if _args.has(pair[0]):
			opts[pair[1]] = String(_args[pair[0]])
	opts["extra_targets"] = [["body", "Body (visual)", body_params], ["gait", "Walk (visual)", gait_params],
		["graph", "Animation graph", visual.walk_animation.params]]
	tuning.setup(params, midi, opts)
	tuning.scene_action.connect(_on_tuning_action)
	tuning.editor_toggled.connect(_on_editor_toggled)


func _on_editor_toggled(open: bool) -> void:
	live.enabled = not open
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


## Things only the scene can do on behalf of controller buttons.
func _on_tuning_action(action: String, _ctx: Dictionary) -> void:
	match action:
		"respawn":
			body.respawn()
		"teleport_next":
			teleport_to_landmark(1)
		"teleport_prev":
			teleport_to_landmark(-1)
		"record_toggle":
			tuning.toast.emit("Input recording is not available yet", "warn")


func landmark_names() -> Array[String]:
	var out: Array[String] = ["spawn"]
	for k in world.landmarks:
		if k != "spawn":
			out.append(String(k))
	return out


## Moves the character to the next / previous test landmark (ramps, stairs, tunnel, ledge ...), facing it sensibly.
func teleport_to_landmark(step: int) -> void:
	var names := landmark_names()
	_landmark_index = (_landmark_index + step + names.size()) % names.size()
	var name := names[_landmark_index]
	var yaw := 0.0
	if name.begins_with("stairs"):
		yaw = -PI / 2.0
	elif name == "tunnel":
		yaw = PI
	body.teleport(world.landmarks[name] + Vector3(0.0, 0.05, 0.0))
	_teleported = true
	cam.yaw = yaw
	cam.snap()
	if tuning != null:
		tuning.toast.emit("Teleported to %s (%d/%d)" % [name, _landmark_index + 1, names.size()], "info")


func _build_readout() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_readout = Label.new()
	_readout.position = Vector2(12, 10)
	_readout.add_theme_font_size_override("font_size", 16)
	_readout.add_theme_color_override("font_outline_color", Color.BLACK)
	_readout.add_theme_constant_override("outline_size", 6)
	layer.add_child(_readout)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B and not (tuning != null and tuning.editor != null and tuning.editor.visible):
		toggle_body_dynamics()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _args.has("no-capture") and not (tuning != null and tuning.editor != null and tuning.editor.visible):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Losing focus (alt-tab, clicking another window) frees the mouse so the window can be moved and resized.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## B: the spring body model on / off (off = the original simple pose). Physics is unaffected either way.
func toggle_body_dynamics() -> void:
	var on: bool = body_params.is_on("body_dynamics")
	body_params.set_value("body_dynamics", 0.0 if on else 1.0)
	if tuning != null:
		tuning.toast.emit("Body dynamics %s" % ("off" if on else "ON"), "info")


func _physics_process(dt: float) -> void:
	var frame: Dictionary = live.sample(cam.yaw)
	if _args.has("autowalk"):   # smoke/screenshot aid: walk forward and sprint without a keyboard
		frame.move = Vector2(0, 1)
		frame.yaw = 0.0   # fixed heading (-Z) so the camera options can frame the character from any side
		frame.sprint = true
		frame.jump_pressed = _args.has("autojump") and Engine.get_physics_frames() % 90 == 0
	simulate_tick(frame, dt)


## One physics tick of the body, plus the acceleration bookkeeping the (visual-only) body model reads next frame.
func simulate_tick(frame: Dictionary, dt: float) -> void:
	body.simulate(frame, dt)
	_accel_sum += body.core.acceleration
	_accel_ticks += 1


func _process(delta: float) -> void:
	_frames += 1
	if Input.is_action_just_pressed("respawn"):
		body.respawn()
	var v: Vector3 = body.core.velocity
	var speed := Vector2(v.x, v.z).length()
	var heading := atan2(-v.x, -v.z) if speed > 0.01 else NAN
	var fwd_accel := 0.0
	if speed > 0.01:
		fwd_accel = Vector3(body.core.acceleration.x, 0, body.core.acceleration.z).dot(Vector3(v.x, 0, v.z).normalized())
	var visual_offset: float = body.step_offset
	visual.follow(body, visual_offset)
	if animation_enabled:
		visual.walk_animation.sync_parameters()
		var pose: Dictionary = gait_model.update(delta * float(visual.walk_animation.params.get_value("playback_speed")), speed)
		var state := {"speed": speed, "vy": v.y, "grounded": body.core.grounded, "crouching": body.core.crouching,
			"accel_forward": fwd_accel, "heading": heading, "landed_impact": _pending_impact, "gait": pose}
		# The model sees the mean acceleration of the physics ticks since the last frame, so it does not depend on how
		# many ticks happened to fall in this frame.
		var accel := _accel_sum / float(_accel_ticks) if _accel_ticks > 0 else Vector3.ZERO
		state["dyn"] = dynamics.update(delta, {"velocity": v, "accel": Vector3(accel.x, 0.0, accel.z), "heading": heading,
			"grounded": body.core.grounded, "gait_phase": float(pose.get("phase", 0.0)) * TAU, "gait_amount": float(pose.get("gait_amount", 0.0)),
			"landed_impact": _pending_impact, "teleported": _teleported})
		visual.update_pose(state, delta)
	_pending_impact = 0.0
	_teleported = false
	_accel_sum = Vector3.ZERO
	_accel_ticks = 0
	_readout.text = "speed %.2f m/s   vy %+.2f   %s%s\nWASD move   Mouse look   Space jump   Shift sprint   Ctrl/C crouch   R respawn\nEsc frees the mouse   F3 HUD   F4 bindings   PgUp/PgDn bank   [ ] preset   F5 save   Home reset all   B body dynamics   F6/F7/F8 window   F11 fullscreen" % [
		speed, v.y, "grounded" if body.core.grounded else "airborne", "  crouching" if body.core.crouching else ""]
	if _args.has("screenshot") and _frames == int(_args.get("screenshot-frame", 90)):
		get_viewport().get_texture().get_image().save_png(String(_args.screenshot))
		get_tree().quit()
	if _args.has("quit-after") and Time.get_ticks_msec() / 1000.0 > float(_args["quit-after"]):
		get_tree().quit()
