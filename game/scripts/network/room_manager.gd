extends Node
class_name RoomManager

## Local runtime room registry. A future network adapter can replace this API.

signal room_updated(room_code: String, room_record: Dictionary)
signal match_started(room_code: String, roster: Array, game_mode: String)
signal room_closed(room_code: String, reason: String)
signal network_error(error_code: String, message: String)

const ROOM_DATA_SCRIPT = preload("res://scripts/network/room_data.gd")
const NETWORK_CLIENT_SCRIPT = preload("res://scripts/network/network_client.gd")
const NetworkConfig = preload("res://scripts/network/network_config.gd")
const ROOM_CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const VALID_MAX_PLAYER_COUNTS: Array[int] = [2, 4, 6, 8, 10]
const TEAM_RED := 1
const TEAM_BLUE := 2
const STATUS_WAITING := "WAITING"
const STATUS_STARTED := "STARTED"
const STATUS_CLOSED := "CLOSED"
const DEFAULT_CHARACTER_ID := "mint"
const VALID_CHARACTER_IDS: Array[String] = ["mint", "peach", "sky"]
const MODE_1V1 := "1v1"
const MODE_2V2 := "2v2"
const MODE_3V3 := "3v3"
const VALID_MODES: Array[String] = [MODE_1V1, MODE_2V2, MODE_3V3]
const MODE_CAPACITIES := {
	MODE_1V1: 2,
	MODE_2V2: 4,
	MODE_3V3: 6,
}
const MODE_GRID_SIZES := {
	MODE_1V1: 6,
	MODE_2V2: 8,
	MODE_3V3: 10,
}

@export var use_networking := true
@export var server_url := ""

var active_room_code := ""
var active_player_id := ""
var local_player_name := ""
var network_client: NetworkClient = null
var _rooms_by_code: Dictionary = {}


func _init() -> void:
	if server_url.is_empty():
		server_url = NetworkConfig.get_default_server_url()


func _ready() -> void:
	if server_url.is_empty():
		server_url = NetworkConfig.get_default_server_url()
	if use_networking:
		_setup_network_client()


func _setup_network_client() -> void:
	if network_client != null:
		return
	network_client = NETWORK_CLIENT_SCRIPT.new()
	network_client.name = "NetworkClient"
	network_client.server_url = server_url
	add_child(network_client)
	network_client.client_id_assigned.connect(func(cid: String) -> void: active_player_id = cid)
	network_client.room_state_received.connect(_on_server_room_state)
	network_client.match_started_received.connect(_on_server_match_started)
	network_client.room_closed_received.connect(_on_server_room_closed)
	network_client.error_received.connect(_on_server_error)


func is_online() -> bool:
	return network_client != null and network_client.is_connected_to_server


func set_server_url(new_url: String) -> Dictionary:
	var clean := NetworkConfig.normalize_server_url(new_url)
	var validation := NetworkConfig.validate_server_url(clean)
	if not bool(validation.get("valid", false)):
		var err_msg := str(validation.get("error"))
		var err_code := str(validation.get("code"))
		network_error.emit(err_code, err_msg)
		return {"success": false, "message": err_msg, "code": err_code}

	server_url = clean
	if network_client != null:
		network_client.disconnect_from_server()
		network_client.connect_to_server(server_url)
	return {"success": true, "url": server_url}


func is_active_room_online() -> bool:
	if not is_online():
		return false
	var room: RoomData = _rooms_by_code.get(active_room_code)
	return room != null and room.is_server_room


func create_room_online(
	host_player_id: String,
	host_display_name: String,
	room_name: String = "",
	max_players: int = 10,
	visibility: String = "PRIVATE",
	game_mode: String = ""
) -> Dictionary:
	if not is_online():
		var validation := NetworkConfig.validate_server_url(server_url)
		if not bool(validation.get("valid", false)):
			return _failure(str(validation.get("code")), str(validation.get("error")))
		return _failure("NOT_CONNECTED", "Not connected to game server at %s." % server_url)

	var selected_mode := game_mode.strip_edges()
	if not selected_mode.is_empty() and not VALID_MODES.has(selected_mode):
		return _failure("INVALID_MODE", "Choose 1v1, 2v2, or 3v3.")

	if not selected_mode.is_empty():
		max_players = int(MODE_CAPACITIES.get(selected_mode, max_players))

	var clean_name := room_name.strip_edges()
	var clean_disp := _clean_display_name(host_display_name, "Host")

	var msg := {
		"type": "CREATE_ROOM",
		"room_name": clean_name,
		"max_players": max_players,
		"visibility": visibility.strip_edges().to_upper(),
		"game_mode": selected_mode,
		"display_name": clean_disp,
	}
	network_client.send_message(msg)

	var response: Dictionary = await _await_network_response(5.0)
	if not bool(response.get("success", false)):
		if str(response.get("error_code")) == "ALREADY_IN_ROOM" or str(response.get("message")).contains("Leave current room"):
			network_client.send_message({"type": "LEAVE_ROOM"})
			var tree := get_tree()
			if tree != null:
				await tree.create_timer(0.35).timeout
			network_client.send_message(msg)
			response = await _await_network_response(5.0)
			if not bool(response.get("success", false)):
				return response
		else:
			return response

	return {"success": true, "room": get_active_room_record(), "error_code": "", "message": "Room created."}


func join_room_online(room_code: String, player_id: String, display_name: String) -> Dictionary:
	if not is_online():
		var validation := NetworkConfig.validate_server_url(server_url)
		if not bool(validation.get("valid", false)):
			return _failure(str(validation.get("code")), str(validation.get("error")))
		return _failure("NOT_CONNECTED", "Not connected to game server at %s." % server_url)

	var normalized_code := normalize_room_code(room_code)
	if not is_valid_room_code(normalized_code):
		return _failure("INVALID_CODE", "Enter a valid six-character room code.")

	var clean_disp := _clean_display_name(display_name, "Player")

	var msg := {
		"type": "JOIN_ROOM",
		"room_code": normalized_code,
		"display_name": clean_disp,
	}
	network_client.send_message(msg)

	var response: Dictionary = await _await_network_response(5.0)
	if not bool(response.get("success", false)):
		if str(response.get("error_code")) == "ALREADY_IN_ROOM" or str(response.get("message")).contains("Leave current room"):
			network_client.send_message({"type": "LEAVE_ROOM"})
			var tree := get_tree()
			if tree != null:
				await tree.create_timer(0.35).timeout
			network_client.send_message(msg)
			response = await _await_network_response(5.0)
			if not bool(response.get("success", false)):
				return response
		else:
			return response

	return {"success": true, "room": get_active_room_record(), "error_code": "", "message": "Joined room."}


func _await_network_response(timeout_seconds: float = 5.0) -> Dictionary:
	var result := {"resolved": false, "success": false, "error_code": "", "message": ""}

	var on_state: Callable
	var on_error: Callable

	on_state = func(room_dict: Dictionary) -> void:
		if not result["resolved"]:
			result["resolved"] = true
			result["success"] = true
			result["room"] = room_dict

	on_error = func(err_code: String, err_msg: String) -> void:
		if not result["resolved"]:
			result["resolved"] = true
			result["success"] = false
			result["error_code"] = err_code
			result["message"] = err_msg

	network_client.room_state_received.connect(on_state)
	network_client.error_received.connect(on_error)

	var elapsed := 0.0
	var tree := get_tree()
	while not result["resolved"] and elapsed < timeout_seconds:
		if tree != null:
			await tree.process_frame
			elapsed += get_process_delta_time()
		else:
			break

	if network_client.room_state_received.is_connected(on_state):
		network_client.room_state_received.disconnect(on_state)
	if network_client.error_received.is_connected(on_error):
		network_client.error_received.disconnect(on_error)

	if not result["resolved"]:
		return _failure("TIMEOUT", "Server request timed out. Please check server connection.")
	return result


func _on_server_room_state(room_dict: Dictionary) -> void:
	var code := str(room_dict.get("room_code", ""))
	if code.is_empty():
		return
	var room: RoomData = _rooms_by_code.get(code)
	if room == null:
		room = ROOM_DATA_SCRIPT.new()
		_rooms_by_code[code] = room

	room.room_id = str(room_dict.get("room_id", "room_" + code))
	room.room_code = code
	room.room_name = str(room_dict.get("room_name", "Room " + code))
	room.host_player_id = str(room_dict.get("host_player_id", ""))
	room.max_players = int(room_dict.get("max_players", 2))
	room.visibility = str(room_dict.get("visibility", "PRIVATE"))
	room.status = str(room_dict.get("status", STATUS_WAITING))
	room.game_mode = str(room_dict.get("game_mode", ""))
	room.is_server_room = true

	room.players.clear()
	for p in room_dict.get("players", []):
		if p is Dictionary:
			room.players.append((p as Dictionary).duplicate(true))

	room.started_match_roster.clear()
	for p in room_dict.get("started_match_roster", []):
		if p is Dictionary:
			room.started_match_roster.append((p as Dictionary).duplicate(true))

	active_room_code = code
	if network_client != null and not network_client.client_player_id.is_empty():
		active_player_id = network_client.client_player_id

	_emit_room_updated(room)


func _on_server_match_started(code: String, roster: Array, mode: String) -> void:
	var room: RoomData = _rooms_by_code.get(code)
	if room != null:
		room.status = STATUS_STARTED
		room.started_match_roster.clear()
		for p in roster:
			if p is Dictionary:
				room.started_match_roster.append((p as Dictionary).duplicate(true))
		_emit_room_updated(room)
	match_started.emit(code, roster, mode)


func _on_server_room_closed(code: String, reason: String) -> void:
	var room: RoomData = _rooms_by_code.get(code)
	if room != null:
		room.status = STATUS_CLOSED
		_emit_room_updated(room)
	if active_room_code == code or active_room_code.is_empty():
		active_room_code = ""
		if network_client != null and not network_client.client_player_id.is_empty():
			active_player_id = network_client.client_player_id
		else:
			active_player_id = ""
	room_closed.emit(code, reason)


func _on_server_error(code: String, message: String) -> void:
	network_error.emit(code, message)


func create_room(
	host_player_id: String,
	host_display_name: String,
	room_name: String = "",
	max_players: int = 10,
	visibility: String = "PRIVATE",
	game_mode: String = ""
) -> Dictionary:
	var normalized_host_id := host_player_id.strip_edges()
	if normalized_host_id.is_empty():
		return _failure("INVALID_PLAYER_ID", "A valid host player ID is required.")

	var selected_mode := game_mode.strip_edges()
	if not selected_mode.is_empty() and not VALID_MODES.has(selected_mode):
		return _failure("INVALID_MODE", "Choose 1v1, 2v2, or 3v3.")

	if not selected_mode.is_empty():
		max_players = int(MODE_CAPACITIES.get(selected_mode, max_players))

	if not VALID_MAX_PLAYER_COUNTS.has(max_players):
		return _failure("INVALID_MAX_PLAYERS", "Choose an even room size from 2, 4, 6, 8, or 10.")

	var normalized_visibility := visibility.strip_edges().to_upper()
	if normalized_visibility != "PUBLIC" and normalized_visibility != "PRIVATE":
		return _failure("INVALID_VISIBILITY", "Room visibility must be Public or Private.")

	var room_code := generate_unique_room_code()
	if room_code.is_empty():
		return _failure("CODE_GENERATION_FAILED", "A unique room code could not be generated. Please try again.")

	var room: Variant = ROOM_DATA_SCRIPT.new()
	room.room_id = "room_%s" % room_code
	room.room_code = room_code
	var clean_room_name := room_name.strip_edges()
	room.room_name = clean_room_name if not clean_room_name.is_empty() else "Room %s" % room_code
	room.host_player_id = normalized_host_id
	room.max_players = max_players
	room.visibility = normalized_visibility
	room.status = STATUS_WAITING
	room.game_mode = selected_mode
	var host_record := {
		"player_id": normalized_host_id,
		"display_name": _clean_display_name(host_display_name, "Host"),
		"team_id": TEAM_RED,
		"character_id": DEFAULT_CHARACTER_ID,
		"is_host": true,
		"is_ready": false,
	}
	if not room.add_player(host_record):
		return _failure("HOST_REGISTRATION_FAILED", "The host could not be added to the room.")

	_rooms_by_code[room_code] = room
	active_room_code = room_code
	active_player_id = normalized_host_id
	if is_online():
		network_client.send_message({
			"type": "CREATE_ROOM",
			"room_code": room_code,
			"room_name": clean_room_name,
			"max_players": max_players,
			"visibility": normalized_visibility,
			"game_mode": selected_mode,
			"display_name": _clean_display_name(host_display_name, "Host"),
		})
	return {"success": true, "room": room.to_dictionary(), "error_code": "", "message": "Room created."}


func find_room_by_code(room_code: String) -> Variant:
	var normalized_code := normalize_room_code(room_code)
	if not is_valid_room_code(normalized_code):
		return null
	return _rooms_by_code.get(normalized_code)


func get_room_record(room_code: String) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	return room.to_dictionary() if room != null else {}


func get_room_info(room_code: String) -> Dictionary:
	return get_room_record(room_code)


func get_active_room_record() -> Dictionary:
	if active_room_code.is_empty():
		return {}
	return get_room_record(active_room_code)


func get_players_by_team(room_code: String, team_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var room: Variant = find_room_by_code(room_code)
	if room == null or (team_id != TEAM_RED and team_id != TEAM_BLUE):
		return result
	for player in room.players:
		if int(player.get("team_id", 0)) == team_id:
			result.append(player.duplicate(true))
	return result


func get_ready_count(room_code: String) -> int:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return 0
	var ready_count := 0
	for player in room.players:
		if bool(player.get("is_ready", false)):
			ready_count += 1
	return ready_count


func toggle_player_ready(room_code: String, player_id: String) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	if room.status != STATUS_WAITING:
		return _failure("ROOM_NOT_WAITING", "Readiness is locked because this match has started.")

	if is_online():
		network_client.send_message({
			"type": "TOGGLE_READY",
			"room_code": room_code,
		})

	var normalized_player_id := player_id.strip_edges()
	for index in range(room.players.size()):
		if str(room.players[index].get("player_id", "")) != normalized_player_id:
			continue
		room.players[index]["is_ready"] = not bool(room.players[index].get("is_ready", false))
		_emit_room_updated(room)
		return {
			"success": true,
			"is_ready": bool(room.players[index]["is_ready"]),
			"room": room.to_dictionary(),
			"message": "You are READY." if bool(room.players[index]["is_ready"]) else "You are NOT READY.",
		}
	return _failure("PLAYER_NOT_IN_ROOM", "This player is not in the room.")


func get_match_start_validation(room_code: String, requesting_player_id: String) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	return _validate_match_start(room, requesting_player_id)


func start_match(room_code: String, requesting_player_id: String) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	var validation := _validate_match_start(room, requesting_player_id)
	if not bool(validation.get("success", false)):
		return validation

	if is_online():
		network_client.send_message({
			"type": "START_MATCH",
			"room_code": room_code,
		})
		return {
			"success": true,
			"room": room.to_dictionary(),
			"roster": room.players.duplicate(true),
			"message": "Starting match...",
		}

	# Snapshot exact registered records once; the roster is immutable after start.
	room.started_match_roster = room.players.duplicate(true)
	room.status = STATUS_STARTED
	_emit_room_updated(room)
	match_started.emit(room_code, room.started_match_roster.duplicate(true), str(room.game_mode))
	return {
		"success": true,
		"room": room.to_dictionary(),
		"roster": room.started_match_roster.duplicate(true),
		"message": "Match started.",
	}


func start_room_match(room_code: String, requesting_player_id: String) -> Dictionary:
	return start_match(room_code, requesting_player_id)


func switch_player_team(room_code: String, player_id: String, target_team_id: int) -> Dictionary:
	return update_player_team(room_code, player_id, target_team_id)


func get_started_match_roster(room_code: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var room: Variant = find_room_by_code(room_code)
	if room == null or room.status != STATUS_STARTED:
		return result
	return room.started_match_roster.duplicate(true)


func update_player_team(room_code: String, player_id: String, target_team_id: int) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	if room.status != STATUS_WAITING:
		return _failure("ROOM_NOT_WAITING", "Teams can only be changed while the room is waiting.")
	if target_team_id != TEAM_RED and target_team_id != TEAM_BLUE:
		return _failure("INVALID_TEAM", "Choose Red Team or Blue Team.")

	var normalized_player_id := player_id.strip_edges()
	var found_index := -1
	for index in range(room.players.size()):
		if str(room.players[index].get("player_id", "")) == normalized_player_id:
			found_index = index
			break
	if found_index < 0:
		return _failure("PLAYER_NOT_IN_ROOM", "This player is not in the room.")
	if int(room.players[found_index].get("team_id", 0)) == target_team_id:
		return {"success": true, "room": room.to_dictionary(), "message": "Player is already on that team."}

	var team_capacity := int(room.max_players / 2)
	var target_team_count := 0
	for player in room.players:
		if int(player.get("team_id", 0)) == target_team_id:
			target_team_count += 1
	if target_team_count >= team_capacity:
		return _failure("TEAM_FULL", "That team is full. Choose the other team or wait for a spot.")

	if is_online():
		network_client.send_message({
			"type": "UPDATE_TEAM",
			"room_code": room_code,
			"team_id": target_team_id,
		})

	room.players[found_index]["team_id"] = target_team_id
	_emit_room_updated(room)
	return {"success": true, "room": room.to_dictionary(), "message": "Team changed."}


func update_player_character(room_code: String, player_id: String, character_id: String) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	if room.status != STATUS_WAITING:
		return _failure("ROOM_NOT_WAITING", "Characters can only be changed while the room is waiting.")
	if not VALID_CHARACTER_IDS.has(character_id):
		return _failure("INVALID_CHARACTER", "Choose one of the available characters.")

	var normalized_player_id := player_id.strip_edges()
	for index in range(room.players.size()):
		if str(room.players[index].get("player_id", "")) != normalized_player_id:
			continue
		if is_online():
			network_client.send_message({
				"type": "UPDATE_CHARACTER",
				"room_code": room_code,
				"character_id": character_id,
			})
		room.players[index]["character_id"] = character_id
		_emit_room_updated(room)
		return {"success": true, "room": room.to_dictionary(), "message": "Character updated."}
	return _failure("PLAYER_NOT_IN_ROOM", "This player is not in the room.")


func update_player_name(room_code: String, player_id: String, new_display_name: String) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	if room.status != STATUS_WAITING:
		return _failure("ROOM_NOT_WAITING", "Names can only be changed while the room is waiting.")

	var clean_name := new_display_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Player"

	var normalized_player_id := player_id.strip_edges()
	for index in range(room.players.size()):
		if str(room.players[index].get("player_id", "")) != normalized_player_id:
			continue
		if is_online():
			network_client.send_message({
				"type": "UPDATE_NAME",
				"room_code": room_code,
				"display_name": clean_name,
			})
		room.players[index]["display_name"] = clean_name
		local_player_name = clean_name
		_emit_room_updated(room)
		return {"success": true, "room": room.to_dictionary(), "message": "Name updated."}
	return _failure("PLAYER_NOT_IN_ROOM", "This player is not in the room.")


func join_room(room_code: String, player_id: String, display_name: String) -> Dictionary:
	var normalized_code := normalize_room_code(room_code)
	if not is_valid_room_code(normalized_code):
		return _failure("INVALID_CODE", "Enter a valid six-character room code.")
	var normalized_player_id := player_id.strip_edges()
	if normalized_player_id.is_empty():
		return _failure("INVALID_PLAYER_ID", "A valid player ID is required to join.")

	var room: Variant = find_room_by_code(normalized_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "No room with that code exists in this running game.")
	if room.status == STATUS_STARTED:
		return _failure("ROOM_STARTED", "This room has already started.")
	if room.status == STATUS_CLOSED:
		return _failure("ROOM_CLOSED", "This room is closed.")
	if room.host_player_id == normalized_player_id:
		return _failure("HOST_ALREADY_IN_ROOM", "The host is already in this room.")
	if room.find_player(normalized_player_id).size() > 0:
		return _failure("DUPLICATE_PLAYER", "This player is already in the room.")
	if room.players.size() >= room.max_players:
		return _failure("ROOM_FULL", "This room is full.")

	var guest_record := {
		"player_id": normalized_player_id,
		"display_name": _clean_display_name(display_name, "Player"),
		"team_id": _get_team_with_space(room),
		"character_id": DEFAULT_CHARACTER_ID,
		"is_host": false,
		"is_ready": false,
	}
	if not room.add_player(guest_record):
		return _failure("JOIN_FAILED", "The player could not be added to the room.")

	active_room_code = normalized_code
	active_player_id = guest_record["player_id"]
	_emit_room_updated(room)
	return {"success": true, "room": room.to_dictionary(), "error_code": "", "message": "Joined room."}


func leave_room(room_code: String, player_id: String) -> Dictionary:
	if is_online():
		network_client.send_message({
			"type": "LEAVE_ROOM",
			"room_code": room_code,
		})
	if active_room_code == room_code:
		active_room_code = ""
		if network_client != null and not network_client.client_player_id.is_empty():
			active_player_id = network_client.client_player_id

	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	if room.status == STATUS_CLOSED:
		return _failure("ROOM_CLOSED", "This room is already closed.")
	if room.find_player(player_id).is_empty():
		return _failure("PLAYER_NOT_IN_ROOM", "This player is not in the room.")

	if player_id == room.host_player_id:
		if room.players.size() > 1:
			room.remove_player(player_id)
			var next_player: Dictionary = room.players[0]
			room.host_player_id = str(next_player.get("player_id", ""))
			next_player["is_host"] = true
			_emit_room_updated(room)
			return {"success": true, "room": room.to_dictionary(), "room_closed": false, "message": "Host left. Migrated host to next player."}
		else:
			room.status = STATUS_CLOSED
			_rooms_by_code.erase(normalize_room_code(room_code))
			_emit_room_updated(room)
			return {"success": true, "room": room.to_dictionary(), "room_closed": true, "message": "The host left and closed the room."}

	room.remove_player(player_id)
	_emit_room_updated(room)
	return {"success": true, "room": room.to_dictionary(), "room_closed": false, "message": "Player left the room."}


func close_room(room_code: String) -> bool:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return false
	room.status = STATUS_CLOSED
	if active_room_code == room.room_code:
		active_room_code = ""
		active_player_id = ""
	return true


func start_room(room_code: String, requesting_player_id: String) -> bool:
	return bool(start_match(room_code, requesting_player_id).get("success", false))


func _validate_match_start(room: Variant, requesting_player_id: String) -> Dictionary:
	if room.status != STATUS_WAITING:
		return _failure("ROOM_NOT_WAITING", "This room has already started or is closed.")
	if str(room.host_player_id) != requesting_player_id:
		return _failure("HOST_ONLY", "Only the host can start the match.")
	var player_count: int = room.players.size()
	if player_count < 2:
		return _failure("NOT_ENOUGH_PLAYERS", "At least 2 registered players are required.")
	if player_count > int(room.max_players):
		return _failure("ROOM_OVER_CAPACITY", "The player count exceeds this room's capacity.")
	var red_count := 0
	var blue_count := 0
	var ready_count := 0
	var seen_ids: Dictionary = {}
	for player in room.players:
		var player_id := str(player.get("player_id", ""))
		if player_id.is_empty() or seen_ids.has(player_id):
			return _failure("INVALID_ROSTER", "Every player must have a unique player ID.")
		seen_ids[player_id] = true
		match int(player.get("team_id", 0)):
			TEAM_RED:
				red_count += 1
			TEAM_BLUE:
				blue_count += 1
			_:
				return _failure("INVALID_TEAM", "Every player must be assigned to Red or Blue Team.")
		if bool(player.get("is_ready", false)):
			ready_count += 1
	if VALID_MODES.has(str(room.game_mode)):
		var expected_capacity := int(MODE_CAPACITIES[str(room.game_mode)])
		var target_per_team := int(expected_capacity / 2)
		if player_count != expected_capacity:
			return _failure("ROOM_NOT_FULL", "The room must be full (%d players) before the host can start." % expected_capacity)
		if red_count != target_per_team or blue_count != target_per_team:
			return _failure("TEAMS_NOT_EQUAL", "Both teams must have exactly %d players each." % target_per_team)
	elif red_count < 1 or blue_count < 1:
		return _failure("BOTH_TEAMS_REQUIRED", "At least one player must be on each team.")
	if ready_count != player_count:
		return _failure("PLAYERS_NOT_READY", "Every player must be READY before the host can start.")
	return {"success": true, "error_code": "", "message": "The room is ready to start."}


func reset_room_for_replay(room_code: String) -> Dictionary:
	var room: Variant = find_room_by_code(room_code)
	if room == null:
		return _failure("ROOM_NOT_FOUND", "The room could not be found.")
	room.status = STATUS_WAITING
	room.started_match_roster.clear()
	for index in range(room.players.size()):
		room.players[index]["is_ready"] = false
	_emit_room_updated(room)
	return {"success": true, "room": room.to_dictionary(), "message": "Room reset for play again."}


func _emit_room_updated(room: Variant) -> void:
	room_updated.emit(str(room.room_code), room.to_dictionary())


func normalize_room_code(room_code: String) -> String:
	return room_code.strip_edges().to_upper()


func is_valid_room_code(room_code: String) -> bool:
	if room_code.length() != 6:
		return false
	for character in room_code:
		if not ROOM_CODE_ALPHABET.contains(character):
			return false
	return true


func generate_unique_room_code() -> String:
	for _attempt in range(256):
		var candidate := ""
		for _character_index in range(6):
			var alphabet_index := randi_range(0, ROOM_CODE_ALPHABET.length() - 1)
			candidate += ROOM_CODE_ALPHABET.substr(alphabet_index, 1)
		if not _rooms_by_code.has(candidate):
			return candidate
	return ""


func _get_team_with_space(room: Variant) -> int:
	var red_count := 0
	var blue_count := 0
	for player in room.players:
		if int(player.get("team_id", 0)) == TEAM_RED:
			red_count += 1
		elif int(player.get("team_id", 0)) == TEAM_BLUE:
			blue_count += 1
	return TEAM_RED if red_count <= blue_count else TEAM_BLUE


func _clean_display_name(display_name: String, fallback: String) -> String:
	var clean_name := display_name.strip_edges()
	return clean_name if not clean_name.is_empty() else fallback


func _failure(error_code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "message": message}
