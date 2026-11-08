extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://scenes/saloon/ForeheadPokerRoom.tscn")
	var room: Node = packed.instantiate()
	root.add_child(room)
	
	# Wait for seats, HUD, and Round 1 cards to settle
	await create_timer(1.2).timeout
	
	# Screenshot 1: Initial state (Minty turn active, Turn ring visible, Action History panel on left)
	var img1: Image = root.get_viewport().get_texture().get_image()
	if img1 != null:
		img1.save_png("res://forehead_poker_p4_1_initial.png")
		print("P4_1_INITIAL_SAVED")
	
	# Local player (Minty) raises to 8 chips
	room.call("_on_hud_betting_action_requested", "RAISE", 8)
	
	# Wait 2.2 seconds for NPCs to sequentially think and respond (Peaches, Bubbles, Lemmy, etc.)
	await create_timer(2.2).timeout
	
	# Screenshot 2: Sequential NPC actions in progress (different actions, per-seat badges, action history)
	var img2: Image = root.get_viewport().get_texture().get_image()
	if img2 != null:
		img2.save_png("res://forehead_poker_p4_1_npc_turns.png")
		print("P4_1_NPC_TURNS_SAVED")

	# Wait for betting to fully complete
	await create_timer(3.0).timeout

	# Screenshot 3: Final settled state showing individual actions, side/main pot, and folded/all-in states
	var img3: Image = root.get_viewport().get_texture().get_image()
	if img3 != null:
		img3.save_png("res://forehead_poker_p4_1_settled.png")
		print("P4_1_SETTLED_SAVED")
	
	quit(0)

