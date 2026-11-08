extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://scenes/saloon/ForeheadPokerRoom.tscn")
	var room: Node = packed.instantiate()
	root.add_child(room)
	
	# Wait for seats to spawn, HUD to initialize, and Round 1 cards + ante to settle
	await create_timer(1.2).timeout
	
	# Capture initial Round 1 betting view
	var img1: Image = root.get_viewport().get_texture().get_image()
	if img1 != null:
		img1.save_png("res://forehead_poker_p4_betting_preview.png")
		print("P4_BETTING_PREVIEW_SAVED")
	
	# Simulate local player performing a RAISE to 10
	room.call("_process_simulated_action", 0, "RAISE", 10)
	await create_timer(0.6).timeout
	
	var img2: Image = root.get_viewport().get_texture().get_image()
	if img2 != null:
		img2.save_png("res://forehead_poker_p4_action_preview.png")
		print("P4_ACTION_PREVIEW_SAVED")
	
	quit(0)

