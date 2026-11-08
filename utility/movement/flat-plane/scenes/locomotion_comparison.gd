## Independent physics worlds receive the same recorded input frame and the same parameter object.
extends Control

const Playground = preload("res://scenes/flat_plane.tscn")
const TrialPath := "res://config/locomotion_trial.json"

var left
var right
var frames: Array = []
var cursor := 0
var paused := false
var _cameras: Array[Camera3D] = []
var _ready_for_trial := false
var _render_frames := 0
var _options := {}


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair := arg.trim_prefix("--").split("=", true, 1)
			_options[pair[0]] = pair[1] if pair.size() > 1 else "true"
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(TrialPath)) != OK or not parser.data is Dictionary:
		push_error("Invalid locomotion recording: %s" % parser.get_error_message())
		get_tree().quit(1)
		return
	var data: Dictionary = parser.data
	if data.get("schema") != 1 or data.get("hz") != Engine.physics_ticks_per_second or not data.get("frames") is Array:
		push_error("Locomotion recording schema/rate mismatch; expected 120 Hz recording")
		get_tree().quit(1)
		return
	frames = data.frames
	if frames.is_empty() or frames.any(func(frame: Variant) -> bool: return not frame is Array or frame.size() != 7):
		push_error("Locomotion recording contains malformed frames")
		get_tree().quit(1)
		return
	right = Playground.instantiate()
	left = Playground.instantiate()
	left.params = right.params
	left.options = {"no-tuning": "true", "no-capture": "true", "no-window-state": "true", "legacy-animation": "true"}
	right.options = {"no-capture": "true", "no-window-state": "true", "tuning-state": "user://tuning_state_comparison.json"}
	if _options.has("no-hardware"):
		right.options["no-hardware"] = "true"
	for pair in [[left, $Views/A/Viewport], [right, $Views/B/Viewport]]:
		var scene: Node = pair[0]
		pair[1].add_child(scene)
		scene.set_physics_process(false)
		scene.set_process(false)
		scene.live.enabled = false
		scene.cam.set_process(false)
		scene._readout.hide()
		scene._args.erase("screenshot")
		scene._args.erase("quit-after")
		var camera := Camera3D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		scene.add_child(camera)
		camera.current = true
		camera.fov = 34.0
		_cameras.append(camera)
	right.tuning.engine.switch_bank(3)
	right.tuning.scene_action.disconnect(right._on_tuning_action)
	right.tuning.scene_action.connect(func(action: String, context: Dictionary) -> void:
		if action in ["respawn", "teleport_next", "teleport_prev"]:
			left._on_tuning_action(action, context)
		right._on_tuning_action(action, context))
	if right.tuning.hud != null:
		right.tuning.hud.cycle()
	$Controls/Toolbar/Pause.toggled.connect(func(value: bool) -> void: paused = value)
	$Controls/Toolbar/Replay.pressed.connect(restart)
	$Controls/Toolbar/System.toggled.connect(func(value: bool) -> void: right.locomotion_params.set_value("legacy", 1.0 if value else 0.0))
	$Controls/Toolbar/Playground.pressed.connect(func() -> void:
		var error := get_tree().change_scene_to_packed(Playground)
		if error != OK:
			push_error("Cannot open Playground: %s" % error_string(error)))
	restart()
	_ready_for_trial = true


static func input_frame(record: Array) -> Dictionary:
	return {"move": Vector2(record[0], record[1]), "yaw": float(record[2]), "sprint": bool(record[3]),
		"jump_pressed": bool(record[4]), "jump_held": bool(record[5]), "crouch": bool(record[6])}


func restart() -> void:
	cursor = 0
	for scene in [left, right]:
		scene.body.teleport(Vector3(150, 0.05, 150))
		scene._teleported = true
		scene.gait_model.phase = 0.0
		scene.dynamics.reset()
	right.authored_animation.playback.start("Idle")
	right.authored_animation.model.run_weight = 0.0
	right.authored_animation.model.sprint_blend = 0.0


func _physics_process(dt: float) -> void:
	if not _ready_for_trial or paused:
		return
	if cursor == frames.size():
		restart()
	var frame := input_frame(frames[cursor])
	left.simulate_tick(frame, dt)
	right.simulate_tick(frame, dt)
	cursor += 1


func _process(dt: float) -> void:
	if not _ready_for_trial:
		return
	for i in 2:
		var scene: Node = left if i == 0 else right
		if not paused:
			scene._process(dt)
		var body_position: Vector3 = scene.body.get_global_transform_interpolated().origin
		_cameras[i].position = body_position + Vector3(-5.0, 1.0, 0.0)
		_cameras[i].look_at(body_position + Vector3.UP)
	var separation: float = left.body.global_position.distance_to(right.body.global_position)
	$Controls/Toolbar/System.set_pressed_no_signal(right.locomotion_params.is_on("legacy"))
	$Controls/Status.text = "A: LEGACY   |   B: %s   |   %.2f m/s   |   frame %d/%d   |   physics difference %.6f m" % [
		"LEGACY" if right.locomotion_params.is_on("legacy") else "AUTHORED " + right.authored_animation.model.state,
		right.body.core.horizontal_speed(), cursor, frames.size(), separation]
	_render_frames += 1
	if _options.has("screenshot") and _render_frames == int(_options.get("screenshot-frame", 360)):
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(_options.screenshot)
		if error != OK:
			push_error("Comparison capture failed: %s" % error_string(error))
		get_tree().quit(0 if error == OK else 1)
