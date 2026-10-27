## Wire-protocol constants and validation of everything a client can send.
## Bump structure/network/protocol_version in project.godot whenever any of this changes shape.
extends RefCounted

const ACTION_PICKUP := "pickup"
const ACTION_DROP := "drop"
const ACTION_DEPOSIT := "deposit"
const ACTIONS := [ACTION_PICKUP, ACTION_DROP, ACTION_DEPOSIT]

const CHANNEL_RELIABLE := 0
const CHANNEL_STATE := 1

const MAX_AUTH_BYTES := 1024
const MAX_NAME_LENGTH := 24
const MAX_ID_LENGTH := 32
const MAX_COORDINATE := 10000.0


static func make_hello(protocol: int, build: String, player_name: String) -> PackedByteArray:
	return JSON.stringify({"protocol": protocol, "build": build, "name": player_name}).to_utf8_buffer()


## -> {ok, protocol, build, name} or {ok: false, error}
static func parse_hello(data: PackedByteArray) -> Dictionary:
	if data.size() == 0 or data.size() > MAX_AUTH_BYTES:
		return {"ok": false, "error": "bad_hello_size"}
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"ok": false, "error": "bad_hello_json"}
	var d: Dictionary = json.data
	if not (d.get("protocol") is float or d.get("protocol") is int) or not d.get("build") is String or not d.get("name") is String:
		return {"ok": false, "error": "bad_hello_fields"}
	return {"ok": true, "protocol": int(d.protocol), "build": d.build, "name": sanitize_name(d.name)}


static func make_auth_reply(ok: bool, reason: String, info: Dictionary) -> PackedByteArray:
	return JSON.stringify({"ok": ok, "reason": reason, "info": info}).to_utf8_buffer()


static func parse_auth_reply(data: PackedByteArray) -> Dictionary:
	var json := JSON.new()
	if data.size() > MAX_AUTH_BYTES * 8 or json.parse(data.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"ok": false, "reason": "bad_server_reply", "info": {}}
	var d: Dictionary = json.data
	return {"ok": d.get("ok") == true, "reason": str(d.get("reason", "")), "info": d.get("info", {}) if d.get("info") is Dictionary else {}}


## Printable, trimmed, length-limited display name. Never trusted for authority.
static func sanitize_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c >= 32 and c != 127:
			out += char(c)
	out = out.strip_edges().left(MAX_NAME_LENGTH)
	return out if out != "" else "player"


static func valid_id(v: Variant) -> bool:
	if not v is String:
		return false
	var s: String = v
	if s.is_empty() or s.length() > MAX_ID_LENGTH:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return true


static func valid_vec3(v: Variant) -> bool:
	if not v is Vector3:
		return false
	var p: Vector3 = v
	return p.is_finite() and absf(p.x) <= MAX_COORDINATE and absf(p.y) <= MAX_COORDINATE and absf(p.z) <= MAX_COORDINATE


static func valid_yaw(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


## Validates a client action request. -> "" when valid, otherwise a violation code.
static func check_action(action: Variant, target: Variant) -> String:
	if not action is String or not action in ACTIONS:
		return "bad_action"
	if action == ACTION_DROP:
		return "" if (target is String and target == "") else "bad_target"
	return "" if valid_id(target) else "bad_target"
