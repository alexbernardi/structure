## Dedicated authoritative server. Owns the WorldState; clients only send requests.
## Tick order: position reports -> action requests -> player-state broadcast -> save (if dirty).
## Runtime files in <data_dir>/runtime: status.json (heartbeat lease), shutdown.request (graceful stop).
extends Node

const Log = preload("res://core/log.gd")
const BuildInfo = preload("res://core/build_info.gd")
const Metrics = preload("res://core/metrics.gd")
const Protocol = preload("res://net/protocol.gd")
const WorldGen = preload("res://world/world_gen.gd")
const WorldState = preload("res://world/world_state.gd")
const WorldStore = preload("res://world/world_store.gd")

const HEARTBEAT_S := 1.0
const LEASE_OBSERVE_S := 3.0
const MAX_ACTIONS_PER_TICK := 8
const MAX_VIOLATIONS := 50

var cfg: Dictionary
var session: Node
var state: WorldState
var store: WorldStore
var metrics := Metrics.ServerMetrics.new()

var _instance_id := ""
var _started_unix := 0.0
var _dirty := false
var _stopping := false
var _ready_to_serve := false
var _next_slot := 0
var _pending_moves := {}      # peer -> [pos, yaw, received_ms]
var _pending_actions := []    # [peer, action, target]
var _actions_this_tick := {}  # peer -> count
var _violations := {}         # peer -> count
var _counters := {"actions_ok": 0, "actions_rejected": 0, "moves_rejected": 0, "violations": 0, "saves": 0, "save_errors": 0}
var _sync_accum := 0.0
var _heartbeat_accum := 0.0
var _metrics_accum := 0.0


func setup(config: Dictionary, session_node: Node) -> void:
	cfg = config
	session = session_node


func _ready() -> void:
	Engine.physics_ticks_per_second = cfg.tick_rate
	Engine.max_fps = cfg.tick_rate  # headless: do not spin between ticks
	_started_unix = Time.get_unix_time_from_system()
	_instance_id = "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	Log.event("server.starting", {"build": BuildInfo.summary(), "world": cfg.world_id, "seed": cfg.seed,
		"port": cfg.port, "bind": cfg.bind_ip, "data_dir": cfg.data_dir, "tick_rate": cfg.tick_rate, "pid": OS.get_process_id()})
	DirAccess.make_dir_recursive_absolute(_runtime_dir())
	if await _data_dir_in_use():
		_fail("data_dir_in_use", 3, "another server holds the lease on %s" % _runtime_dir().path_join("status.json"))
		return
	DirAccess.remove_absolute(_runtime_dir().path_join("shutdown.request"))
	store = WorldStore.new(cfg.data_dir.path_join("world"))
	var loaded := store.load_or_create(cfg.world_id, cfg.seed)
	if not loaded.ok:
		_fail("world_load_failed", 4, loaded.error)
		return
	state = loaded.state
	if state.world_seed != cfg.seed:
		Log.event("server.seed_ignored", {"configured": cfg.seed, "world_seed": state.world_seed,
			"note": "an existing world keeps its original seed"}, "warn")
	if loaded.created or loaded.recovered or loaded.migrated_from > 0:
		_save()
	Log.event("world.loaded", {"created": loaded.created, "recovered": loaded.recovered, "migrated_from": loaded.migrated_from,
		"revision": state.revision, "resources": state.resources.size(), "site_progress": _site_progress(),
		"file": store.file_path()})
	session.accept_hello = _accept_hello
	session.peer_joined.connect(_on_peer_joined)
	session.peer_left.connect(_on_peer_left)
	session.state_reported.connect(_on_state_reported)
	session.action_requested.connect(_on_action_requested)
	session.violation.connect(_on_violation)
	# Spare transport slots let over-capacity clients reach auth and receive an explicit "server_full".
	var err: Error = session.start_server(cfg.port, cfg.bind_ip, mini(cfg.max_players + 4, 4095))
	if err != OK:
		_fail("listen_failed", 5, "cannot listen on %s:%d/udp (error %d)" % [cfg.bind_ip, cfg.port, err])
		return
	_write_status()
	_ready_to_serve = true
	Log.event("server.ready", {"port": cfg.port, "world": state.world_id, "seed": state.world_seed,
		"protocol": BuildInfo.protocol_version(), "world_schema": BuildInfo.world_schema_version(),
		"site_progress": _site_progress(), "max_players": cfg.max_players})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown("close_request")


func _physics_process(delta: float) -> void:
	if not _ready_to_serve or _stopping:
		return
	var t0 := Time.get_ticks_usec()
	_process_moves()
	_process_actions()
	_sync_accum += delta
	if _sync_accum >= 1.0 / cfg.sync_rate:
		_sync_accum = 0.0
		if not state.players.is_empty():
			session.broadcast_players(state.player_states())
	if _dirty:
		_save()
	_heartbeat_accum += delta
	if _heartbeat_accum >= HEARTBEAT_S:
		_heartbeat_accum = 0.0
		_write_status()
		if FileAccess.file_exists(_runtime_dir().path_join("shutdown.request")):
			shutdown("shutdown_request")
			return
	metrics.record_tick(Time.get_ticks_usec() - t0)
	if cfg.metrics_interval > 0.0:
		_metrics_accum += delta
		if _metrics_accum >= cfg.metrics_interval:
			var fields := metrics.collect(state.players.size(), state.entity_count(), session.pop_net_rates(_metrics_accum))
			fields.merge(_counters)
			Log.event("server.metrics", fields)
			_metrics_accum = 0.0


func shutdown(reason: String) -> void:
	if _stopping:
		return
	_stopping = true
	Log.event("server.stopping", {"reason": reason, "players": state.players.size() if state else 0})
	if state != null:
		for peer in state.players.keys():
			_commit(state.player_leave(peer))
		if _dirty:
			_save()
	session.close()
	DirAccess.remove_absolute(_runtime_dir().path_join("status.json"))
	DirAccess.remove_absolute(_runtime_dir().path_join("shutdown.request"))
	Log.event("server.stopped", {"reason": reason, "revision": state.revision if state else -1,
		"saves": _counters.saves, "uptime_s": Time.get_unix_time_from_system() - _started_unix})
	get_tree().quit(0)


# ------------------------------------------------------------------------------------------ session events

func _accept_hello(peer_id: int, hello: Dictionary) -> Dictionary:
	if _stopping or not _ready_to_serve:
		return {"ok": false, "reason": "not_ready"}
	if hello.protocol != BuildInfo.protocol_version():
		return {"ok": false, "reason": "protocol_mismatch", "info": {"server_protocol": BuildInfo.protocol_version(),
			"server_build": BuildInfo.build_version()}}
	if state.players.size() >= cfg.max_players:
		return {"ok": false, "reason": "server_full"}
	return {"ok": true, "name": _unique_name(hello.name), "info": {"server_build": BuildInfo.build_version()}}


func _on_peer_joined(peer_id: int, hello: Dictionary) -> void:
	var pos := WorldGen.spawn_point(_next_slot)
	_next_slot += 1
	var events := state.player_join(peer_id, hello.name, pos, WorldGen.yaw_towards_site(pos))
	for e in events:
		state.apply_event(e)
	session.send_welcome(peer_id, {
		"you": peer_id,
		"name": hello.name,
		"env": cfg.env_id,
		"server": BuildInfo.summary(),
		"rules": {"interact_range": WorldState.INTERACT_RANGE, "deposit_range": WorldState.DEPOSIT_RANGE,
			"movement": state.movement_params, "sync_rate": cfg.sync_rate},
		"snapshot": state.to_snapshot(),
	})
	for e in events:
		session.broadcast_event(e)
	Log.event("player.joined", {"peer": peer_id, "name": hello.name, "client_build": hello.build, "players": state.players.size()})


func _on_peer_left(peer_id: int) -> void:
	_pending_moves.erase(peer_id)
	_violations.erase(peer_id)
	if state.players.has(peer_id):
		var player_name: String = state.players[peer_id].name
		_commit(state.player_leave(peer_id))
		Log.event("player.left", {"peer": peer_id, "name": player_name, "players": state.players.size()})


func _on_state_reported(peer_id: int, position: Vector3, yaw: float) -> void:
	_pending_moves[peer_id] = [position, yaw, Time.get_ticks_msec()]


func _on_action_requested(peer_id: int, action: String, target: String) -> void:
	var count: int = _actions_this_tick.get(peer_id, 0) + 1
	_actions_this_tick[peer_id] = count
	if count > MAX_ACTIONS_PER_TICK:
		_on_violation(peer_id, "action_flood")
		return
	_pending_actions.append([peer_id, action, target])


func _on_violation(peer_id: int, kind: String) -> void:
	_counters.violations += 1
	var count: int = _violations.get(peer_id, 0) + 1
	_violations[peer_id] = count
	Log.event("net.violation", {"peer": peer_id, "kind": kind, "count": count}, "warn")
	if count >= MAX_VIOLATIONS:
		session.kick(peer_id, "too_many_violations")


# ------------------------------------------------------------------------------------------ tick work

func _process_moves() -> void:
	for peer in _pending_moves:
		if not state.players.has(peer):
			continue
		var m: Array = _pending_moves[peer]
		var result := state.request_move(peer, m[0], m[1], m[2])
		if not result.ok:
			_counters.moves_rejected += 1
			session.send_correction(peer, state.players[peer].pos)
			Log.event("move.rejected", {"peer": peer, "reason": result.reason, "reported": m[0],
				"server_pos": state.players[peer].pos}, "debug")
	_pending_moves.clear()


func _process_actions() -> void:
	_actions_this_tick.clear()
	var queue := _pending_actions
	_pending_actions = []
	for req in queue:
		var peer: int = req[0]
		var action: String = req[1]
		var target: String = req[2]
		if not state.players.has(peer):
			continue
		var result := {"ok": false, "reason": "bad_action", "events": []}
		match action:
			Protocol.ACTION_PICKUP:
				result = state.request_pickup(peer, target)
			Protocol.ACTION_DROP:
				result = state.request_drop(peer)
			Protocol.ACTION_DEPOSIT:
				result = state.request_deposit(peer, target)
		if result.ok:
			_counters.actions_ok += 1
			_commit(result.events)
			Log.event("action.accepted", {"peer": peer, "action": action, "target": target})
			if action == Protocol.ACTION_DEPOSIT:
				Log.event("site.progress", {"site": target, "deposited": state.sites[target].deposited,
					"by": state.players[peer].name, "revision": state.revision})
		else:
			_counters.actions_rejected += 1
			session.send_event_to(peer, {"type": "rejected", "action": action, "target": target, "reason": result.reason})
			Log.event("action.rejected", {"peer": peer, "action": action, "target": target, "reason": result.reason})


func _commit(events: Array) -> void:
	for e in events:
		if state.apply_event(e):
			_dirty = true
		session.broadcast_event(e)


func _save() -> void:
	var err := store.save(state)
	if err == OK:
		_dirty = false
		_counters.saves += 1
	else:
		_counters.save_errors += 1
		Log.event("world.save_failed", {"error": err, "file": store.file_path()}, "error")


# ------------------------------------------------------------------------------------------ runtime files

func _runtime_dir() -> String:
	return cfg.data_dir.path_join("runtime")


## Lease check: a status.json whose heartbeat keeps advancing means another live server uses this data dir.
func _data_dir_in_use() -> bool:
	var path := _runtime_dir().path_join("status.json")
	if not FileAccess.file_exists(path):
		return false
	var first := FileAccess.get_file_as_string(path)
	var waited := 0.0
	while waited < LEASE_OBSERVE_S:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		if not FileAccess.file_exists(path):
			return false
		if FileAccess.get_file_as_string(path) != first:
			return true
	Log.event("server.stale_lease_ignored", {"file": path}, "warn")
	return false


func _write_status() -> void:
	var status := {
		"instance": _instance_id, "pid": OS.get_process_id(), "env": cfg.env_id, "world": cfg.world_id,
		"port": cfg.port, "players": state.players.size() if state else 0, "revision": state.revision if state else 0,
		"site_progress": _site_progress(), "build": BuildInfo.summary(),
		"started_unix": _started_unix, "updated_unix": Time.get_unix_time_from_system(),
	}
	var path := _runtime_dir().path_join("status.json")
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(status, "  "))
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)


func _fail(reason: String, exit_code: int, detail: String) -> void:
	Log.event("server.start_failed", {"reason": reason, "detail": detail, "exit_code": exit_code}, "error")
	get_tree().quit(exit_code)


func _site_progress() -> int:
	return int(state.sites[WorldGen.SITE_ID].deposited) if state and state.sites.has(WorldGen.SITE_ID) else 0


func _unique_name(base: String) -> String:
	var taken := {}
	for peer in state.players:
		taken[state.players[peer].name] = true
	var candidate := base
	var n := 2
	while taken.has(candidate):
		candidate = "%s#%d" % [base, n]
		n += 1
	return candidate
