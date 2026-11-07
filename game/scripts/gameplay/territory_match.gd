extends Node3D

## Runs the territory arena match. Dynamically scales grid and bounds to game mode.

signal arena_completed(result: Dictionary)

const TEAM_RED := 1
const TEAM_BLUE := 2
const PLAYER_SCENE = preload("res://scenes/characters/PlayerCharacter.tscn")
const ARENA_PLAYER_SCRIPT = preload("res://scripts/gameplay/arena_player.gd")
const DEFAULT_ROUND_SECONDS := 30.0
const LOBBY_SCENE_PATH := "res://scenes/lobby/Lobby.tscn"

@export var player_roster: Array = []:
	set(value):
		player_roster = []
		for item in value:
			if item is Dictionary:
				player_roster.append(item)
@export_range(0.1, 600.0, 0.1) var round_duration_seconds := DEFAULT_ROUND_SECONDS
@export var game_mode := ""
@export var grid_size := 8

@onready var territory_grid: Node = $TileGrid
@onready var players_container: Node3D = $Players
@onready var red_score_label: Label = $HUD/Overlay/ScorePanel/RedScore
@onready var blue_score_label: Label = $HUD/Overlay/ScorePanel/BlueScore
@onready var clock_label: Label = $HUD/Overlay/ScorePanel/Clock
@onready var mode_label: Label = $HUD/Overlay/ScorePanel/ModeLabel
@onready var status_label: Label = $HUD/Overlay/ScorePanel/StatusLabel
@onready var result_panel: Panel = $HUD/Overlay/ResultPanel
@onready var result_label: Label = $HUD/Overlay/ResultPanel/ResultLabel
@onready var result_details: Label = $HUD/Overlay/ResultPanel/ResultDetails
@onready var restart_button: Button = $HUD/Overlay/ResultPanel/RestartButton
@onready var virtual_joystick: Control = $HUD/Overlay/VirtualJoystick if has_node("HUD/Overlay/VirtualJoystick") else null
@onready var camera: Camera3D = $Camera3D
@onready var arena_floor: StaticBody3D = $ArenaFloor
@onready var floor_mesh: MeshInstance3D = $ArenaFloor/FloorMesh
@onready var floor_collision: CollisionShape3D = $ArenaFloor/FloorCollision
@onready var north_rail: StaticBody3D = $Boundary/NorthRail
@onready var south_rail: StaticBody3D = $Boundary/SouthRail
@onready var west_rail: StaticBody3D = $Boundary/WestRail
@onready var east_rail: StaticBody3D = $Boundary/EastRail
@onready var north_west_post: Node3D = $CornerPosts/NorthWestPost
@onready var north_east_post: Node3D = $CornerPosts/NorthEastPost
@onready var south_west_post: Node3D = $CornerPosts/SouthWestPost
@onready var south_east_post: Node3D = $CornerPosts/SouthEastPost
@onready var north_west_cap: Node3D = $CornerPosts/NorthWestCap
@onready var north_east_cap: Node3D = $CornerPosts/NorthEastCap
@onready var south_west_cap: Node3D = $CornerPosts/SouthWestCap
@onready var south_east_cap: Node3D = $CornerPosts/SouthEastCap
@onready var red_banner: Node3D = $TeamBanners/RedBanner
@onready var red_banner_label: Node3D = $TeamBanners/RedBannerLabel
@onready var blue_banner: Node3D = $TeamBanners/BlueBanner
@onready var blue_banner_label: Node3D = $TeamBanners/BlueBannerLabel

var round_active := false
var is_preview_mode := false
var room_code := ""
var network_client: Node = null
var _time_remaining := DEFAULT_ROUND_SECONDS
var _player_controllers: Array[Node] = []
var _spawn_positions: Dictionary = {}
var _spawned_roster: Array[Dictionary] = []
var _controllers_by_player_id: Dictionary = {}


func _ready() -> void:
	territory_grid.connect("scores_changed", _on_scores_changed)
	restart_button.pressed.connect(_on_restart_pressed)
	get_viewport().size_changed.connect(_update_camera_for_viewport)

	_initialize_from_room_if_available()
	_apply_game_mode_settings()
	_setup_arena_dimensions(grid_size)
	territory_grid.call("build_grid", grid_size, grid_size)
	_update_camera_for_viewport()

	if _spawn_qualified_players() == 0:
		territory_grid.set("capture_enabled", false)
		result_label.text = "NO PLAYERS"
		result_panel.show()
		return

	_start_round()


func _process(delta: float) -> void:
	if not round_active:
		return

	_time_remaining = maxf(0.0, _time_remaining - delta)
	_update_clock()
	if _time_remaining <= 0.0:
		_finish_round()


func _initialize_from_room_if_available() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	var room_manager: Node = main.get_node_or_null("RoomManager") if main != null else null
	if room_manager == null:
		room_manager = get_tree().root.get_node_or_null("OfflineRoomManager")

	var room: Dictionary = room_manager.call("get_active_room_record") if room_manager != null else {}

	if not room.is_empty():
		self.room_code = str(room.get("room_code", ""))
		var is_server_room: bool = bool(room.get("is_server_room", false))
		if room_manager != null and room_manager.has_method("is_active_room_online"):
			is_server_room = bool(room_manager.call("is_active_room_online"))

		if is_server_room and room_manager != null and room_manager.get("network_client") != null:
			network_client = room_manager.get("network_client")
			if network_client != null:
				if not network_client.player_moved_received.is_connected(_on_network_player_moved):
					network_client.player_moved_received.connect(_on_network_player_moved)
				if not network_client.tile_claimed_received.is_connected(_on_network_tile_claimed):
					network_client.tile_claimed_received.connect(_on_network_tile_claimed)
				if not network_client.match_reset_received.is_connected(_on_network_match_reset):
					network_client.match_reset_received.connect(_on_network_match_reset)

		if game_mode.is_empty():
			game_mode = str(room.get("game_mode", ""))

		if player_roster.is_empty():
			var active_player_id := str(room_manager.get("active_player_id"))
			var source_roster: Array = room_manager.call("get_started_match_roster", self.room_code)
			if source_roster.is_empty():
				source_roster = room.get("players", [])

			for p in source_roster:
				if not (p is Dictionary):
					continue
				var player_record := (p as Dictionary).duplicate(true)
				var pid := str(player_record.get("player_id", ""))
				player_record["human_controlled"] = (pid == active_player_id)
				player_record["is_human"] = player_record["human_controlled"]
				player_record["qualification_status"] = "QUALIFIED"
				player_roster.append(player_record)

	# If there is no active room and no player roster was provided, enter standalone preview mode
	if player_roster.is_empty():
		is_preview_mode = true
		print("[TerritoryArena] No active room or roster found. Entering PREVIEW MODE.")
		var preview_player := {
			"player_id": "preview_player",
			"display_name": "Player 1 (Preview)",
			"team_id": TEAM_RED,
			"character_id": "mint",
			"human_controlled": true,
			"is_human": true,
			"qualification_status": "QUALIFIED",
			"is_preview": true,
		}
		player_roster.append(preview_player)
	else:
		is_preview_mode = false
		var r_code := str(room.get("room_code", "CUSTOM_ROSTER"))
		print("[TerritoryArena] Active room mode active (room code: %s, roster size: %d)" % [r_code, player_roster.size()])


func _apply_game_mode_settings() -> void:
	match game_mode:
		"1v1":
			grid_size = 6
		"2v2":
			grid_size = 8
		"3v3":
			grid_size = 10
		_:
			if grid_size <= 0:
				grid_size = 8

	if not game_mode.is_empty() and is_equal_approx(round_duration_seconds, DEFAULT_ROUND_SECONDS):
		round_duration_seconds = 30.0

	if mode_label != null:
		if is_preview_mode:
			mode_label.text = "PREVIEW MODE"
		elif not game_mode.is_empty():
			mode_label.text = "%s TERRITORY" % game_mode.to_upper()
		else:
			mode_label.text = "%dx%d TERRITORY" % [grid_size, grid_size]

	if is_preview_mode and status_label != null:
		status_label.text = "PREVIEW MODE"


func _setup_arena_dimensions(size: int) -> void:
	var tile_spacing: float = float(territory_grid.get("tile_spacing")) if territory_grid != null else 1.05
	var half_width: float = float(size) * tile_spacing * 0.5
	var floor_dim := float(size) * tile_spacing + 3.1

	if floor_mesh != null and floor_mesh.mesh is BoxMesh:
		var bmesh := (floor_mesh.mesh as BoxMesh).duplicate() as BoxMesh
		bmesh.size = Vector3(floor_dim, 0.25, floor_dim)
		floor_mesh.mesh = bmesh
	if floor_collision != null and floor_collision.shape is BoxShape3D:
		var bshape := (floor_collision.shape as BoxShape3D).duplicate() as BoxShape3D
		bshape.size = Vector3(floor_dim, 0.25, floor_dim)
		floor_collision.shape = bshape

	var rail_pos := half_width + 0.35
	var rail_len := float(size) * tile_spacing + 0.75
	if north_rail != null:
		north_rail.position.z = -rail_pos
		_resize_rail(north_rail, rail_len, true)
	if south_rail != null:
		south_rail.position.z = rail_pos
		_resize_rail(south_rail, rail_len, true)
	if west_rail != null:
		west_rail.position.x = -rail_pos
		_resize_rail(west_rail, rail_len, false)
	if east_rail != null:
		east_rail.position.x = rail_pos
		_resize_rail(east_rail, rail_len, false)

	if north_west_post != null: north_west_post.position = Vector3(-rail_pos, 0.55, -rail_pos)
	if north_east_post != null: north_east_post.position = Vector3(rail_pos, 0.55, -rail_pos)
	if south_west_post != null: south_west_post.position = Vector3(-rail_pos, 0.55, rail_pos)
	if south_east_post != null: south_east_post.position = Vector3(rail_pos, 0.55, rail_pos)

	if north_west_cap != null: north_west_cap.position = Vector3(-rail_pos, 1.15, -rail_pos)
	if north_east_cap != null: north_east_cap.position = Vector3(rail_pos, 1.15, -rail_pos)
	if south_west_cap != null: south_west_cap.position = Vector3(-rail_pos, 1.15, rail_pos)
	if south_east_cap != null: south_east_cap.position = Vector3(rail_pos, 1.15, rail_pos)

	var banner_z := -rail_pos - 0.47
	var banner_x := rail_pos * 0.5
	if red_banner != null: red_banner.position = Vector3(-banner_x, 1.55, banner_z)
	if red_banner_label != null: red_banner_label.position = Vector3(-banner_x, 1.55, banner_z + 0.08)
	if blue_banner != null: blue_banner.position = Vector3(banner_x, 1.55, banner_z)
	if blue_banner_label != null: blue_banner_label.position = Vector3(banner_x, 1.55, banner_z + 0.08)

	_update_camera_for_viewport()


func _update_camera_for_viewport() -> void:
	if camera == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var aspect := vp_size.x / maxf(vp_size.y, 1.0)
	var is_portrait := aspect < 1.0
	var size := grid_size if grid_size > 0 else 6
	var spacing: float = float(territory_grid.get("tile_spacing")) if territory_grid != null else 1.05
	var grid_extent := float(size) * spacing

	if is_portrait:
		# Mobile portrait mode: Keep entire horizontal span of the arena visible
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = 48.0
		var aspect_factor := 0.92 / clampf(aspect, 0.38, 0.90)
		var cam_dist := grid_extent * 1.35 * aspect_factor
		camera.position = Vector3(0.0, cam_dist * 1.08, cam_dist * 0.96)
		# Shift look_at slightly forward to keep arena centered in the upper portion
		camera.look_at(Vector3(0.0, 0.0, -grid_extent * 0.16))
	else:
		# Desktop / Landscape mode
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = 44.0
		var cam_dist := grid_extent * 1.22
		camera.position = Vector3(0.0, cam_dist * 1.05, cam_dist * 1.08)
		camera.look_at(Vector3(0.0, 0.0, 0.0))

	var score_panel: Panel = get_node_or_null("HUD/Overlay/ScorePanel") as Panel
	if score_panel != null:
		score_panel.anchor_left = 0.5
		score_panel.anchor_right = 0.5
		var half_w := minf(vp_size.x * 0.46, 288.0)
		score_panel.offset_left = -half_w
		score_panel.offset_right = half_w

	if virtual_joystick != null and virtual_joystick.has_method("update_responsive_layout"):
		virtual_joystick.call("update_responsive_layout", is_portrait)


func _resize_rail(rail: StaticBody3D, new_length: float, is_horizontal: bool) -> void:
	var mesh_inst: MeshInstance3D = rail.get_node_or_null("Mesh")
	var col_shape: CollisionShape3D = rail.get_node_or_null("Collision")
	if mesh_inst != null and mesh_inst.mesh is BoxMesh:
		var bmesh := (mesh_inst.mesh as BoxMesh).duplicate() as BoxMesh
		if is_horizontal:
			bmesh.size = Vector3(new_length, 0.78, 0.18)
		else:
			bmesh.size = Vector3(0.18, 0.78, new_length)
		mesh_inst.mesh = bmesh
	if col_shape != null and col_shape.shape is BoxShape3D:
		var bshape := (col_shape.shape as BoxShape3D).duplicate() as BoxShape3D
		if is_horizontal:
			bshape.size = Vector3(new_length, 0.78, 0.18)
		else:
			bshape.size = Vector3(0.18, 0.78, new_length)
		col_shape.shape = bshape


func _spawn_qualified_players() -> int:
	var team_spawn_slots := {TEAM_RED: 0, TEAM_BLUE: 0}
	var seen_player_ids: Dictionary = {}
	var spawned_count := 0

	for participant in player_roster:
		if not (participant is Dictionary):
			push_warning("[TerritoryArena] Skipping invalid roster item (not a Dictionary): %s" % participant)
			continue

		var player_id := str(participant.get("player_id", "")).strip_edges()
		if player_id.is_empty():
			push_warning("[TerritoryArena] Skipping roster item with missing or empty player_id: %s" % participant)
			continue

		if seen_player_ids.has(player_id):
			push_warning("[TerritoryArena] Skipping duplicate player_id '%s'" % player_id)
			continue

		if not _is_qualified(participant):
			push_warning("[TerritoryArena] Skipping unqualified player '%s' (status: %s)" % [player_id, participant.get("qualification_status", "")])
			continue

		var team_id := int(participant.get("team_id", 0))
		if team_id != TEAM_RED and team_id != TEAM_BLUE:
			push_warning("[TerritoryArena] Skipping player '%s' with invalid team id: %s" % [player_id, participant.get("team_id", 0)])
			continue

		var team_slot := int(team_spawn_slots[team_id])
		team_spawn_slots[team_id] = team_slot + 1
		var spawn_position := _get_spawn_position(team_id, team_slot)
		var character := PLAYER_SCENE.instantiate() as CharacterBody3D
		if character == null:
			push_error("[TerritoryArena] Failed to instantiate PlayerCharacter for '%s'" % player_id)
			continue

		character.name = player_id.validate_node_name()
		character.set_meta("player_id", player_id)
		character.position = spawn_position

		var is_human := bool(participant.get("human_controlled", participant.get("is_human", false)))
		var is_bot := bool(participant.get("is_bot", participant.get("is_test_bot", false)))
		var display_name := str(participant.get("display_name", player_id))
		var character_id := str(participant.get("character_id", "mint"))

		var controller := Node.new()
		controller.name = "ArenaControl"
		controller.set_script(ARENA_PLAYER_SCRIPT)
		controller.set("team_id", team_id)
		controller.set("human_controlled", is_human)
		controller.set("is_bot", is_bot)
		controller.set("display_name", display_name)
		controller.set("character_id", character_id)
		controller.set("player_id", player_id)
		controller.set("room_code", room_code)
		if virtual_joystick != null:
			controller.set("virtual_joystick", virtual_joystick)
		if network_client != null:
			controller.set("network_client", network_client)
		character.add_child(controller)

		players_container.add_child(character)
		_player_controllers.append(controller)
		_controllers_by_player_id[player_id] = controller
		_spawn_positions[str(character.name)] = spawn_position
		seen_player_ids[player_id] = true
		_spawned_roster.append(participant.duplicate(true))
		spawned_count += 1

		print("[TerritoryArena] Successfully spawned player '%s' (display: '%s', team: %d, preset: %s, human: %s, pos: %s)" % [
			player_id, display_name, team_id, character_id, is_human, spawn_position
		])

	return spawned_count


func _is_qualified(participant: Dictionary) -> bool:
	if participant.has("qualification_status"):
		return str(participant.get("qualification_status", "")) == "QUALIFIED"
	if participant.has("qualified") and not participant.has("qualification_status"):
		return false
	return true


func _get_spawn_position(team_id: int, team_slot: int) -> Vector3:
	var tile_spacing: float = float(territory_grid.get("tile_spacing")) if territory_grid != null else 1.05
	var half_width: float = float(grid_size) * tile_spacing * 0.5
	var start_x := -(half_width - 0.8) if team_id == TEAM_RED else (half_width - 0.8)
	var start_z := -1.05 + float(team_slot % 5) * 1.05
	return Vector3(start_x, 0.04, start_z)


func _start_round() -> void:
	territory_grid.call("reset_grid")
	territory_grid.set("capture_enabled", true)
	_time_remaining = round_duration_seconds
	round_active = true
	result_panel.hide()
	if status_label != null:
		status_label.text = "PREVIEW MODE" if is_preview_mode else "MATCH ACTIVE"
	_update_clock()
	_on_scores_changed(int(territory_grid.get("red_score")), int(territory_grid.get("blue_score")))


func _finish_round() -> void:
	if not round_active:
		return

	round_active = false
	territory_grid.set("capture_enabled", false)
	var red_score := int(territory_grid.get("red_score"))
	var blue_score := int(territory_grid.get("blue_score"))
	var winner_team_id := 0
	if red_score > blue_score:
		winner_team_id = TEAM_RED
		result_label.text = "RED TEAM WINS!"
	elif blue_score > red_score:
		winner_team_id = TEAM_BLUE
		result_label.text = "BLUE TEAM WINS!"
	else:
		result_label.text = "IT'S A TIE!"

	if status_label != null:
		status_label.text = "MATCH FINISHED"

	var red_names: Array[String] = []
	var blue_names: Array[String] = []
	for p in _spawned_roster:
		var pname := str(p.get("display_name", p.get("player_id", "Player")))
		if int(p.get("team_id", 0)) == TEAM_RED:
			red_names.append(pname)
		else:
			blue_names.append(pname)

	if result_details != null:
		result_details.text = "FINAL SCORE: RED %d  •  BLUE %d\nMATCH DURATION: %.0f SECONDS\n\nRED TEAM: %s\nBLUE TEAM: %s" % [
			red_score,
			blue_score,
			round_duration_seconds - _time_remaining,
			", ".join(red_names) if not red_names.is_empty() else "None",
			", ".join(blue_names) if not blue_names.is_empty() else "None",
		]
	result_panel.show()

	arena_completed.emit({
		"winner_team_id": winner_team_id,
		"red_score": red_score,
		"blue_score": blue_score,
		"qualified_red_count": red_names.size(),
		"qualified_blue_count": blue_names.size(),
		"game_mode": game_mode,
		"arena_duration_seconds": round_duration_seconds,
		"arena_elapsed_seconds": round_duration_seconds - _time_remaining,
	})


func _on_scores_changed(red_score: int, blue_score: int) -> void:
	red_score_label.text = "RED   %02d" % red_score
	blue_score_label.text = "%02d   BLUE" % blue_score


func get_joystick_vector() -> Vector2:
	if virtual_joystick != null and virtual_joystick.has_method("get_output_vector"):
		return virtual_joystick.call("get_output_vector")
	return Vector2.ZERO


func _update_clock() -> void:
	var seconds := int(ceil(_time_remaining))
	clock_label.text = "%02d:%02d" % [int(seconds / 60), seconds % 60]


func _on_network_player_moved(pid: String, pos: Vector3, vel: Vector3, rot_y: float) -> void:
	var ctrl: Node = _controllers_by_player_id.get(pid)
	if ctrl != null and ctrl.has_method("set_remote_transform"):
		ctrl.call("set_remote_transform", pos, vel, rot_y)


func _on_network_tile_claimed(col: int, row: int, team_id: int, r_score: int, b_score: int) -> void:
	if territory_grid != null and territory_grid.has_method("claim_tile_from_network"):
		territory_grid.call("claim_tile_from_network", col, row, team_id, r_score, b_score)


func _on_network_match_reset(code: String) -> void:
	var main := get_tree().root.get_node_or_null("Main")
	var room_manager: Node = main.get_node_or_null("RoomManager") if main != null else null
	if room_manager != null:
		var target_code := code if not code.is_empty() else str(room_manager.get("active_room_code"))
		if not target_code.is_empty():
			room_manager.call("reset_room_for_replay", target_code)
	_navigate_to_lobby()


func _on_restart_pressed() -> void:
	if is_preview_mode:
		for controller in _player_controllers:
			var character := controller.get_parent() as CharacterBody3D
			var player_id := str(character.name)
			controller.call("reset_controller", _spawn_positions.get(player_id, character.position))
		_start_round()
		return

	var main := get_tree().root.get_node_or_null("Main")
	var room_manager: Node = main.get_node_or_null("RoomManager") if main != null else null
	if room_manager == null:
		room_manager = get_tree().root.get_node_or_null("OfflineRoomManager")

	var is_room_online := false
	if room_manager != null and room_manager.has_method("is_active_room_online"):
		is_room_online = bool(room_manager.call("is_active_room_online"))
	elif room_manager != null and room_manager.has_method("is_online"):
		is_room_online = bool(room_manager.call("is_online"))

	if is_room_online and network_client != null and not room_code.is_empty():
		network_client.send_rematch_request(room_code)
		return

	if room_manager != null and not str(room_manager.get("active_room_code")).is_empty():
		var code := str(room_manager.get("active_room_code"))
		room_manager.call("reset_room_for_replay", code)
		_navigate_to_lobby()
		return

	for controller in _player_controllers:
		var character := controller.get_parent() as CharacterBody3D
		var player_id := str(character.name)
		controller.call("reset_controller", _spawn_positions.get(player_id, character.position))
	_start_round()


func _navigate_to_lobby() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var main := tree.root.get_node_or_null("Main")
	if main != null and main.has_method("change_scene"):
		main.call("change_scene", LOBBY_SCENE_PATH)
		return
	var packed := load(LOBBY_SCENE_PATH) as PackedScene
	if packed != null:
		tree.change_scene_to_packed(packed)
