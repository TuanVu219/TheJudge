extends CanvasLayer

## Dedicated HUD for Forehead Poker (Stage P3 & P4.1).
## Features:
## - Private Hand Card UI: Bottom-center cartoon display showing ONLY the local player's Hand card.
## - Permitted Card History Panel: Displays player's past hand cards & observed opponent foreheads.
## - Compact Action History Panel: Live chronological feed of validated player actions.
## - Authoritative Betting Controls: Fold, Check, Call, Raise (with slider/stepper), All-In.
## - Seamless Mouse Control: Automatically provides visible cursor for HUD interaction without ESC.
## - Pot Banner: Detailed Main Pot, To-Call, and Min-Raise readout.

const CardNumTextures: Dictionary = {
	1: preload("res://assets/textures/saloon/card_num_1.png"),
	2: preload("res://assets/textures/saloon/card_num_2.png"),
	3: preload("res://assets/textures/saloon/card_num_3.png"),
	4: preload("res://assets/textures/saloon/card_num_4.png"),
	5: preload("res://assets/textures/saloon/card_num_5.png"),
	6: preload("res://assets/textures/saloon/card_num_6.png"),
	7: preload("res://assets/textures/saloon/card_num_7.png"),
	8: preload("res://assets/textures/saloon/card_num_8.png"),
	9: preload("res://assets/textures/saloon/card_num_9.png"),
	10: preload("res://assets/textures/saloon/card_num_10.png"),
}

signal request_draw_round
signal request_reset_match
signal betting_action_requested(action: String, target_bet: int)
signal hud_hover_changed(is_hovered: bool)
signal card_picks_submitted(hand_slot: int, forehead_slot: int)

var current_round: int = 0
var total_rounds: int = 10
var my_hand_card: Variant = null
var my_hand_history: Array[int] = []
var opponent_forehead_history: Dictionary = {} # player_id -> Array[int]

# Card Picker State
var card_picker_panel: PanelContainer
var picker_title_label: Label
var picker_timer_label: Label
var picker_status_label: Label
var picker_confirm_btn: Button
var hand_slot_buttons: Array[Button] = []
var forehead_slot_buttons: Array[Button] = []
var selected_hand_slot: int = -1
var selected_forehead_slot: int = -1
var used_hand_slots: Array = []
var used_forehead_slots: Array = []
var _is_picker_active: bool = false
var _picker_countdown: float = 15.0
var _card_back_tex: Texture2D = preload("res://assets/textures/saloon/card_back_red.png")

# Betting State Cache
var local_player_id: String = ""
var local_balance: int = 100
var local_round_bet: int = 0
var is_my_turn: bool = false
var betting_active: bool = false
var current_highest_bet: int = 0
var min_raise_inc: int = 2

# UI Nodes
var hand_card_container: Control
var hand_card_texture_rect: TextureRect
var hand_number_label: Label
var waiting_label: Label
var round_label: Label
var pot_label: Label
var pot_details_label: Label
var turn_label: Label
var announcement_label: Label
var chips_label: Label

var history_panel: PanelContainer
var history_text_label: RichTextLabel
var history_toggle_btn: Button

# Compact Action History Panel
var action_history_panel: PanelContainer
var action_history_label: RichTextLabel
var _action_history_entries: Array[Dictionary] = []

# Betting UI Nodes
var betting_panel: PanelContainer
var btn_fold: Button
var btn_check: Button
var btn_call: Button
var btn_raise: Button
var btn_all_in: Button
var raise_slider: HSlider
var raise_value_label: Label


func _ready() -> void:
	layer = 10
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "PokerHUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── TOP CENTER: ROUND STATUS & POT BANNER ─────────────────────────────────
	var top_bar := PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_bar.position = Vector2(-220, 12)
	top_bar.size = Vector2(440, 78)
	
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.12, 0.08, 0.06, 0.92)
	top_style.set_corner_radius_all(14)
	top_style.set_border_width_all(2)
	top_style.border_color = Color(0.92, 0.78, 0.35, 1.0)
	top_style.content_margin_left = 16
	top_style.content_margin_right = 16
	top_style.content_margin_top = 4
	top_style.content_margin_bottom = 4
	top_bar.add_theme_stylebox_override("panel", top_style)
	_bind_hover_events(top_bar)
	root.add_child(top_bar)

	var top_vbox := VBoxContainer.new()
	top_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_vbox.add_theme_constant_override("separation", 2)
	top_bar.add_child(top_vbox)

	round_label = Label.new()
	round_label.text = "FOREHEAD POKER • ROUND 1 / 10"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_font_size_override("font_size", 15)
	round_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65, 1.0))
	top_vbox.add_child(round_label)

	pot_label = Label.new()
	pot_label.text = "💰 POT: 0 CHIPS"
	pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot_label.add_theme_font_size_override("font_size", 20)
	pot_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.20, 1.0))
	top_vbox.add_child(pot_label)

	pot_details_label = Label.new()
	pot_details_label.text = "Bet: 0 • To Call: 0 • Min Raise: 2"
	pot_details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot_details_label.add_theme_font_size_override("font_size", 12)
	pot_details_label.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90, 0.9))
	top_vbox.add_child(pot_details_label)

	# ── TURN BANNER & ACTION FEED (CENTER BELOW TOP BAR) ─────────────────────
	var banner_box := PanelContainer.new()
	banner_box.name = "TurnBanner"
	banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_box.position = Vector2(-220, 96)
	banner_box.size = Vector2(440, 46)

	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.08, 0.06, 0.05, 0.84)
	banner_style.set_corner_radius_all(10)
	banner_style.set_border_width_all(1)
	banner_style.border_color = Color(0.8, 0.65, 0.3, 0.6)
	banner_box.add_theme_stylebox_override("panel", banner_style)
	_bind_hover_events(banner_box)
	root.add_child(banner_box)

	var banner_vbox := VBoxContainer.new()
	banner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.add_child(banner_vbox)

	turn_label = Label.new()
	turn_label.text = "WAITING FOR ROUND START..."
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.add_theme_font_size_override("font_size", 14)
	turn_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	banner_vbox.add_child(turn_label)

	announcement_label = Label.new()
	announcement_label.text = ""
	announcement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcement_label.add_theme_font_size_override("font_size", 12)
	announcement_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 1.0))
	banner_vbox.add_child(announcement_label)

	# ── TOP LEFT: COMPACT ACTION HISTORY PANEL ──────────────────────────────
	action_history_panel = PanelContainer.new()
	action_history_panel.name = "ActionHistoryPanel"
	action_history_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	action_history_panel.position = Vector2(16, 14)
	action_history_panel.size = Vector2(250, 210)

	var act_hist_style := StyleBoxFlat.new()
	act_hist_style.bg_color = Color(0.09, 0.06, 0.05, 0.88)
	act_hist_style.set_corner_radius_all(12)
	act_hist_style.set_border_width_all(1)
	act_hist_style.border_color = Color(0.85, 0.70, 0.35, 0.8)
	act_hist_style.content_margin_left = 12
	act_hist_style.content_margin_right = 12
	act_hist_style.content_margin_top = 8
	act_hist_style.content_margin_bottom = 8
	action_history_panel.add_theme_stylebox_override("panel", act_hist_style)
	_bind_hover_events(action_history_panel)
	root.add_child(action_history_panel)

	action_history_label = RichTextLabel.new()
	action_history_label.bbcode_enabled = true
	action_history_label.fit_content = false
	action_history_label.scroll_following = true
	action_history_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	action_history_panel.add_child(action_history_label)
	_refresh_action_history_display()

	# ── BOTTOM CENTER: MY PRIVATE HAND CARD UI ───────────────────────────────
	hand_card_container = Control.new()
	hand_card_container.name = "HandCardContainer"
	hand_card_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hand_card_container.size = Vector2(160, 224)
	hand_card_container.position = Vector2(-80, -240)
	_bind_hover_events(hand_card_container)
	root.add_child(hand_card_container)

	# Card Panel Shadow & Frame
	var card_bg := PanelContainer.new()
	card_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.99, 0.98, 0.95, 1.0)
	card_style.set_corner_radius_all(16)
	card_style.set_border_width_all(4)
	card_style.border_color = Color(0.78, 0.22, 0.18, 1.0)
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 12
	card_style.shadow_offset = Vector2(0, 6)
	card_bg.add_theme_stylebox_override("panel", card_style)
	hand_card_container.add_child(card_bg)

	# Badge "MY HAND"
	var badge := PanelContainer.new()
	badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	badge.position = Vector2(-54, -14)
	badge.size = Vector2(108, 26)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.82, 0.18, 0.15, 1.0)
	badge_style.set_corner_radius_all(10)
	badge_style.set_border_width_all(2)
	badge_style.border_color = Color(1.0, 0.88, 0.45, 1.0)
	badge.add_theme_stylebox_override("panel", badge_style)
	hand_card_container.add_child(badge)

	var badge_lbl := Label.new()
	badge_lbl.text = "★ MY HAND ★"
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_font_size_override("font_size", 12)
	badge_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	badge.add_child(badge_lbl)

	# Card Face Texture Display
	hand_card_texture_rect = TextureRect.new()
	hand_card_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hand_card_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand_card_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hand_card_container.add_child(hand_card_texture_rect)

	# Waiting / Dealing state overlay
	waiting_label = Label.new()
	waiting_label.text = "DEALING..."
	waiting_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	waiting_label.add_theme_font_size_override("font_size", 18)
	waiting_label.add_theme_color_override("font_color", Color(0.35, 0.28, 0.22, 1.0))
	hand_card_container.add_child(waiting_label)

	# ── BOTTOM RIGHT: AUTHORITATIVE BETTING CONTROLS ─────────────────────────
	betting_panel = PanelContainer.new()
	betting_panel.name = "BettingPanel"
	betting_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	betting_panel.position = Vector2(-360, -220)
	betting_panel.size = Vector2(344, 204)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.10, 0.07, 0.05, 0.94)
	panel_style.set_corner_radius_all(14)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.85, 0.70, 0.35, 0.9)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	betting_panel.add_theme_stylebox_override("panel", panel_style)
	_bind_hover_events(betting_panel)
	root.add_child(betting_panel)

	var bet_vbox := VBoxContainer.new()
	bet_vbox.add_theme_constant_override("separation", 8)
	betting_panel.add_child(bet_vbox)

	# Chips label
	chips_label = Label.new()
	chips_label.text = "YOUR STACK: 100 CHIPS"
	chips_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chips_label.add_theme_font_size_override("font_size", 14)
	chips_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40, 1.0))
	bet_vbox.add_child(chips_label)

	# Row 1: Quick Actions (FOLD, CHECK, CALL)
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 6)
	bet_vbox.add_child(row1)

	btn_fold = Button.new()
	btn_fold.text = "FOLD"
	btn_fold.custom_minimum_size = Vector2(96, 36)
	_style_button(btn_fold, Color(0.75, 0.20, 0.20, 1.0))
	btn_fold.pressed.connect(func(): _on_action_clicked("FOLD"))
	row1.add_child(btn_fold)

	btn_check = Button.new()
	btn_check.text = "CHECK"
	btn_check.custom_minimum_size = Vector2(96, 36)
	_style_button(btn_check, Color(0.25, 0.45, 0.75, 1.0))
	btn_check.pressed.connect(func(): _on_action_clicked("CHECK"))
	row1.add_child(btn_check)

	btn_call = Button.new()
	btn_call.text = "CALL"
	btn_call.custom_minimum_size = Vector2(104, 36)
	_style_button(btn_call, Color(0.20, 0.65, 0.35, 1.0))
	btn_call.pressed.connect(func(): _on_action_clicked("CALL"))
	row1.add_child(btn_call)

	# Row 2: Raise Controls (Slider + Raise Button)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 6)
	bet_vbox.add_child(row2)

	raise_slider = HSlider.new()
	raise_slider.custom_minimum_size = Vector2(170, 24)
	raise_slider.min_value = 2
	raise_slider.max_value = 100
	raise_slider.step = 1
	raise_slider.value = 2
	raise_slider.value_changed.connect(_on_raise_slider_changed)
	row2.add_child(raise_slider)

	btn_raise = Button.new()
	btn_raise.text = "RAISE 2"
	btn_raise.custom_minimum_size = Vector2(120, 34)
	_style_button(btn_raise, Color(0.85, 0.55, 0.15, 1.0))
	btn_raise.pressed.connect(func(): _on_action_clicked("RAISE", int(raise_slider.value)))
	row2.add_child(btn_raise)

	# Row 3: All-In Button
	btn_all_in = Button.new()
	btn_all_in.text = "⚡ ALL-IN"
	btn_all_in.custom_minimum_size = Vector2(300, 32)
	_style_button(btn_all_in, Color(0.60, 0.20, 0.70, 1.0))
	btn_all_in.pressed.connect(func(): _on_action_clicked("ALL_IN"))
	bet_vbox.add_child(btn_all_in)

	# ── TOP RIGHT: HISTORY TOGGLE BUTTON & CONTROLS ──────────────────────────
	var top_right := HBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.position = Vector2(-280, 16)
	top_right.size = Vector2(264, 40)
	top_right.alignment = BoxContainer.ALIGNMENT_END
	top_right.add_theme_constant_override("separation", 8)
	_bind_hover_events(top_right)
	root.add_child(top_right)

	history_toggle_btn = Button.new()
	history_toggle_btn.text = "📜 Card History"
	history_toggle_btn.custom_minimum_size = Vector2(120, 36)
	history_toggle_btn.pressed.connect(_on_history_toggled)
	top_right.add_child(history_toggle_btn)

	var draw_btn := Button.new()
	draw_btn.name = "DrawButton"
	draw_btn.text = "🎲 Next Round"
	draw_btn.custom_minimum_size = Vector2(110, 36)
	draw_btn.pressed.connect(func(): request_draw_round.emit())
	top_right.add_child(draw_btn)

	# ── TOP RIGHT: CARD HISTORY PANEL (COLLAPSIBLE) ─────────────────────────
	history_panel = PanelContainer.new()
	history_panel.name = "HistoryPanel"
	history_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	history_panel.position = Vector2(-360, 68)
	history_panel.size = Vector2(344, 280)
	history_panel.visible = false

	var hist_style := StyleBoxFlat.new()
	hist_style.bg_color = Color(0.08, 0.06, 0.05, 0.92)
	hist_style.set_corner_radius_all(12)
	hist_style.set_border_width_all(2)
	hist_style.border_color = Color(0.85, 0.70, 0.35, 0.9)
	hist_style.content_margin_left = 14
	hist_style.content_margin_right = 14
	hist_style.content_margin_top = 12
	hist_style.content_margin_bottom = 12
	history_panel.add_theme_stylebox_override("panel", hist_style)
	_bind_hover_events(history_panel)
	root.add_child(history_panel)

	history_text_label = RichTextLabel.new()
	history_text_label.bbcode_enabled = true
	history_text_label.fit_content = false
	history_text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	history_panel.add_child(history_text_label)
	_update_history_text()

	# ── CENTER: 15-SECOND 2-ROW CARD PICKER MODAL OVERLAY ───────────────────
	_build_card_picker_ui(root)

	# Initial button states disabled until game begins
	_set_betting_buttons_enabled(false)


func _bind_hover_events(control: Control) -> void:
	control.mouse_entered.connect(func(): hud_hover_changed.emit(true))
	control.mouse_exited.connect(func(): hud_hover_changed.emit(false))


func _style_button(btn: Button, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = col.lightened(0.3)
	btn.add_theme_stylebox_override("normal", sb)

	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = col.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sb_hover)

	var sb_disabled := sb.duplicate() as StyleBoxFlat
	sb_disabled.bg_color = Color(0.2, 0.2, 0.2, 0.6)
	sb_disabled.border_color = Color(0.3, 0.3, 0.3, 0.4)
	btn.add_theme_stylebox_override("disabled", sb_disabled)


func _process(delta: float) -> void:
	if _is_picker_active:
		_picker_countdown -= delta
		if _picker_countdown <= 0.0:
			_picker_countdown = 0.0
			_is_picker_active = false
			_on_picker_timeout()
		else:
			_update_picker_timer_display()


# ── CARD PICKER OVERLAY (15-SECOND 2-ROW INTERFACE) ─────────────────────────

func _build_card_picker_ui(parent: Control) -> void:
	card_picker_panel = PanelContainer.new()
	card_picker_panel.name = "CardPickerPanel"
	card_picker_panel.set_anchors_preset(Control.PRESET_CENTER)
	card_picker_panel.size = Vector2(760, 360)
	card_picker_panel.position = Vector2(-380, -180)
	card_picker_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.04, 0.96)
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	style.border_color = Color(0.92, 0.78, 0.35, 1.0)
	style.shadow_color = Color(0, 0, 0, 0.75)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	card_picker_panel.add_theme_stylebox_override("panel", style)
	_bind_hover_events(card_picker_panel)
	parent.add_child(card_picker_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	card_picker_panel.add_child(main_vbox)

	# 1. Header (Title & Countdown)
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(header)

	picker_title_label = Label.new()
	picker_title_label.text = "🃏 GIAI ĐOẠN BỐC BÀI • VÒNG 1 / 10"
	picker_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_title_label.add_theme_font_size_override("font_size", 18)
	picker_title_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.50, 1.0))
	header.add_child(picker_title_label)

	var timer_badge := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.65, 0.12, 0.12, 0.95)
	t_style.set_corner_radius_all(10)
	t_style.set_border_width_all(2)
	t_style.border_color = Color(1.0, 0.85, 0.3, 1.0)
	t_style.content_margin_left = 12
	t_style.content_margin_right = 12
	t_style.content_margin_top = 2
	t_style.content_margin_bottom = 2
	timer_badge.add_theme_stylebox_override("panel", t_style)
	header.add_child(timer_badge)

	picker_timer_label = Label.new()
	picker_timer_label.text = "⏱️ 15s"
	picker_timer_label.add_theme_font_size_override("font_size", 18)
	picker_timer_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 1.0))
	timer_badge.add_child(picker_timer_label)

	# Instruction
	var inst_lbl := Label.new()
	inst_lbl.text = "Bốc 1 lá từ dãy TRÊN TAY và 1 lá từ dãy TRÊN TRÁN trong 15s (Hết giờ tự động random)"
	inst_lbl.add_theme_font_size_override("font_size", 12)
	inst_lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70, 0.9))
	main_vbox.add_child(inst_lbl)

	# 2. Row 1: Hand Deck
	var row1_header := Label.new()
	row1_header.text = "🎴 DÃY BÀI TRÊN TAY (BẠN SẼ THẤY SỐ)"
	row1_header.add_theme_font_size_override("font_size", 13)
	row1_header.add_theme_color_override("font_color", Color(0.95, 0.45, 0.40, 1.0))
	main_vbox.add_child(row1_header)

	var row1_hbox := HBoxContainer.new()
	row1_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	row1_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(row1_hbox)

	hand_slot_buttons.clear()
	for i in range(10):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(66, 88)
		btn.clip_text = true
		btn.pressed.connect(func(): _on_card_slot_clicked(true, i))
		_bind_hover_events(btn)
		row1_hbox.add_child(btn)
		hand_slot_buttons.append(btn)

	# 3. Row 2: Forehead Deck
	var row2_header := Label.new()
	row2_header.text = "🤠 DÃY BÀI TRÊN TRÁN (ĐỐI THỦ SẼ THẤY SỐ)"
	row2_header.add_theme_font_size_override("font_size", 13)
	row2_header.add_theme_color_override("font_color", Color(0.40, 0.75, 1.0, 1.0))
	main_vbox.add_child(row2_header)

	var row2_hbox := HBoxContainer.new()
	row2_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	row2_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(row2_hbox)

	forehead_slot_buttons.clear()
	for i in range(10):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(66, 88)
		btn.clip_text = true
		btn.pressed.connect(func(): _on_card_slot_clicked(false, i))
		_bind_hover_events(btn)
		row2_hbox.add_child(btn)
		forehead_slot_buttons.append(btn)

	# 4. Bottom Controls & Status
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 12)
	main_vbox.add_child(bottom_bar)

	picker_status_label = Label.new()
	picker_status_label.text = "Trên Tay: [Chưa chọn]  •  Trên Trán: [Chưa chọn]"
	picker_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_status_label.add_theme_font_size_override("font_size", 13)
	picker_status_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55, 1.0))
	bottom_bar.add_child(picker_status_label)

	picker_confirm_btn = Button.new()
	picker_confirm_btn.text = "XÁC NHẬN BỐC BÀI"
	picker_confirm_btn.custom_minimum_size = Vector2(180, 36)
	_style_button(picker_confirm_btn, Color(0.18, 0.55, 0.25, 1.0))
	picker_confirm_btn.pressed.connect(_on_picker_confirm_clicked)
	picker_confirm_btn.disabled = true
	_bind_hover_events(picker_confirm_btn)
	bottom_bar.add_child(picker_confirm_btn)


func show_card_picker(round_num: int, countdown: float = 15.0, used_h: Array = [], used_f: Array = []) -> void:
	current_round = round_num
	_picker_countdown = countdown
	_is_picker_active = true
	selected_hand_slot = -1
	selected_forehead_slot = -1
	used_hand_slots = used_h.duplicate()
	used_forehead_slots = used_f.duplicate()

	if picker_title_label != null:
		picker_title_label.text = "🃏 GIAI ĐOẠN BỐC BÀI • VÒNG %d / %d" % [round_num, total_rounds]
	_update_picker_timer_display()
	_refresh_card_picker_slots()
	if picker_confirm_btn != null:
		picker_confirm_btn.disabled = true
		picker_confirm_btn.text = "XÁC NHẬN BỐC BÀI"
	if picker_status_label != null:
		picker_status_label.text = "Trên Tay: [Chưa chọn]  •  Trên Trán: [Chưa chọn]"
	if card_picker_panel != null:
		card_picker_panel.visible = true
	
	# Release mouse cursor so player can easily click cards
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_card_picker() -> void:
	_is_picker_active = false
	if card_picker_panel != null:
		card_picker_panel.visible = false


func mark_slots_used(hand_slot: int, forehead_slot: int) -> void:
	if hand_slot >= 0 and not used_hand_slots.has(hand_slot):
		used_hand_slots.append(hand_slot)
	if forehead_slot >= 0 and not used_forehead_slots.has(forehead_slot):
		used_forehead_slots.append(forehead_slot)
	_refresh_card_picker_slots()


func _update_picker_timer_display() -> void:
	if picker_timer_label == null:
		return
	var secs := ceili(_picker_countdown)
	picker_timer_label.text = "⏱️ %ds" % secs
	if secs <= 5:
		picker_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
	else:
		picker_timer_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 1.0))


func _on_card_slot_clicked(is_hand: bool, slot_idx: int) -> void:
	if not _is_picker_active:
		return
	if is_hand:
		if used_hand_slots.has(slot_idx):
			return
		selected_hand_slot = slot_idx
	else:
		if used_forehead_slots.has(slot_idx):
			return
		selected_forehead_slot = slot_idx

	_refresh_card_picker_slots()

	var h_str := "Ô #%d" % (selected_hand_slot + 1) if selected_hand_slot != -1 else "[Chưa chọn]"
	var f_str := "Ô #%d" % (selected_forehead_slot + 1) if selected_forehead_slot != -1 else "[Chưa chọn]"
	picker_status_label.text = "Trên Tay: %s  •  Trên Trán: %s" % [h_str, f_str]

	# Enable confirm button
	picker_confirm_btn.disabled = false
	if selected_hand_slot != -1 and selected_forehead_slot != -1:
		picker_confirm_btn.text = "XÁC NHẬN BỐC BÀI ✓"
	else:
		picker_confirm_btn.text = "XÁC NHẬN (CÒN LẠI RANDOM)"


func _update_slot_button_style(btn: Button, slot_idx: int, is_hand: bool, is_used: bool, is_selected: bool) -> void:
	if is_used:
		btn.text = "TRỐNG\n#%d" % (slot_idx + 1)
		btn.icon = null
		btn.disabled = true
		var sb_empty := StyleBoxFlat.new()
		sb_empty.bg_color = Color(0.04, 0.03, 0.02, 0.6)
		sb_empty.set_corner_radius_all(6)
		sb_empty.set_border_width_all(1)
		sb_empty.border_color = Color(0.35, 0.30, 0.25, 0.3)
		btn.add_theme_stylebox_override("disabled", sb_empty)
		btn.add_theme_color_override("font_disabled_color", Color(0.40, 0.35, 0.30, 0.5))
		btn.add_theme_font_size_override("font_size", 11)
		return

	btn.disabled = false
	btn.icon = _card_back_tex
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.text = "#%d" % (slot_idx + 1)
	btn.add_theme_font_size_override("font_size", 12)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2

	if is_selected:
		var sel_color := Color(1.0, 0.85, 0.2, 1.0) if is_hand else Color(0.35, 0.85, 1.0, 1.0)
		sb.bg_color = Color(0.20, 0.15, 0.05, 0.95) if is_hand else Color(0.05, 0.15, 0.20, 0.95)
		sb.set_border_width_all(3)
		sb.border_color = sel_color
		btn.text = "✓ #%d" % (slot_idx + 1)
		btn.add_theme_color_override("font_color", sel_color)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
	else:
		sb.bg_color = Color(0.12, 0.08, 0.06, 0.9)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.65, 0.50, 0.30, 0.8)
		btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 0.9))
		btn.add_theme_stylebox_override("normal", sb)

		var sb_hov := sb.duplicate() as StyleBoxFlat
		sb_hov.border_color = Color(1.0, 0.85, 0.40, 1.0)
		sb_hov.bg_color = Color(0.22, 0.16, 0.12, 0.95)
		btn.add_theme_stylebox_override("hover", sb_hov)


func _refresh_card_picker_slots() -> void:
	for i in range(10):
		if i < hand_slot_buttons.size():
			var is_used: bool = used_hand_slots.has(i)
			var is_sel: bool = (selected_hand_slot == i)
			_update_slot_button_style(hand_slot_buttons[i], i, true, is_used, is_sel)
		if i < forehead_slot_buttons.size():
			var is_used: bool = used_forehead_slots.has(i)
			var is_sel: bool = (selected_forehead_slot == i)
			_update_slot_button_style(forehead_slot_buttons[i], i, false, is_used, is_sel)


func _on_picker_timeout() -> void:
	if selected_hand_slot == -1:
		var avail_hand: Array = []
		for i in range(10):
			if not used_hand_slots.has(i):
				avail_hand.append(i)
		if not avail_hand.is_empty():
			selected_hand_slot = avail_hand[randi() % avail_hand.size()]

	if selected_forehead_slot == -1:
		var avail_forehead: Array = []
		for i in range(10):
			if not used_forehead_slots.has(i):
				avail_forehead.append(i)
		if not avail_forehead.is_empty():
			selected_forehead_slot = avail_forehead[randi() % avail_forehead.size()]

	_refresh_card_picker_slots()
	picker_status_label.text = "⏳ Hết giờ! Tự động chọn Trên Tay: #%d, Trên Trán: #%d" % [selected_hand_slot + 1, selected_forehead_slot + 1]
	picker_confirm_btn.disabled = true
	card_picks_submitted.emit(selected_hand_slot, selected_forehead_slot)


func _on_picker_confirm_clicked() -> void:
	if not _is_picker_active:
		return
	if selected_hand_slot == -1 or selected_forehead_slot == -1:
		_on_picker_timeout()
		return
	_is_picker_active = false
	picker_confirm_btn.disabled = true
	picker_status_label.text = "✅ Đã xác nhận bốc bài! Đang chia bài..."
	card_picks_submitted.emit(selected_hand_slot, selected_forehead_slot)


## Updates HUD with authoritative server betting state.
func update_betting_state(state: Dictionary, my_id: String) -> void:
	local_player_id = my_id
	betting_active = bool(state.get("betting_phase_active", false))
	current_highest_bet = int(state.get("current_highest_bet", 0))
	min_raise_inc = int(state.get("min_raise_increment", 2))
	var cur_turn: String = str(state.get("current_turn_player_id", ""))
	is_my_turn = (cur_turn == local_player_id) and betting_active

	# Pot Display
	var total_pot := int(state.get("total_pot", 0))
	var side_pots: Array = state.get("side_pots", [])
	if side_pots.size() > 0:
		var main_p := int(state.get("main_pot", total_pot))
		pot_label.text = "💰 POT: %d CHIPS (Main: %d | Side: %d)" % [total_pot, main_p, side_pots.size()]
	else:
		pot_label.text = "💰 POT: %d CHIPS" % total_pot

	# Find local player in players array
	var players_data: Array = state.get("players", [])
	var am_folded := false
	var am_all_in := false
	for p_entry in players_data:
		if not (p_entry is Dictionary):
			continue
		if str(p_entry.get("player_id", "")) == local_player_id:
			local_balance = int(p_entry.get("balance", local_balance))
			local_round_bet = int(p_entry.get("round_bet", 0))
			am_folded = bool(p_entry.get("is_folded", false))
			am_all_in = bool(p_entry.get("is_all_in", false))
			break

	chips_label.text = "YOUR STACK: %d CHIPS" % local_balance

	var to_call := current_highest_bet - local_round_bet
	pot_details_label.text = "Current Bet: %d • To Call: %d • Min Raise: %d" % [current_highest_bet, maxi(0, to_call), min_raise_inc]

	# Turn Banner
	if not betting_active:
		turn_label.text = "BETTING PHASE CLOSED"
		turn_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	elif is_my_turn:
		turn_label.text = "★ YOUR TURN TO ACT ★"
		turn_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.20, 1.0))
		# Automatically provide visible cursor when player's turn begins
		hud_hover_changed.emit(true)
	else:
		var display_name: String = str(state.get("current_turn_name", cur_turn))
		if display_name.is_empty():
			display_name = cur_turn
		turn_label.text = "Waiting for %s to act..." % display_name
		turn_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))

	# Action Announcement feed
	var last_pid: String = str(state.get("last_action_player_id", ""))
	var last_act: String = str(state.get("last_action_type", ""))
	var last_amt: int = int(state.get("last_action_amount", 0))
	if not last_pid.is_empty() and not last_act.is_empty():
		announcement_label.text = "Last: %s %s (%d chips)" % [last_pid, last_act, last_amt]

	# Control Enablement
	if not is_my_turn or am_folded or am_all_in or not betting_active:
		_set_betting_buttons_enabled(false)
		return

	# We are active player:
	btn_fold.disabled = false
	btn_all_in.disabled = (local_balance <= 0)
	btn_all_in.text = "⚡ ALL-IN (%d)" % local_balance

	if to_call <= 0:
		btn_check.disabled = false
		btn_call.disabled = true
		btn_call.text = "CALL"
	else:
		btn_check.disabled = true
		btn_call.disabled = false
		if local_balance < to_call:
			btn_call.text = "CALL (ALL-IN %d)" % local_balance
		else:
			btn_call.text = "CALL %d" % to_call

	# Raise Configuration
	var min_target_raise := current_highest_bet + min_raise_inc
	var max_target_raise := local_balance + local_round_bet

	if max_target_raise <= current_highest_bet or local_balance <= to_call:
		btn_raise.disabled = true
		raise_slider.editable = false
	else:
		btn_raise.disabled = false
		raise_slider.editable = true
		raise_slider.min_value = min_target_raise
		raise_slider.max_value = max_target_raise
		raise_slider.value = min_target_raise
		_on_raise_slider_changed(min_target_raise)


func _on_raise_slider_changed(val: float) -> void:
	var target := int(val)
	var additional := target - local_round_bet
	btn_raise.text = "RAISE TO %d (+%d)" % [target, additional]


func _on_action_clicked(action: String, target_bet: int = 0) -> void:
	_set_betting_buttons_enabled(false)
	betting_action_requested.emit(action, target_bet)


func _set_betting_buttons_enabled(enabled: bool) -> void:
	btn_fold.disabled = not enabled
	btn_check.disabled = not enabled
	btn_call.disabled = not enabled
	btn_raise.disabled = not enabled
	btn_all_in.disabled = not enabled
	raise_slider.editable = enabled


# ── COMPACT ACTION HISTORY FEED ──────────────────────────────────────────────

func add_action_history_entry(p_name: String, act_str: String, col_hex: String = "#E2E8F0") -> void:
	_action_history_entries.append({
		"name": p_name,
		"action": act_str,
		"color": col_hex
	})
	_refresh_action_history_display()


func reset_action_history(round_num: int) -> void:
	_action_history_entries.clear()
	_refresh_action_history_display()


func _refresh_action_history_display() -> void:
	if action_history_label == null:
		return
	var bb := "[b][color=#FFD700]ROUND %d – ACTIONS[/color][/b]\n" % current_round
	if _action_history_entries.is_empty():
		bb += "[color=#A0AEC0][i]Waiting for first action...[/i][/color]"
	else:
		var start_idx: int = maxi(0, _action_history_entries.size() - 8)
		for i in range(start_idx, _action_history_entries.size()):
			var e: Dictionary = _action_history_entries[i]
			bb += "• [color=#CBD5E0]%s:[/color] [b][color=%s]%s[/color][/b]\n" % [e["name"], e["color"], e["action"]]
	action_history_label.text = bb


## Updates the local player's private Hand card.
## CRITICAL: Only accepts Hand card values. Local forehead cards are NEVER shown here.
func set_private_hand_card(round_num: int, card_value: Variant, history: Array = []) -> void:
	current_round = round_num
	my_hand_card = card_value
	
	if history.size() > 0:
		my_hand_history.clear()
		for val in history:
			my_hand_history.append(int(val))
	elif card_value != null and typeof(card_value) == TYPE_INT:
		if not my_hand_history.has(int(card_value)):
			my_hand_history.append(int(card_value))

	_update_round_label()
	_refresh_action_history_display()

	if card_value == null or int(card_value) < 1 or int(card_value) > 10:
		waiting_label.visible = true
		waiting_label.text = "WAITING..."
		hand_card_texture_rect.texture = null
		hand_card_texture_rect.visible = false
	else:
		waiting_label.visible = false
		var tex: Texture2D = CardNumTextures.get(int(card_value), null)
		hand_card_texture_rect.texture = tex
		hand_card_texture_rect.visible = (tex != null)

	_update_history_text()


## Records permitted opponent forehead history
func record_opponent_forehead(opp_id: String, opp_name: String, card_val: int) -> void:
	var key := opp_name if not opp_name.is_empty() else opp_id
	if not opponent_forehead_history.has(key):
		opponent_forehead_history[key] = []
	var arr: Array = opponent_forehead_history[key]
	if not arr.has(card_val):
		arr.append(card_val)
	_update_history_text()


func update_round_status(round_num: int, total: int = 10, is_exhausted: bool = false) -> void:
	current_round = round_num
	total_rounds = total
	_update_round_label()
	if is_exhausted:
		round_label.text = "MATCH FINISHED • ALL 10 ROUNDS PLAYED"


func _update_round_label() -> void:
	if current_round <= 0:
		round_label.text = "FOREHEAD POKER • READY TO DEAL"
	else:
		round_label.text = "FOREHEAD POKER • ROUND %d / %d" % [current_round, total_rounds]


func _on_history_toggled() -> void:
	history_panel.visible = not history_panel.visible


func _update_history_text() -> void:
	var bb := "[b][color=#FFD700]📜 CARD HISTORY (PERMITTED INFO)[/color][/b]\n\n"
	
	# Local Hand Deck History
	bb += "[color=#63B3ED][b]My Hand Cards Drawn:[/b][/color] "
	if my_hand_history.is_empty():
		bb += "[i]None yet[/i]\n"
	else:
		var items: Array[String] = []
		for n in my_hand_history:
			items.append("[b][color=#FFF]%d[/color][/b]" % n)
		bb += ", ".join(items) + "\n"

	bb += "\n[color=#FEB2B2][b]Observed Opponent Foreheads:[/b][/color]\n"
	if opponent_forehead_history.is_empty():
		bb += "[i]None observed yet[/i]\n"
	else:
		for opp in opponent_forehead_history.keys():
			var cards: Array = opponent_forehead_history[opp]
			var card_strs: Array[String] = []
			for c in cards:
				card_strs.append("[b]%d[/b]" % c)
			bb += "• %s: %s\n" % [opp, ", ".join(card_strs)]

	bb += "\n[color=#A0AEC0][i]Note: In accordance with Forehead Poker rules, your own forehead cards and opponent hand cards are strictly hidden.[/i][/color]"
	
	if history_text_label != null:
		history_text_label.text = bb


func reset_hud() -> void:
	current_round = 0
	my_hand_card = null
	my_hand_history.clear()
	opponent_forehead_history.clear()
	_action_history_entries.clear()
	used_hand_slots.clear()
	used_forehead_slots.clear()
	hide_card_picker()
	_update_round_label()
	waiting_label.visible = true
	waiting_label.text = "READY"
	hand_card_texture_rect.texture = null
	hand_card_texture_rect.visible = false
	pot_label.text = "💰 POT: 0 CHIPS"
	pot_details_label.text = "Bet: 0 • To Call: 0 • Min Raise: 2"
	turn_label.text = "READY TO START"
	announcement_label.text = ""
	_update_history_text()
	_refresh_action_history_display()
	_set_betting_buttons_enabled(false)
