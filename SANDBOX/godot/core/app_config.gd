## Runtime configuration. Precedence: built-in defaults < STRUCTURE_* environment variables < user args.
## User args follow `--` on the Godot command line: `godot --headless -- --server --port=24565`.
extends RefCounted

const ROLES := ["server", "client", "bot"]
const ID_PATTERN := "^[a-z0-9][a-z0-9_-]{0,31}$"

const DEFAULTS := {
	"role": "client",
	"env_id": "local",
	"world_id": "dev",
	"seed": 1337,
	"port": 24565,
	"bind_ip": "127.0.0.1",   # server bind address; containers use "*" (published on host loopback only)
	"connect": "",            # client/bot: host:port
	"name": "",               # player display name
	"max_players": 16,
	"data_dir": "",           # server: absolute dir holding world/ and runtime/
	"tick_rate": 30,          # server logic ticks per second
	"sync_rate": 15,          # player-state broadcasts per second
	"metrics_interval": 5.0,  # seconds between metrics log lines (0 = off)
	"log_level": "info",
	"vsync": true,
	"screenshot": "",         # client: save PNG to this absolute path, then quit
	"screenshot_delay": 3.0,
	"quit_after": 0.0,        # client: quit after N seconds and log a metrics summary
	"protocol_override": -1,  # test-only: advertise another protocol version
	"bot_plan": "observe",    # observe | gather:<n> | cheat | wander
	"bot_report": "",         # absolute path for the bot's JSON report
	"bot_timeout": 60.0,
	"bot_wait_players": 1,    # wait until this many players are present before acting
	"bot_until_progress": -1, # after the plan, wait until the site reaches this progress
	"bot_hold": 0.0,          # stay connected this many seconds after the plan
}

const ENV_VARS := {
	"STRUCTURE_ROLE": "role",
	"STRUCTURE_ENV_ID": "env_id",
	"STRUCTURE_WORLD_ID": "world_id",
	"STRUCTURE_WORLD_SEED": "seed",
	"STRUCTURE_PORT": "port",
	"STRUCTURE_BIND_IP": "bind_ip",
	"STRUCTURE_MAX_PLAYERS": "max_players",
	"STRUCTURE_DATA_DIR": "data_dir",
	"STRUCTURE_TICK_RATE": "tick_rate",
	"STRUCTURE_METRICS_INTERVAL": "metrics_interval",
	"STRUCTURE_LOG_LEVEL": "log_level",
}


static func load_from_os() -> Dictionary:
	var env := {}
	for key in ENV_VARS:
		env[key] = OS.get_environment(key)
	return parse(OS.get_cmdline_user_args(), env)


## Pure function (unit-tested): returns DEFAULTS merged with overrides plus an `errors` array.
static func parse(args: PackedStringArray, env: Dictionary) -> Dictionary:
	var cfg := DEFAULTS.duplicate()
	var errors: Array[String] = []
	for env_name in ENV_VARS:
		var value := String(env.get(env_name, ""))
		if value != "":
			_assign(cfg, ENV_VARS[env_name], value, env_name, errors)
	for raw in args:
		var arg := String(raw)
		if arg == "--server" or arg == "--bot" or arg == "--client":
			cfg.role = arg.substr(2)
			continue
		if not arg.begins_with("--"):
			errors.append("unexpected argument '%s'" % arg)
			continue
		var parts := arg.substr(2).split("=", true, 1)
		var key := parts[0].replace("-", "_")
		var value := parts[1] if parts.size() > 1 else "true"
		_assign(cfg, key, value, "--" + parts[0], errors)
	_validate(cfg, errors)
	cfg["errors"] = errors
	return cfg


static func _assign(cfg: Dictionary, key: String, value: String, source: String, errors: Array[String]) -> void:
	if not DEFAULTS.has(key):
		errors.append("unknown option %s" % source)
		return
	match typeof(DEFAULTS[key]):
		TYPE_INT:
			if value.is_valid_int():
				cfg[key] = value.to_int()
			else:
				errors.append("%s expects an integer, got '%s'" % [source, value])
		TYPE_FLOAT:
			if value.is_valid_float():
				cfg[key] = value.to_float()
			else:
				errors.append("%s expects a number, got '%s'" % [source, value])
		TYPE_BOOL:
			if value.to_lower() in ["true", "1", "yes", "on"]:
				cfg[key] = true
			elif value.to_lower() in ["false", "0", "no", "off"]:
				cfg[key] = false
			else:
				errors.append("%s expects true/false, got '%s'" % [source, value])
		_:
			cfg[key] = value


static func _validate(cfg: Dictionary, errors: Array[String]) -> void:
	if not cfg.role in ROLES:
		errors.append("role must be one of %s" % [ROLES])
	if cfg.port < 1 or cfg.port > 65535:
		errors.append("port must be 1-65535")
	if cfg.seed < 0 or cfg.seed > 2147483646:
		errors.append("seed must be 0-2147483646 (stored exactly in JSON)")
	var id_re := RegEx.create_from_string(ID_PATTERN)
	for key in ["world_id", "env_id"]:
		if id_re.search(cfg[key]) == null:
			errors.append("%s '%s' must match %s" % [key, cfg[key], ID_PATTERN])
	if cfg.role == "server":
		if cfg.data_dir == "" or not (cfg.data_dir.is_absolute_path()):
			errors.append("server requires an absolute --data-dir (or STRUCTURE_DATA_DIR)")
		if cfg.tick_rate < 1 or cfg.tick_rate > 240:
			errors.append("tick_rate must be 1-240")
		if cfg.sync_rate < 1 or cfg.sync_rate > cfg.tick_rate:
			errors.append("sync_rate must be 1-tick_rate")
		if cfg.max_players < 1 or cfg.max_players > 256:
			errors.append("max_players must be 1-256")
	if cfg.role == "bot" and cfg.connect == "":
		errors.append("bot requires --connect=host:port")
	if cfg.connect != "" and parse_address(cfg.connect).is_empty():
		errors.append("--connect expects host:port, got '%s'" % cfg.connect)
	if not cfg.log_level in ["debug", "info", "warn", "error"]:
		errors.append("log_level must be debug|info|warn|error")


## "host:port" -> {"host": String, "port": int}; {} when malformed.
static func parse_address(address: String) -> Dictionary:
	var idx := address.rfind(":")
	if idx <= 0:
		return {}
	var port_text := address.substr(idx + 1)
	if not port_text.is_valid_int():
		return {}
	var port := port_text.to_int()
	if port < 1 or port > 65535:
		return {}
	return {"host": address.substr(0, idx), "port": port}
