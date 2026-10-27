## Authoritative world model: plain data + gameplay rules. No nodes, networking or file I/O.
##   Server : request_*() validates a client request and returns events; apply_event() commits them.
##   Clients: apply_event() only, mirroring the server (read-only replica).
## Persistent: resources, construction sites, spawn counter. Players are session-only.
extends RefCounted

const Movement = preload("res://systems/movement/movement_model.gd")
const WorldGen = preload("res://world/world_gen.gd")

const RESOURCE_KIND := "stone"
const INTERACT_RANGE := 3.0       # player -> resource (m)
const DEPOSIT_RANGE := 4.5        # player -> site centre, horizontal (m)
const RANGE_SLACK := 1.0          # latency allowance on interaction distances (m)
const DROP_DISTANCE := 1.2        # dropped items land this far in front of the player
const WORLD_HALF_EXTENT := 80.0   # playable square [-80, 80] on x/z
const MIN_Y := -5.0
const MAX_Y := 60.0
const MOVE_TOLERANCE := 1.5       # multiplier on the movement system's speed bounds
const MOVE_BURST_S := 1.0         # movement budget can bank at most this many seconds
const MOVE_SLACK := 1.0           # extra metres in the budget cap for jitter

var world_id := ""
var world_seed := 0
var created_at := ""
var spawn_counter := 0
var revision := 0                 # bumps on every persistent change
var resources := {}               # id -> {id, kind, pos: Vector3, carrier: int (0 = on the ground)}
var sites := {}                   # id -> {id, pos: Vector3, deposited: int, contributors: {name: int}}
var players := {}                 # peer -> {peer, name, pos, yaw, carrying, last_move_ms, budget_h, budget_v}
var movement_params := Movement.default_params()


func init_new(id: String, seed_value: int) -> void:
	world_id = id
	world_seed = seed_value
	created_at = Time.get_datetime_string_from_system(true) + "Z"
	sites[WorldGen.SITE_ID] = {"id": WorldGen.SITE_ID, "pos": WorldGen.SITE_POSITION, "deposited": 0, "contributors": {}}
	for i in WorldGen.INITIAL_RESOURCES:
		apply_event(make_spawn_event())


# ------------------------------------------------------------------------------------------ requests (server)

func request_pickup(peer: int, resource_id: String) -> Dictionary:
	var pl: Variant = players.get(peer)
	if pl == null:
		return _reject("unknown_player")
	if pl.carrying != "":
		return _reject("already_carrying")
	var res: Variant = resources.get(resource_id)
	if res == null:
		return _reject("no_such_resource")
	if res.carrier != 0:
		return _reject("resource_taken")
	if (pl.pos as Vector3).distance_to(res.pos) > INTERACT_RANGE + RANGE_SLACK:
		return _reject("out_of_range")
	return _accept([{"type": "resource_picked", "id": resource_id, "by": peer}])


func request_drop(peer: int) -> Dictionary:
	var pl: Variant = players.get(peer)
	if pl == null:
		return _reject("unknown_player")
	if pl.carrying == "":
		return _reject("not_carrying")
	return _accept([{"type": "resource_dropped", "id": pl.carrying, "pos": _drop_position(pl)}])


func request_deposit(peer: int, site_id: String) -> Dictionary:
	var pl: Variant = players.get(peer)
	if pl == null:
		return _reject("unknown_player")
	if pl.carrying == "":
		return _reject("not_carrying")
	var site: Variant = sites.get(site_id)
	if site == null:
		return _reject("no_such_site")
	var offset: Vector3 = pl.pos - site.pos
	if Vector2(offset.x, offset.z).length() > DEPOSIT_RANGE + RANGE_SLACK:
		return _reject("out_of_range")
	return _accept([
		{"type": "resource_deposited", "id": pl.carrying, "site": site_id, "by": peer, "by_name": pl.name,
			"deposited": int(site.deposited) + 1},
		make_spawn_event(),  # a replacement keeps the loop going
	])


## Client-predicted movement, validated against the movement system's speed bounds with a token budget:
## bursts up to MOVE_BURST_S are tolerated, sustained speed cannot exceed MOVE_TOLERANCE x the bound.
func request_move(peer: int, pos: Vector3, yaw: float, now_ms: int) -> Dictionary:
	var pl: Variant = players.get(peer)
	if pl == null:
		return _reject("unknown_player")
	var rate_h := Movement.max_horizontal_speed(movement_params) * MOVE_TOLERANCE
	var rate_v := Movement.max_vertical_speed(movement_params) * MOVE_TOLERANCE
	var elapsed := clampf((now_ms - int(pl.last_move_ms)) / 1000.0, 0.0, 10.0)
	pl.last_move_ms = now_ms
	pl.budget_h = minf(pl.budget_h + rate_h * elapsed, rate_h * MOVE_BURST_S + MOVE_SLACK)
	pl.budget_v = minf(pl.budget_v + rate_v * elapsed, rate_v * MOVE_BURST_S + MOVE_SLACK)
	if absf(pos.x) > WORLD_HALF_EXTENT or absf(pos.z) > WORLD_HALF_EXTENT or pos.y < MIN_Y or pos.y > MAX_Y:
		return _reject("out_of_bounds")
	var d: Vector3 = pos - pl.pos
	var dist_h := Vector2(d.x, d.z).length()
	if dist_h > pl.budget_h or absf(d.y) > pl.budget_v:
		return _reject("too_fast")
	pl.budget_h -= dist_h
	pl.budget_v -= absf(d.y)
	pl.pos = pos
	pl.yaw = wrapf(yaw, -PI, PI)
	return {"ok": true, "reason": "", "events": []}


func player_join(peer: int, player_name: String, pos: Vector3, yaw: float) -> Array:
	return [{"type": "player_joined", "peer": peer, "name": player_name, "pos": pos, "yaw": yaw}]


func player_leave(peer: int) -> Array:
	var pl: Variant = players.get(peer)
	if pl == null:
		return []
	var events := []
	if pl.carrying != "":
		events.append({"type": "resource_dropped", "id": pl.carrying, "pos": _ground(pl.pos)})
	events.append({"type": "player_left", "peer": peer})
	return events


func make_spawn_event() -> Dictionary:
	var seq := spawn_counter
	return {"type": "resource_spawned", "id": "r%d" % seq, "seq": seq, "kind": RESOURCE_KIND,
		"pos": WorldGen.resource_position(world_seed, seq)}


# ------------------------------------------------------------------------------------------ state changes

## Applies one server event. Returns true when persistent state changed (the server then saves).
func apply_event(e: Dictionary) -> bool:
	match String(e.get("type", "")):
		"resource_spawned":
			resources[e.id] = {"id": e.id, "kind": e.kind, "pos": e.pos, "carrier": 0}
			spawn_counter = maxi(spawn_counter, int(e.seq) + 1)
		"resource_picked":
			var res: Variant = resources.get(e.id)
			if res != null:
				res.carrier = e.by
				if players.has(e.by):
					players[e.by].carrying = e.id
			return false  # carried items are saved at their last resting position
		"resource_dropped":
			var res: Variant = resources.get(e.id)
			if res == null:
				return false
			if players.has(res.carrier) and players[res.carrier].carrying == e.id:
				players[res.carrier].carrying = ""
			res.carrier = 0
			res.pos = e.pos
		"resource_deposited":
			var res: Variant = resources.get(e.id)
			if res != null and players.has(res.carrier):
				players[res.carrier].carrying = ""
			resources.erase(e.id)
			var site: Variant = sites.get(e.site)
			if site != null:
				site.deposited = int(e.deposited)
				site.contributors[e.by_name] = int(site.contributors.get(e.by_name, 0)) + 1
		"player_joined":
			players[e.peer] = {"peer": e.peer, "name": e.name, "pos": e.pos, "yaw": e.yaw, "carrying": "",
				"last_move_ms": Time.get_ticks_msec(), "budget_h": MOVE_SLACK, "budget_v": MOVE_SLACK}
			return false
		"player_left":
			players.erase(e.peer)
			return false
		_:
			return false
	revision += 1
	return true


## Applies a periodic player-state broadcast ([[peer, pos, yaw], ...]) on clients.
func apply_player_states(states: Array) -> void:
	for s in states:
		if s is Array and s.size() == 3 and players.has(s[0]):
			players[s[0]].pos = s[1]
			players[s[0]].yaw = s[2]


func player_states() -> Array:
	var out := []
	for peer in players:
		out.append([peer, players[peer].pos, players[peer].yaw])
	return out


func entity_count() -> int:
	return resources.size() + sites.size() + players.size()


# ------------------------------------------------------------------------------------------ serialisation

## Full state for a joining client (engine types; sent over RPC).
func to_snapshot() -> Dictionary:
	var res_list := []
	for id in _sorted_keys(resources):
		var r: Dictionary = resources[id]
		res_list.append({"id": r.id, "kind": r.kind, "pos": r.pos, "carrier": r.carrier})
	var site_list := []
	for id in _sorted_keys(sites):
		site_list.append(sites[id].duplicate(true))
	var player_list := []
	for peer in players:
		var p: Dictionary = players[peer]
		player_list.append({"peer": p.peer, "name": p.name, "pos": p.pos, "yaw": p.yaw, "carrying": p.carrying})
	return {"world_id": world_id, "seed": world_seed, "revision": revision, "spawn_counter": spawn_counter,
		"resources": res_list, "sites": site_list, "players": player_list}


func load_snapshot(s: Dictionary) -> void:
	world_id = s.world_id
	world_seed = s.seed
	revision = s.revision
	spawn_counter = s.spawn_counter
	resources.clear()
	sites.clear()
	players.clear()
	for r in s.resources:
		resources[r.id] = r.duplicate()
	for site in s.sites:
		sites[site.id] = site.duplicate(true)
	for p in s.players:
		players[p.peer] = {"peer": p.peer, "name": p.name, "pos": p.pos, "yaw": p.yaw, "carrying": p.carrying,
			"last_move_ms": 0, "budget_h": 0.0, "budget_v": 0.0}


## Persistent document (JSON-friendly). Carried resources are stored at their last resting position.
func to_save_dict() -> Dictionary:
	var res_list := []
	for id in _sorted_keys(resources):
		var r: Dictionary = resources[id]
		res_list.append({"id": r.id, "kind": r.kind, "pos": _vec_to_list(r.pos)})
	var site_list := []
	for id in _sorted_keys(sites):
		var s: Dictionary = sites[id]
		site_list.append({"id": s.id, "pos": _vec_to_list(s.pos), "deposited": s.deposited, "contributors": s.contributors.duplicate()})
	return {"world_id": world_id, "seed": world_seed, "created_at": created_at, "spawn_counter": spawn_counter,
		"revision": revision, "resources": res_list, "sites": site_list}


## Loads a persistent document. Returns "" on success, otherwise a description of the problem.
func load_save_dict(d: Dictionary) -> String:
	if not d.get("world_id") is String or not _is_num(d.get("seed")) or not _is_num(d.get("spawn_counter")):
		return "missing world_id/seed/spawn_counter"
	if not d.get("resources") is Array or not d.get("sites") is Array:
		return "missing resources/sites arrays"
	world_id = d.world_id
	world_seed = int(d.seed)
	created_at = str(d.get("created_at", ""))
	spawn_counter = int(d.spawn_counter)
	revision = int(d.get("revision", 0))
	resources.clear()
	sites.clear()
	players.clear()
	for r in d.resources:
		if not r is Dictionary or not r.get("id") is String or not _is_vec_list(r.get("pos")):
			return "malformed resource entry"
		resources[r.id] = {"id": r.id, "kind": str(r.get("kind", RESOURCE_KIND)), "pos": _list_to_vec(r.pos), "carrier": 0}
	for s in d.sites:
		if not s is Dictionary or not s.get("id") is String or not _is_vec_list(s.get("pos")) or not _is_num(s.get("deposited")):
			return "malformed site entry"
		var contributors := {}
		if s.get("contributors") is Dictionary:
			for k in s.contributors:
				contributors[str(k)] = int(s.contributors[k])
		sites[s.id] = {"id": s.id, "pos": _list_to_vec(s.pos), "deposited": int(s.deposited), "contributors": contributors}
	return ""


# ------------------------------------------------------------------------------------------ helpers

func _drop_position(pl: Dictionary) -> Vector3:
	var forward := Vector3(-sin(pl.yaw), 0.0, -cos(pl.yaw))
	var p: Vector3 = _ground(pl.pos + forward * DROP_DISTANCE)
	p.x = clampf(p.x, -WORLD_HALF_EXTENT, WORLD_HALF_EXTENT)
	p.z = clampf(p.z, -WORLD_HALF_EXTENT, WORLD_HALF_EXTENT)
	return p.snapped(Vector3(0.001, 0.001, 0.001))


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z).snapped(Vector3(0.001, 0.001, 0.001))


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": []}


static func _accept(events: Array) -> Dictionary:
	return {"ok": true, "reason": "", "events": events}


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(a, b) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)
	return keys


static func _vec_to_list(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _list_to_vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _is_vec_list(v: Variant) -> bool:
	return v is Array and v.size() == 3 and _is_num(v[0]) and _is_num(v[1]) and _is_num(v[2])


static func _is_num(v: Variant) -> bool:
	return v is int or v is float
