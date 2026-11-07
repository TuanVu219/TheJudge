extends Control

## Displays the current local room without fabricating empty player slots.

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu/MainMenu.tscn"
const LOBBY_SCENE_PATH := "res://scenes/lobby/Lobby.tscn"

@onready var room_name_label: Label = $Margin/Center/RoomCard/Content/RoomName
@onready var room_code_label: Label = $Margin/Center/RoomCard/Content/CodeCard/CodeRow/RoomCode
@onready var visibility_label: Label = $Margin/Center/RoomCard/Content/RoomSummary/Visibility
@onready var player_count_label: Label = $Margin/Center/RoomCard/Content/RoomSummary/PlayerCount
@onready var host_label: Label = $Margin/Center/RoomCard/Content/HostLabel
@onready var player_list: VBoxContainer = $Margin/Center/RoomCard/Content/PlayerScroll/PlayerList
@onready var message_label: Label = $Margin/Center/RoomCard/Content/Message
@onready var copy_button: Button = $Margin/Center/RoomCard/Content/CodeCard/CodeRow/CopyButton
@onready var enter_lobby_button: Button = $Margin/Center/RoomCard/Content/ActionRow/EnterLobbyButton
@onready var leave_button: Button = $Margin/Center/RoomCard/Content/ActionRow/LeaveButton

var _room_manager: Node
var _room_record: Dictionary = {}


func _ready() -> void:
	_room_manager = _get_room_manager()
	copy_button.pressed.connect(_on_copy_code_pressed)
	enter_lobby_button.pressed.connect(_on_enter_lobby_pressed)
	leave_button.pressed.connect(_on_leave_room_pressed)
	if _room_manager == null:
		message_label.text = "Room service is unavailable. Return to the menu and try again."
		return
	if _room_manager.has_signal("room_updated"):
		_room_manager.connect("room_updated", _on_room_updated)
	_refresh_room_details()


func _on_room_updated(room_code: String, _record: Dictionary) -> void:
	if str(_room_record.get("room_code", "")) == room_code or _room_record.is_empty():
		_refresh_room_details()


func _refresh_room_details() -> void:
	_room_record = _room_manager.call("get_active_room_record")
	if _room_record.is_empty():
		message_label.text = "There is no active room. Return to the menu to create or join one."
		return

	room_name_label.text = str(_room_record.get("room_name", "Courtroom"))
	room_code_label.text = str(_room_record.get("room_code", "------"))
	visibility_label.text = "%s ROOM" % str(_room_record.get("visibility", "PRIVATE"))
	var players: Array = _room_record.get("players", [])
	player_count_label.text = "%d / %d PLAYERS" % [players.size(), int(_room_record.get("max_players", 0))]
	var host_player_id := str(_room_record.get("host_player_id", ""))
	host_label.text = "HOST: %s" % _get_display_name(players, host_player_id)
	if _room_manager.has_method("is_online") and _room_manager.call("is_online"):
		message_label.text = "Online room: players can join using room code %s." % str(_room_record.get("room_code", ""))
	else:
		message_label.text = "Offline room: only this running application can see this room."
	_render_player_list(players)


func _render_player_list(players: Array) -> void:
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	for player in players:
		var row := Label.new()
		var team_id := int(player.get("team_id", 0))
		var team_name := "RED" if team_id == 1 else "BLUE"
		row.text = "%s   •   %s%s" % [
			team_name,
			str(player.get("display_name", player.get("player_id", "Player"))),
			"   — HOST" if bool(player.get("is_host", false)) else "",
		]
		row.custom_minimum_size = Vector2(0, 38)
		row.add_theme_font_size_override("font_size", 18)
		row.add_theme_color_override("font_color", Color(0.82, 0.25, 0.28, 1) if team_id == 1 else Color(0.14, 0.48, 0.7, 1))
		player_list.add_child(row)


func _get_display_name(players: Array, player_id: String) -> String:
	for player in players:
		if str(player.get("player_id", "")) == player_id:
			return str(player.get("display_name", player_id))
	return "Unknown"


func _on_copy_code_pressed() -> void:
	var room_code := str(_room_record.get("room_code", ""))
	if room_code.is_empty():
		message_label.text = "There is no room code to copy."
		return
	DisplayServer.clipboard_set(room_code)
	message_label.text = "Room code %s copied." % room_code


func _on_enter_lobby_pressed() -> void:
	if _room_record.is_empty():
		message_label.text = "There is no active room to enter."
		return
	_navigate_to_scene(LOBBY_SCENE_PATH)


func _on_leave_room_pressed() -> void:
	if _room_manager == null or _room_record.is_empty():
		_navigate_to_main_menu()
		return
	var result: Dictionary = _room_manager.call(
		"leave_room",
		str(_room_record.get("room_code", "")),
		str(_room_manager.get("active_player_id"))
	)
	if not bool(result.get("success", false)):
		message_label.text = str(result.get("message", "Could not leave the room."))
		return
	_navigate_to_main_menu()


func _get_room_manager() -> Node:
	var root_node := get_tree().root
	var main_node := root_node.get_node_or_null("Main")
	if main_node != null:
		return main_node.get_node_or_null("RoomManager")
	return root_node.get_node_or_null("OfflineRoomManager")


func _navigate_to_main_menu() -> void:
	_navigate_to_scene(MAIN_MENU_SCENE_PATH)


func _navigate_to_scene(scene_path: String) -> void:
	var main_node := get_tree().root.get_node_or_null("Main")
	if main_node != null and main_node.has_method("change_scene"):
		main_node.call("change_scene", scene_path)
		return
	var target_scene := load(scene_path) as PackedScene
	if target_scene != null:
		get_tree().change_scene_to_packed(target_scene)
