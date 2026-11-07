## Flat-plane movement lab: composes the independent modules (world, collision body, humanoid visual, orbit camera,
## input source, movement parameters) into one launchable scene.
##   godot --path utility/movement/flat-plane res://scenes/flat_plane.tscn
## Options after `--`: --no-capture (keep the mouse free)  --screenshot=<abs.png>  --quit-after=<seconds>
extends Node3D

const World = preload("res://world/flat_plane_world.gd")
const Body = preload("res://character/character_body.gd")
const Visual = preload("res://character/character_visual.gd")
const OrbitCamera = preload("res://character/orbit_camera.gd")
const Params = preload("res://movement/movement_params.gd")
const Actions = preload("res://movement/input_actions.gd")
const InputSource = preload("res://movement/input_source.gd")
const WindowState = preload("res://scenes/window_state.gd")

var params: Params = Params.new()
var world
var body
var visual
var cam
var live = InputSource.Live.new()
var options := {}   ## overrides command-line options (used by tests)

var _args := {}
var _pending_impact := 0.0
var _frames := 0
var _readout: Label


func _ready() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_args.merge(options, true)
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
	body.respawned.connect(func() -> void: cam.snap())

	visual = Visual.new()
	visual.name = "Visual"
	body.add_child(visual)

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
	if DisplayServer.get_name() != "headless" and not _args.has("no-window-state"):
		var ws := WindowState.new()
		ws.name = "WindowState"
		add_child(ws)
		ws.attach(get_window(), String(_args.get("side", "left")))
	if not _args.has("no-capture") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _args.has("no-capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Losing focus (alt-tab, clicking another window) frees the mouse so the window can be moved and resized.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(dt: float) -> void:
	var frame: Dictionary = live.sample(cam.yaw)
	if _args.has("autowalk"):   # smoke/screenshot aid: walk forward and sprint without a keyboard
		frame.move = Vector2(0, 1)
		frame.yaw = 0.0   # fixed heading (-Z) so the camera options can frame the character from any side
		frame.sprint = true
		frame.jump_pressed = _args.has("autojump") and Engine.get_physics_frames() % 90 == 0
	body.simulate(frame, dt)


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
	visual.update_pose({"speed": speed, "vy": v.y, "grounded": body.core.grounded, "crouching": body.core.crouching,
		"accel_forward": fwd_accel, "heading": heading, "landed_impact": _pending_impact}, delta)
	_pending_impact = 0.0
	_readout.text = "speed %.2f m/s   vy %+.2f   %s%s\nWASD move   Mouse look   Space jump   Shift sprint   Ctrl/C crouch   R respawn\nEsc frees the mouse (then drag / resize the window; click the view to recapture)   F6 left  F7 right  F8 centre  F11 fullscreen" % [
		speed, v.y, "grounded" if body.core.grounded else "airborne", "  crouching" if body.core.crouching else ""]
	if _args.has("screenshot") and _frames == int(_args.get("screenshot-frame", 90)):
		get_viewport().get_texture().get_image().save_png(String(_args.screenshot))
		get_tree().quit()
	if _args.has("quit-after") and Time.get_ticks_msec() / 1000.0 > float(_args["quit-after"]):
		get_tree().quit()
