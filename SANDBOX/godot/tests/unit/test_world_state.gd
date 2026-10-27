extends RefCounted

const WorldState = preload("res://world/world_state.gd")
const WorldGen = preload("res://world/world_gen.gd")

var s: WorldState


func before_each() -> void:
	s = WorldState.new()
	s.init_new("test", 1337)


func _join(peer: int, pos: Vector3, player_name := "") -> void:
	for e in s.player_join(peer, player_name if player_name != "" else "p%d" % peer, pos, 0.0):
		s.apply_event(e)


func _commit(result: Dictionary) -> void:
	for e in result.events:
		s.apply_event(e)


func _first_resource() -> Dictionary:
	return s.resources[s.resources.keys()[0]]


func test_new_world_has_site_and_resources(t) -> void:
	t.eq(s.sites.size(), 1, "one construction site")
	t.eq(s.resources.size(), WorldGen.INITIAL_RESOURCES, "initial resources")
	t.eq(s.sites[WorldGen.SITE_ID].deposited, 0, "no progress yet")


func test_pickup_in_range_is_accepted(t) -> void:
	var r := _first_resource()
	_join(1, r.pos + Vector3(1, 0, 0))
	var result := s.request_pickup(1, r.id)
	t.ok(result.ok, "pickup accepted: %s" % result.reason)
	_commit(result)
	t.eq(s.players[1].carrying, r.id, "player carries the resource")
	t.eq(s.resources[r.id].carrier, 1, "resource records its carrier")


func test_pickup_rules_reject_invalid_requests(t) -> void:
	var r := _first_resource()
	_join(1, r.pos + Vector3(20, 0, 0))
	t.eq(s.request_pickup(1, r.id).reason, "out_of_range", "far away")
	t.eq(s.request_pickup(1, "nope").reason, "no_such_resource", "unknown id")
	t.eq(s.request_pickup(99, r.id).reason, "unknown_player", "unknown player")
	_join(2, r.pos)
	_commit(s.request_pickup(2, r.id))
	_join(3, r.pos)
	t.eq(s.request_pickup(3, r.id).reason, "resource_taken", "already carried by someone else")
	var other: Dictionary = s.resources[s.resources.keys()[1]]
	s.players[2].pos = other.pos
	t.eq(s.request_pickup(2, other.id).reason, "already_carrying", "one item at a time")


func test_deposit_increments_progress_and_respawns(t) -> void:
	var r := _first_resource()
	_join(1, r.pos, "alice")
	_commit(s.request_pickup(1, r.id))
	t.eq(s.request_deposit(1, WorldGen.SITE_ID).reason, "out_of_range", "must be near the site")
	s.players[1].pos = WorldGen.SITE_POSITION + Vector3(3.5, 0, 0)
	var rev := s.revision
	var result := s.request_deposit(1, WorldGen.SITE_ID)
	t.ok(result.ok, "deposit accepted: %s" % result.reason)
	_commit(result)
	t.eq(s.sites[WorldGen.SITE_ID].deposited, 1, "progress incremented")
	t.eq(s.sites[WorldGen.SITE_ID].contributors.get("alice"), 1, "contribution recorded")
	t.ok(not s.resources.has(r.id), "deposited resource consumed")
	t.eq(s.resources.size(), WorldGen.INITIAL_RESOURCES, "replacement spawned")
	t.eq(s.players[1].carrying, "", "hands empty")
	t.ok(s.revision > rev, "revision bumped")


func test_deposit_and_drop_require_carrying(t) -> void:
	_join(1, WorldGen.SITE_POSITION)
	t.eq(s.request_deposit(1, WorldGen.SITE_ID).reason, "not_carrying", "deposit empty-handed")
	t.eq(s.request_drop(1).reason, "not_carrying", "drop empty-handed")


func test_drop_places_resource_in_front_on_ground(t) -> void:
	var r := _first_resource()
	var origin: Vector3 = r.pos  # r is the live dictionary; keep the pre-drop position
	_join(1, origin + Vector3(0, 1.5, 0))
	s.players[1].yaw = 0.0  # facing -Z
	_commit(s.request_pickup(1, r.id))
	var result := s.request_drop(1)
	t.ok(result.ok, "drop accepted")
	_commit(result)
	t.near(s.resources[r.id].pos, Vector3(origin.x, 0, origin.z - WorldState.DROP_DISTANCE), 0.01, "dropped in front, on the ground")
	t.eq(s.resources[r.id].carrier, 0, "back on the ground")


func test_leaving_player_drops_carried_resource(t) -> void:
	var r := _first_resource()
	_join(1, r.pos)
	_commit(s.request_pickup(1, r.id))
	s.players[1].pos = Vector3(5, 0, 5)
	for e in s.player_leave(1):
		s.apply_event(e)
	t.ok(not s.players.has(1), "player removed")
	t.eq(s.resources[r.id].carrier, 0, "resource released")
	t.near(s.resources[r.id].pos, Vector3(5, 0, 5), 0.01, "dropped where the player left")


func test_move_validation_uses_speed_budget(t) -> void:
	_join(1, Vector3.ZERO)
	s.players[1].last_move_ms = 1000
	s.players[1].budget_h = 0.0
	var walk := s.request_move(1, Vector3(0.3, 0, 0), 0.0, 1050)  # 6 m/s
	t.ok(walk.ok, "walking speed accepted")
	t.eq(s.request_move(1, Vector3(30, 0, 0), 0.0, 1100).reason, "too_fast", "teleport rejected")
	t.near(s.players[1].pos, Vector3(0.3, 0, 0), 0.001, "rejected move keeps server position")
	t.eq(s.request_move(1, Vector3(500, 0, 0), 0.0, 9000).reason, "out_of_bounds", "outside the world")
	# Sustained over-speed: 20 m/s for 2 s must be caught even though single steps look small.
	var rejected := 0
	var x := 0.3
	for i in 40:
		x += 1.0
		if not s.request_move(1, Vector3(x, 0, 0), 0.0, 10000 + 50 * (i + 1)).ok:
			rejected += 1
			x = s.players[1].pos.x
	t.ok(rejected > 0, "sustained speed hack detected (%d rejections)" % rejected)


func test_replica_mirrors_server_through_events(t) -> void:
	_join(1, Vector3.ZERO, "alice")
	var replica := WorldState.new()
	replica.load_snapshot(s.to_snapshot())
	var r := _first_resource()
	s.players[1].pos = r.pos
	var events: Array = []
	var pickup := s.request_pickup(1, r.id)
	events.append_array(pickup.events)
	_commit(pickup)
	s.players[1].pos = WorldGen.SITE_POSITION
	var deposit := s.request_deposit(1, WorldGen.SITE_ID)
	events.append_array(deposit.events)
	_commit(deposit)
	for e in events:
		replica.apply_event(e)
	t.eq(replica.to_save_dict().resources, s.to_save_dict().resources, "resources identical")
	t.eq(replica.to_save_dict().sites, s.to_save_dict().sites, "sites identical")
	t.eq(replica.revision, s.revision, "revision identical")


func test_save_roundtrip_preserves_state(t) -> void:
	var r := _first_resource()
	_join(1, r.pos)
	_commit(s.request_pickup(1, r.id))
	var doc := s.to_save_dict()
	var restored := WorldState.new()
	t.eq(restored.load_save_dict(JSON.parse_string(JSON.stringify(doc))), "", "loads its own document")
	t.eq(restored.to_save_dict(), doc, "identical after JSON roundtrip")
	t.eq(restored.resources[r.id].carrier, 0, "carried resource restored on the ground")
	t.eq(restored.players.size(), 0, "players are not persisted")


func test_load_rejects_malformed_documents(t) -> void:
	var w := WorldState.new()
	t.ne(w.load_save_dict({}), "", "empty document")
	t.ne(w.load_save_dict({"world_id": "x", "seed": 1, "spawn_counter": 0, "resources": [{"id": 3}], "sites": []}), "", "bad resource")
