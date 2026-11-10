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
const LocomotionParams = preload("res://animation/locomotion_params.gd")
const AuthoredVisual = preload("res://character/authored_mannequin.gd")
const AuthoredAnimation = preload("res://animation/authored_animation.gd")
const Bindings = preload("res://tuning/tuning_bindings.gd")
const TraversalParams = preload("res://traversal/traversal_params.gd")
const VaultProfile = preload("res://traversal/vault_profile.gd")
const VaultAction = preload("res://traversal/vault_action.gd")
const VaultDebug = preload("res://traversal/vault_debug.gd")
const VaultClip = preload("res://traversal/vault_clip.gd")

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
var locomotion_params = LocomotionParams.create()
var authored_visual
var authored_animation
var traversal_params = TraversalParams.create()   ## the four traversal controls plus the traversal / overlay switches
var vault_profile = VaultProfile.new()            ## the authored vault measured on the mannequin (invalid: no clip)
var vault = VaultAction.new()                     ## the body's physical vault action
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
var _vault_debug
var _side_cam := Camera3D.new()
var _side_offset := Vector3.RIGHT * 7.5
var _side_focus_y := NAN
const SIDE_FOLLOW_RATE := 5.0   ## 1/s: how quickly a side view's height follows the character


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
	authored_visual = AuthoredVisual.new()
	authored_visual.name = "AuthoredVisual"
	authored_visual.top_level = true
	authored_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _args.has("no-traversal-clip"):   # test aid: behave as if the traversal clips were not installed
		authored_visual.traversal_source = null
	body.add_child(authored_visual)
	authored_animation = AuthoredAnimation.new()
	authored_visual.add_child(authored_animation)
	authored_animation.setup(authored_visual, locomotion_params)
	vault_profile.build(authored_visual)
	var exclude: Array[RID] = [body.get_rid()]
	vault.setup(traversal_params, vault_profile, exclude)
	body.action = vault
	authored_animation.setup_traversal(traversal_params, vault_profile)

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
	_side_cam.name = "SideCamera"
	_side_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_side_cam.fov = 40.0
	add_child(_side_cam)
	_vault_debug = VaultDebug.new()
	_vault_debug.name = "TraversalDebug"
	add_child(_vault_debug)
	_vault_debug.setup(vault, body)
	if _args.has("traversal-debug"):
		traversal_params.set_value("debug_overlay", 1.0)
	if _args.has("no-traversal"):
		traversal_params.set_value("traversal", 0.0)

	_build_readout()
	_build_tuning()
	gait_params.set_value("run_mode", 1.0)
	if _args.has("legacy-animation"):
		locomotion_params.set_value("legacy", 1.0)
	locomotion_params.changed.connect(func(id: String, _value: float) -> void:
		if id == "legacy":
			_select_animation_system())
	_select_animation_system()
	if _args.has("landmark"):
		teleport_to(String(_args["landmark"]))
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
	var opts := {"no_ui": _args.has("no-tuning-ui") or DisplayServer.get_name() == "headless" and not _args.has("tuning-ui"),
		"bindings_path": "res://config/locomotion_bindings.json", "state_path": "user://tuning_state_locomotion.json",
		"default_bindings": Bindings.locomotion_data()}
	for pair in [["tuning-bindings", "bindings_path"], ["preset-dir", "preset_dir"], ["tuning-state", "state_path"]]:
		if _args.has(pair[0]):
			opts[pair[1]] = String(_args[pair[0]])
	opts["extra_targets"] = [["locomotion", "Authored animation", locomotion_params], ["traversal", "Traversal", traversal_params],
		["body", "Legacy body", body_params], ["gait", "Legacy gait", gait_params],
		["graph", "Legacy graph", visual.walk_animation.params]]
	tuning.setup(params, midi, opts)
	tuning.scene_action.connect(_on_tuning_action)
	tuning.editor_toggled.connect(_on_editor_toggled)


func _select_animation_system() -> void:
	var legacy: bool = locomotion_params.is_on("legacy")
	visual.visible = legacy
	visual.walk_animation.tree.active = legacy
	authored_animation.set_enabled(not legacy)
	dynamics.reset()
	_teleported = true


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
	teleport_to(names[_landmark_index])


## Moves the character to a named landmark (T / Shift+T cycle them; `--landmark=vault_a` starts at one). False if unknown.
func teleport_to(name: String) -> bool:
	var names := landmark_names()
	if not names.has(name):
		push_warning("Unknown landmark '%s'; known: %s" % [name, ", ".join(names)])
		return false
	_landmark_index = names.find(name)
	var yaw := 0.0
	if name.begins_with("stairs") or name.begins_with("vault"):
		yaw = -PI / 2.0
	elif name == "tunnel":
		yaw = PI
	body.teleport(world.landmarks[name] + Vector3(0.0, 0.05, 0.0))
	_teleported = true
	cam.yaw = yaw
	cam.snap()
	if tuning != null:
		tuning.toast.emit("Teleported to %s (%d/%d)" % [name, _landmark_index + 1, names.size()], "info")
	return true


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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9 and get_tree().current_scene == self and not (tuning != null and tuning.editor != null and tuning.editor.visible):
		var error := get_tree().change_scene_to_file("res://scenes/locomotion_comparison.tscn")
		if error != OK:
			push_error("Cannot open locomotion comparison: %s" % error_string(error))
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B and not (tuning != null and tuning.editor != null and tuning.editor.visible):
		toggle_body_dynamics()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		traversal_params.set_value("debug_overlay", 0.0 if traversal_params.is_on("debug_overlay") else 1.0)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V and not (tuning != null and tuning.editor != null and tuning.editor.visible):
		toggle_side_view()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T and not (tuning != null and tuning.editor != null and tuning.editor.visible):
		teleport_to_landmark(-1 if event.shift_pressed else 1)
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
	if not locomotion_params.is_on("legacy"):
		if tuning != null:
			tuning.toast.emit("B controls legacy body dynamics; select legacy animation to compare", "info")
		return
	var on: bool = body_params.is_on("body_dynamics")
	body_params.set_value("body_dynamics", 0.0 if on else 1.0)
	if tuning != null:
		tuning.toast.emit("Body dynamics %s" % ("off" if on else "ON"), "info")


## V: a side view square to the current camera heading (fixed while it is on), for inspecting the vault silhouette.
func toggle_side_view() -> void:
	if _side_cam.current:
		cam.camera.current = true
		return
	_side_cam.current = true
	_update_side_view(0.0)


func _update_side_view(delta: float) -> void:
	if delta <= 0.0:
		# Lane C needs a closer, wider outside view: the back wall is only 5 m away.
		var lane_c := _landmark_index == landmark_names().find("vault_c")
		var side := Vector3.LEFT * 4.0 if lane_c else Vector3.RIGHT * 7.5
		_side_offset = Basis(Vector3.UP, cam.yaw) * side
		_side_cam.fov = 60.0 if lane_c else 40.0
	var focus := side_focus(delta)
	_side_cam.global_position = focus + _side_offset + Vector3.UP * 0.3
	_side_cam.look_at(focus, Vector3.UP)


## Focus of a side view: follows where the character travels (the interpolated body plus the follow offset, not the
## collider's vault hump) and eases its height, so jumps and vaults read as arcs against a steady horizon.
## `delta` 0 snaps (on opening the view and after teleports).
func side_focus(delta: float) -> Vector3:
	var root: Vector3 = body.get_global_transform_interpolated().origin + body.follow_offset()
	if delta <= 0.0 or is_nan(_side_focus_y):
		_side_focus_y = root.y
	else:
		_side_focus_y = lerpf(_side_focus_y, root.y, 1.0 - exp(-SIDE_FOLLOW_RATE * delta))
	return Vector3(root.x, _side_focus_y + 0.9, root.z)


## One line describing the traversal state for the readout.
func traversal_status() -> String:
	if not vault.enabled():
		return "Traversal %s" % ("off" if vault_profile.valid else "unavailable (vault clip not installed)")
	var plan: Dictionary = vault.plan
	if vault.presenting:
		return "VAULT %s  clip %.2f/%.2f s  %.1f -> %.1f m/s  wall %.2f m x %.2f m  stretch %.2f  lean %.0f deg  hand error %.3f m" % [
			"(landing)" if not vault.active() else "", vault.time, VaultClip.LENGTH, vault.entry_speed, plan.exit_speed,
			plan.height, plan.depth, plan.stretch, rad_to_deg(plan.lean), authored_animation.hand_error]
	var counts := "   vaults %d  aborted %d" % [vault.vaults, vault.aborts]
	if vault.armed():
		return "Vault ARMED  takeoff in %.2f m (%.2f s)  %.1f -> %.1f m/s  gait phase %.2f (entry %.2f)  steer x%.2f%s" % [
			maxf(vault.face_distance - vault.takeoff, 0.0), authored_animation.takeoff_eta, vault.entry_speed, vault.travel_speed,
			authored_animation.gait_phase(), vault_profile.entry_phase, authored_animation.phase_steer, counts]
	var ahead: String = vault.reason if vault.reason != "" else "clear"
	return "Vault ready   ahead: %s%s" % [ahead.replace("_", " "), counts]


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
	gait_params.set_value("run_mode", 1.0)
	body.simulate(frame, dt)
	_accel_sum += body.core.acceleration
	_accel_ticks += 1


func _process(delta: float) -> void:
	_frames += 1
	var teleported := _teleported
	if Input.is_action_just_pressed("respawn"):
		body.respawn()
	var v: Vector3 = body.core.velocity
	var speed := Vector2(v.x, v.z).length()
	var heading := atan2(-v.x, -v.z) if speed > 0.01 else NAN
	var fwd_accel := 0.0
	if speed > 0.01:
		fwd_accel = Vector3(body.core.acceleration.x, 0, body.core.acceleration.z).dot(Vector3(v.x, 0, v.z).normalized())
	var visual_offset: Vector3 = body.presentation_offset()
	visual.follow(body, visual_offset.y)
	if not locomotion_params.is_on("legacy"):
		authored_animation.follow(body, visual_offset, _teleported, delta)
	if animation_enabled and not locomotion_params.is_on("legacy"):
		authored_animation.update(delta, {"speed": authored_animation.measured_speed, "vy": v.y, "grounded": body.core.grounded,
			"crouching": body.core.crouching and not vault.presenting, "accel_forward": fwd_accel, "heading": heading, "teleported": _teleported,
			"vault": vault.presentation(Engine.get_physics_interpolation_fraction())})
	elif animation_enabled:
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
	_vault_debug.visible = traversal_params.is_on("debug_overlay")
	if _vault_debug.visible:
		_vault_debug.redraw(Engine.get_physics_interpolation_fraction())
	if _side_cam.current:
		_update_side_view(0.0 if teleported else delta)
	_readout.text = "speed %.2f m/s   vy %+.2f   %s%s   [%s]\n%s\nWASD run   Mouse look   Space jump   Hold Shift to sprint (2x by default)   Ctrl/C crouch   R respawn   T/Shift+T landmarks (vault_a/b/c)   Run at a wall to vault\nEsc frees mouse   F3 HUD   F4 bindings   PgUp/PgDn bank   [ ] preset   F5 save   Home reset   F6/F7/F8 window   F9 A/B   F10 traversal debug   V side view   F11 fullscreen" % [
		speed, v.y, "grounded" if body.core.grounded else "airborne", "  crouching" if body.core.crouching and not vault.active() else "",
		"LEGACY" if locomotion_params.is_on("legacy") else "AUTHORED " + authored_animation.model.state, traversal_status()]
	if _args.has("screenshot") and _frames == int(_args.get("screenshot-frame", 90)):
		get_viewport().get_texture().get_image().save_png(String(_args.screenshot))
		get_tree().quit()
	if _args.has("quit-after") and Time.get_ticks_msec() / 1000.0 > float(_args["quit-after"]):
		get_tree().quit()
