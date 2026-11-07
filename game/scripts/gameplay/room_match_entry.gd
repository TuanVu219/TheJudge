extends Node

## Adapts a started room roster to MatchFlow's existing registration API.

const MATCH_FLOW_SCENE := preload("res://scenes/match/MatchFlow.tscn")

var match_flow: Node


func _ready() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	var room_manager := main.get_node_or_null("RoomManager") if main != null else null
	if room_manager == null:
		push_error("Room Match Entry could not find Main/RoomManager.")
		return

	var room: Dictionary = room_manager.call("get_active_room_record")
	if room.is_empty() or str(room.get("status", "")) != "STARTED":
		push_error("Room Match Entry requires a started room.")
		return

	var source_roster: Array[Dictionary] = room_manager.call("get_started_match_roster", str(room.get("room_code", "")))
	if source_roster.size() != Array(room.get("players", [])).size():
		push_error("Started room roster does not match the registered room players.")
		return

	var local_player_id := str(room_manager.get("active_player_id"))
	var registrations: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	var local_player_found := false
	for player in source_roster:
		var player_id := str(player.get("player_id", ""))
		if player_id.is_empty() or seen_ids.has(player_id):
			push_error("Started room roster contains a missing or duplicate player ID.")
			return
		seen_ids[player_id] = true
		var is_local_player := player_id == local_player_id
		local_player_found = local_player_found or is_local_player
		registrations.append({
			"player_id": player_id,
			"display_name": str(player.get("display_name", player_id)),
			"team_id": int(player.get("team_id", 0)),
			"character_id": str(player.get("character_id", "mint")),
			# Offline mode only controls this application's active player. Other
			# room members remain registered but are not simulated as bots.
			"is_human": is_local_player,
			"is_test_bot": false,
		})
	if not local_player_found:
		push_error("The local player is missing from the started room roster.")
		return

	match_flow = MATCH_FLOW_SCENE.instantiate()
	if not bool(match_flow.call("configure_registrations", registrations)):
		push_error("MatchFlow rejected the started room roster.")
		match_flow.queue_free()
		match_flow = null
		return
	add_child(match_flow)
