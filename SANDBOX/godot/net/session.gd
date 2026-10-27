## Network endpoint shared by every role (server, client, bot). All RPCs are declared here so the RPC
## configuration is identical on every peer. RPC bodies only authenticate the sender and validate argument
## types; role logic subscribes to the signals. Server-to-client RPCs are "authority" mode: Godot drops
## them if a client tries to send them.
extends Node

const Protocol = preload("res://net/protocol.gd")
const Log = preload("res://core/log.gd")

# Server-side signals.
signal peer_joined(peer_id: int, hello: Dictionary)
signal peer_left(peer_id: int)
signal state_reported(peer_id: int, position: Vector3, yaw: float)
signal action_requested(peer_id: int, action: String, target: String)
signal violation(peer_id: int, kind: String)
# Client-side signals.
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal welcome_received(payload: Dictionary)
signal event_received(event: Dictionary)
signal players_received(states: Array)
signal correction_received(position: Vector3)

## Server: Callable(peer_id: int, hello: Dictionary) -> {ok: bool, reason: String, name: String, info: Dictionary}
var accept_hello: Callable
var is_server := false

var _peer: ENetMultiplayerPeer
var _api: SceneMultiplayer
var _authenticated := {}  # server: peer_id -> hello, accepted but not yet connected
var _joined := {}         # server: peer_id -> hello, fully connected (receives broadcasts)
var _hello := PackedByteArray()
var _reject_reason := ""
var _closing := false


func _ready() -> void:
	_api = multiplayer as SceneMultiplayer


# ------------------------------------------------------------------------------------------ lifecycle

func start_server(port: int, bind_ip: String, max_clients: int) -> Error:
	is_server = true
	_closing = false
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(bind_ip)
	var err := _peer.create_server(port, max_clients)
	if err != OK:
		return err
	_api.server_relay = false  # clients may only talk to the server
	_api.auth_timeout = 5.0
	_api.auth_callback = _server_auth
	_api.peer_connected.connect(_on_peer_connected)
	_api.peer_disconnected.connect(_on_peer_disconnected)
	_api.peer_authentication_failed.connect(_on_auth_failed)
	_api.multiplayer_peer = _peer
	return OK


func start_client(host: String, port: int, hello: PackedByteArray) -> Error:
	is_server = false
	_closing = false
	_hello = hello
	_reject_reason = ""
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(host, port)
	if err != OK:
		return err
	_api.auth_timeout = 5.0
	_api.auth_callback = _client_auth
	if not _api.peer_authenticating.is_connected(_on_peer_authenticating):
		_api.peer_authenticating.connect(_on_peer_authenticating)
		_api.connection_failed.connect(_on_connection_failed)
		_api.server_disconnected.connect(_on_server_disconnected)
		_api.peer_authentication_failed.connect(_on_auth_failed)
	_api.multiplayer_peer = _peer
	return OK


func close() -> void:
	_closing = true
	if _peer != null:
		_peer.close()
	_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	_authenticated.clear()
	_joined.clear()


func is_connected_to_server() -> bool:
	return not is_server and _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func joined_peers() -> Array:
	return _joined.keys()


func kick(peer_id: int, reason: String) -> void:
	Log.event("net.kick", {"peer": peer_id, "reason": reason}, "warn")
	_api.disconnect_peer(peer_id)


## Bytes/second in and out since the previous call (server host statistics).
func pop_net_rates(interval_s: float) -> Dictionary:
	if _peer == null or _peer.host == null or interval_s <= 0.0:
		return {}
	return {
		"in_bps": _peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA) / interval_s,
		"out_bps": _peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / interval_s,
	}


func round_trip_ms() -> float:
	if is_server or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return -1.0
	var server_peer := _peer.get_peer(1)
	return server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if server_peer else -1.0


# ------------------------------------------------------------------------------------------ authentication

func _server_auth(peer_id: int, data: PackedByteArray) -> void:
	if _authenticated.has(peer_id) or _joined.has(peer_id):
		return
	var hello := Protocol.parse_hello(data)
	var verdict := {"ok": false, "reason": hello.get("error", "bad_hello"), "info": {}}
	if hello.ok:
		verdict = accept_hello.call(peer_id, hello)
	_api.send_auth(peer_id, Protocol.make_auth_reply(verdict.ok, verdict.get("reason", ""), verdict.get("info", {})))
	if verdict.ok:
		hello["name"] = verdict.get("name", hello.name)
		_authenticated[peer_id] = hello
		_api.complete_auth(peer_id)
	else:
		Log.event("net.auth_rejected", {"peer": peer_id, "reason": verdict.reason, "client_protocol": hello.get("protocol")}, "warn")
		# Give the reply time to reach the client before dropping it.
		get_tree().create_timer(0.5).timeout.connect(func() -> void: _api.disconnect_peer(peer_id))


func _on_peer_authenticating(peer_id: int) -> void:
	if not is_server and peer_id == 1:
		_api.send_auth(1, _hello)


func _client_auth(_peer_id: int, data: PackedByteArray) -> void:
	var reply := Protocol.parse_auth_reply(data)
	if reply.ok:
		_api.complete_auth(1)
	else:
		_reject_reason = reply.reason if reply.reason != "" else "rejected"
		Log.event("net.rejected_by_server", {"reason": _reject_reason, "info": reply.info}, "warn")


func _on_auth_failed(peer_id: int) -> void:
	if is_server:
		_authenticated.erase(peer_id)
	else:
		_emit_failure(_reject_reason if _reject_reason != "" else "auth_failed")


func _on_peer_connected(peer_id: int) -> void:
	if not _authenticated.has(peer_id):
		_api.disconnect_peer(peer_id)
		return
	_joined[peer_id] = _authenticated[peer_id]
	_authenticated.erase(peer_id)
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer:
		packet_peer.set_timeout(32, 3000, 8000)  # detect dead clients within ~8 s
	peer_joined.emit(peer_id, _joined[peer_id])


func _on_peer_disconnected(peer_id: int) -> void:
	_authenticated.erase(peer_id)
	if _joined.has(peer_id):
		_joined.erase(peer_id)
		peer_left.emit(peer_id)


func _on_connection_failed() -> void:
	_emit_failure(_reject_reason if _reject_reason != "" else "unreachable")


func _on_server_disconnected() -> void:
	if _reject_reason != "":
		_emit_failure(_reject_reason)
	elif not _closing:
		disconnected.emit("server_disconnected")


func _emit_failure(reason: String) -> void:
	if not _closing:
		connection_failed.emit(reason)


# ------------------------------------------------------------------------------------------ outbound helpers

func send_state(position: Vector3, yaw: float) -> void:
	_rpc_state.rpc_id(1, position, yaw)


func send_action(action: String, target: String) -> void:
	_rpc_action.rpc_id(1, action, target)


func send_welcome(peer_id: int, payload: Dictionary) -> void:
	if _can_send(peer_id):
		_rpc_welcome.rpc_id(peer_id, payload)


func broadcast_event(event: Dictionary) -> void:
	for peer_id in _joined:
		if _can_send(peer_id):
			_rpc_event.rpc_id(peer_id, event)


func send_event_to(peer_id: int, event: Dictionary) -> void:
	if _can_send(peer_id):
		_rpc_event.rpc_id(peer_id, event)


func broadcast_players(states: Array) -> void:
	for peer_id in _joined:
		if _can_send(peer_id):
			_rpc_players.rpc_id(peer_id, states)


func send_correction(peer_id: int, position: Vector3) -> void:
	if _can_send(peer_id):
		_rpc_correct.rpc_id(peer_id, position)


## A peer can be mid-disconnect (ENet channels gone) before peer_disconnected is processed.
func _can_send(peer_id: int) -> bool:
	if _peer == null or not _joined.has(peer_id):
		return false
	var packet_peer := _peer.get_peer(peer_id)
	return packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED


# ------------------------------------------------------------------------------------------ client -> server

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_state(position: Variant, yaw: Variant) -> void:
	var sender := _authorised_sender()
	if sender == 0:
		return
	if not Protocol.valid_vec3(position) or not Protocol.valid_yaw(yaw):
		violation.emit(sender, "bad_state")
		return
	state_reported.emit(sender, position, float(yaw))


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_action(action: Variant, target: Variant) -> void:
	var sender := _authorised_sender()
	if sender == 0:
		return
	var problem := Protocol.check_action(action, target)
	if problem != "":
		violation.emit(sender, problem)
		return
	action_requested.emit(sender, action, target)


func _authorised_sender() -> int:
	if not is_server:
		return 0
	var sender := multiplayer.get_remote_sender_id()
	return sender if _joined.has(sender) else 0


# ------------------------------------------------------------------------------------------ server -> clients

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_welcome(payload: Dictionary) -> void:
	welcome_received.emit(payload)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_event(event: Dictionary) -> void:
	event_received.emit(event)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_players(states: Array) -> void:
	players_received.emit(states)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_correct(position: Vector3) -> void:
	correction_received.emit(position)
