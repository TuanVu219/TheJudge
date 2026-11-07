extends Control

## Room lobby UI. RoomManager remains the source of truth for players and choices.

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu/MainMenu.tscn"
const MATCH_ENTRY_SCENE_PATH := "res://scenes/match/RoomMatchEntry.tscn"
const ARENA_SCENE_PATH := "res://scenes/arena/TerritoryArena.tscn"
const PLAYER_SCENE := preload("res://scenes/characters/PlayerCharacter.tscn")
const WebMobileInput = preload("res://scripts/ui/web_mobile_input.gd")
const TEAM_RED := 1
const TEAM_BLUE := 2
const PRESETS := [
	{"id": "mint", "name": "Minty", "color": Color(0.43, 0.88, 0.66), "accessory": "Feather"},
	{"id": "peach", "name": "Peaches", "color": Color(1.0, 0.58, 0.37), "accessory": "TinyHat"},
	{"id": "sky", "name": "Bubbles", "color": Color(0.38, 0.72, 1.0), "accessory": "TinyGlasses"},
]

var _manager: Node
var _room: Dictionary = {}
var _local_player_id := ""
var _message: Label
var _header: Label
var _copy_button: Button
var _ready_button: Button
var _start_button: Button
var _start_hint: Label
var _customize_button: Button
var _team_rows: Dictionary = {}
var _custom_panel: PanelContainer
var _custom_preview: SubViewport
var _custom_name: Label
var _custom_name_edit: LineEdit
var _preset_index := 0


func _ready() -> void:
	_manager = _get_room_manager()
	_local_player_id = str(_manager.get("active_player_id")) if _manager != null else ""
	if _manager != null:
		if _manager.has_signal("room_updated"):
			_manager.connect("room_updated", _on_room_updated)
		if _manager.has_signal("match_started"):
			_manager.connect("match_started", _on_match_started)
		if _manager.has_signal("room_closed"):
			_manager.connect("room_closed", _on_room_closed)
	_build_ui()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_refresh()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("#bde8f2")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin_c := MarginContainer.new()
	margin_c.name = "MarginContainer"
	margin_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_c.add_theme_constant_override("margin_left", 20)
	margin_c.add_theme_constant_override("margin_right", 20)
	margin_c.add_theme_constant_override("margin_top", 16)
	margin_c.add_theme_constant_override("margin_bottom", 20)
	add_child(margin_c)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	margin_c.add_child(page)

	# Header Box (responsive VBox with Title row & Sub row)
	var top_box := VBoxContainer.new()
	top_box.name = "TopBox"
	top_box.add_theme_constant_override("separation", 6)
	page.add_child(top_box)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	top_box.add_child(title_row)

	var title := _label("THE JUDGE  •  PARTY LOBBY", 24, Color("#18364d"))
	title.name = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var sub_row := HBoxContainer.new()
	sub_row.name = "SubRow"
	sub_row.add_theme_constant_override("separation", 10)
	top_box.add_child(sub_row)

	_copy_button = _button("ROOM ------  •  COPY", Color("#18364d"))
	_copy_button.custom_minimum_size = Vector2(0, 40)
	_copy_button.add_theme_font_size_override("font_size", 14)
	_copy_button.pressed.connect(_copy_room_code)
	sub_row.add_child(_copy_button)

	_header = _label("0 / 0 PLAYERS  •  PRIVATE", 14, Color("#18364d"))
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_row.add_child(_header)

	# Teams Container (Red & Blue panels)
	var teams := HBoxContainer.new()
	teams.name = "TeamsContainer"
	teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams.add_theme_constant_override("separation", 12)
	page.add_child(teams)
	_team_rows[TEAM_RED] = _make_team_panel(teams, TEAM_RED)
	_team_rows[TEAM_BLUE] = _make_team_panel(teams, TEAM_BLUE)

	_message = _label("Choose your side and character!", 15, Color("#18364d"))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_message)

	# Footer (Responsive 2-row layout with big easy-to-tap buttons)
	var footer := VBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 8)
	page.add_child(footer)

	var primary_row := HBoxContainer.new()
	primary_row.name = "PrimaryRow"
	primary_row.add_theme_constant_override("separation", 10)
	footer.add_child(primary_row)

	_ready_button = _button("READY UP", Color("#45a876"))
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_button.custom_minimum_size = Vector2(0, 56)
	_ready_button.add_theme_font_size_override("font_size", 18)
	_ready_button.pressed.connect(_toggle_ready)
	primary_row.add_child(_ready_button)

	_start_button = _button("START MATCH", Color("#f3a939"))
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.custom_minimum_size = Vector2(0, 56)
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.disabled = true
	_start_button.visible = false
	_start_button.pressed.connect(_start_match)
	primary_row.add_child(_start_button)

	var secondary_row := HBoxContainer.new()
	secondary_row.name = "SecondaryRow"
	secondary_row.add_theme_constant_override("separation", 10)
	footer.add_child(secondary_row)

	_customize_button = _button("CUSTOMIZE CHARACTER", Color("#f3a939"))
	_customize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_customize_button.custom_minimum_size = Vector2(0, 48)
	_customize_button.add_theme_font_size_override("font_size", 15)
	_customize_button.disabled = true
	_customize_button.pressed.connect(_show_customizer)
	secondary_row.add_child(_customize_button)

	var leave := _button("LEAVE ROOM", Color("#e85f58"))
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.custom_minimum_size = Vector2(0, 48)
	leave.add_theme_font_size_override("font_size", 15)
	leave.pressed.connect(_leave_room)
	secondary_row.add_child(leave)

	_start_hint = _label("Waiting for room status…", 13, Color("#18364d"))
	_start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_hint.visible = false
	page.add_child(_start_hint)

	_build_customizer()


func _update_responsive_layout() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var is_portrait := vp_size.x < vp_size.y or vp_size.x < 768.0

	var margin_c := get_node_or_null("MarginContainer") as MarginContainer
	if margin_c != null:
		if is_portrait:
			margin_c.add_theme_constant_override("margin_left", 14)
			margin_c.add_theme_constant_override("margin_right", 14)
			margin_c.add_theme_constant_override("margin_top", 12)
			margin_c.add_theme_constant_override("margin_bottom", 24)
		else:
			margin_c.add_theme_constant_override("margin_left", 28)
			margin_c.add_theme_constant_override("margin_right", 28)
			margin_c.add_theme_constant_override("margin_top", 20)
			margin_c.add_theme_constant_override("margin_bottom", 20)


func _make_team_panel(parent: HBoxContainer, team_id: int) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff5dc")
	style.border_color = Color("#ed6b63") if team_id == TEAM_RED else Color("#51a9d2")
	style.set_border_width_all(5)
	style.set_corner_radius_all(24)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var heading := _label("RED TEAM" if team_id == TEAM_RED else "BLUE TEAM", 23,
		Color("#c84949") if team_id == TEAM_RED else Color("#2476a5"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(heading)
	var count := _label("0 PLAYERS", 14, Color("#365365"))
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(count)
	var list := VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	content.add_child(list)
	var empty := _label("No players yet — this team is open.", 15, Color("#71838a"))
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(empty)
	var join := _button("JOIN RED" if team_id == TEAM_RED else "JOIN BLUE",
		Color("#e85f58") if team_id == TEAM_RED else Color("#3995c4"))
	join.pressed.connect(_join_team.bind(team_id))
	content.add_child(join)
	return list


func _build_customizer() -> void:
	_custom_panel = PanelContainer.new()
	_custom_panel.visible = false
	_custom_panel.set_anchors_preset(Control.PRESET_CENTER)
	_custom_panel.position = Vector2(-220, -250)
	_custom_panel.custom_minimum_size = Vector2(440, 500)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff5dc")
	style.border_color = Color("#f3a939")
	style.set_border_width_all(5)
	style.set_corner_radius_all(28)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	_custom_panel.add_theme_stylebox_override("panel", style)
	add_child(_custom_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_custom_panel.add_child(content)
	var heading := _label("PICK YOUR LOOK", 25, Color("#18364d"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(heading)
	_custom_preview = SubViewport.new()
	_custom_preview.size = Vector2i(300, 250)
	_custom_preview.transparent_bg = false
	_custom_preview.own_world_3d = true
	_custom_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_custom_preview.ready.connect(_setup_viewport_world.bind(_custom_preview), CONNECT_ONE_SHOT)
	content.add_child(_viewport_container(_custom_preview, Vector2(0, 250)))
	_custom_name = _label("Minty", 20, Color("#18364d"))
	_custom_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_custom_name)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	content.add_child(controls)
	var previous := _button("◀ PREVIOUS", Color("#3995c4"))
	previous.pressed.connect(_cycle_preset.bind(-1))
	controls.add_child(previous)
	var next := _button("NEXT ▶", Color("#3995c4"))
	next.pressed.connect(_cycle_preset.bind(1))
	controls.add_child(next)

	var name_box := HBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 8)
	var name_lbl := _label("NAME:", 16, Color("#18364d"))
	name_box.add_child(name_lbl)
	_custom_name_edit = LineEdit.new()
	_custom_name_edit.custom_minimum_size = Vector2(180, 40)
	_custom_name_edit.placeholder_text = "Your Name"
	_custom_name_edit.max_length = 20
	_custom_name_edit.text_submitted.connect(func(_t: String) -> void: _apply_custom_name())
	WebMobileInput.bind_line_edit(_custom_name_edit, "Nhập tên nhân vật / Enter player name:")
	name_box.add_child(_custom_name_edit)
	content.add_child(name_box)

	var done := _button("DONE", Color("#ed6b63"))
	done.pressed.connect(func() -> void:
		_apply_custom_name()
		_custom_panel.hide()
	)
	content.add_child(done)


func _viewport_container(viewport: SubViewport, minimum_size: Vector2) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = minimum_size
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.stretch = true
	container.add_child(viewport)
	return container


func _setup_viewport_world(viewport: SubViewport) -> void:
	if not is_inside_tree() or not viewport.is_inside_tree():
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#d8f0f2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 0.95, 0.86)
	environment.ambient_light_energy = 1.25
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.shadow_enabled = false
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.9, 4.5)
	camera.current = true
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	var character := PLAYER_SCENE.instantiate()
	character.name = "PreviewCharacter"
	character.position.y = 0.05
	viewport.add_child(character)
	character.set_display_name_visible(false)
	_apply_preset(character, _preset_index)


func _refresh() -> void:
	if _manager == null:
		_message.text = "Room service is unavailable. Return to the menu."
		return
	var mgr_pid := str(_manager.get("active_player_id"))
	if not mgr_pid.is_empty():
		_local_player_id = mgr_pid
	_room = _manager.call("get_active_room_record")
	if _room.is_empty():
		_message.text = "There is no active room. Return to the menu to create or join one."
		return
	var players: Array = _room.get("players", [])
	var ready_count := int(_manager.call("get_ready_count", str(_room.get("room_code", ""))))
	var mode_text := str(_room.get("game_mode", "")).to_upper()
	var mode_prefix := "%s  •  " % mode_text if not mode_text.is_empty() else ""
	_header.text = "%s%d / %d PLAYERS  •  %d / %d READY  •  %s" % [
		mode_prefix,
		players.size(),
		int(_room.get("max_players", 0)),
		ready_count,
		players.size(),
		str(_room.get("visibility", "PRIVATE"))
	]
	_copy_button.text = "ROOM %s  •  COPY" % str(_room.get("room_code", "------"))
	var local_player := _find_player(players, _local_player_id)
	var waiting_for_players := str(_room.get("status", "")) == "WAITING"
	_ready_button.disabled = local_player.is_empty() or not waiting_for_players
	_customize_button.disabled = local_player.is_empty() or not waiting_for_players
	_ready_button.text = "SET NOT READY" if bool(local_player.get("is_ready", false)) else "READY UP"
	var is_host := str(_room.get("host_player_id", "")) == _local_player_id
	_start_button.visible = is_host
	_start_hint.visible = is_host
	if is_host:
		var validation: Dictionary = _manager.call("get_match_start_validation", str(_room.get("room_code", "")), _local_player_id)
		_start_button.disabled = not bool(validation.get("success", false))
		_start_hint.text = str(validation.get("message", "The match cannot start yet."))
	else:
		_message.text = "Waiting for the host to start the match. You are %s." % ("READY" if bool(local_player.get("is_ready", false)) else "NOT READY")
	for team_id in [TEAM_RED, TEAM_BLUE]:
		var list: VBoxContainer = _team_rows[team_id]
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		var members: Array = _manager.call("get_players_by_team", str(_room.get("room_code", "")), team_id)
		var capacity := int(int(_room.get("max_players", 0)) / 2)
		var heading: Label = list.get_parent().get_child(1)
		heading.text = "%d / %d PLAYERS" % [members.size(), capacity]
		for player in members:
			list.add_child(_make_player_row(player, team_id))
		if members.is_empty():
			var empty := _label("No players yet — this team is open.", 15, Color("#71838a"))
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			list.add_child(empty)
		var fill := Control.new()
		fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.add_child(fill)
		var join_button: Button = list.get_parent().get_child(list.get_parent().get_child_count() - 1)
		var team_is_full := members.size() >= capacity
		var can_change_team := not local_player.is_empty() and waiting_for_players
		join_button.disabled = team_is_full or not can_change_team
		if team_is_full:
			join_button.text = "RED TEAM FULL" if team_id == TEAM_RED else "BLUE TEAM FULL"
			join_button.tooltip_text = "Each team can hold up to %d players." % capacity
		elif not can_change_team:
			join_button.text = "TEAM LOCKED" if waiting_for_players else "MATCH STARTED"
			join_button.tooltip_text = "Team selection is unavailable without an active player in a waiting room."
		else:
			join_button.text = "JOIN RED" if team_id == TEAM_RED else "JOIN BLUE"
			join_button.tooltip_text = "Move your player to this team."

	if not local_player.is_empty():
		_preset_index = _preset_index_for(str(local_player.get("character_id", "mint")))
		_refresh_custom_preview()


func _make_player_row(player: Dictionary, team_id: int) -> Control:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("#f8fbf1")
	card_style.set_corner_radius_all(14)
	card_style.content_margin_left = 8
	card_style.content_margin_right = 8
	card_style.content_margin_top = 6
	card_style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", card_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var portrait_viewport := SubViewport.new()
	portrait_viewport.size = Vector2i(75, 75)
	portrait_viewport.own_world_3d = true
	portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	portrait_viewport.ready.connect(_setup_viewport_world_for_player.bind(portrait_viewport, player), CONNECT_ONE_SHOT)
	row.add_child(_viewport_container(portrait_viewport, Vector2(68, 68)))
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(labels)
	var name := _label(str(player.get("display_name", player.get("player_id", "Player"))), 19, Color("#18364d"))
	labels.add_child(name)
	var preset: Dictionary = PRESETS[_preset_index_for(str(player.get("character_id", "mint")))]
	var ready_text := "READY" if bool(player.get("is_ready", false)) else "NOT READY"
	var details := _label("%s  •  %s  •  %s%s" % [preset["name"], "RED" if team_id == TEAM_RED else "BLUE", ready_text, "  ★ HOST" if bool(player.get("is_host", false)) else ""], 14,
		Color("#27804e") if bool(player.get("is_ready", false)) else Color("#78858b"))
	labels.add_child(details)
	return card


func _setup_viewport_world_for_player(viewport: SubViewport, player: Dictionary) -> void:
	if not is_inside_tree() or not viewport.is_inside_tree():
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#d8f0f2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 0.95, 0.86)
	environment.ambient_light_energy = 1.25
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.shadow_enabled = false
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.9, 4.2)
	camera.current = true
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	var character: Node = PLAYER_SCENE.instantiate()
	character.name = "PreviewCharacter"
	character.position.y = 0.05
	viewport.add_child(character)
	character.set_display_name(str(player.get("display_name", "Player")))
	character.set_display_name_visible(false)
	_apply_preset(character, _preset_index_for(str(player.get("character_id", "mint"))))


func _apply_preset(character: Node, index: int) -> void:
	var preset: Dictionary = PRESETS[index]
	character.set_body_color(preset["color"])
	for accessory in ["Feather", "TinyHat", "TinyGlasses"]:
		character.set_accessory_visible(accessory, accessory == preset["accessory"])


func _show_customizer() -> void:
	if _local_player_id.is_empty():
		_message.text = "No local player is registered in this room."
		return
	var local_p := _find_player(_room.get("players", []), _local_player_id)
	if not local_p.is_empty() and _custom_name_edit != null:
		_custom_name_edit.text = str(local_p.get("display_name", ""))
	_custom_panel.show()
	_refresh_custom_preview()


func _apply_custom_name() -> void:
	if _custom_name_edit == null or _manager == null or _local_player_id.is_empty():
		return
	var new_name := _custom_name_edit.text.strip_edges()
	if new_name.is_empty():
		return
	var code := str(_room.get("room_code", ""))
	if _manager.has_method("update_player_name"):
		_manager.call("update_player_name", code, _local_player_id, new_name)
	_refresh()


func _cycle_preset(direction: int) -> void:
	_preset_index = posmod(_preset_index + direction, PRESETS.size())
	var result: Dictionary = _manager.call("update_player_character", str(_room.get("room_code", "")), _local_player_id, str(PRESETS[_preset_index]["id"]))
	if not bool(result.get("success", false)):
		_message.text = str(result.get("message", "Could not update character."))
		return
	_message.text = "%s is now your selected character." % PRESETS[_preset_index]["name"]
	_refresh()


func _refresh_custom_preview() -> void:
	if _custom_name == null:
		return
	_custom_name.text = str(PRESETS[_preset_index]["name"])
	if _custom_preview == null or _custom_preview.get_child_count() == 0:
		return
	var character := _custom_preview.get_node_or_null("PreviewCharacter")
	if character != null:
		_apply_preset(character, _preset_index)


func _preset_index_for(character_id: String) -> int:
	for index in range(PRESETS.size()):
		if str(PRESETS[index]["id"]) == character_id:
			return index
	return 0


func _join_team(team_id: int) -> void:
	if _manager == null or _local_player_id.is_empty():
		return
	var result: Dictionary = _manager.call("update_player_team", str(_room.get("room_code", "")), _local_player_id, team_id)
	_message.text = str(result.get("message", "Could not change teams."))
	if bool(result.get("success", false)):
		_refresh()


func _toggle_ready() -> void:
	if _manager == null or _local_player_id.is_empty() or _room.is_empty():
		return
	var result: Dictionary = _manager.call("toggle_player_ready", str(_room.get("room_code", "")), _local_player_id)
	_message.text = str(result.get("message", "Could not update readiness."))
	_refresh()


func _start_match() -> void:
	if _manager == null or _room.is_empty():
		return
	var result: Dictionary = _manager.call("start_match", str(_room.get("room_code", "")), _local_player_id)
	if not bool(result.get("success", false)):
		_message.text = str(result.get("message", "The match cannot start yet."))
		_refresh()
		return

	# If offline, navigate immediately. If online, wait for server MATCH_STARTED packet.
	if not (_manager.has_method("is_online") and _manager.call("is_online")):
		var game_mode := str(_room.get("game_mode", ""))
		if game_mode.is_empty():
			_navigate(MATCH_ENTRY_SCENE_PATH)
		else:
			_navigate(ARENA_SCENE_PATH)
	else:
		_start_button.disabled = true
		_message.text = "Starting match..."


func _on_room_updated(room_code: String, room_record: Dictionary) -> void:
	if str(_room.get("room_code", "")) == room_code or _room.is_empty():
		if str(room_record.get("status", "")) == "STARTED":
			_start_button.disabled = true
			var mode := str(room_record.get("game_mode", ""))
			if mode.is_empty():
				_navigate(MATCH_ENTRY_SCENE_PATH)
			else:
				_navigate(ARENA_SCENE_PATH)
			return
		_refresh()


func _on_match_started(room_code: String, _roster: Array, game_mode: String) -> void:
	if str(_room.get("room_code", "")) == room_code or _room.is_empty():
		_start_button.disabled = true
		if game_mode.is_empty():
			_navigate(MATCH_ENTRY_SCENE_PATH)
		else:
			_navigate(ARENA_SCENE_PATH)


func _on_room_closed(room_code: String, reason: String) -> void:
	if str(_room.get("room_code", "")) == room_code or _room.is_empty():
		_message.text = "Room closed: %s" % reason
		await get_tree().create_timer(1.2).timeout
		_navigate(MAIN_MENU_SCENE_PATH)


func _copy_room_code() -> void:
	var code := str(_room.get("room_code", ""))
	if code.is_empty():
		_message.text = "There is no room code to copy."
		return
	DisplayServer.clipboard_set(code)
	_message.text = "Room code %s copied." % code


func _leave_room() -> void:
	if _manager != null and not _room.is_empty():
		var result: Dictionary = _manager.call("leave_room", str(_room.get("room_code", "")), _local_player_id)
		if not bool(result.get("success", false)):
			_message.text = str(result.get("message", "Could not leave room."))
			return
	_navigate(MAIN_MENU_SCENE_PATH)


func _get_room_manager() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var main := tree.root.get_node_or_null("Main")
	if main != null:
		return main.get_node_or_null("RoomManager")
	return tree.root.get_node_or_null("OfflineRoomManager")


func _find_player(players: Array, player_id: String) -> Dictionary:
	for player in players:
		if str(player.get("player_id", "")) == player_id:
			return player
	return {}


func _navigate(scene_path: String) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var main := tree.root.get_node_or_null("Main")
	if main != null and main.has_method("change_scene"):
		main.call("change_scene", scene_path)
		return
	var packed := load(scene_path) as PackedScene
	if packed != null:
		tree.change_scene_to_packed(packed)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#fffaf0"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.12)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	return button
