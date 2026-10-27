## Boot: resolve configuration, then build the node graph for one role.
##   /root/Main/Session  network endpoint (identical on every peer, so RPC paths match)
##   /root/Main/App      role logic: server | client | bot
extends Node

const AppConfig = preload("res://core/app_config.gd")
const Log = preload("res://core/log.gd")
const Session = preload("res://net/session.gd")
const ServerApp = preload("res://server/server_app.gd")
const ClientApp = preload("res://client/client_app.gd")
const BotApp = preload("res://bots/bot_app.gd")


func _ready() -> void:
	var cfg := AppConfig.load_from_os()
	Log.configure(cfg.role, cfg.env_id, cfg.log_level)
	if not cfg.errors.is_empty():
		Log.event("config.invalid", {"errors": cfg.errors}, "error")
		get_tree().quit(2)
		return
	if cfg.role == "client" and DisplayServer.get_name() == "headless":
		Log.event("config.invalid", {"errors": ["the client role needs a display; use --bot for headless clients"]}, "error")
		get_tree().quit(2)
		return
	var session := Session.new()
	session.name = "Session"
	add_child(session)
	var app: Node
	match cfg.role:
		"server":
			app = ServerApp.new()
		"bot":
			app = BotApp.new()
		_:
			app = ClientApp.new()
	app.name = "App"
	app.setup(cfg, session)
	add_child(app)
