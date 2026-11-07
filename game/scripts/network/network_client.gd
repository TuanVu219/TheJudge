extends Node
class_name NetworkClient

## Manages WebSocket connection to The Judge authoritative game server.

signal connected_to_server
signal connection_closed
signal client_id_assigned(client_id: String)
signal room_state_received(room_record: Dictionary)
signal match_started_received(room_code: String, roster: Array, game_mode: String)
signal room_closed_received(room_code: String, reason: String)
signal player_moved_received(player_id: String, position: Vector3, velocity: Vector3, rotation_y: float)
signal tile_claimed_received(col: int, row: int, team_id: int, red_score: int, blue_score: int)
signal match_reset_received(room_code: String)
signal error_received(error_code: String, message: String)

const NetworkConfig = preload("res://scripts/network/network_config.gd")
const RECONNECT_INTERVAL_SECONDS := 2.0

@export var server_url := ""
@export var auto_connect := true

var _peer: WebSocketPeer = WebSocketPeer.new()
var is_connected_to_server := false
var client_player_id := ""
var _last_state := WebSocketPeer.STATE_CLOSED
var _reconnect_timer := 0.0


func _init() -> void:
	if server_url.is_empty():
		server_url = NetworkConfig.get_default_server_url()


func _ready() -> void:
	if server_url.is_empty():
		server_url = NetworkConfig.get_default_server_url()
	if auto_connect:
		connect_to_server(server_url)


func connect_to_server(url: String = "") -> Error:
	if not url.is_empty():
		server_url = url
	elif server_url.is_empty():
		server_url = NetworkConfig.get_default_server_url()

	server_url = NetworkConfig.normalize_server_url(server_url)

	var validation := NetworkConfig.validate_server_url(server_url)
	if not bool(validation.get("valid", false)):
		var err_msg := str(validation.get("error", "Invalid server address."))
		var err_code := str(validation.get("code", "INVALID_SERVER_URL"))
		push_warning("[NetworkClient] Server address rejected: %s" % err_msg)
		error_received.emit(err_code, err_msg)
		return ERR_INVALID_PARAMETER

	print("[NetworkClient] Connecting to %s..." % server_url)
	var err := _peer.connect_to_url(server_url)
	if err != OK:
		push_warning("[NetworkClient] Failed to initiate connection to %s (code %d)" % [server_url, err])
		error_received.emit("CONNECTION_FAILED", "Failed to connect to server (%d)" % err)
	return err


func disconnect_from_server() -> void:
	_peer.close()
	_peer = WebSocketPeer.new()
	is_connected_to_server = false
	_last_state = WebSocketPeer.STATE_CLOSED


func _process(delta: float) -> void:
	_peer.poll()
	var state := _peer.get_ready_state()

	if state != _last_state:
		_last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			is_connected_to_server = true
			print("[NetworkClient] Connected to server successfully.")
			connected_to_server.emit()
		elif state == WebSocketPeer.STATE_CLOSED:
			if is_connected_to_server:
				print("[NetworkClient] Connection to server closed (code %d: %s)" % [_peer.get_close_code(), _peer.get_close_reason()])
				connection_closed.emit()
			is_connected_to_server = false

	if state == WebSocketPeer.STATE_OPEN:
		while _peer.get_available_packet_count() > 0:
			var raw := _peer.get_packet().get_string_from_utf8()
			_handle_server_message(raw)
	elif auto_connect and state == WebSocketPeer.STATE_CLOSED:
		var validation := NetworkConfig.validate_server_url(server_url)
		if bool(validation.get("valid", false)):
			_reconnect_timer += delta
			if _reconnect_timer >= RECONNECT_INTERVAL_SECONDS:
				_reconnect_timer = 0.0
				connect_to_server()


func send_message(message: Dictionary) -> bool:
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var json_str := JSON.stringify(message)
	var err := _peer.send_text(json_str)
	return err == OK


func _handle_server_message(raw_json: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_json)
	if not (parsed is Dictionary):
		return
	var data := parsed as Dictionary
	var msg_type := str(data.get("type", ""))

	match msg_type:
		"CONNECTED":
			client_player_id = str(data.get("client_id", ""))
			print("[NetworkClient] Assigned client ID: %s" % client_player_id)
			client_id_assigned.emit(client_player_id)

		"ROOM_STATE":
			var room_dict: Dictionary = data.get("room", {})
			room_state_received.emit(room_dict)

		"MATCH_STARTED":
			var code := str(data.get("room_code", ""))
			var roster: Array = data.get("roster", [])
			var mode := str(data.get("game_mode", ""))
			match_started_received.emit(code, roster, mode)

		"ROOM_CLOSED":
			var code := str(data.get("room_code", ""))
			var reason := str(data.get("reason", "Room was closed."))
			room_closed_received.emit(code, reason)

		"PLAYER_MOVED":
			var pid := str(data.get("player_id", ""))
			var pos_arr: Array = data.get("position", [0.0, 0.0, 0.0])
			var vel_arr: Array = data.get("velocity", [0.0, 0.0, 0.0])
			var rot_y := float(data.get("rotation", 0.0))
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) if pos_arr.size() >= 3 else Vector3.ZERO
			var vel := Vector3(float(vel_arr[0]), float(vel_arr[1]), float(vel_arr[2])) if vel_arr.size() >= 3 else Vector3.ZERO
			player_moved_received.emit(pid, pos, vel, rot_y)

		"TILE_CLAIMED":
			var col := int(data.get("col", 0))
			var row := int(data.get("row", 0))
			var tid := int(data.get("team_id", 0))
			var r_score := int(data.get("red_score", 0))
			var b_score := int(data.get("blue_score", 0))
			tile_claimed_received.emit(col, row, tid, r_score, b_score)

		"MATCH_RESET":
			var code := str(data.get("room_code", ""))
			match_reset_received.emit(code)

		"ERROR":
			var code := str(data.get("error_code", "ERROR"))
			var message := str(data.get("message", "An error occurred."))
			push_warning("[NetworkClient] Server error: [%s] %s" % [code, message])
			error_received.emit(code, message)

		"PONG":
			pass


func send_player_move(room_code: String, pos: Vector3, vel: Vector3, rot_y: float) -> void:
	send_message({
		"type": "PLAYER_MOVE",
		"room_code": room_code,
		"position": [pos.x, pos.y, pos.z],
		"velocity": [vel.x, vel.y, vel.z],
		"rotation": rot_y,
	})


func send_claim_tile(room_code: String, col: int, row: int) -> void:
	send_message({
		"type": "CLAIM_TILE",
		"room_code": room_code,
		"col": col,
		"row": row,
	})


func send_rematch_request(room_code: String) -> void:
	send_message({
		"type": "REMATCH_REQUEST",
		"room_code": room_code,
	})
