extends RefCounted

const Protocol = preload("res://net/protocol.gd")


func test_hello_roundtrip(t) -> void:
	var h := Protocol.parse_hello(Protocol.make_hello(1, "0.1.0", "alice"))
	t.ok(h.ok, "parsed")
	t.eq(h.protocol, 1, "protocol")
	t.eq(h.name, "alice", "name")


func test_malformed_hello_is_rejected(t) -> void:
	t.eq(Protocol.parse_hello(PackedByteArray()).error, "bad_hello_size", "empty")
	t.eq(Protocol.parse_hello("x".repeat(5000).to_utf8_buffer()).error, "bad_hello_size", "oversized")
	t.eq(Protocol.parse_hello("not json".to_utf8_buffer()).error, "bad_hello_json", "not json")
	t.eq(Protocol.parse_hello("[1,2]".to_utf8_buffer()).error, "bad_hello_json", "not an object")
	t.eq(Protocol.parse_hello('{"protocol":"1","build":"x","name":"y"}'.to_utf8_buffer()).error, "bad_hello_fields", "wrong types")


func test_names_are_sanitised(t) -> void:
	t.eq(Protocol.sanitize_name("  bob  "), "bob", "trimmed")
	t.eq(Protocol.sanitize_name("a\nb\tc"), "abc", "control characters removed")
	t.eq(Protocol.sanitize_name(""), "player", "default")
	t.eq(Protocol.sanitize_name("x".repeat(100)).length(), Protocol.MAX_NAME_LENGTH, "length limited")


func test_action_validation(t) -> void:
	t.eq(Protocol.check_action("pickup", "r12"), "", "valid pickup")
	t.eq(Protocol.check_action("drop", ""), "", "valid drop")
	t.eq(Protocol.check_action("deposit", "site_0"), "", "valid deposit")
	t.eq(Protocol.check_action("teleport", "r1"), "bad_action", "unknown action")
	t.eq(Protocol.check_action(42, "r1"), "bad_action", "non-string action")
	t.eq(Protocol.check_action("pickup", 7), "bad_target", "non-string target")
	t.eq(Protocol.check_action("pickup", "../x"), "bad_target", "path characters")
	t.eq(Protocol.check_action("pickup", "R1"), "bad_target", "uppercase not allowed")
	t.eq(Protocol.check_action("drop", "r1"), "bad_target", "drop takes no target")


func test_vector_validation(t) -> void:
	t.ok(Protocol.valid_vec3(Vector3(1, 2, 3)), "finite")
	t.ok(not Protocol.valid_vec3(Vector3(INF, 0, 0)), "infinite")
	t.ok(not Protocol.valid_vec3(Vector3(NAN, 0, 0)), "NaN")
	t.ok(not Protocol.valid_vec3(Vector3(1e9, 0, 0)), "huge")
	t.ok(not Protocol.valid_vec3([1, 2, 3]), "array is not a vector")
	t.ok(Protocol.valid_yaw(1.5), "yaw")
	t.ok(not Protocol.valid_yaw("1.5"), "string yaw")
