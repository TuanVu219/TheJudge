extends SceneTree

## Test Suite for Solution A: Mobile Virtual Keyboard & Web Input Prompt

const WebMobileInput = preload("res://scripts/ui/web_mobile_input.gd")
const MAIN_SCENE = preload("res://scenes/main/Main.tscn")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run_checks")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)


func _run_checks() -> void:
	print("\n=== STARTING MOBILE VIRTUAL KEYBOARD TESTS (SOLUTION A) ===\n")

	_test_mobile_detection()
	_test_standalone_line_edit_touch_prompt()
	_test_standalone_line_edit_cancel()
	_test_desktop_mode_ignores_prompt()
	_test_main_menu_room_code_touch_integration()

	# Cleanup static state
	WebMobileInput.force_mobile_mode = null
	WebMobileInput.mock_prompt_callback = Callable()

	if _failures == 0:
		print("\n=== ALL MOBILE VIRTUAL KEYBOARD TESTS PASSED! ===")
		quit(0)
	else:
		push_error("\n=== %d TEST(S) FAILED IN MOBILE KEYBOARD TESTS ===" % _failures)
		quit(1)


func _test_mobile_detection() -> void:
	print("--- Testing Environment Detection ---")
	WebMobileInput.force_mobile_mode = true
	_check(WebMobileInput.is_touch_or_mobile() == true, "is_touch_or_mobile returns true when forced mobile")

	WebMobileInput.force_mobile_mode = false
	_check(WebMobileInput.is_touch_or_mobile() == false, "is_touch_or_mobile returns false when forced desktop")


func _test_standalone_line_edit_touch_prompt() -> void:
	print("\n--- Testing LineEdit Touch Prompt ---")
	var line_edit := LineEdit.new()
	root.add_child(line_edit)

	WebMobileInput.force_mobile_mode = true

	var captured := {
		"title": "",
		"default": "",
		"changed": "",
		"submitted": ""
	}
	WebMobileInput.mock_prompt_callback = func(title: String, default_text: String) -> Variant:
		captured["title"] = title
		captured["default"] = default_text
		return "tt y8 en"

	WebMobileInput.bind_line_edit(line_edit, "Enter room code:", true)

	line_edit.text_changed.connect(func(new_text: String) -> void: captured["changed"] = new_text)
	line_edit.text_submitted.connect(func(new_text: String) -> void: captured["submitted"] = new_text)

	# Simulate touch on the line edit
	var touch_event := InputEventScreenTouch.new()
	touch_event.pressed = true
	touch_event.position = Vector2(10, 10)
	line_edit.gui_input.emit(touch_event)

	_check(captured["title"] == "Enter room code:", "Prompt received correct title")
	_check(line_edit.text == "TTY8EN", "Input text was automatically capitalized and spaces stripped ('TTY8EN')")
	_check(captured["changed"] == "TTY8EN", "text_changed signal was emitted with updated text")
	_check(captured["submitted"] == "TTY8EN", "text_submitted signal was emitted with updated text")

	line_edit.queue_free()


func _test_standalone_line_edit_cancel() -> void:
	print("\n--- Testing User Cancellation (Cancel Button) ---")
	var line_edit := LineEdit.new()
	line_edit.text = "ORIGIN"
	root.add_child(line_edit)

	WebMobileInput.force_mobile_mode = true
	# Mock user pressing 'Cancel' in browser prompt (returns null)
	WebMobileInput.mock_prompt_callback = func(_title: String, _default_text: String) -> Variant:
		return null

	WebMobileInput.bind_line_edit(line_edit, "Enter code:", true)

	var touch_event := InputEventScreenTouch.new()
	touch_event.pressed = true
	line_edit.gui_input.emit(touch_event)

	_check(line_edit.text == "ORIGIN", "Cancelling prompt preserves existing text without overwrite")

	line_edit.queue_free()


func _test_desktop_mode_ignores_prompt() -> void:
	print("\n--- Testing Desktop Mode (No Prompt Popup) ---")
	var line_edit := LineEdit.new()
	root.add_child(line_edit)

	WebMobileInput.force_mobile_mode = false
	var prompt_called := false
	WebMobileInput.mock_prompt_callback = func(_t: String, _d: String) -> Variant:
		prompt_called = true
		return "DESKTOP"

	WebMobileInput.bind_line_edit(line_edit, "Enter code:", true)

	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	line_edit.gui_input.emit(mouse_event)

	_check(not prompt_called, "Desktop mode does not trigger prompt (allows physical keyboard typing)")
	_check(line_edit.text == "", "Desktop line edit remains un-prompted")

	line_edit.queue_free()


func _test_main_menu_room_code_touch_integration() -> void:
	print("\n--- Testing Main Menu JoinRoomPage Integration ---")
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)

	var menu: Control = main.get_node("SceneContainer/MainMenu")
	_check(menu != null, "MainMenu instantiates inside Main scene")

	# Enable mobile mode
	WebMobileInput.force_mobile_mode = true
	WebMobileInput.mock_prompt_callback = func(_title: String, _default_text: String) -> Variant:
		return "cxpf4n"

	# Navigate to Join Room Page
	menu.get_node("Layout/Columns/MenuCard/MenuContent/HomePage/PlayButton").emit_signal("pressed")
	menu.get_node("Layout/Columns/MenuCard/MenuContent/ModePage/JoinRoomButton").emit_signal("pressed")

	var join_code_input: LineEdit = menu.get_node("Layout/Columns/MenuCard/MenuContent/JoinRoomPage/RoomCodeInput")
	_check(join_code_input != null, "RoomCodeInput is present on JoinRoomPage")

	# Simulate touch on RoomCodeInput
	var touch_event := InputEventScreenTouch.new()
	touch_event.pressed = true
	join_code_input.gui_input.emit(touch_event)

	_check(join_code_input.text == "CXPF4N", "Touching RoomCodeInput on iPhone triggers prompt and fills code CXPF4N")

	# Test player name input touch prompt as well
	var player_name_input: LineEdit = menu.get_node("Layout/Columns/MenuCard/MenuContent/JoinRoomPage/PlayerNameInput")
	WebMobileInput.mock_prompt_callback = func(_title: String, _default_text: String) -> Variant:
		return "iPhonePlayer"

	player_name_input.gui_input.emit(touch_event)
	_check(player_name_input.text == "iPhonePlayer", "Touching PlayerNameInput on iPhone triggers prompt and fills player name")

	main.queue_free()
