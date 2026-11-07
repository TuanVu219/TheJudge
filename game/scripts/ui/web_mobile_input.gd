class_name WebMobileInput
extends RefCounted

## Utility to support virtual keyboard and text input on iOS / mobile web browsers.
## On iOS Safari / WebKit, native LineEdit cannot summon the OS virtual keyboard
## because canvas taps are not recognized as DOM text inputs.
## Solution: Use window.prompt() to summon the native iOS keyboard reliably.

## Global override used for testing or manual forcing.
static var force_mobile_mode: Variant = null
static var mock_prompt_callback: Callable = Callable()


## Checks if the current client is a touch/mobile device or running in mobile browser.
static func is_touch_or_mobile() -> bool:
	if force_mobile_mode != null:
		return bool(force_mobile_mode)

	if OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android"):
		return true

	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js: Object = Engine.get_singleton("JavaScriptBridge")
		var check_script := """
		(function() {
			try {
				var ua = navigator.userAgent || '';
				var isMobileUA = /iPhone|iPad|iPod|Android|webOS|BlackBerry|IEMobile|Opera Mini/i.test(ua);
				var isTouch = ('ontouchstart' in window) || (navigator.maxTouchPoints > 0);
				return isMobileUA || isTouch;
			} catch(e) {
				return false;
			}
		})();
		"""
		var result: Variant = js.eval(check_script)
		return bool(result)

	return false


## Prompts the user for text input.
## On Web: opens window.prompt() which reliably triggers native iOS/Android keyboard.
## On native platforms: invokes DisplayServer.virtual_keyboard_show().
static func request_text_input(prompt_title: String, default_text: String = "") -> Variant:
	# If a mock callback is installed (for automated testing), use it
	if mock_prompt_callback.is_valid():
		return mock_prompt_callback.call(prompt_title, default_text)

	# Web implementation using JavaScriptBridge
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js: Object = Engine.get_singleton("JavaScriptBridge")
		var js_code := """
		(function() {
			try {
				var res = window.prompt(%s, %s);
				return res;
			} catch(e) {
				return null;
			}
		})();
		""" % [JSON.stringify(prompt_title), JSON.stringify(default_text)]
		var result: Variant = js.eval(js_code)
		return result

	# Native mobile virtual keyboard fallback
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show(default_text)

	return null


## Binds a LineEdit so that tapping it on iPhone / mobile web summons the native prompt.
static func bind_line_edit(line_edit: LineEdit, prompt_title: String, auto_uppercase: bool = false) -> void:
	if line_edit == null:
		return

	# Handle screen touch and mouse clicks on mobile
	line_edit.gui_input.connect(func(event: InputEvent) -> void:
		var is_pressed := false
		if event is InputEventScreenTouch:
			var touch_ev := event as InputEventScreenTouch
			is_pressed = touch_ev.pressed
		elif event is InputEventMouseButton:
			var mouse_ev := event as InputEventMouseButton
			is_pressed = mouse_ev.pressed and mouse_ev.button_index == MOUSE_BUTTON_LEFT

		if is_pressed and is_touch_or_mobile():
			line_edit.release_focus()
			trigger_prompt_for_line_edit(line_edit, prompt_title, auto_uppercase)
	)


## Triggers the mobile prompt for a specific LineEdit.
static func trigger_prompt_for_line_edit(line_edit: LineEdit, prompt_title: String, auto_uppercase: bool = false) -> void:
	if line_edit == null:
		return

	var prompt_res: Variant = request_text_input(prompt_title, line_edit.text)
	if prompt_res != null and typeof(prompt_res) == TYPE_STRING:
		var new_text := str(prompt_res).strip_edges()
		if auto_uppercase:
			new_text = new_text.to_upper().replace(" ", "")
		line_edit.text = new_text
		line_edit.text_changed.emit(new_text)
		line_edit.text_submitted.emit(new_text)
