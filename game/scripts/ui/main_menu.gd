extends Control

## Main menu and Stage 4.1 UI-only room selection.

const PAGE_HOME := "HomePage"
const PAGE_MODE := "ModePage"
const PAGE_HOW_TO_PLAY := "HowToPlayPage"
const PAGE_SETTINGS := "SettingsPage"
const PAGE_CREATE_ROOM := "CreateRoomPage"
const PAGE_JOIN_ROOM := "JoinRoomPage"
const ROOM_DETAILS_SCENE_PATH := "res://scenes/room/RoomDetails.tscn"
const LOBBY_SCENE_PATH := "res://scenes/lobby/Lobby.tscn"
const ROOM_MANAGER_SCRIPT = preload("res://scripts/network/room_manager.gd")
const NetworkConfig = preload("res://scripts/network/network_config.gd")
const WebMobileInput = preload("res://scripts/ui/web_mobile_input.gd")
const LOCAL_PLAYER_ID := "local_player"
const LOCAL_DISPLAY_NAME := "You"

@onready var pages: Dictionary = {
	PAGE_HOME: $Layout/Columns/MenuCard/MenuContent/HomePage,
	PAGE_MODE: $Layout/Columns/MenuCard/MenuContent/ModePage,
	PAGE_HOW_TO_PLAY: $Layout/Columns/MenuCard/MenuContent/HowToPlayPage,
	PAGE_SETTINGS: $Layout/Columns/MenuCard/MenuContent/SettingsPage,
	PAGE_CREATE_ROOM: $Layout/Columns/MenuCard/MenuContent/CreateRoomPage,
	PAGE_JOIN_ROOM: $Layout/Columns/MenuCard/MenuContent/JoinRoomPage,
}
@onready var create_room_name_input: LineEdit = $Layout/Columns/MenuCard/MenuContent/CreateRoomPage/RoomNameInput
@onready var create_player_name_input: LineEdit = $Layout/Columns/MenuCard/MenuContent/CreateRoomPage/PlayerNameInput
@onready var max_players_option: OptionButton = $Layout/Columns/MenuCard/MenuContent/CreateRoomPage/MaxPlayersOption
@onready var visibility_option: OptionButton = $Layout/Columns/MenuCard/MenuContent/CreateRoomPage/VisibilityOption
@onready var create_error_label: Label = $Layout/Columns/MenuCard/MenuContent/CreateRoomPage/CreateError
@onready var join_player_name_input: LineEdit = $Layout/Columns/MenuCard/MenuContent/JoinRoomPage/PlayerNameInput
@onready var join_code_input: LineEdit = $Layout/Columns/MenuCard/MenuContent/JoinRoomPage/RoomCodeInput
@onready var join_server_input: LineEdit = $Layout/Columns/MenuCard/MenuContent/JoinRoomPage/ServerInput if has_node("Layout/Columns/MenuCard/MenuContent/JoinRoomPage/ServerInput") else null
@onready var join_error_label: Label = $Layout/Columns/MenuCard/MenuContent/JoinRoomPage/JoinError
@onready var offline_limit_label: Label = $Layout/Columns/MenuCard/MenuContent/JoinRoomPage/OfflineLimit
@onready var master_slider: HSlider = $Layout/Columns/MenuCard/MenuContent/SettingsPage/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Layout/Columns/MenuCard/MenuContent/SettingsPage/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Layout/Columns/MenuCard/MenuContent/SettingsPage/SfxRow/SfxSlider
@onready var settings_server_input: LineEdit = $Layout/Columns/MenuCard/MenuContent/SettingsPage/ServerRow/ServerInput if has_node("Layout/Columns/MenuCard/MenuContent/SettingsPage/ServerRow/ServerInput") else null
@onready var fullscreen_toggle: CheckButton = $Layout/Columns/MenuCard/MenuContent/SettingsPage/FullscreenToggle
@onready var layout_margin: MarginContainer = $Layout
@onready var columns_container: HBoxContainer = $Layout/Columns
@onready var menu_card: PanelContainer = $Layout/Columns/MenuCard
@onready var preview_card: PanelContainer = $Layout/Columns/PreviewCard if has_node("Layout/Columns/PreviewCard") else null

var _bus_indices: Dictionary = {}


func _ready() -> void:
	_ensure_audio_bus("Master")
	_ensure_audio_bus("Music")
	_ensure_audio_bus("SFX")
	_connect_navigation()
	_connect_settings()
	_connect_button_feedback()
	_init_player_names()
	_setup_mobile_inputs()
	_hook_network_events()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_show_page(PAGE_HOME, false)


func _update_responsive_layout() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var is_portrait := vp_size.x < vp_size.y or vp_size.x < 768.0

	if preview_card != null:
		preview_card.visible = not is_portrait

	if menu_card != null:
		if is_portrait:
			menu_card.custom_minimum_size = Vector2(0, 0)
			menu_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			menu_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if layout_margin != null:
				layout_margin.offset_left = 18.0
				layout_margin.offset_right = -18.0
				layout_margin.offset_top = 16.0
				layout_margin.offset_bottom = -24.0
		else:
			menu_card.custom_minimum_size = Vector2(455, 0)
			menu_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			menu_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
			if layout_margin != null:
				layout_margin.offset_left = 64.0
				layout_margin.offset_right = -64.0
				layout_margin.offset_top = 28.0
				layout_margin.offset_bottom = -28.0


func _setup_mobile_inputs() -> void:
	WebMobileInput.bind_line_edit(join_code_input, "Nhập mã phòng (6 ký tự) / Enter room code:", true)
	WebMobileInput.bind_line_edit(join_player_name_input, "Nhập tên người chơi / Enter your name:", false)
	WebMobileInput.bind_line_edit(create_player_name_input, "Nhập tên người chơi / Enter your name:", false)
	WebMobileInput.bind_line_edit(create_room_name_input, "Nhập tên phòng / Enter room name:", false)
	if join_server_input != null:
		WebMobileInput.bind_line_edit(join_server_input, "Nhập địa chỉ máy chủ / Enter server address:", false)
	if settings_server_input != null:
		WebMobileInput.bind_line_edit(settings_server_input, "Nhập địa chỉ máy chủ / Enter server address:", false)


func _hook_network_events() -> void:
	var rm := _get_room_manager()
	if rm != null:
		var nc: NetworkClient = rm.get("network_client") as NetworkClient
		if nc != null:
			if not nc.connected_to_server.is_connected(_update_network_status_ui):
				nc.connected_to_server.connect(_update_network_status_ui)
			if not nc.connection_closed.is_connected(_update_network_status_ui):
				nc.connection_closed.connect(_update_network_status_ui)


func _update_network_status_ui() -> void:
	if offline_limit_label == null:
		return
	var rm := _get_room_manager()
	if NetworkConfig.is_web() and not NetworkConfig.is_production_configured():
		offline_limit_label.text = "Production server URL is not configured yet. Browser multiplayer is unavailable until Render is deployed."
		return

	if rm != null and rm.has_method("is_online") and rm.call("is_online"):
		offline_limit_label.text = "Online: Connected to server. Enter a 6-character room code to join."
	else:
		if NetworkConfig.is_web():
			offline_limit_label.text = "Connecting to multiplayer server..."
		else:
			offline_limit_label.text = "Offline prototype: only rooms created in this running app are visible."


func _init_player_names() -> void:
	var rm := _get_room_manager()
	var saved: String = str(rm.get("local_player_name")) if rm != null else ""
	if saved.is_empty():
		create_player_name_input.text = "Host"
		join_player_name_input.text = "Guest"
	else:
		create_player_name_input.text = saved
		join_player_name_input.text = saved

	var current_url: String = str(rm.get("server_url")) if rm != null else NetworkConfig.get_default_server_url()
	if current_url.is_empty():
		current_url = NetworkConfig.get_default_server_url()

	if join_server_input != null:
		join_server_input.text = current_url
		join_server_input.placeholder_text = NetworkConfig.get_default_server_url()
	if settings_server_input != null:
		settings_server_input.text = current_url
		settings_server_input.placeholder_text = NetworkConfig.get_default_server_url()
		settings_server_input.text_submitted.connect(func(new_url: String) -> void:
			if rm != null and rm.has_method("set_server_url"):
				rm.call("set_server_url", new_url)
				if join_server_input != null:
					join_server_input.text = str(rm.get("server_url"))
				_update_network_status_ui()
		)


func _connect_navigation() -> void:
	$Layout/Columns/MenuCard/MenuContent/HomePage/PlayButton.pressed.connect(_on_play_pressed)
	$Layout/Columns/MenuCard/MenuContent/HomePage/HowToPlayButton.pressed.connect(_on_how_to_play_pressed)
	$Layout/Columns/MenuCard/MenuContent/HomePage/SettingsButton.pressed.connect(_on_settings_pressed)
	$Layout/Columns/MenuCard/MenuContent/HomePage/QuitButton.pressed.connect(_on_quit_pressed)
	$Layout/Columns/MenuCard/MenuContent/ModePage/CreateRoomButton.pressed.connect(_on_open_create_room_pressed)
	$Layout/Columns/MenuCard/MenuContent/ModePage/JoinRoomButton.pressed.connect(_on_open_join_room_pressed)
	$Layout/Columns/MenuCard/MenuContent/ModePage/BackButton.pressed.connect(_on_back_to_home_pressed)
	$Layout/Columns/MenuCard/MenuContent/CreateRoomPage/CreateButton.pressed.connect(_on_create_room_pressed)
	$Layout/Columns/MenuCard/MenuContent/CreateRoomPage/BackButton.pressed.connect(_on_back_to_mode_pressed)
	$Layout/Columns/MenuCard/MenuContent/JoinRoomPage/JoinButton.pressed.connect(_on_join_room_pressed)
	$Layout/Columns/MenuCard/MenuContent/JoinRoomPage/BackButton.pressed.connect(_on_back_to_mode_pressed)
	$Layout/Columns/MenuCard/MenuContent/HowToPlayPage/BackButton.pressed.connect(_on_back_to_home_pressed)
	$Layout/Columns/MenuCard/MenuContent/SettingsPage/BackButton.pressed.connect(_on_back_to_home_pressed)
	join_code_input.text_changed.connect(_on_join_code_changed)


func _connect_settings() -> void:
	master_slider.value = _get_bus_volume("Master")
	music_slider.value = _get_bus_volume("Music")
	sfx_slider.value = _get_bus_volume("SFX")
	var window_mode := DisplayServer.window_get_mode()
	fullscreen_toggle.button_pressed = window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

	master_slider.value_changed.connect(_on_master_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	_apply_fullscreen(fullscreen_toggle.button_pressed)


func _connect_button_feedback() -> void:
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		button.pivot_offset = button.size / 2.0
		button.resized.connect(func() -> void: button.pivot_offset = button.size / 2.0)
		button.mouse_entered.connect(_animate_button.bind(button, Vector2(1.025, 1.025)))
		button.mouse_exited.connect(_animate_button.bind(button, Vector2.ONE))
		button.button_down.connect(_animate_button.bind(button, Vector2(0.975, 0.975)))
		button.button_up.connect(_animate_button.bind(button, Vector2(1.025, 1.025) if button.is_hovered() else Vector2.ONE))


func _animate_button(button: Button, target_scale: Vector2) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, 0.12)


func _show_page(page_name: String, animate := true) -> void:
	for key in pages:
		var page: Control = pages[key]
		page.visible = key == page_name
		if key == page_name and animate:
			page.modulate.a = 0.0
			var tween := create_tween()
			tween.tween_property(page, "modulate:a", 1.0, 0.18)


func _on_play_pressed() -> void:
	_show_page(PAGE_MODE)


func _on_how_to_play_pressed() -> void:
	_show_page(PAGE_HOW_TO_PLAY)


func _on_settings_pressed() -> void:
	_show_page(PAGE_SETTINGS)


func _on_open_create_room_pressed() -> void:
	create_error_label.text = ""
	create_room_name_input.text = ""
	max_players_option.select(max_players_option.get_item_count() - 1)
	visibility_option.select(1)
	_show_page(PAGE_CREATE_ROOM)


func _on_open_join_room_pressed() -> void:
	join_error_label.text = ""
	join_code_input.text = ""
	var rm := _get_room_manager()
	if join_server_input != null:
		var current_url := str(rm.get("server_url")) if rm != null else NetworkConfig.get_default_server_url()
		if current_url.is_empty():
			current_url = NetworkConfig.get_default_server_url()
		join_server_input.text = current_url
	_update_network_status_ui()
	_show_page(PAGE_JOIN_ROOM)


func _on_create_room_pressed() -> void:
	var max_players := max_players_option.get_selected_id()
	var visibility := visibility_option.get_item_text(visibility_option.selected).to_upper()
	var game_mode := ""
	if max_players == 2:
		game_mode = "1v1"
	elif max_players == 4:
		game_mode = "2v2"
	elif max_players == 6:
		game_mode = "3v3"

	var rm := _get_room_manager()
	var player_name := create_player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	if rm != null:
		rm.set("local_player_name", player_name)

	if rm != null and rm.get("use_networking"):
		if NetworkConfig.is_web() and not NetworkConfig.is_production_configured():
			create_error_label.text = "Production server URL has not been configured yet. Please configure the Render service URL."
			return

		var current_url := str(rm.get("server_url"))
		var validation := NetworkConfig.validate_server_url(current_url)
		if not bool(validation.get("valid", false)):
			create_error_label.text = str(validation.get("error", "Invalid server address."))
			return

		create_error_label.text = "Connecting to server..."
		var wait_t := 0.0
		while not rm.call("is_online") and wait_t < 2.5:
			await get_tree().process_frame
			wait_t += get_process_delta_time()

		if rm.call("is_online"):
			create_error_label.text = "Creating room on server..."
			var result: Dictionary = await rm.call(
				"create_room_online",
				rm.get("active_player_id"),
				player_name,
				create_room_name_input.text,
				max_players,
				visibility,
				game_mode
			)
			if not bool(result.get("success", false)):
				create_error_label.text = str(result.get("message", "Room could not be created."))
				return
			_open_room_details()
			return
		else:
			create_error_label.text = "Could not connect to game server at %s. Please ensure the server is running." % current_url
			return

	var result: Dictionary = rm.call(
		"create_room",
		LOCAL_PLAYER_ID,
		player_name,
		create_room_name_input.text,
		max_players,
		visibility,
		game_mode
	)
	if not bool(result.get("success", false)):
		create_error_label.text = str(result.get("message", "Room could not be created."))
		return
	_open_room_details()


func _on_join_room_pressed() -> void:
	var code := join_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		join_error_label.text = "Enter a valid room code."
		return

	var rm := _get_room_manager()
	if rm == null:
		join_error_label.text = "Room manager is unavailable."
		return

	var player_name := join_player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Guest"
	if rm != null:
		rm.set("local_player_name", player_name)

	if join_server_input != null and not join_server_input.text.strip_edges().is_empty():
		var desired_url := join_server_input.text.strip_edges()
		var input_validation := NetworkConfig.validate_server_url(desired_url)
		if not bool(input_validation.get("valid", false)):
			join_error_label.text = str(input_validation.get("error", "Invalid server address."))
			return
		if rm != null and rm.has_method("set_server_url") and str(rm.get("server_url")) != desired_url:
			rm.call("set_server_url", desired_url)
			_update_network_status_ui()

	# If networking is disabled, join locally (offline/test mode)
	if not bool(rm.get("use_networking")):
		var result: Dictionary = rm.call(
			"join_room",
			code,
			LOCAL_PLAYER_ID,
			player_name
		)
		if not bool(result.get("success", false)):
			join_error_label.text = str(result.get("message", "Room could not be joined."))
			return
		_open_room_details()
		return

	# Online join
	if NetworkConfig.is_web() and not NetworkConfig.is_production_configured():
		join_error_label.text = "Production server URL has not been configured yet. Please configure the Render service URL."
		return

	var target_url := str(rm.get("server_url"))
	var validation := NetworkConfig.validate_server_url(target_url)
	if not bool(validation.get("valid", false)):
		join_error_label.text = str(validation.get("error", "Invalid server address."))
		return

	# Online join: wait for connection if currently connecting
	var wait_t := 0.0
	while not rm.call("is_online") and wait_t < 2.5:
		await get_tree().process_frame
		wait_t += get_process_delta_time()

	if not rm.call("is_online"):
		join_error_label.text = "Could not connect to game server at %s. Please ensure the server is running." % target_url
		return

	join_error_label.text = "Connecting to room..."
	var result: Dictionary = await rm.call(
		"join_room_online",
		code,
		rm.get("active_player_id"),
		player_name
	)
	if not bool(result.get("success", false)):
		join_error_label.text = str(result.get("message", "Room could not be joined."))
		return
	_open_room_details()


func _on_join_code_changed(value: String) -> void:
	var normalized := value.strip_edges().to_upper()
	if normalized != value:
		var cursor_position := join_code_input.caret_column
		join_code_input.text = normalized
		join_code_input.caret_column = mini(cursor_position, normalized.length())


func _on_back_to_mode_pressed() -> void:
	_show_page(PAGE_MODE)


func _get_room_manager() -> Node:
	var root_node := get_tree().root
	var main_node := root_node.get_node_or_null("Main")
	if main_node != null:
		var persistent_manager := main_node.get_node_or_null("RoomManager")
		if persistent_manager != null:
			return persistent_manager

	var fallback_manager := root_node.get_node_or_null("OfflineRoomManager")
	if fallback_manager == null:
		fallback_manager = ROOM_MANAGER_SCRIPT.new()
		fallback_manager.name = "OfflineRoomManager"
		root_node.add_child(fallback_manager)
	return fallback_manager


func _open_room_details() -> void:
	var main_node := get_tree().root.get_node_or_null("Main")
	if main_node != null and main_node.has_method("change_scene"):
		main_node.call("change_scene", LOBBY_SCENE_PATH)
		return
	var lobby_scene := load(LOBBY_SCENE_PATH) as PackedScene
	if lobby_scene == null:
		push_error("Lobby scene could not be loaded.")
		return
	get_tree().change_scene_to_packed(lobby_scene)


func _on_back_to_home_pressed() -> void:
	_show_page(PAGE_HOME)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_master_volume_changed(value: float) -> void:
	_set_bus_volume("Master", value)


func _on_music_volume_changed(value: float) -> void:
	_set_bus_volume("Music", value)


func _on_sfx_volume_changed(value: float) -> void:
	_set_bus_volume("SFX", value)


func _set_bus_volume(bus_name: String, linear_volume: float) -> void:
	var bus_index := int(_bus_indices.get(bus_name, -1))
	if bus_index < 0:
		return
	var volume_db := -80.0 if linear_volume <= 0.001 else linear_to_db(linear_volume)
	AudioServer.set_bus_volume_db(bus_index, volume_db)


func _on_fullscreen_toggled(enabled: bool) -> void:
	_apply_fullscreen(enabled)


func _apply_fullscreen(enabled: bool) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _ensure_audio_bus(bus_name: String) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, "Master")
	_bus_indices[bus_name] = bus_index


func _get_bus_volume(bus_name: String) -> float:
	var bus_index := int(_bus_indices[bus_name])
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(bus_index)), 0.0, 1.0)
