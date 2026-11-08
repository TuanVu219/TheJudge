extends Node3D
class_name PokerSeat

## Represents a fixed seated position around the circular Forehead Poker table.
## Handles spawning the player character, applying presets, sitting pose,
## and managing the forehead card attachment point and coin balance.

const PlayerCharacterScene: PackedScene = preload("res://scenes/characters/PlayerCharacter.tscn")
const CardBackTexture: Texture2D = preload("res://assets/textures/saloon/card_back_red.png")

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

# Visual Layer definitions for card privacy
const LAYER_WORLD_AND_OPPONENTS: int = 1
const LAYER_LOCAL_PLAYER_HIDDEN: int = 2

@export var seat_index: int = 0
@export var is_local_player: bool = false
@export var player_name: String = "Player"
@export var coin_amount: int = 1000
@export var wardrobe_skin: Dictionary = {}

var character_instance: Node3D = null
var forehead_card_node: Node3D = null
var balance_label: Label3D = null
var action_badge_label: Label3D = null
var turn_indicator_ring: MeshInstance3D = null
var _current_temp_action: String = ""

# Sitting pose configuration
const SEAT_HEIGHT_OFFSET: float = 0.46
const LEG_PITCH_DEGREES: float = -68.0


func _ready() -> void:
	pass


func clear_character() -> void:
	if character_instance != null and is_instance_valid(character_instance):
		character_instance.queue_free()
		character_instance = null
	forehead_card_node = null
	balance_label = null
	action_badge_label = null
	set_turn_active(false)


func setup_character(
	p_name: String,
	p_coins: int,
	p_skin: Dictionary,
	p_is_local: bool
) -> void:
	player_name = p_name
	coin_amount = p_coins
	wardrobe_skin = p_skin
	is_local_player = p_is_local
	
	_spawn_seated_character()


func _spawn_seated_character() -> void:
	# Clean up previous character if re-spawning
	if character_instance != null and is_instance_valid(character_instance):
		character_instance.queue_free()
		character_instance = null
	
	if PlayerCharacterScene == null:
		push_error("PokerSeat: PlayerCharacterScene failed to load")
		return
	
	character_instance = PlayerCharacterScene.instantiate() as Node3D
	if character_instance == null:
		return
	
	# Add as child of seat
	add_child(character_instance)
	
	# Position naturally on top of stool cushion
	character_instance.position = Vector3(0, SEAT_HEIGHT_OFFSET, 0)
	
	# Face toward the center of the table (0, Y, 0 in global space)
	# Note: PlayerCharacter's face is on +Z axis, while Godot's look_at aims -Z at target,
	# so we rotate by PI (180 deg) so the character's face points directly at the table center.
	var center_point := Vector3(0, global_position.y + SEAT_HEIGHT_OFFSET, 0)
	character_instance.look_at(center_point, Vector3.UP)
	character_instance.rotate_y(PI)
	
	# Apply display name
	character_instance.set_display_name(player_name)
	
	# Apply wardrobe customization preset
	if not wardrobe_skin.is_empty():
		character_instance.apply_wardrobe(wardrobe_skin)
	
	# Configure sitting pose (legs forward, arms relaxed toward table)
	_apply_seated_pose()
	
	# Create coin / balance display under display name
	_setup_balance_label()
	
	# Create action indicator badge above character head
	_setup_action_badge_label()

	# Create turn ring around base of chair
	_setup_turn_ring()
	
	# Create forehead card attachment
	_setup_forehead_card()
	
	# Apply visual layer culling & card privacy architecture
	_apply_visibility_architecture()


func _apply_seated_pose() -> void:
	if character_instance == null:
		return
	
	var visual_root := character_instance.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		return
	
	# Rotate legs forward naturally to simulate sitting on stool
	var left_leg := visual_root.get_node_or_null("Legs/LeftLeg") as Node3D
	if left_leg != null:
		left_leg.rotation_degrees = Vector3(LEG_PITCH_DEGREES, 0, -4)
	
	var right_leg := visual_root.get_node_or_null("Legs/RightLeg") as Node3D
	if right_leg != null:
		right_leg.rotation_degrees = Vector3(LEG_PITCH_DEGREES, 0, 4)
	
	# Angle arms slightly forward toward table
	var left_arm := visual_root.get_node_or_null("Arms/LeftArm") as Node3D
	if left_arm != null:
		left_arm.rotation_degrees = Vector3(-25, 15, -12)
	
	var right_arm := visual_root.get_node_or_null("Arms/RightArm") as Node3D
	if right_arm != null:
		right_arm.rotation_degrees = Vector3(-25, -15, 12)


func _setup_balance_label() -> void:
	if balance_label != null and is_instance_valid(balance_label):
		balance_label.queue_free()
	
	balance_label = Label3D.new()
	balance_label.name = "CoinBalance"
	balance_label.position = Vector3(0, 1.70, 0)
	balance_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	balance_label.text = "$%s" % _format_number(coin_amount)
	balance_label.font_size = 28
	balance_label.pixel_size = 0.007
	balance_label.outline_size = 6
	balance_label.modulate = Color(1.0, 0.86, 0.28, 1.0)
	balance_label.outline_modulate = Color(0.18, 0.12, 0.06, 1.0)
	
	character_instance.add_child(balance_label)


func _setup_action_badge_label() -> void:
	if action_badge_label != null and is_instance_valid(action_badge_label):
		action_badge_label.queue_free()
	
	action_badge_label = Label3D.new()
	action_badge_label.name = "ActionBadge"
	action_badge_label.position = Vector3(0, 1.95, 0)
	action_badge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	action_badge_label.font_size = 32
	action_badge_label.pixel_size = 0.007
	action_badge_label.outline_size = 8
	action_badge_label.text = ""
	action_badge_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	action_badge_label.outline_modulate = Color(0.1, 0.1, 0.1, 1.0)
	action_badge_label.visible = not is_local_player
	
	character_instance.add_child(action_badge_label)


func _setup_turn_ring() -> void:
	if turn_indicator_ring != null and is_instance_valid(turn_indicator_ring):
		turn_indicator_ring.queue_free()
	
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.65
	ring_mesh.outer_radius = 0.78
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 12

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.85, 0.2)
	ring_mat.emission_energy_multiplier = 1.8
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	turn_indicator_ring = MeshInstance3D.new()
	turn_indicator_ring.name = "TurnIndicatorRing"
	turn_indicator_ring.mesh = ring_mesh
	turn_indicator_ring.material_override = ring_mat
	turn_indicator_ring.position = Vector3(0, 0.04, 0)
	turn_indicator_ring.visible = false
	add_child(turn_indicator_ring)


func _setup_forehead_card() -> void:
	if forehead_card_node != null and is_instance_valid(forehead_card_node):
		forehead_card_node.queue_free()
	
	var visual_root := character_instance.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		return
	
	var head_node := visual_root.get_node_or_null("Body") as Node3D
	if head_node == null:
		head_node = visual_root
	
	forehead_card_node = Node3D.new()
	forehead_card_node.name = "ForeheadCardAttachment"
	# Position at upper forehead above eyebrows, proud of bean surface & outline
	forehead_card_node.position = Vector3(0, 1.48, 0.52)
	forehead_card_node.rotation_degrees = Vector3(-8, 0, 0)
	
	# Front Card Face (facing outward +Z toward opponents)
	var card_front_mesh := QuadMesh.new()
	card_front_mesh.size = Vector2(0.32, 0.46)
	
	var card_front_mat := StandardMaterial3D.new()
	# Default initial number based on seat or 1
	var initial_val: int = (seat_index % 10) + 1
	var default_tex: Texture2D = CardNumTextures.get(initial_val, null)
	if default_tex != null:
		card_front_mat.albedo_texture = default_tex
	card_front_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	card_front_mat.cull_mode = BaseMaterial3D.CULL_BACK
	card_front_mat.roughness = 0.45
	
	var front_inst := MeshInstance3D.new()
	front_inst.name = "CardFront"
	front_inst.mesh = card_front_mesh
	front_inst.material_override = card_front_mat
	front_inst.position = Vector3(0, 0, 0.003)
	forehead_card_node.add_child(front_inst)
	
	# Back of Card (facing inward toward player head -Z)
	var card_back_mesh := QuadMesh.new()
	card_back_mesh.size = Vector2(0.32, 0.46)
	
	var card_back_mat := StandardMaterial3D.new()
	if CardBackTexture != null:
		card_back_mat.albedo_texture = CardBackTexture
	card_back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	card_back_mat.cull_mode = BaseMaterial3D.CULL_BACK
	card_back_mat.roughness = 0.45
	
	var back_inst := MeshInstance3D.new()
	back_inst.name = "CardBack"
	back_inst.mesh = card_back_mesh
	back_inst.material_override = card_back_mat
	back_inst.position = Vector3(0, 0, -0.003)
	back_inst.rotation_degrees = Vector3(0, 180, 0)
	forehead_card_node.add_child(back_inst)
	
	head_node.add_child(forehead_card_node)
	
	# CRITICAL REQUIREMENT FOR FOREHEAD POKER:
	# Local player NEVER sees their own forehead card or intrusive billboard name label
	if is_local_player:
		forehead_card_node.visible = false
		character_instance.set_display_name_visible(false)
		if balance_label != null:
			balance_label.visible = false
		if action_badge_label != null:
			action_badge_label.visible = false


var current_status: String = "ACTIVE"


func update_balance(new_amount: int) -> void:
	coin_amount = new_amount
	_refresh_balance_display()


func set_player_status(status: String) -> void:
	current_status = status.to_upper()
	_refresh_balance_display()
	_refresh_persistent_status_badge()
	_apply_character_folded_visuals(current_status == "FOLDED")


func set_turn_active(active: bool) -> void:
	if turn_indicator_ring != null and is_instance_valid(turn_indicator_ring):
		turn_indicator_ring.visible = active
	
	if active:
		if not is_local_player and current_status != "FOLDED" and current_status != "ALL_IN":
			set_temporary_action("THINKING...", Color(1.0, 0.92, 0.28, 1.0), 0.0)
	else:
		if _current_temp_action == "THINKING...":
			_refresh_persistent_status_badge()


func set_temporary_action(action_text: String, col: Color = Color.WHITE, duration: float = 2.5) -> void:
	if is_local_player or action_badge_label == null or not is_instance_valid(action_badge_label):
		return
	
	_current_temp_action = action_text
	action_badge_label.text = action_text
	action_badge_label.modulate = col
	action_badge_label.visible = true

	if duration > 0.0:
		var saved_act := action_text
		await get_tree().create_timer(duration).timeout
		if not is_instance_valid(action_badge_label):
			return
		if _current_temp_action == saved_act:
			_refresh_persistent_status_badge()


func _refresh_persistent_status_badge() -> void:
	if is_local_player or action_badge_label == null or not is_instance_valid(action_badge_label):
		return
	
	_current_temp_action = ""
	match current_status:
		"FOLDED":
			action_badge_label.text = "[FOLDED]"
			action_badge_label.modulate = Color(0.92, 0.25, 0.25, 1.0)
			action_badge_label.visible = true
		"ALL_IN", "ALL-IN":
			action_badge_label.text = "[ALL-IN]"
			action_badge_label.modulate = Color(0.85, 0.40, 1.0, 1.0)
			action_badge_label.visible = true
		_:
			action_badge_label.text = ""
			action_badge_label.visible = false


func _apply_character_folded_visuals(is_folded: bool) -> void:
	if character_instance == null or not is_instance_valid(character_instance):
		return
	var visual_root := character_instance.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		return
	
	var head := visual_root.get_node_or_null("Body") as Node3D
	if head != null:
		# Slump head slightly forward when folded
		head.rotation_degrees = Vector3(14, 0, 0) if is_folded else Vector3(0, 0, 0)


func _refresh_balance_display() -> void:
	if balance_label == null or not is_instance_valid(balance_label):
		return
	
	var text_str := "$%s" % _format_number(coin_amount)
	match current_status:
		"FOLDED":
			balance_label.text = "%s [FOLDED]" % text_str
			balance_label.modulate = Color(0.65, 0.35, 0.35, 0.75)
		"ALL_IN", "ALL-IN":
			balance_label.text = "%s [ALL-IN]" % text_str
			balance_label.modulate = Color(1.0, 0.84, 0.0, 1.0)
		_:
			balance_label.text = text_str
			balance_label.modulate = Color(1.0, 0.86, 0.28, 1.0)


## Updates the forehead card to display the server-provided number (1–10).
## Enforces that the local player NEVER sees their own forehead card.
func set_forehead_card_value(card_val: int) -> void:
	if is_local_player:
		# Double-lock guarantee: local player's forehead card is strictly hidden
		if forehead_card_node != null and is_instance_valid(forehead_card_node):
			forehead_card_node.visible = false
		return
	
	if forehead_card_node == null or not is_instance_valid(forehead_card_node):
		return
	
	var front_inst := forehead_card_node.get_node_or_null("CardFront") as MeshInstance3D
	if front_inst == null:
		return
	
	var tex: Texture2D = CardNumTextures.get(card_val, null)
	if tex != null:
		var mat := front_inst.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			mat.roughness = 0.45
			front_inst.material_override = mat
		mat.albedo_texture = tex
	
	forehead_card_node.visible = true


func _apply_visibility_architecture() -> void:
	if character_instance == null:
		return
	
	# Assign local player character and card to LAYER_LOCAL_PLAYER_HIDDEN (Layer 2),
	# and opponents to LAYER_WORLD_AND_OPPONENTS (Layer 1).
	var target_layer := LAYER_LOCAL_PLAYER_HIDDEN if is_local_player else LAYER_WORLD_AND_OPPONENTS
	_set_visual_layers_recursive(character_instance, target_layer)
	
	if is_local_player:
		# Double-lock: explicitly hide local card and overhead billboard labels
		if forehead_card_node != null and is_instance_valid(forehead_card_node):
			forehead_card_node.visible = false
		character_instance.set_display_name_visible(false)
		if balance_label != null and is_instance_valid(balance_label):
			balance_label.visible = false
		if action_badge_label != null and is_instance_valid(action_badge_label):
			action_badge_label.visible = false
		if turn_indicator_ring != null and is_instance_valid(turn_indicator_ring):
			turn_indicator_ring.visible = false
	else:
		# Opponent cards and labels remain visible to all other seated players
		if forehead_card_node != null and is_instance_valid(forehead_card_node):
			forehead_card_node.visible = true
		character_instance.set_display_name_visible(true)
		if balance_label != null and is_instance_valid(balance_label):
			balance_label.visible = true
		if action_badge_label != null and is_instance_valid(action_badge_label):
			action_badge_label.visible = true


static func _set_visual_layers_recursive(node: Node, layer_index: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = (1 << (layer_index - 1))
	for child in node.get_children():
		_set_visual_layers_recursive(child, layer_index)


## Returns the precise first-person eye position of this seated player
func get_first_person_eye_position() -> Vector3:
	var eye_height := SEAT_HEIGHT_OFFSET + 1.20
	var center_point := Vector3(0.0, global_position.y, 0.0)
	var dir_to_center := (center_point - global_position).normalized()
	dir_to_center.y = 0.0
	# Offset 0.48m forward toward the table rim at eye level
	return global_position + Vector3(0.0, eye_height, 0.0) + dir_to_center * 0.48


func get_card_attachment_point() -> Vector3:
	if forehead_card_node != null and is_instance_valid(forehead_card_node):
		return forehead_card_node.global_position
	return global_position + Vector3(0, 1.8, 0)


static func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i > 0 and s[i - 1] != "-":
			result = "," + result
	return result
