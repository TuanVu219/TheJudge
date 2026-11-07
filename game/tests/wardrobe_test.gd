extends SceneTree

const PLAYER_SCENE := preload("res://scenes/characters/PlayerCharacter.tscn")
const ARENA_PLAYER_SCRIPT := preload("res://scripts/gameplay/arena_player.gd")
const Wardrobe = preload("res://scripts/characters/wardrobe.gd")

var _failures: int = 0
var _successes: int = 0


func _init() -> void:
	print("--- Starting Wardrobe & Modular Skin Test Suite ---")
	test_wardrobe_data()
	test_serialization_and_encoding()
	test_player_character_wardrobe()
	test_arena_player_integration()
	test_lobby_standalone_preview()
	test_room_manager_match_start()

	print("\n--- Wardrobe Test Summary ---")
	print("Passed: %d, Failed: %d" % [_successes, _failures])
	if _failures == 0:
		print("ALL WARDROBE TESTS PASSED SUCCESSFULLY! :)")
		quit(0)
	else:
		push_error("Some tests failed!")
		quit(1)


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		_successes += 1
		print("  [PASS] %s" % test_name)
	else:
		_failures += 1
		push_error("  [FAIL] %s" % test_name)


func test_wardrobe_data() -> void:
	print("\nTesting Wardrobe Definitions:")
	_assert(Wardrobe.BODY_COLORS.size() >= 5, "Has at least 5 body colors")
	_assert(Wardrobe.HATS.size() >= 5, "Has at least 5 hats")
	_assert(Wardrobe.GLASSES.size() >= 4, "Has at least 4 glasses")
	_assert(Wardrobe.HAIRSTYLES.size() >= 4, "Has at least 4 hairstyles")
	_assert(Wardrobe.OUTFITS.size() >= 4, "Has at least 4 outfits")


func test_serialization_and_encoding() -> void:
	print("\nTesting Serialization & Display Name Encoding:")
	var skin := {
		"color": "peach",
		"hat": "party_cone",
		"glasses": "sunglasses",
		"hair": "afro",
		"outfit": "overalls"
	}
	var serialized := Wardrobe.serialize(skin)
	_assert(serialized == "peach.party_cone.sunglasses.afro.overalls", "Serialized string format matches: %s" % serialized)

	var deserialized := Wardrobe.deserialize(serialized)
	_assert(deserialized["color"] == "peach", "Deserialized color is peach")
	_assert(deserialized["hat"] == "party_cone", "Deserialized hat is party_cone")
	_assert(deserialized["glasses"] == "sunglasses", "Deserialized glasses is sunglasses")
	_assert(deserialized["hair"] == "afro", "Deserialized hair is afro")
	_assert(deserialized["outfit"] == "overalls", "Deserialized outfit is overalls")

	var encoded := Wardrobe.encode_to_display_name("BinPro", skin)
	_assert(encoded.begins_with("BinPro#"), "Encoded display name starts with player name and hash: %s" % encoded)

	var decoded := Wardrobe.decode_from_display_name(encoded)
	_assert(decoded["name"] == "BinPro", "Decoded clean name is 'BinPro'")
	_assert(decoded["skin"]["hat"] == "party_cone", "Decoded skin hat matches")
	_assert(decoded["skin"]["outfit"] == "overalls", "Decoded skin outfit matches")

	# Clean name test
	_assert(Wardrobe.clean_name(encoded) == "BinPro", "clean_name strips hash properly")
	_assert(Wardrobe.clean_name("SingleName") == "SingleName", "clean_name handles plain string")


func test_player_character_wardrobe() -> void:
	print("\nTesting PlayerCharacter Wardrobe Application:")
	var character := PLAYER_SCENE.instantiate() as PlayerCharacter
	root.add_child(character)

	var skin := {
		"color": "sky",
		"hat": "crown",
		"glasses": "sunglasses",
		"hair": "sprout",
		"outfit": "overalls"
	}
	character.apply_wardrobe(skin)

	# Verify accessory visibility
	var acc_root := character.get_node("VisualRoot/Accessories")
	_assert(acc_root.get_node("Crown").visible == true, "Crown is visible")
	_assert(acc_root.get_node("TinyHat").visible == false, "TinyHat is hidden")
	_assert(acc_root.get_node("Sunglasses").visible == true, "Sunglasses is visible")
	_assert(acc_root.get_node("TinyGlasses").visible == false, "TinyGlasses is hidden")
	_assert(acc_root.get_node("Sprout").visible == true, "Sprout hair is visible")
	_assert(acc_root.get_node("Tuft").visible == false, "Tuft hair is hidden")

	# Verify overalls straps
	var straps := character.get_node("VisualRoot/Body/OverallsStraps")
	_assert(straps != null and straps.visible == true, "Overalls straps are visible")

	# Change to another outfit without overalls
	var skin2 := {
		"color": "mint",
		"hat": "none",
		"glasses": "none",
		"hair": "bald",
		"outfit": "classic"
	}
	character.apply_wardrobe(skin2)
	_assert(acc_root.get_node("Crown").visible == false, "Crown is now hidden")
	_assert(acc_root.get_node("Sunglasses").visible == false, "Sunglasses is now hidden")
	_assert(straps.visible == false, "Overalls straps are now hidden")

	character.queue_free()


func test_arena_player_integration() -> void:
	print("\nTesting ArenaPlayer Decoding:")
	var character := PLAYER_SCENE.instantiate() as PlayerCharacter
	root.add_child(character)

	var skin := {
		"color": "lemon",
		"hat": "headband",
		"glasses": "nerd",
		"hair": "tuft",
		"outfit": "sporty"
	}
	var raw_name := Wardrobe.encode_to_display_name("Gamer123", skin)

	# Decode simulation
	var decoded := Wardrobe.decode_from_display_name(raw_name)
	_assert(decoded["name"] == "Gamer123", "ArenaPlayer receives clean name Gamer123")
	character.set_display_name(decoded["name"])
	character.apply_wardrobe(decoded["skin"])

	var label := character.get_node("DisplayName") as Label3D
	_assert(label.text == "Gamer123", "Character Label3D text is clean Gamer123 without # code")

	var acc_root := character.get_node("VisualRoot/Accessories")
	_assert(acc_root.get_node("Headband").visible == true, "Headband is applied")
	_assert(acc_root.get_node("NerdGlasses").visible == true, "NerdGlasses is applied")
	_assert(acc_root.get_node("Tuft").visible == true, "Tuft hair is applied")

	character.queue_free()


func test_lobby_standalone_preview() -> void:
	print("\nTesting Lobby Standalone Preview Mode (F6):")
	var lobby_scene := load("res://scenes/lobby/Lobby.tscn") as PackedScene
	var lobby := lobby_scene.instantiate() as Control
	root.add_child(lobby)
	lobby._ready()

	var cust_btn: Button = lobby.get("_customize_button")
	_assert(cust_btn != null and cust_btn.disabled == false, "Customize Character button is ENABLED in standalone preview mode")

	# Test team switching in preview mode
	lobby.call("_join_team", 2) # Switch to Blue
	var room: Dictionary = lobby.get("_room")
	var player_team: int = int(room["players"][0]["team_id"])
	_assert(player_team == 2, "JOIN BLUE switches player to Blue team (team_id: 2)")

	lobby.call("_join_team", 1) # Switch back to Red
	room = lobby.get("_room")
	player_team = int(room["players"][0]["team_id"])
	_assert(player_team == 1, "JOIN RED switches player back to Red team (team_id: 1)")

	# Test customizer opening in preview mode
	lobby.call("_show_customizer")
	var custom_panel: Control = lobby.get("_custom_panel")
	_assert(custom_panel != null and custom_panel.visible == true, "Customizer panel opens successfully")

	# Test changing wardrobe in preview mode
	var prev_hat: String = str(lobby.get("_current_skin").get("hat", ""))
	lobby.call("_cycle_hat", 1)
	var next_skin: Dictionary = lobby.get("_current_skin")
	_assert(next_skin["hat"] != prev_hat, "Hat changed from %s to %s" % [prev_hat, next_skin["hat"]])

	lobby.queue_free()


func test_room_manager_match_start() -> void:
	print("\nTesting RoomManager Match Start & Team Switch Aliases:")
	var rm_script := load("res://scripts/network/room_manager.gd") as GDScript
	var rm := rm_script.new() as Node
	rm.set("use_networking", false)
	root.add_child(rm)

	# Verify methods exist
	_assert(rm.has_method("start_match"), "RoomManager has start_match")
	_assert(rm.has_method("start_room_match"), "RoomManager has start_room_match alias")
	_assert(rm.has_method("update_player_team"), "RoomManager has update_player_team")
	_assert(rm.has_method("switch_player_team"), "RoomManager has switch_player_team alias")

	# Create room and test
	var create_res: Dictionary = rm.call("create_room", "1v1", "TestHost")
	_assert(create_res.get("success") == true, "Room created successfully")
	var code: String = str(rm.get("active_room_code"))
	var host_id: String = str(rm.get("active_player_id"))

	# Join a second player to satisfy 1v1 requirements
	var join_res: Dictionary = rm.call("join_room", code, "guest_player", "Guest")
	_assert(join_res.get("success") == true, "Guest joined room")

	# Ready both players
	rm.call("toggle_player_ready", code, host_id)
	rm.call("toggle_player_ready", code, "guest_player")

	# Switch player team alias
	var switch_res: Dictionary = rm.call("switch_player_team", code, "guest_player", 2)
	_assert(switch_res.get("success") == true, "switch_player_team alias succeeded")

	# Test calling start_room_match alias
	var match_res: Dictionary = rm.call("start_room_match", code, host_id)
	_assert(match_res.get("success") == true, "start_room_match alias starts match successfully without crashing")

	rm.queue_free()
