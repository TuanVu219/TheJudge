extends RefCounted
class_name RoomData

## In-memory room record. UI code receives copies through to_dictionary().

const STATUS_WAITING := "WAITING"
const STATUS_STARTED := "STARTED"
const STATUS_CLOSED := "CLOSED"
const DEFAULT_CHARACTER_ID := "mint"

var room_id := ""
var room_code := ""
var room_name := ""
var host_player_id := ""
var max_players := 10
var visibility := "PRIVATE"
var status := STATUS_WAITING
var game_mode := ""
var is_server_room := false
var players: Array[Dictionary] = []
var started_match_roster: Array[Dictionary] = []


func to_dictionary() -> Dictionary:
	return {
		"room_id": room_id,
		"room_code": room_code,
		"room_name": room_name,
		"host_player_id": host_player_id,
		"max_players": max_players,
		"visibility": visibility,
		"status": status,
		"game_mode": game_mode,
		"is_server_room": is_server_room,
		"players": players.duplicate(true),
		"started_match_roster": started_match_roster.duplicate(true),
	}


func find_player(player_id: String) -> Dictionary:
	for player in players:
		if str(player.get("player_id", "")) == player_id:
			return player.duplicate(true)
	return {}


func add_player(player: Dictionary) -> bool:
	var player_id := str(player.get("player_id", ""))
	if player_id.is_empty() or not find_player(player_id).is_empty():
		return false
	if status != STATUS_WAITING or players.size() >= max_players:
		return false
	var stored_player := player.duplicate(true)
	if not stored_player.has("character_id"):
		stored_player["character_id"] = DEFAULT_CHARACTER_ID
	if not stored_player.has("is_ready"):
		stored_player["is_ready"] = false
	players.append(stored_player)
	return true


func remove_player(player_id: String) -> bool:
	for index in range(players.size()):
		if str(players[index].get("player_id", "")) == player_id:
			players.remove_at(index)
			return true
	return false
