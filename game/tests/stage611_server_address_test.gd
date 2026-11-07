extends SceneTree

## Stage 6.1.1 Test Suite — Server Address Configuration for Local and Production

const NetworkConfig = preload("res://scripts/network/network_config.gd")
const ROOM_MANAGER_SCRIPT = preload("res://scripts/network/room_manager.gd")
const NETWORK_CLIENT_SCRIPT = preload("res://scripts/network/network_client.gd")
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
	print("--- Running Stage 6.1.1 Server Address Tests ---")

	_test_environment_defaults()
	_test_production_placeholder_detection()
	_test_url_normalization()
	_test_url_validation()
	_test_room_manager_initialization()
	_test_manual_address_update()
	_test_network_client_connection_target()
	_test_main_menu_ui_server_address()

	if _failures == 0:
		print("\n=== ALL STAGE 6.1.1 TESTS PASSED ===")
		quit(0)
	else:
		push_error("\n=== %d TEST(S) FAILED IN STAGE 6.1.1 ===" % _failures)
		quit(1)


func _test_environment_defaults() -> void:
	var local_default := NetworkConfig.get_default_server_url(false)
	_check(local_default == "ws://127.0.0.1:8080", "Local environment defaults to ws://127.0.0.1:8080")

	var web_default := NetworkConfig.get_default_server_url(true)
	_check(web_default.begins_with("wss://"), "Browser environment default begins with wss://")
	_check(web_default != "ws://127.0.0.1:8080", "Browser environment does not use 127.0.0.1 default")


func _test_production_placeholder_detection() -> void:
	# Force placeholder in ProjectSettings to test unconfigured detection
	ProjectSettings.set_setting(NetworkConfig.PROJECT_SETTING_PRODUCTION_URL, "wss://YOUR-RENDER-SERVICE.onrender.com")
	_check(not NetworkConfig.is_production_configured(), "Unconfigured placeholder is detected as unconfigured")

	var validation := NetworkConfig.validate_server_url("wss://YOUR-RENDER-SERVICE.onrender.com", true)
	_check(not bool(validation.get("valid", false)), "Unconfigured placeholder URL is rejected by validator")
	_check(str(validation.get("code")) == "UNCONFIGURED_PRODUCTION", "Unconfigured placeholder returns UNCONFIGURED_PRODUCTION code")

	# Set valid URL in ProjectSettings
	ProjectSettings.set_setting(NetworkConfig.PROJECT_SETTING_PRODUCTION_URL, "wss://thejudge.onrender.com")
	_check(NetworkConfig.is_production_configured(), "Configured production URL is recognized as configured")
	var configured_default := NetworkConfig.get_default_server_url(true)
	_check(configured_default == "wss://thejudge.onrender.com", "Configured production URL is returned for web environment")

	# Reset override
	ProjectSettings.set_setting(NetworkConfig.PROJECT_SETTING_PRODUCTION_URL, "")


func _test_url_normalization() -> void:
	var norm_local := NetworkConfig.normalize_server_url("127.0.0.1", false)
	_check(norm_local == "ws://127.0.0.1:8080", "Normalizes 127.0.0.1 to ws://127.0.0.1:8080 in local mode")

	var norm_web := NetworkConfig.normalize_server_url("my-game.onrender.com", true)
	_check(norm_web == "wss://my-game.onrender.com", "Normalizes domain to wss://domain in web mode without port 8080")

	var norm_empty := NetworkConfig.normalize_server_url("", false)
	_check(norm_empty == "ws://127.0.0.1:8080", "Normalizes empty string to local default in local mode")


func _test_url_validation() -> void:
	var empty_val := NetworkConfig.validate_server_url("")
	_check(not bool(empty_val.get("valid", false)), "Empty server address is rejected")

	var invalid_scheme := NetworkConfig.validate_server_url("http://127.0.0.1:8080")
	_check(not bool(invalid_scheme.get("valid", false)), "http:// scheme is rejected (must be ws:// or wss://)")

	var insecure_web := NetworkConfig.validate_server_url("ws://some-host.com", true)
	_check(not bool(insecure_web.get("valid", false)), "Insecure ws:// is rejected in browser mode")
	_check(str(insecure_web.get("code")) == "INSECURE_BROWSER_SCHEME", "Returns INSECURE_BROWSER_SCHEME code for ws:// in browser")

	var secure_web := NetworkConfig.validate_server_url("wss://valid-service.onrender.com", true)
	_check(bool(secure_web.get("valid", false)), "Secure wss:// is accepted in browser mode")

	var valid_local := NetworkConfig.validate_server_url("ws://127.0.0.1:8080", false)
	_check(bool(valid_local.get("valid", false)), "ws://127.0.0.1:8080 is accepted in local mode")


func _test_room_manager_initialization() -> void:
	var rm: RoomManager = ROOM_MANAGER_SCRIPT.new()
	rm.use_networking = false
	root.add_child(rm)

	_check(rm.server_url == NetworkConfig.get_default_server_url(), "RoomManager initializes server_url from NetworkConfig")
	rm.queue_free()


func _test_manual_address_update() -> void:
	var rm: RoomManager = ROOM_MANAGER_SCRIPT.new()
	rm.use_networking = false
	root.add_child(rm)

	var res1: Dictionary = rm.set_server_url("ws://192.168.1.50:8080")
	_check(bool(res1.get("success", false)), "set_server_url succeeds with valid custom IP")
	_check(rm.server_url == "ws://192.168.1.50:8080", "RoomManager updates server_url to new value")

	var res2: Dictionary = rm.set_server_url("wss://YOUR-RENDER-SERVICE.onrender.com")
	_check(not bool(res2.get("success", false)), "set_server_url rejects unconfigured production placeholder")

	rm.queue_free()


func _test_network_client_connection_target() -> void:
	var nc: NetworkClient = NETWORK_CLIENT_SCRIPT.new()
	nc.auto_connect = false
	root.add_child(nc)

	_check(nc.server_url == NetworkConfig.get_default_server_url(), "NetworkClient defaults server_url to NetworkConfig default")

	var err1 := nc.connect_to_server("http://not-websocket.com")
	_check(err1 == ERR_INVALID_PARAMETER, "connect_to_server returns ERR_INVALID_PARAMETER for http:// URL")

	var err2 := nc.connect_to_server("ws://")
	_check(err2 == ERR_INVALID_PARAMETER, "connect_to_server returns ERR_INVALID_PARAMETER for empty host ws://")

	nc.queue_free()


func _test_main_menu_ui_server_address() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)

	var menu: Control = main.get_node("SceneContainer/MainMenu")
	var join_room: Control = menu.get_node("Layout/Columns/MenuCard/MenuContent/JoinRoomPage")
	var server_input: LineEdit = join_room.get_node("ServerInput")
	var server_helper: Label = join_room.get_node("ServerHelper")

	_check(server_input != null, "JoinRoomPage contains ServerInput field")
	_check(server_helper != null, "JoinRoomPage contains ServerHelper label")
	_check(server_input.text == NetworkConfig.get_default_server_url(), "JoinRoomPage ServerInput displays default server URL")
	_check(server_helper.text.contains("Multiplayer server address"), "ServerHelper explains multiplayer server address")

	main.queue_free()
