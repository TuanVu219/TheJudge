extends Node

## Offline movement controller for a reused PlayerCharacter scene instance.

const TEAM_RED := 1
const TEAM_BLUE := 2

@export_enum("Red", "Blue") var team_id := TEAM_RED
@export var human_controlled := true
@export var is_bot := false
@export var display_name := ""
@export var character_id := "mint"
@export var player_id := ""
@export var room_code := ""
@export_range(1.0, 12.0, 0.1) var move_speed := 5.2
@export var grid_path: NodePath = NodePath("../../../TileGrid")
@export var match_path: NodePath = NodePath("../../..")

var network_client: Node = null
var virtual_joystick: Node = null
var _character: CharacterBody3D
var _grid: Node
var _match_controller: Node
var _bot_waypoint_index := 0
var _bot_waypoints: Array[Vector3] = [
	Vector3(-3.15, 0.04, 3.15),
	Vector3(-3.15, 0.04, -3.15),
	Vector3(3.15, 0.04, -3.15),
	Vector3(3.15, 0.04, 3.15),
]
var _target_position := Vector3.ZERO
var _target_velocity := Vector3.ZERO
var _target_rotation := 0.0
var _has_target_position := false
var _send_timer := 0.0
var _last_sent_col := -1
var _last_sent_row := -1


func _ready() -> void:
	_character = get_parent() as CharacterBody3D
	_grid = get_node_or_null(grid_path)
	_match_controller = get_node_or_null(match_path)

	if _character == null:
		push_error("ArenaPlayer controller must be a child of a CharacterBody3D.")
		set_physics_process(false)
		return

	_target_position = _character.global_position
	if _match_controller != null:
		if _match_controller.get("network_client") != null:
			network_client = _match_controller.get("network_client")
		if room_code.is_empty():
			room_code = str(_match_controller.get("room_code"))

	# Child nodes enter _ready before their parent character. Wait until the
	# reused PlayerCharacter has initialized its @onready API references.
	await _character.ready

	var shirt_color: Color
	var default_display_name: String
	if team_id == TEAM_RED:
		shirt_color = Color(0.63, 0.08, 0.20)
		default_display_name = "Red Player" if not is_bot else "RED Bot"
	else:
		shirt_color = Color(0.08, 0.24, 0.65)
		default_display_name = "Blue Player" if not is_bot else "BLUE Bot"

	var final_name := display_name if not display_name.is_empty() else default_display_name
	_character.call("set_display_name", final_name)
	_apply_character_preset()
	var shirt := _character.get_node_or_null("VisualRoot/Body/Shirt") as MeshInstance3D
	if shirt != null:
		var shirt_material := shirt.material_override as ShaderMaterial
		if shirt_material != null:
			shirt_material.set_shader_parameter("albedo_color", shirt_color)

	if _grid == null:
		push_error("ArenaPlayer could not find the TerritoryGrid at %s." % grid_path)
	if _match_controller == null:
		push_error("ArenaPlayer could not find the MatchController at %s." % match_path)



func _apply_character_preset() -> void:
	var preset_color := Color(0.43, 0.88, 0.66)
	var accessory_name := "Feather"
	match character_id:
		"peach":
			preset_color = Color(1.0, 0.58, 0.37)
			accessory_name = "TinyHat"
		"sky":
			preset_color = Color(0.38, 0.72, 1.0)
			accessory_name = "TinyGlasses"
	_character.call("set_body_color", preset_color)
	for candidate in ["Feather", "TinyHat", "TinyGlasses"]:
		_character.call("set_accessory_visible", candidate, candidate == accessory_name)


func _physics_process(delta: float) -> void:
	if _character == null:
		return

	if _match_controller != null and not bool(_match_controller.get("round_active")):
		_character.velocity.x = 0.0
		_character.velocity.z = 0.0
		_apply_gravity(delta)
		_character.move_and_slide()
		return

	if human_controlled:
		var movement := _get_human_direction()
		if movement.length_squared() > 1.0:
			movement = movement.normalized()

		_character.velocity.x = movement.x * move_speed
		_character.velocity.z = movement.z * move_speed
		if movement.length_squared() > 0.01:
			var target_rot := atan2(movement.x, movement.z)
			_character.rotation.y = lerp_angle(_character.rotation.y, target_rot, delta * 14.0)

		_apply_gravity(delta)
		_character.move_and_slide()

		if network_client != null and not room_code.is_empty():
			_send_timer += delta
			if _send_timer >= 0.05:
				_send_timer = 0.0
				network_client.send_player_move(room_code, _character.global_position, _character.velocity, _character.rotation.y)

			if _grid != null and movement.length_squared() > 0.01:
				var coords: Vector2i = _grid.call("get_tile_coordinates", _character.global_position)
				if coords.x >= 0 and coords.y >= 0:
					if coords.x != _last_sent_col or coords.y != _last_sent_row:
						_last_sent_col = coords.x
						_last_sent_row = coords.y
						network_client.send_claim_tile(room_code, coords.x, coords.y)
		elif _grid != null and movement.length_squared() > 0.01:
			_grid.call("claim_at_global_position", _character.global_position, team_id)

	elif is_bot:
		var movement := _get_bot_direction()
		if movement.length_squared() > 1.0:
			movement = movement.normalized()
		_character.velocity.x = movement.x * move_speed
		_character.velocity.z = movement.z * move_speed
		_apply_gravity(delta)
		_character.move_and_slide()
		if _grid != null and movement.length_squared() > 0.01:
			_grid.call("claim_at_global_position", _character.global_position, team_id)

	else:
		if _has_target_position:
			_character.global_position = _character.global_position.lerp(_target_position, clampf(delta * 18.0, 0.0, 1.0))
			_character.rotation.y = lerp_angle(_character.rotation.y, _target_rotation, clampf(delta * 18.0, 0.0, 1.0))
			_character.velocity = _target_velocity
			_apply_gravity(delta)
			_character.move_and_slide()


func set_remote_transform(target_pos: Vector3, target_vel: Vector3, target_rot: float) -> void:
	_target_position = target_pos
	_target_velocity = target_vel
	_target_rotation = target_rot
	_has_target_position = true


func reset_controller(spawn_position: Vector3) -> void:
	if _character == null:
		return

	_character.global_position = spawn_position
	_character.velocity = Vector3.ZERO
	_bot_waypoint_index = 0


func _get_joystick_vector() -> Vector2:
	if virtual_joystick != null and virtual_joystick.has_method("get_output_vector"):
		return virtual_joystick.call("get_output_vector")
	if _match_controller != null and _match_controller.has_method("get_joystick_vector"):
		return _match_controller.call("get_joystick_vector")
	return Vector2.ZERO


func _get_human_direction() -> Vector3:
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.z += 1.0

	var joy := _get_joystick_vector()
	if joy.length_squared() > 0.001:
		direction.x += joy.x
		direction.z += joy.y

	return direction


func _get_bot_direction() -> Vector3:
	var target := _bot_waypoints[_bot_waypoint_index]
	var offset := target - _character.global_position
	offset.y = 0.0
	if offset.length() < 0.3:
		_bot_waypoint_index = (_bot_waypoint_index + 1) % _bot_waypoints.size()
		target = _bot_waypoints[_bot_waypoint_index]
		offset = target - _character.global_position
		offset.y = 0.0
	return offset.normalized()


func _apply_gravity(delta: float) -> void:
	if _character.is_on_floor():
		_character.velocity.y = 0.0
	else:
		_character.velocity.y -= 18.0 * delta
