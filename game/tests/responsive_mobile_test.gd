extends SceneTree

## Responsive Mobile Test Suite — Testing UI & Camera adaptivity for phones (Portrait & Landscape)

const MAIN_SCENE = preload("res://scenes/main/Main.tscn")
const LOBBY_SCENE = preload("res://scenes/lobby/Lobby.tscn")
const ARENA_SCENE = preload("res://scenes/arena/TerritoryArena.tscn")

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
	print("\n=== STARTING RESPONSIVE MOBILE & ARENA TESTS ===\n")

	_test_virtual_joystick_responsive()
	_test_arena_camera_responsive()
	_test_main_menu_responsive()
	_test_lobby_responsive()

	if _failures == 0:
		print("\n=== ALL RESPONSIVE MOBILE & ARENA TESTS PASSED! ===")
		quit(0)
	else:
		push_error("\n=== %d TEST(S) FAILED IN RESPONSIVE TESTS ===" % _failures)
		quit(1)


func _test_virtual_joystick_responsive() -> void:
	print("--- Testing Virtual Joystick Responsive Dimensions ---")
	var arena := ARENA_SCENE.instantiate()
	root.add_child(arena)

	var joystick: TouchJoystick = arena.get_node("HUD/Overlay/VirtualJoystick")
	_check(joystick != null, "VirtualJoystick is present in TerritoryArena")

	# Test portrait mode (phone held vertically)
	joystick.update_responsive_layout(true)
	_check(joystick.base_radius >= 90.0, "Portrait joystick base radius is enlarged (>= 90px for comfortable thumbing)")
	_check(joystick.knob_radius >= 40.0, "Portrait knob radius is enlarged (>= 40px)")
	_check(joystick.custom_minimum_size.x >= 240.0, "Portrait joystick control area is at least 240x240px")
	_check(joystick.offset_bottom <= -80.0, "Portrait joystick is lifted safely above Netlify/browser bar")

	# Test landscape mode (phone rotated horizontally)
	joystick.update_responsive_layout(false)
	_check(joystick.base_radius >= 70.0, "Landscape joystick base radius is comfortable (>= 70px)")
	_check(joystick.custom_minimum_size.x >= 190.0, "Landscape joystick size is at least 190x190px")

	arena.queue_free()


func _test_arena_camera_responsive() -> void:
	print("\n--- Testing Territory Arena Camera & Field of View ---")
	var arena := ARENA_SCENE.instantiate()
	root.add_child(arena)

	var camera: Camera3D = arena.get_node("Camera3D")
	_check(camera != null, "Camera3D is present in TerritoryArena")

	# Standalone preview mode calls _update_camera_for_viewport
	_check(arena.has_method("_update_camera_for_viewport"), "TerritoryArena provides _update_camera_for_viewport")

	# Verify camera keeps width on portrait screens so left/right walls are not cut off
	arena.call("_update_camera_for_viewport")
	var vp_size := root.get_viewport().get_visible_rect().size
	var is_portrait := vp_size.x < vp_size.y

	if is_portrait:
		_check(camera.keep_aspect == Camera3D.KEEP_WIDTH, "In portrait mode, Camera3D uses KEEP_WIDTH to prevent arena horizontal overflow")
		_check(camera.position.z > 0, "Camera position is properly distanced from center")
	else:
		_check(camera.keep_aspect == Camera3D.KEEP_HEIGHT, "In landscape mode, Camera3D uses KEEP_HEIGHT")

	arena.queue_free()


func _test_main_menu_responsive() -> void:
	print("\n--- Testing Main Menu Responsive Layout ---")
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)

	var menu: Control = main.get_node("SceneContainer/MainMenu")
	var preview_card: Control = menu.get_node("Layout/Columns/PreviewCard")
	var menu_card: Control = menu.get_node("Layout/Columns/MenuCard")

	_check(menu.has_method("_update_responsive_layout"), "MainMenu provides _update_responsive_layout")

	# Test simulated portrait mode
	menu.call("_update_responsive_layout")
	var is_portrait := root.get_viewport().get_visible_rect().size.x < root.get_viewport().get_visible_rect().size.y
	if is_portrait:
		_check(not preview_card.visible, "PreviewCard is hidden on portrait phone to give MenuCard 100% width")
		_check(menu_card.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "MenuCard takes full available width")

	main.queue_free()


func _test_lobby_responsive() -> void:
	print("\n--- Testing Lobby Responsive Layout & Big Buttons ---")
	var lobby := LOBBY_SCENE.instantiate()
	root.add_child(lobby)

	var ready_btn: Button = lobby.find_child("PrimaryRow", true, false).get_child(0) as Button
	_check(ready_btn != null, "Lobby has PrimaryRow with big Ready button")
	_check(ready_btn.custom_minimum_size.y >= 54.0, "Ready button has large touch target height (>= 54px)")

	var secondary_row := lobby.find_child("SecondaryRow", true, false)
	_check(secondary_row != null, "Lobby has SecondaryRow for secondary actions")
	_check(secondary_row.get_child_count() >= 2, "SecondaryRow contains Customize and Leave buttons")

	lobby.queue_free()

