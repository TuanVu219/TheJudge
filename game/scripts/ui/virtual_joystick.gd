extends Control
class_name TouchJoystick

## On-screen circular touch joystick for mobile devices and mouse controls.

signal visibility_changed_mode(visible: bool)

@export var base_radius: float = 85.0
@export var knob_radius: float = 40.0
@export var clamp_radius: float = 75.0
@export var deadzone: float = 10.0

@export var base_color: Color = Color(0.10, 0.18, 0.28, 0.55)
@export var base_border_color: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var knob_color: Color = Color(0.96, 0.72, 0.28, 0.90)
@export var knob_border_color: Color = Color(1.0, 1.0, 1.0, 0.95)

var output_vector: Vector2 = Vector2.ZERO
var is_active: bool = false

var _tip_offset: Vector2 = Vector2.ZERO
var _touch_id: int = -1
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_center()
	resized.connect(_update_center)
	var vp_size := get_viewport().get_visible_rect().size
	update_responsive_layout(vp_size.x < vp_size.y)


func update_responsive_layout(is_portrait: bool) -> void:
	if is_portrait:
		base_radius = 95.0
		knob_radius = 45.0
		clamp_radius = 82.0
		deadzone = 12.0
		custom_minimum_size = Vector2(250, 250)
		offset_left = 36.0
		offset_bottom = -90.0
		offset_right = 286.0
		offset_top = -340.0
	else:
		base_radius = 70.0
		knob_radius = 34.0
		clamp_radius = 62.0
		deadzone = 10.0
		custom_minimum_size = Vector2(190, 190)
		offset_left = 32.0
		offset_bottom = -30.0
		offset_right = 222.0
		offset_top = -220.0
	_update_center()


func _update_center() -> void:
	_center = size * 0.5
	queue_redraw()


func get_output_vector() -> Vector2:
	return output_vector


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_handle_touch(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch_id:
			_release_touch()
			accept_event()

	elif event is InputEventScreenDrag:
		if event.index == _touch_id:
			_handle_touch(event.position)
			accept_event()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _touch_id == -1:
				_touch_id = 999
				_handle_touch(event.position)
				accept_event()
			elif not event.pressed and _touch_id == 999:
				_release_touch()
				accept_event()

	elif event is InputEventMouseMotion:
		if _touch_id == 999:
			_handle_touch(event.position)
			accept_event()


func _input(event: InputEvent) -> void:
	if _touch_id == -1:
		return

	if event is InputEventScreenDrag and event.index == _touch_id:
		var local_pos: Vector2 = event.position - global_position
		_handle_touch(local_pos)
	elif event is InputEventScreenTouch and not event.pressed and event.index == _touch_id:
		_release_touch()
	elif event is InputEventMouseMotion and _touch_id == 999:
		var local_pos: Vector2 = event.position - global_position
		_handle_touch(local_pos)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _touch_id == 999:
		_release_touch()


func _handle_touch(touch_pos: Vector2) -> void:
	var diff := touch_pos - _center
	var dist := diff.length()

	if dist > clamp_radius:
		diff = diff.normalized() * clamp_radius

	_tip_offset = diff

	if dist > deadzone:
		output_vector = diff / clamp_radius
		if output_vector.length() > 1.0:
			output_vector = output_vector.normalized()
	else:
		output_vector = Vector2.ZERO

	is_active = true
	queue_redraw()


func _release_touch() -> void:
	_touch_id = -1
	is_active = false
	output_vector = Vector2.ZERO

	var tween := create_tween()
	tween.tween_property(self, "_tip_offset", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_redraw)
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_active and _tip_offset != Vector2.ZERO:
		queue_redraw()


func _draw() -> void:
	var center := _center

	# Base outer circle
	draw_circle(center, base_radius, base_color)
	draw_arc(center, base_radius, 0.0, TAU, 48, base_border_color if not is_active else Color(0.96, 0.72, 0.28, 0.7), 3.0, true)

	# 4 subtle direction tick indicators (N, S, W, E)
	var tick_dist := base_radius - 8.0
	draw_line(center + Vector2(0, -tick_dist + 5), center + Vector2(0, -tick_dist), Color(1, 1, 1, 0.35), 2.0)
	draw_line(center + Vector2(0, tick_dist - 5), center + Vector2(0, tick_dist), Color(1, 1, 1, 0.35), 2.0)
	draw_line(center + Vector2(-tick_dist + 5, 0), center + Vector2(-tick_dist, 0), Color(1, 1, 1, 0.35), 2.0)
	draw_line(center + Vector2(tick_dist - 5, 0), center + Vector2(tick_dist, 0), Color(1, 1, 1, 0.35), 2.0)

	# Inner thumb knob
	var knob_pos := center + _tip_offset
	draw_circle(knob_pos, knob_radius, knob_color)
	draw_arc(knob_pos, knob_radius, 0.0, TAU, 36, knob_border_color, 2.5, true)
	draw_circle(knob_pos, 5.0, Color(0.12, 0.25, 0.36, 0.6))
