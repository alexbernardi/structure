## Windowed player client. Presentation only: world changes arrive as server events applied to a
## read-only WorldState replica; local input becomes requests the server may accept or reject.
extends Node

const AppConfig = preload("res://core/app_config.gd")
const BuildInfo = preload("res://core/build_info.gd")
const InputSetup = preload("res://core/input_setup.gd")
const Log = preload("res://core/log.gd")
const Metrics = preload("res://core/metrics.gd")
const Protocol = preload("res://net/protocol.gd")
const WorldState = preload("res://world/world_state.gd")
const WorldView = preload("res://client/world_view.gd")
const PlayerController = preload("res://client/player_controller.gd")
const Hud = preload("res://client/hud.gd")
const ConnectMenu = preload("res://client/connect_menu.gd")

const STATE_SEND_HZ := 20.0
const PICK_CONE_DEG := 25.0

var cfg: Dictionary
var session: Node
var replica := WorldState.new()
var me := 0
var rules := {}
var view: WorldView
var player: PlayerController
var hud: Hud
var menu: ConnectMenu
var frame_stats := Metrics.FrameStats.new()

var _address := ""
var _joined := false
var _send_accum := 0.0
var _elapsed := 0.0
var _screenshot_done := false


func setup(config: Dictionary, session_node: Node) -> void:
	cfg = config
	session = session_node


func _ready() -> void:
	InputSetup.ensure_actions()
	if not cfg.vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_title("STRUCTURE sandbox %s" % BuildInfo.build_version())
	view = WorldView.new()
	add_child(view)
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	menu = ConnectMenu.new()
	ui.add_child(menu)
	menu.connect_requested.connect(_connect)
	session.welcome_received.connect(_on_welcome)
	session.event_received.connect(_on_event)
	session.players_received.connect(_on_players)
	session.correction_received.connect(_on_correction)
	session.connection_failed.connect(_on_connection_lost.bind("Connection failed"))
	session.disconnected.connect(_on_connection_lost.bind("Disconnected"))
	var default_name: String = cfg.name if cfg.name != "" else "player%03d" % (randi() % 1000)
	var default_port := int(ProjectSettings.get_setting("structure/network/default_port", 24565))
	menu.set_defaults(default_name, cfg.connect if cfg.connect != "" else "127.0.0.1:%d" % default_port)
	hud.set_status("Not connected")
	Log.event("client.started", {"build": BuildInfo.summary(), "renderer": RenderingServer.get_current_rendering_method()})
	if cfg.connect != "":
		_connect(cfg.connect, default_name)


func _connect(address: String, player_name: String) -> void:
	var addr := AppConfig.parse_address(address)
	if addr.is_empty():
		menu.show_status("Address must look like host:port")
		return
	var protocol: int = BuildInfo.protocol_version() if cfg.protocol_override < 0 else cfg.protocol_override
	var err: Error = session.start_client(addr.host, addr.port, Protocol.make_hello(protocol, BuildInfo.build_version(), player_name))
	if err != OK:
		menu.show_status("Could not start the client (error %d)" % err)
		return
	_address = address
	menu.show_status("Connecting to %s ..." % address)
	hud.set_status("Connecting to %s ..." % address)
	Log.event("client.connecting", {"address": address, "name": player_name})


func _on_welcome(payload: Dictionary) -> void:
	me = payload.you
	rules = payload.rules
	replica.load_snapshot(payload.snapshot)
	view.build_world(replica, me)
	if player != null:
		player.queue_free()
	player = PlayerController.new()
	player.movement_params = rules.movement
	view.add_child(player)
	var mine: Dictionary = replica.players[me]
	player.global_position = mine.pos
	player.rotation.y = mine.yaw
	_joined = true
	menu.visible = false
	_set_mouse_captured(true)
	Log.event("client.joined", {"peer": me, "name": payload.name, "env": payload.env, "server": payload.server,
		"players": replica.players.size(), "site_progress": _site_progress()})


func _on_event(e: Dictionary) -> void:
	if e.type == "rejected":
		hud.toast("Server rejected %s: %s" % [e.action, e.reason])
		Log.event("client.action_rejected", {"action": e.action, "target": e.target, "reason": e.reason})
		return
	if not _joined:
		return
	replica.apply_event(e)
	view.on_event(e, replica, me)
	match String(e.type):
		"resource_deposited":
			hud.toast("%s added a stone - structure now %d" % [e.by_name, e.deposited])
		"player_joined":
			if e.peer != me:
				hud.toast("%s joined" % e.name)
		"player_left":
			hud.toast("a player left")


func _on_players(states: Array) -> void:
	if _joined:
		replica.apply_player_states(states)
		view.update_players(replica, me)


func _on_correction(position: Vector3) -> void:
	if player != null:
		player.global_position = position
		player.velocity = Vector3.ZERO
		Log.event("client.position_corrected", {"position": position}, "debug")


func _on_connection_lost(reason: String, prefix: String) -> void:
	_joined = false
	_set_mouse_captured(false)
	if player != null:
		player.queue_free()
		player = null
	view.clear_world()
	menu.visible = true
	menu.show_status("%s: %s" % [prefix, reason])
	hud.set_status("Not connected")
	hud.set_prompt("")
	Log.event("client.connection_lost", {"reason": reason})


func _process(delta: float) -> void:
	frame_stats.record(delta)
	_elapsed += delta
	if _joined and player != null:
		_send_accum += delta
		if _send_accum >= 1.0 / STATE_SEND_HZ:
			_send_accum = 0.0
			session.send_state(player.global_position, player.rotation.y)
		var mine: Variant = replica.players.get(me)
		player.set_carrying(mine != null and mine.carrying != "")
		var target := _interaction_target()
		hud.set_prompt(target.get("label", "Carrying a stone - bring it to the structure   [Q] drop" if mine != null and mine.carrying != "" else ""))
		hud.set_status("%s  |  %s  |  players %d  |  structure %d" % [replica.players[me].name if mine else "?", _address,
			replica.players.size(), _site_progress()])
	if hud.debug_visible():
		hud.set_debug("FPS %d  frame %.2f ms\nphysics %.2f ms  draw calls %d\nRTT %d ms  nodes %d" % [
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), session.round_trip_ms(),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	_check_automation()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		hud.toggle_debug()
	if not _joined:
		return
	if event.is_action_pressed("release_mouse"):
		_set_mouse_captured(false)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_set_mouse_captured(true)
	elif event.is_action_pressed("interact"):
		var target := _interaction_target()
		if not target.is_empty():
			session.send_action(target.action, target.id)
	elif event.is_action_pressed("drop"):
		session.send_action(Protocol.ACTION_DROP, "")


## What [E] would do right now: deposit near the site while carrying, else the resource in view and range.
func _interaction_target() -> Dictionary:
	var mine: Variant = replica.players.get(me)
	if mine == null or player == null:
		return {}
	var feet := player.global_position
	if mine.carrying != "":
		for site in replica.sites.values():
			var d: Vector3 = feet - site.pos
			if Vector2(d.x, d.z).length() <= rules.deposit_range:
				return {"action": Protocol.ACTION_DEPOSIT, "id": site.id, "label": "[E] Deposit the stone into the structure"}
		return {}
	var eye := player.camera.global_position
	var forward := -player.camera.global_basis.z
	var best := {}
	var best_dist := INF
	for r in replica.resources.values():
		if int(r.carrier) != 0:
			continue
		var dist := feet.distance_to(r.pos)
		if dist > rules.interact_range or dist >= best_dist:
			continue
		if rad_to_deg(forward.angle_to(r.pos + Vector3(0, 0.2, 0) - eye)) > PICK_CONE_DEG:
			continue
		best_dist = dist
		best = {"action": Protocol.ACTION_PICKUP, "id": r.id, "label": "[E] Pick up stone"}
	return best


func _set_mouse_captured(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if player != null:
		player.look_enabled = on
	hud.set_crosshair(on)


func _site_progress() -> int:
	for site in replica.sites.values():
		return int(site.deposited)
	return 0


## --screenshot / --quit-after support for automated visual checks and client benchmarks.
func _check_automation() -> void:
	if cfg.screenshot != "" and not _screenshot_done and _elapsed >= cfg.screenshot_delay:
		_screenshot_done = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(cfg.screenshot)
		Log.event("client.screenshot", {"path": cfg.screenshot, "error": err, "joined": _joined})
		_quit()
	elif cfg.quit_after > 0.0 and _elapsed >= cfg.quit_after:
		_quit()


func _quit() -> void:
	set_process(false)
	Log.event("client.metrics", frame_stats.summary().merged({"joined": _joined, "rtt_ms": session.round_trip_ms(),
		"renderer": RenderingServer.get_current_rendering_method(), "vsync": cfg.vsync}))
	session.close()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
