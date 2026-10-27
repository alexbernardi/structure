## Structured logging: one JSON object per line on stdout.
##   {"ts":"2026-10-27T21:16:25.237Z","lvl":"info","role":"server","env":"dev","evt":"server.ready",...}
## Event names are dotted (`area.what`) and documented in AGENT-WORKSHOP/DOCUMENTATION/LOG-EVENTS.md.
extends RefCounted

const LEVELS := {"debug": 10, "info": 20, "warn": 30, "error": 40}

static var _role := "app"
static var _env := ""
static var _min_level := 20


static func configure(role: String, env_id: String, level: String) -> void:
	_role = role
	_env = env_id
	_min_level = LEVELS.get(level, 20)


static func event(evt: String, fields := {}, level := "info") -> void:
	if LEVELS.get(level, 20) < _min_level:
		return
	var record := {"ts": timestamp(), "lvl": level, "role": _role, "env": _env, "evt": evt}
	for key in fields:
		record[key] = jsonable(fields[key])
	print(JSON.stringify(record, "", false))


static func timestamp() -> String:
	var now := Time.get_unix_time_from_system()
	var whole := int(now)
	return "%s.%03dZ" % [Time.get_datetime_string_from_unix_time(whole), int((now - whole) * 1000.0)]


## Converts engine types into JSON-friendly values (vectors become rounded arrays).
static func jsonable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3:
			return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
		TYPE_VECTOR2:
			return [snappedf(value.x, 0.001), snappedf(value.y, 0.001)]
		TYPE_FLOAT:
			return snappedf(value, 0.001) if is_finite(value) else null
		TYPE_DICTIONARY:
			var out := {}
			for k in value:
				out[str(k)] = jsonable(value[k])
			return out
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var arr := []
			for v in value:
				arr.append(jsonable(v))
			return arr
		TYPE_STRING_NAME:
			return String(value)
	return value
