## Headless scripted client for automated tests and benchmarks. Speaks exactly the player protocol.
## Plans: observe | gather:<n> | cheat | wander (gather loop for --bot-hold seconds, for load tests).
## Writes a JSON report to --bot-report and exits 0 on success, 1 on failure.
extends Node

const AppConfig = preload("res://core/app_config.gd")
const BuildInfo = preload("res://core/build_info.gd")
const Log = preload("res://core/log.gd")
const Protocol = preload("res://net/protocol.gd")
const WorldGen = preload("res://world/world_gen.gd")
const WorldState = preload("res://world/world_state.gd")

const STEP_S := 0.05
const SPEED_FACTOR := 0.9     # stay safely under the server's speed validation
const RESULT_TIMEOUT_S := 4.0

var cfg: Dictionary
var session: Node
var replica := WorldState.new()
var me := 0
var my_pos := Vector3.ZERO
var my_yaw := 0.0
var report := {}

var _events: Array[Dictionary] = []
var _corrections := 0
var _last_seen := {}       # peer -> last position
var _moves_seen := {}      # peer name -> observed position changes
var _names_seen := {}
var _finished := false
var _started_ms := 0


func setup(config: Dictionary, session_node: Node) -> void:
	cfg = config
	session = session_node


func _ready() -> void:
	Engine.max_fps = 60
	_started_ms = Time.get_ticks_msec()
	report = {"ok": false, "reason": "", "name": cfg.name, "plan": cfg.bot_plan, "peer_id": 0, "errors": [],
		"deposits": 0, "pickup_rejections": [], "cheats": [], "connection_failed": ""}
	session.welcome_received.connect(_on_welcome)
	session.event_received.connect(_on_event)
	session.players_received.connect(_on_players)
	session.correction_received.connect(func(pos: Vector3) -> void:
		_corrections += 1
		my_pos = pos)
	session.connection_failed.connect(func(reason: String) -> void:
		report.connection_failed = reason
		_finish(false, "connection_failed"))
	session.disconnected.connect(func(reason: String) -> void: _finish(false, "disconnected: " + reason))
	get_tree().create_timer(cfg.bot_timeout).timeout.connect(func() -> void: _finish(false, "timeout"))
	var addr := AppConfig.parse_address(cfg.connect)
	var protocol: int = BuildInfo.protocol_version() if cfg.protocol_override < 0 else cfg.protocol_override
	var bot_name: String = cfg.name if cfg.name != "" else "bot"
	var err: Error = session.start_client(addr.host, addr.port, Protocol.make_hello(protocol, BuildInfo.build_version(), bot_name))
	if err != OK:
		_finish(false, "client_start_failed:%d" % err)


func _on_welcome(payload: Dictionary) -> void:
	me = payload.you
	replica.load_snapshot(payload.snapshot)
	my_pos = replica.players[me].pos
	my_yaw = replica.players[me].yaw
	for p in replica.players.values():
		_names_seen[p.name] = true
	report.peer_id = me
	report.assigned_name = payload.name
	report.server = payload.server
	report.env = payload.env
	report.initial_progress = _progress()
	Log.event("bot.joined", {"peer": me, "name": payload.name, "players": replica.players.size(), "site_progress": _progress()})
	_run_plan()


func _on_event(e: Dictionary) -> void:
	_events.append(e)
	if e.type == "rejected":
		return
	replica.apply_event(e)
	if e.type == "player_joined":
		_names_seen[e.name] = true


func _on_players(states: Array) -> void:
	replica.apply_player_states(states)
	for s in states:
		var peer: int = s[0]
		if peer == me or not replica.players.has(peer):
			continue
		var player_name: String = replica.players[peer].name
		if _last_seen.has(peer) and (_last_seen[peer] as Vector3).distance_to(s[1]) > 0.01:
			_moves_seen[player_name] = int(_moves_seen.get(player_name, 0)) + 1
		_last_seen[peer] = s[1]


# ------------------------------------------------------------------------------------------ plans

func _run_plan() -> void:
	var need: int = cfg.bot_wait_players
	if not await _wait_for(func() -> bool: return replica.players.size() >= need, cfg.bot_timeout):
		return
	report.max_players_seen = replica.players.size()
	var plan: String = cfg.bot_plan
	var ok := true
	if plan.begins_with("gather:"):
		for i in plan.get_slice(":", 1).to_int():
			if not await _gather_one():
				ok = false
				break
	elif plan == "cheat":
		ok = await _cheat_suite()
	elif plan == "wander":
		var until := Time.get_ticks_msec() + int(cfg.bot_hold * 1000.0)
		while Time.get_ticks_msec() < until and not _finished:
			await _gather_one()
	elif plan != "observe":
		report.errors.append("unknown plan '%s'" % plan)
		ok = false
	if ok and cfg.bot_until_progress >= 0:
		var goal: int = cfg.bot_until_progress
		ok = await _wait_for(func() -> bool: return _progress() >= goal, cfg.bot_timeout)
		if not ok:
			report.errors.append("site never reached progress %d" % goal)
	if ok and cfg.bot_hold > 0.0 and plan != "wander":
		await _sleep(cfg.bot_hold)
	_finish(ok, "" if ok else "plan_failed")


func _gather_one() -> bool:
	var picked := false
	for attempt in 6:
		var target := _nearest_free_resource()
		if target.is_empty():
			await _sleep(0.25)
			continue
		await _walk_to(target.pos, 1.2)
		var result := await _request("pickup", target.id)
		if result == "ok":
			picked = true
			break
		report.pickup_rejections.append(result)
	if not picked:
		report.errors.append("could not pick up a resource")
		return false
	var site: Dictionary = replica.sites[WorldGen.SITE_ID]
	await _walk_to(site.pos, WorldState.DEPOSIT_RANGE * 0.6)
	var deposit := await _request("deposit", site.id)
	if deposit != "ok":
		report.errors.append("deposit failed: %s" % deposit)
		return false
	report.deposits += 1
	return true


## Every check expects the server to refuse; state must not change.
func _cheat_suite() -> bool:
	var checks := []
	var progress_before := _progress()
	var far := _farthest_free_resource()
	checks.append(await _expect("pickup_out_of_range", "pickup", far.get("id", "r0"), "out_of_range"))
	var site: Dictionary = replica.sites[WorldGen.SITE_ID]
	await _walk_to(site.pos, 2.0)
	checks.append(await _expect("deposit_without_carrying", "deposit", site.id, "not_carrying"))
	checks.append(await _expect("drop_without_carrying", "drop", "", "not_carrying"))
	checks.append(await _expect("pickup_missing_resource", "pickup", "r999999", "no_such_resource"))
	# Malformed arguments are dropped by the session's validation; the server must keep serving.
	session._rpc_action.rpc_id(1, 42, {"x": 1})
	session._rpc_action.rpc_id(1, "teleport", "r0")
	session._rpc_action.rpc_id(1, "pickup", "../../etc/passwd")
	session._rpc_state.rpc_id(1, "not-a-vector", null)
	session._rpc_state.rpc_id(1, Vector3(INF, 0, 0), 0.0)
	checks.append(await _expect("server_alive_after_malformed_rpcs", "drop", "", "not_carrying"))
	# Teleporting is corrected back to the server's position.
	var corrections_before := _corrections
	session.send_state(my_pos + Vector3(40, 0, 0), my_yaw)
	var corrected := await _wait_for(func() -> bool: return _corrections > corrections_before, RESULT_TIMEOUT_S)
	checks.append({"name": "teleport_corrected", "ok": corrected})
	# Forged server->client event: "authority" RPCs from clients are refused by the engine.
	session._rpc_event.rpc_id(1, {"type": "resource_deposited", "id": "r0", "site": site.id, "by": me,
		"by_name": "mallory", "deposited": 999})
	await _sleep(0.5)
	checks.append(await _expect("server_alive_after_forged_event", "drop", "", "not_carrying"))
	checks.append({"name": "progress_unchanged", "ok": _progress() == progress_before})
	report.cheats = checks
	var all_ok := true
	for c in checks:
		all_ok = all_ok and c.ok
	return all_ok


func _expect(check_name: String, action: String, target: String, reason: String) -> Dictionary:
	var got := await _request(action, target)
	return {"name": check_name, "ok": got == reason, "expected": reason, "got": got}


# ------------------------------------------------------------------------------------------ helpers

## Sends an action and waits for its outcome: "ok", a rejection reason, or "timeout".
func _request(action: String, target: String) -> String:
	var mark := _events.size()
	session.send_action(action, target)
	var deadline := Time.get_ticks_msec() + int(RESULT_TIMEOUT_S * 1000.0)
	while Time.get_ticks_msec() < deadline and not _finished:
		for i in range(mark, _events.size()):
			var e: Dictionary = _events[i]
			if e.type == "rejected" and e.action == action:
				return e.reason
			if action == "pickup" and e.type == "resource_picked" and e.id == target and e.by == me:
				return "ok"
			if action == "deposit" and e.type == "resource_deposited" and e.by == me:
				return "ok"
			if action == "drop" and e.type == "resource_dropped":
				return "ok"
		await get_tree().process_frame
	return "timeout"


func _walk_to(dest: Vector3, stop_distance: float) -> void:
	var speed: float = replica.movement_params.walk_speed * SPEED_FACTOR
	while not _finished:
		var to := Vector3(dest.x - my_pos.x, 0.0, dest.z - my_pos.z)
		var dist := to.length()
		if dist <= stop_distance:
			break
		my_pos += to / dist * minf(speed * STEP_S, dist - stop_distance * 0.5)
		my_yaw = atan2(-to.x, -to.z)
		session.send_state(my_pos, my_yaw)
		await _sleep(STEP_S)
	session.send_state(my_pos, my_yaw)
	await _sleep(0.15)  # let the server apply the final position before interacting


func _nearest_free_resource() -> Dictionary:
	var best := {}
	var best_d := INF
	for r in replica.resources.values():
		var d := my_pos.distance_to(r.pos)
		if int(r.carrier) == 0 and d < best_d:
			best = r
			best_d = d
	return best


func _farthest_free_resource() -> Dictionary:
	var best := {}
	var best_d := -1.0
	for r in replica.resources.values():
		var d := my_pos.distance_to(r.pos)
		if int(r.carrier) == 0 and d > best_d:
			best = r
			best_d = d
	return best


func _progress() -> int:
	return int(replica.sites[WorldGen.SITE_ID].deposited) if replica.sites.has(WorldGen.SITE_ID) else -1


func _wait_for(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline and not _finished:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _finish(ok: bool, reason: String) -> void:
	if _finished:
		return
	_finished = true
	report.ok = ok
	report.reason = reason
	report.final_progress = _progress()
	report.players_seen = _names_seen.keys()
	report.moves_seen = _moves_seen
	report.corrections = _corrections
	report.elapsed_s = (Time.get_ticks_msec() - _started_ms) / 1000.0
	var counts := {}
	for e in _events:
		counts[e.type] = int(counts.get(e.type, 0)) + 1
	report.event_counts = counts
	if cfg.bot_report != "":
		DirAccess.make_dir_recursive_absolute(cfg.bot_report.get_base_dir())
		var f := FileAccess.open(cfg.bot_report, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(Log.jsonable(report), "  "))
			f.close()
	Log.event("bot.finished", {"ok": ok, "reason": reason, "deposits": report.deposits, "final_progress": report.final_progress,
		"errors": report.errors}, "info" if ok else "error")
	session.close()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if ok else 1)
