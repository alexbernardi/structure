extends RefCounted

const AppConfig = preload("res://core/app_config.gd")
const WorldGen = preload("res://world/world_gen.gd")


func test_defaults_are_valid_client(t) -> void:
	var cfg := AppConfig.parse(PackedStringArray(), {})
	t.eq(cfg.errors.size(), 0, "no errors: %s" % [cfg.errors])
	t.eq(cfg.role, "client", "default role")


func test_precedence_args_over_env(t) -> void:
	var env := {"STRUCTURE_PORT": "25000", "STRUCTURE_WORLD_ID": "envworld", "STRUCTURE_DATA_DIR": "/data"}
	var cfg := AppConfig.parse(PackedStringArray(["--server", "--port=26000"]), env)
	t.eq(cfg.errors.size(), 0, "valid: %s" % [cfg.errors])
	t.eq(cfg.role, "server", "role flag")
	t.eq(cfg.port, 26000, "argument beats environment")
	t.eq(cfg.world_id, "envworld", "environment beats default")


func test_invalid_values_are_reported(t) -> void:
	var cfg := AppConfig.parse(PackedStringArray(["--port=99999", "--world-id=Bad World", "--frobnicate=1", "--seed=abc"]), {})
	t.eq(cfg.errors.size(), 4, "four problems: %s" % [cfg.errors])
	var server := AppConfig.parse(PackedStringArray(["--server", "--data-dir=relative/path"]), {})
	t.ok(server.errors.size() == 1 and server.errors[0].contains("data-dir"), "server needs absolute data dir")
	var bot := AppConfig.parse(PackedStringArray(["--bot"]), {})
	t.ok(bot.errors.size() == 1 and bot.errors[0].contains("connect"), "bot needs --connect")


func test_parse_address(t) -> void:
	t.eq(AppConfig.parse_address("127.0.0.1:24565"), {"host": "127.0.0.1", "port": 24565}, "ipv4")
	t.eq(AppConfig.parse_address("localhost"), {}, "missing port")
	t.eq(AppConfig.parse_address("h:0"), {}, "port zero")


func test_layout_is_deterministic_per_seed(t) -> void:
	t.eq(WorldGen.obstacles(42), WorldGen.obstacles(42), "same seed, same obstacles")
	t.ne(WorldGen.obstacles(42), WorldGen.obstacles(43), "different seed, different obstacles")
	t.eq(WorldGen.resource_position(42, 5), WorldGen.resource_position(42, 5), "same resource position")
	t.eq(WorldGen.mix_seed(1337, 202, 3), 397415941, "seed mixing is a fixed function (changing it moves every world)")


func test_resources_avoid_obstacles_and_stay_in_ring(t) -> void:
	var obs := WorldGen.obstacles(1337)
	for seq in 200:
		var p := WorldGen.resource_position(1337, seq)
		var d := Vector2(p.x, p.z).length()
		t.ok(d >= WorldGen.RESOURCE_RING.x - 0.01 and d <= WorldGen.RESOURCE_RING.y + 0.01, "resource %d within ring" % seq)
		t.ok(not WorldGen.is_blocked(p, obs, 0.5), "resource %d not inside an obstacle" % seq)


func test_spawn_points_face_the_site(t) -> void:
	for slot in 8:
		var p := WorldGen.spawn_point(slot)
		var yaw := WorldGen.yaw_towards_site(p)
		var forward := Vector3(-sin(yaw), 0, -cos(yaw))
		t.near(forward.dot((WorldGen.SITE_POSITION - p).normalized()), 1.0, 1e-4, "slot %d faces the site" % slot)
