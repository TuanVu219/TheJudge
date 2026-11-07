extends Control

## Room lobby UI. RoomManager remains the source of truth for players and choices.
## Features a full Modular Wardrobe Customizer (Body Color, Hats, Glasses, Hair, Outfits).
## Supports standalone editor testing (F6 preview mode) when launched without an active room.

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu/MainMenu.tscn"
const MATCH_ENTRY_SCENE_PATH := "res://scenes/match/RoomMatchEntry.tscn"
const ARENA_SCENE_PATH := "res://scenes/arena/TerritoryArena.tscn"
const PLAYER_SCENE := preload("res://scenes/characters/PlayerCharacter.tscn")
const Wardrobe = preload("res://scripts/characters/wardrobe.gd")
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
var _is_preview_mode := false
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

# Modular Wardrobe state
var _current_skin: Dictionary = Wardrobe.default_skin()
var _color_lbl: Label
var _hat_lbl: Label
var _glasses_lbl: Label
var _hair_lbl: Label
var _outfit_lbl: Label


func _ready() -> void:
	_current_skin = Wardrobe.default_skin()

	_manager = _get_room_manager()
	_local_player_id = str(_manager.get("active_player_id")) if _manager != null else ""
	if _manager != null:
		if _manager.has_signal("room_updated"):
			_manager.connect("room_updated", Callable(self, "_on_room_updated"))
		if _manager.has_signal("match_started"):
			_manager.connect("match_started", Callable(self, "_on_match_started"))
		if _manager.has_signal("room_closed"):
			_manager.connect("room_closed", Callable(self, "_on_room_closed"))
	_build_ui()
	_refresh()
	if is_inside_tree() and get_viewport() != null:
		get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()


func _exit_tree() -> void:
	if _manager != null:
		if _manager.has_signal("room_updated") and _manager.is_connected("room_updated", Callable(self, "_on_room_updated")):
			_manager.disconnect("room_updated", Callable(self, "_on_room_updated"))
		if _manager.has_signal("match_started") and _manager.is_connected("match_started", Callable(self, "_on_match_started")):
			_manager.disconnect("match_started", Callable(self, "_on_match_started"))
		if _manager.has_signal("room_closed") and _manager.is_connected("room_closed", Callable(self, "_on_room_closed")):
			_manager.disconnect("room_closed", Callable(self, "_on_room_closed"))


func _get_room_manager() -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	var root_node := get_tree().root
	var main_node := root_node.get_node_or_null("Main")
	if main_node != null:
		var persistent_manager := main_node.get_node_or_null("RoomManager")
		if persistent_manager != null:
			return persistent_manager
	var offline_mgr := root_node.get_node_or_null("OfflineRoomManager")
	if offline_mgr != null:
		return offline_mgr
	if root_node.has_node("RoomManager"):
		return root_node.get_node("RoomManager")
	var node := Node.new()
	node.name = "OfflineRoomManager"
	var script: Script = load("res://scripts/network/room_manager.gd")
	if script != null:
		node.set_script(script)
	root_node.call_deferred("add_child", node)
	return node


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#d8f0f2")
	add_child(bg)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	page.add_child(top_bar)

	var title := _label("THE JUDGE - PARTY LOBBY", 26, Color("#18364d"))
	top_bar.add_child(title)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer)

	_copy_button = _button("ROOM ------ - COPY", Color("#1f4d6b"))
	_copy_button.custom_minimum_size = Vector2(170, 38)
	_copy_button.add_theme_font_size_override("font_size", 14)
	_copy_button.pressed.connect(_copy_code)
	top_bar.add_child(_copy_button)

	_header = _label("WAITING FOR PLAYERS", 15, Color("#1f4d6b"))
	top_bar.add_child(_header)

	_message = _label("", 16, Color("#365365"))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_message)

	var teams_box := HBoxContainer.new()
	teams_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams_box.add_theme_constant_override("separation", 18)
	page.add_child(teams_box)

	_team_rows[TEAM_RED] = _make_team_panel(teams_box, TEAM_RED)
	_team_rows[TEAM_BLUE] = _make_team_panel(teams_box, TEAM_BLUE)

	var footer := VBoxContainer.new()
	footer.name = "LobbyFooter"
	footer.add_theme_constant_override("separation", 10)
	page.add_child(footer)

	var primary_row := HBoxContainer.new()
	primary_row.name = "PrimaryRow"
	primary_row.add_theme_constant_override("separation", 12)
	footer.add_child(primary_row)

	_ready_button = _button("READY UP", Color("#27ae60"))
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_button.custom_minimum_size = Vector2(0, 56)
	_ready_button.add_theme_font_size_override("font_size", 18)
	_ready_button.pressed.connect(_toggle_ready)
	primary_row.add_child(_ready_button)

	_start_button = _button("START MATCH", Color("#1f4d6b"))
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.custom_minimum_size = Vector2(0, 56)
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.pressed.connect(_start_match)
	primary_row.add_child(_start_button)

	var secondary_row := HBoxContainer.new()
	secondary_row.name = "SecondaryRow"
	secondary_row.add_theme_constant_override("separation", 12)
	footer.add_child(secondary_row)

	_customize_button = _button("CUSTOMIZE CHARACTER", Color("#f3a939"))
	_customize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_customize_button.custom_minimum_size = Vector2(0, 48)
	_customize_button.add_theme_font_size_override("font_size", 15)
	_customize_button.pressed.connect(_show_customizer)
	secondary_row.add_child(_customize_button)

	var leave := _button("LEAVE ROOM", Color("#e85f58"))
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.custom_minimum_size = Vector2(0, 48)
	leave.add_theme_font_size_override("font_size", 15)
	leave.pressed.connect(_leave_room)
	secondary_row.add_child(leave)

	_start_hint = _label("Waiting for room status...", 13, Color("#18364d"))
	_start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_hint.visible = false
	page.add_child(_start_hint)

	_build_customizer()


func _update_responsive_layout() -> void:
	if not is_inside_tree() or get_viewport() == null:
		return
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

	if _custom_panel != null:
		var modal_w := minf(vp_size.x - 20.0, 430.0)
		var modal_h := minf(vp_size.y - 30.0, 620.0)
		_custom_panel.custom_minimum_size = Vector2(modal_w, modal_h)
		_custom_panel.size = Vector2(modal_w, modal_h)
		_custom_panel.offset_left = -modal_w * 0.5
		_custom_panel.offset_top = -modal_h * 0.5
		_custom_panel.offset_right = modal_w * 0.5
		_custom_panel.offset_bottom = modal_h * 0.5


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

	var empty := _label("No players yet - this team is open.", 15, Color("#71838a"))
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
	_custom_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_custom_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff5dc")
	style.border_color = Color("#f3a939")
	style.set_border_width_all(5)
	style.set_corner_radius_all(26)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_custom_panel.add_theme_stylebox_override("panel", style)
	add_child(_custom_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 8)
	_custom_panel.add_child(root_vbox)

	var heading := _label("CUSTOMIZE CHARACTER", 19, Color("#18364d"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(heading)

	# 3D Viewport preview - Large, zoomed-in, prominent
	_custom_preview = SubViewport.new()
	_custom_preview.size = Vector2i(320, 240)
	_custom_preview.transparent_bg = false
	_custom_preview.own_world_3d = true
	_custom_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_custom_preview.ready.connect(_setup_viewport_world.bind(_custom_preview), CONNECT_ONE_SHOT)
	root_vbox.add_child(_viewport_container(_custom_preview, Vector2(0, 230)))

	# Scrollable selectors area
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)

	# 1. Body Color Selector
	_color_lbl = _label("", 14, Color("#18364d"))
	_color_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_color_lbl.custom_minimum_size = Vector2(175, 26)
	content.add_child(_make_selector_box("BODY COLOR", _color_lbl, _cycle_color))

	# 2. Hat Selector
	_hat_lbl = _label("", 14, Color("#18364d"))
	_hat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hat_lbl.custom_minimum_size = Vector2(175, 26)
	content.add_child(_make_selector_box("HAT", _hat_lbl, _cycle_hat))

	# 3. Glasses Selector
	_glasses_lbl = _label("", 14, Color("#18364d"))
	_glasses_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glasses_lbl.custom_minimum_size = Vector2(175, 26)
	content.add_child(_make_selector_box("GLASSES", _glasses_lbl, _cycle_glasses))

	# 4. Hair Selector
	_hair_lbl = _label("", 14, Color("#18364d"))
	_hair_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hair_lbl.custom_minimum_size = Vector2(175, 26)
	content.add_child(_make_selector_box("HAIR", _hair_lbl, _cycle_hair))

	# 5. Outfit Selector
	_outfit_lbl = _label("", 14, Color("#18364d"))
	_outfit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outfit_lbl.custom_minimum_size = Vector2(175, 26)
	content.add_child(_make_selector_box("OUTFIT", _outfit_lbl, _cycle_outfit))

	# Pinned bottom area: NAME + DONE (always visible, no scrolling needed)
	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 6)
	root_vbox.add_child(bottom_box)

	var name_box := HBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 8)
	var name_lbl := _label("NAME:", 14, Color("#18364d"))
	name_box.add_child(name_lbl)
	_custom_name_edit = LineEdit.new()
	_custom_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_name_edit.custom_minimum_size = Vector2(0, 36)
	_custom_name_edit.placeholder_text = "Player Name"
	_custom_name_edit.max_length = 20
	_custom_name_edit.text_submitted.connect(func(_t: String) -> void: _apply_custom_wardrobe())
	WebMobileInput.bind_line_edit(_custom_name_edit, "Enter player name:")
	name_box.add_child(_custom_name_edit)
	bottom_box.add_child(name_box)

	var done := _button("DONE", Color("#ed6b63"))
	done.custom_minimum_size = Vector2(0, 44)
	done.add_theme_font_size_override("font_size", 16)
	done.pressed.connect(func() -> void:
		_apply_custom_wardrobe()
		_custom_panel.hide()
	)
	bottom_box.add_child(done)


func _make_selector_box(title: String, label_node: Label, on_change: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title_lbl := _label(title, 11, Color("#637a89"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_lbl)

	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 6)

	var prev_btn := _button("<", Color("#3995c4"))
	prev_btn.custom_minimum_size = Vector2(34, 28)
	prev_btn.pressed.connect(on_change.bind(-1))
	h.add_child(prev_btn)

	h.add_child(label_node)

	var next_btn := _button(">", Color("#3995c4"))
	next_btn.custom_minimum_size = Vector2(34, 28)
	next_btn.pressed.connect(on_change.bind(1))
	h.add_child(next_btn)

	box.add_child(h)
	return box


func _cycle_color(dir: int) -> void:
	var cur := str(_current_skin.get("color", "mint"))
	var idx := 0
	for i in range(Wardrobe.BODY_COLORS.size()):
		if Wardrobe.BODY_COLORS[i]["id"] == cur:
			idx = i
			break
	var next_idx := posmod(idx + dir, Wardrobe.BODY_COLORS.size())
	_current_skin["color"] = Wardrobe.BODY_COLORS[next_idx]["id"]
	_update_selector_labels()
	_refresh_custom_preview()


func _cycle_hat(dir: int) -> void:
	var cur := str(_current_skin.get("hat", "none"))
	var idx := 0
	for i in range(Wardrobe.HATS.size()):
		if Wardrobe.HATS[i]["id"] == cur:
			idx = i
			break
	var next_idx := posmod(idx + dir, Wardrobe.HATS.size())
	_current_skin["hat"] = Wardrobe.HATS[next_idx]["id"]
	_update_selector_labels()
	_refresh_custom_preview()


func _cycle_glasses(dir: int) -> void:
	var cur := str(_current_skin.get("glasses", "none"))
	var idx := 0
	for i in range(Wardrobe.GLASSES.size()):
		if Wardrobe.GLASSES[i]["id"] == cur:
			idx = i
			break
	var next_idx := posmod(idx + dir, Wardrobe.GLASSES.size())
	_current_skin["glasses"] = Wardrobe.GLASSES[next_idx]["id"]
	_update_selector_labels()
	_refresh_custom_preview()


func _cycle_hair(dir: int) -> void:
	var cur := str(_current_skin.get("hair", "bald"))
	var idx := 0
	for i in range(Wardrobe.HAIRSTYLES.size()):
		if Wardrobe.HAIRSTYLES[i]["id"] == cur:
			idx = i
			break
	var next_idx := posmod(idx + dir, Wardrobe.HAIRSTYLES.size())
	_current_skin["hair"] = Wardrobe.HAIRSTYLES[next_idx]["id"]
	_update_selector_labels()
	_refresh_custom_preview()


func _cycle_outfit(dir: int) -> void:
	var cur := str(_current_skin.get("outfit", "classic"))
	var idx := 0
	for i in range(Wardrobe.OUTFITS.size()):
		if Wardrobe.OUTFITS[i]["id"] == cur:
			idx = i
			break
	var next_idx := posmod(idx + dir, Wardrobe.OUTFITS.size())
	_current_skin["outfit"] = Wardrobe.OUTFITS[next_idx]["id"]
	_update_selector_labels()
	_refresh_custom_preview()


func _update_selector_labels() -> void:
	if _color_lbl != null:
		_color_lbl.text = str(Wardrobe.get_body_color_def(str(_current_skin.get("color", "mint"))).get("name", ""))
	if _hat_lbl != null:
		_hat_lbl.text = str(Wardrobe.get_hat_def(str(_current_skin.get("hat", "none"))).get("name", ""))
	if _glasses_lbl != null:
		_glasses_lbl.text = str(Wardrobe.get_glasses_def(str(_current_skin.get("glasses", "none"))).get("name", ""))
	if _hair_lbl != null:
		_hair_lbl.text = str(Wardrobe.get_hair_def(str(_current_skin.get("hair", "bald"))).get("name", ""))
	if _outfit_lbl != null:
		_outfit_lbl.text = str(Wardrobe.get_outfit_def(str(_current_skin.get("outfit", "classic"))).get("name", ""))


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
	camera.position = Vector3(0, 0.96, 2.35)
	camera.fov = 46.0
	camera.current = true
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.86, 0))

	var character := PLAYER_SCENE.instantiate()
	character.name = "PreviewCharacter"
	character.position.y = 0.05
	viewport.add_child(character)
	character.set_display_name_visible(false)
	if character.has_method("apply_wardrobe"):
		character.call("apply_wardrobe", _current_skin)


func _refresh() -> void:
	if not _is_preview_mode:
		var rec: Dictionary = _manager.call("get_active_room_record") if _manager != null else {}
		if rec.is_empty():
			# Standalone Preview Mode fallback (e.g. running Lobby.tscn directly with F6)
			_is_preview_mode = true
			_local_player_id = "preview_host"
			var p_name: String = "Host (You)"
			var encoded_name := Wardrobe.encode_to_display_name(p_name, _current_skin)
			_room = {
				"room_code": "TEST99",
				"room_name": "Preview Room",
				"host_player_id": "preview_host",
				"max_players": 2,
				"visibility": "PUBLIC",
				"status": "WAITING",
				"game_mode": "1v1",
				"players": [
					{
						"player_id": "preview_host",
						"display_name": encoded_name,
						"team_id": TEAM_RED,
						"character_id": "mint",
						"is_host": true,
						"is_ready": false
					}
				]
			}
		else:
			_room = rec
			var mgr_pid := str(_manager.get("active_player_id")) if _manager != null else ""
			if not mgr_pid.is_empty():
				_local_player_id = mgr_pid

	var players: Array = _room.get("players", [])
	var ready_count := 0
	if _is_preview_mode:
		for p in players:
			if bool(p.get("is_ready", false)):
				ready_count += 1
	else:
		ready_count = int(_manager.call("get_ready_count", str(_room.get("room_code", ""))))

	var mode_text := str(_room.get("game_mode", "")).to_upper()
	var mode_prefix := "%s - " % mode_text if not mode_text.is_empty() else ""
	_header.text = "%s%d / %d PLAYERS - %d / %d READY - %s" % [
		mode_prefix,
		players.size(),
		int(_room.get("max_players", 0)),
		ready_count,
		players.size(),
		str(_room.get("visibility", "PRIVATE"))
	]
	_copy_button.text = "ROOM %s - COPY" % str(_room.get("room_code", "------"))

	var local_player := _find_player(players, _local_player_id)
	var waiting_for_players := str(_room.get("status", "")) == "WAITING"
	_ready_button.disabled = local_player.is_empty() or not waiting_for_players
	_customize_button.disabled = local_player.is_empty() or not waiting_for_players
	_ready_button.text = "SET NOT READY" if bool(local_player.get("is_ready", false)) else "READY UP"

	var is_host := str(_room.get("host_player_id", "")) == _local_player_id
	_start_button.visible = is_host
	_start_hint.visible = is_host
	if is_host:
		if _is_preview_mode:
			_start_button.disabled = false
			_start_hint.text = "Preview Mode: Click Start Match or Customize Character."
		else:
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

		var members: Array = []
		if _is_preview_mode:
			for p in players:
				if int(p.get("team_id", 0)) == team_id:
					members.append(p)
		else:
			members = _manager.call("get_players_by_team", str(_room.get("room_code", "")), team_id)

		var capacity := int(int(_room.get("max_players", 0)) / 2)
		var heading: Label = list.get_parent().get_child(1)
		heading.text = "%d / %d PLAYERS" % [members.size(), capacity]

		for player in members:
			list.add_child(_make_player_row(player, team_id))

		if members.is_empty():
			var empty := _label("No players yet - this team is open.", 15, Color("#71838a"))
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			list.add_child(empty)

		var fill := Control.new()
		fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.add_child(fill)

		var join_button: Button = list.get_parent().get_child(list.get_parent().get_child_count() - 1)
		var is_on_this_team: bool = not local_player.is_empty() and int(local_player.get("team_id", 0)) == team_id
		var team_is_full: bool = members.size() >= capacity and not is_on_this_team
		var can_change_team: bool = not local_player.is_empty() and waiting_for_players

		if is_on_this_team:
			join_button.disabled = true
			join_button.text = "YOUR TEAM"
			join_button.tooltip_text = "You are already on this team."
		elif team_is_full:
			join_button.disabled = true
			join_button.text = "RED TEAM FULL" if team_id == TEAM_RED else "BLUE TEAM FULL"
			join_button.tooltip_text = "Each team can hold up to %d players." % capacity
		elif not can_change_team:
			join_button.disabled = true
			join_button.text = "TEAM LOCKED" if waiting_for_players else "MATCH STARTED"
			join_button.tooltip_text = "Team selection is unavailable without an active player in a waiting room."
		else:
			join_button.disabled = false
			join_button.text = "JOIN RED" if team_id == TEAM_RED else "JOIN BLUE"
			join_button.tooltip_text = "Move your player to this team."

	if not local_player.is_empty():
		var raw_name := str(local_player.get("display_name", ""))
		if raw_name.contains("#"):
			var decoded := Wardrobe.decode_from_display_name(raw_name)
			_current_skin = decoded.get("skin", _current_skin)
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

	var raw_name := str(player.get("display_name", player.get("player_id", "Player")))
	var clean_pname := Wardrobe.clean_name(raw_name)
	var name := _label(clean_pname, 19, Color("#18364d"))
	labels.add_child(name)

	var decoded := Wardrobe.decode_from_display_name(raw_name)
	var skin_info: Dictionary = decoded.get("skin", {})
	var hat_name := str(Wardrobe.get_hat_def(str(skin_info.get("hat", "none"))).get("name", "Classic"))
	var ready_text := "READY" if bool(player.get("is_ready", false)) else "NOT READY"
	var host_badge := "  * HOST" if bool(player.get("is_host", false)) else ""
	var details := _label("%s - %s - %s%s" % [hat_name, "RED" if team_id == TEAM_RED else "BLUE", ready_text, host_badge], 14,
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
	camera.position = Vector3(0, 1.05, 1.95)
	camera.fov = 48.0
	camera.current = true
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))

	var character: Node = PLAYER_SCENE.instantiate()
	character.name = "PreviewCharacter"
	character.position.y = 0.05
	viewport.add_child(character)

	var raw_name := str(player.get("display_name", "Player"))
	character.set_display_name(Wardrobe.clean_name(raw_name))
	character.set_display_name_visible(false)

	var decoded := Wardrobe.decode_from_display_name(raw_name)
	var skin_data: Dictionary = decoded.get("skin", {})
	if skin_data.is_empty():
		var char_id := str(player.get("character_id", "mint"))
		match char_id:
			"peach": skin_data = {"color": "peach", "hat": "tiny_hat", "glasses": "none", "hair": "bald", "outfit": "classic"}
			"sky": skin_data = {"color": "sky", "hat": "none", "glasses": "round", "hair": "bald", "outfit": "classic"}
			_: skin_data = {"color": "mint", "hat": "feather", "glasses": "none", "hair": "bald", "outfit": "classic"}

	if character.has_method("apply_wardrobe"):
		character.call("apply_wardrobe", skin_data)


func _show_customizer() -> void:
	if _local_player_id.is_empty():
		_message.text = "No local player is registered in this room."
		return

	var local_p := _find_player(_room.get("players", []), _local_player_id)
	var current_name := "Player"
	if not local_p.is_empty():
		var raw_name := str(local_p.get("display_name", ""))
		var decoded := Wardrobe.decode_from_display_name(raw_name)
		current_name = str(decoded.get("name", "Player"))
		if raw_name.contains("#"):
			_current_skin = decoded.get("skin", Wardrobe.default_skin())
		else:
			_current_skin = Wardrobe.default_skin()

	if _custom_name_edit != null:
		_custom_name_edit.text = current_name

	_custom_panel.show()
	_update_responsive_layout()
	_refresh_custom_preview()


func _apply_custom_wardrobe() -> void:
	if _custom_name_edit == null or _local_player_id.is_empty():
		return
	var raw_name := _custom_name_edit.text.strip_edges()
	var clean_pname := Wardrobe.clean_name(raw_name)
	Wardrobe.save_local_wardrobe(_current_skin, clean_pname)

	var code := str(_room.get("room_code", ""))
	var encoded_name := Wardrobe.encode_to_display_name(clean_pname, _current_skin)
	var base_char_id := Wardrobe.get_base_character_id(_current_skin)

	if _is_preview_mode:
		for p in _room.get("players", []):
			if str(p.get("player_id", "")) == _local_player_id:
				p["display_name"] = encoded_name
				p["character_id"] = base_char_id
		_refresh()
		return

	if _manager != null:
		_manager.call("update_player_character", code, _local_player_id, base_char_id)
		if _manager.has_method("update_player_name"):
			_manager.call("update_player_name", code, _local_player_id, encoded_name)
	_refresh()


func _refresh_custom_preview() -> void:
	_update_selector_labels()
	if _custom_preview == null or _custom_preview.get_child_count() == 0:
		return
	var character := _custom_preview.get_node_or_null("PreviewCharacter")
	if character != null and character.has_method("apply_wardrobe"):
		character.call("apply_wardrobe", _current_skin)


func _preset_index_for(character_id: String) -> int:
	for index in range(PRESETS.size()):
		if str(PRESETS[index]["id"]) == character_id:
			return index
	return 0


func _find_player(players: Array, player_id: String) -> Dictionary:
	for p in players:
		if str(p.get("player_id", "")) == player_id:
			return p
	return {}


func _join_team(team_id: int) -> void:
	if _local_player_id.is_empty():
		return

	if _is_preview_mode:
		for p in _room.get("players", []):
			if str(p.get("player_id", "")) == _local_player_id:
				p["team_id"] = team_id
		_refresh()
		return

	if _manager == null:
		return
	var room_code := str(_room.get("room_code", ""))
	var result: Dictionary = {}
	if _manager.has_method("update_player_team"):
		result = _manager.call("update_player_team", room_code, _local_player_id, team_id)
	elif _manager.has_method("switch_player_team"):
		result = _manager.call("switch_player_team", room_code, _local_player_id, team_id)
	if not bool(result.get("success", false)):
		_message.text = str(result.get("message", "Could not switch teams."))
		return
	_refresh()


func _toggle_ready() -> void:
	if _local_player_id.is_empty():
		return

	if _is_preview_mode:
		for p in _room.get("players", []):
			if str(p.get("player_id", "")) == _local_player_id:
				p["is_ready"] = not bool(p.get("is_ready", false))
		_refresh()
		return

	if _manager == null:
		return
	var result: Dictionary = _manager.call("toggle_player_ready", str(_room.get("room_code", "")), _local_player_id)
	if not bool(result.get("success", false)):
		_message.text = str(result.get("message", "Could not update ready state."))
		return
	_refresh()


func _start_match() -> void:
	if _is_preview_mode:
		var arena_scene := load(ARENA_SCENE_PATH) as PackedScene
		if arena_scene != null:
			var arena_inst := arena_scene.instantiate()
			arena_inst.set("room_code", "TEST99")
			get_tree().root.add_child(arena_inst)
			queue_free()
		return

	if _manager == null or _local_player_id.is_empty():
		return
	var room_code := str(_room.get("room_code", ""))
	var result: Dictionary = {}
	if _manager.has_method("start_match"):
		result = _manager.call("start_match", room_code, _local_player_id)
	elif _manager.has_method("start_room_match"):
		result = _manager.call("start_room_match", room_code, _local_player_id)
	elif _manager.has_method("start_room"):
		var ok: bool = _manager.call("start_room", room_code, _local_player_id)
		result = {"success": ok}

	if not bool(result.get("success", false)):
		_message.text = str(result.get("message", "Could not start match."))
		return

	var is_online: bool = bool(_manager.call("is_online")) if _manager.has_method("is_online") else false
	if not is_online:
		_navigate_to_scene(ARENA_SCENE_PATH)


func _navigate_to_scene(scene_path: String) -> void:
	var main_node := get_tree().root.get_node_or_null("Main")
	if main_node != null and main_node.has_method("change_scene"):
		main_node.call("change_scene", scene_path)
		return
	get_tree().change_scene_to_file(scene_path)


func _leave_room() -> void:
	if not _is_preview_mode and _manager != null and not _local_player_id.is_empty():
		_manager.call("leave_room", str(_room.get("room_code", "")), _local_player_id)
	_navigate_to_scene(MAIN_MENU_SCENE_PATH)


func _copy_code() -> void:
	var code := str(_room.get("room_code", ""))
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_message.text = "Room code %s copied to clipboard!" % code


func _on_room_updated(arg1: Variant = null, arg2: Variant = null) -> void:
	if arg2 is Dictionary:
		_room = arg2
	elif arg1 is Dictionary:
		_room = arg1
	elif _manager != null and _manager.has_method("get_active_room_record"):
		_room = _manager.call("get_active_room_record")
	_refresh()


func _on_match_started(arg1: Variant = null, _arg2: Variant = null, _arg3: Variant = null) -> void:
	if arg1 is Dictionary:
		_room = arg1
	elif _manager != null and _manager.has_method("get_active_room_record"):
		_room = _manager.call("get_active_room_record")
	var active_code := str(_room.get("room_code", ""))
	print("[Lobby] Match started signal received for room: %s. Transitioning directly to Arena..." % active_code)
	_navigate_to_scene(ARENA_SCENE_PATH)


func _on_room_closed(room_code: String = "", reason: String = "") -> void:
	if room_code.is_empty() or str(_room.get("room_code", "")) == room_code:
		_message.text = "Room was closed: %s" % reason if not reason.is_empty() else "Room was closed."
		_navigate_to_scene(MAIN_MENU_SCENE_PATH)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = color.darkened(0.12)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := style.duplicate()
	disabled.bg_color = Color("#b0bec5")
	button.add_theme_stylebox_override("disabled", disabled)
	return button
