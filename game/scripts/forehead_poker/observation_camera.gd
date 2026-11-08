extends Camera3D

## First-Person Seated Camera for Forehead Poker (Stage P2.1 & P4.1).
## Represents the local player's seated eyes at their assigned chair.
##
## Controls:
## - Mouse movement: Look around the saloon (Yaw left/right, Pitch up/down).
## - Left Click on 3D World: Capture mouse cursor for free-look.
## - Moving towards or hovering HUD: Automatically releases cursor for immediate clicking.
## - Right Click Drag (when visible): Smooth camera look without capturing cursor.
## - Escape: Optional manual release fallback.
##
## Robust Local Card Privacy Architecture:
## - Dedicated Visual Layer 2: Local player character and forehead card are assigned to Layer 2.
## - Camera cull_mask ignores Layer 2, guaranteeing local card and head are NEVER rendered to the player.
## - Opponents and their forehead cards are on Layer 1 and remain 100% visible.
## - Camera remains strictly seated at eye level. Zero physical movement (no WASD, no jumping, no walking).

# Visual Layer definitions
const LAYER_WORLD_AND_OPPONENTS: int = 1
const LAYER_LOCAL_PLAYER_HIDDEN: int = 2

signal camera_rotated(yaw_deg: float, pitch_deg: float)

@export var mouse_sensitivity: float = 0.0022
@export var smooth_speed: float = 16.0

# Pitch limits in degrees to prevent flipping upside down
@export var min_pitch_deg: float = -75.0  # Looking down toward table
@export var max_pitch_deg: float = 75.0   # Looking up toward ceiling

var _eye_position: Vector3 = Vector3(0.0, 1.66, 2.87)
var _target_yaw: float = 0.0
var _target_pitch: float = -12.0

var _current_yaw: float = 0.0
var _current_pitch: float = -12.0

var _is_mouse_captured: bool = false
var _is_pointer_over_hud: bool = false


func _ready() -> void:
	# Guarantee camera culls Visual Layer 2 (Local Player Head & Forehead Card)
	cull_mask = cull_mask & ~(1 << (LAYER_LOCAL_PLAYER_HIDDEN - 1))
	
	_current_yaw = _target_yaw
	_current_pitch = _target_pitch
	_apply_rotation()
	
	# Start in visible cursor mode so HUD buttons are immediately clickable
	set_mouse_captured(false)


## Initializes first-person position at seated eye height, facing table center
func setup_first_person_view(eye_pos: Vector3, look_target: Vector3) -> void:
	_eye_position = eye_pos
	global_position = _eye_position
	
	var diff := look_target - eye_pos
	var horiz_dist := Vector2(diff.x, diff.z).length()
	
	# Pitch: angle looking down toward table center
	_target_pitch = rad_to_deg(atan2(diff.y, horiz_dist))
	# Yaw: angle facing toward table center
	_target_yaw = rad_to_deg(atan2(-diff.x, -diff.z))
	
	_current_pitch = _target_pitch
	_current_yaw = _target_yaw
	_apply_rotation()


func set_pointer_over_hud(over_hud: bool) -> void:
	_is_pointer_over_hud = over_hud
	if over_hud and _is_mouse_captured:
		set_mouse_captured(false)


func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape as optional fallback
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_mouse_captured(false)
		return
	
	# Clicking 3D background captures mouse for free-look
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _is_pointer_over_hud and not _is_mouse_captured:
			set_mouse_captured(true)
			get_viewport().set_input_as_handled()
			return
	
	# Mouse Look (First-Person Yaw & Pitch)
	if event is InputEventMouseMotion and not _is_pointer_over_hud:
		var motion := event as InputEventMouseMotion
		# Either captured or right-click dragging while cursor is visible
		if _is_mouse_captured or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_target_yaw -= motion.relative.x * mouse_sensitivity * (180.0 / PI)
			_target_pitch -= motion.relative.y * mouse_sensitivity * (180.0 / PI)
			_target_pitch = clampf(_target_pitch, min_pitch_deg, max_pitch_deg)


func _process(delta: float) -> void:
	# Lock position firmly to the seated eye position (NO physical movement)
	global_position = _eye_position
	
	# Smooth interpolation
	var yaw_diff := wrapf(_target_yaw - _current_yaw, -180.0, 180.0)
	var prev_yaw := _current_yaw
	var prev_pitch := _current_pitch
	_current_yaw += yaw_diff * clampf(delta * smooth_speed, 0.0, 1.0)
	_current_pitch = lerpf(_current_pitch, _target_pitch, clampf(delta * smooth_speed, 0.0, 1.0))
	
	_apply_rotation()
	
	if absf(_current_yaw - prev_yaw) > 0.02 or absf(_current_pitch - prev_pitch) > 0.02:
		camera_rotated.emit(_current_yaw, _current_pitch)


func _apply_rotation() -> void:
	var yaw_rad := deg_to_rad(_current_yaw)
	var pitch_rad := deg_to_rad(_current_pitch)
	rotation = Vector3(pitch_rad, yaw_rad, 0.0)


func set_mouse_captured(captured: bool) -> void:
	_is_mouse_captured = captured
	if captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Compatibility helper for room setup
func set_initial_seat_view(seat_pos: Vector3) -> void:
	var eye_height: float = 1.66
	var center_point := Vector3(0.0, 1.05, 0.0)
	var dir_to_center := (Vector3(0, 0, 0) - seat_pos)
	dir_to_center.y = 0.0
	dir_to_center = dir_to_center.normalized()
	
	var eye_pos := seat_pos + Vector3(0, eye_height, 0) + dir_to_center * 0.48
	setup_first_person_view(eye_pos, center_point)
