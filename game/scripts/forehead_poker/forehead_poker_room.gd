extends Node3D

## Main controller for Forehead Poker Room (Stage P3, P4 & P4.1).
## Features:
## - 6 fixed seats arranged evenly around circular saloon table.
## - First-person seated camera at local player's eye level with card privacy culling.
## - Integration with Two Independent Decks per Player architecture (P3).
## - Complete Authoritative Betting System (P4):
##   * Fold, Check, Call, Raise (slider/stepper), All-In.
##   * Live Pot display (main & side pots) and turn indicator.
##   * 3D Seat chip balance updates & status badges ([FOLDED], [ALL-IN]).
## - Stage P4.1 Enhancements:
##   * Sequential asynchronous NPC turn pacing (0.6s–1.0s thinking delay).
##   * Diverse, independent NPC decision personalities (Peaches, Bubbles, Lemmy, Berry, Vindy).
##   * Per-seat 3D visual action banners and active turn highlight rings.
##   * Seamless mouse interaction: automatic cursor visibility over HUD without pressing ESC.
##   * Compact live chronological action history feed on HUD.
##   * NetworkClient integration with comprehensive offline simulation fallback.

const PokerSeatClass = preload("res://scripts/forehead_poker/poker_seat.gd")
const ObservationCameraClass = preload("res://scripts/forehead_poker/observation_camera.gd")
const PokerHUDClass = preload("res://scripts/forehead_poker/poker_hud.gd")
const Wardrobe = preload("res://scripts/characters/wardrobe.gd")

# 6 Fixed Seat Angles around the circular table (in degrees, 0 = South / Local Player)
const SEAT_ANGLES_DEG: Array[float] = [
	0.0,    # Seat 0: South (Local Player - Minty)
	60.0,   # Seat 1: South-East (Peaches)
	120.0,  # Seat 2: North-East (Bubbles)
	180.0,  # Seat 3: North (Opposite - Lemmy)
	240.0,  # Seat 4: North-West (Berry)
	300.0   # Seat 5: South-West (Vindy)
]

const TABLE_RADIUS: float = 3.35

# 6 Distinct Character Presets from THE JUDGE Wardrobe system with poker personalities
const PRESETS: Array[Dictionary] = [
	{
		"id": "player_1_minty",
		"name": "Minty (You)",
		"coins": 100,
		"skin": { "color": "mint", "hat": "headband", "glasses": "sunglasses", "hair": "tuft", "outfit": "sporty" },
		"ai_type": "HUMAN"
	},
	{
		"id": "player_2_peaches",
		"name": "Peaches",
		"coins": 100,
		"skin": { "color": "peach", "hat": "chef_hat", "glasses": "round", "hair": "bald", "outfit": "classic" },
		"ai_type": "CONSERVATIVE", # High check/call, folds to heavy bets, rarely raises
		"call_rate": 0.65,
		"fold_rate": 0.28,
		"raise_rate": 0.07,
		"open_rate": 0.08
	},
	{
		"id": "player_3_bubbles",
		"name": "Bubbles",
		"coins": 100,
		"skin": { "color": "sky", "hat": "party_cone", "glasses": "none", "hair": "spiky", "outfit": "overalls" },
		"ai_type": "LOOSE", # Loves to call, rarely folds, occasional small raises
		"call_rate": 0.78,
		"fold_rate": 0.10,
		"raise_rate": 0.12,
		"open_rate": 0.18
	},
	{
		"id": "player_4_lemmy",
		"name": "Lemmy",
		"coins": 100,
		"skin": { "color": "lemon", "hat": "crown", "glasses": "monocle", "hair": "bald", "outfit": "golden" },
		"ai_type": "AGGRESSIVE", # Frequent opener, highest re-raise frequency
		"call_rate": 0.50,
		"fold_rate": 0.18,
		"raise_rate": 0.32,
		"open_rate": 0.35
	},
	{
		"id": "player_5_berry",
		"name": "Berry",
		"coins": 100,
		"skin": { "color": "berry", "hat": "feather", "glasses": "nerd", "hair": "afro", "outfit": "pastel" },
		"ai_type": "BALANCED", # Analytical, folds to big bets, calls medium bets
		"call_rate": 0.68,
		"fold_rate": 0.22,
		"raise_rate": 0.10,
		"open_rate": 0.15
	},
	{
		"id": "player_6_vindy",
		"name": "Vindy",
		"coins": 100,
		"skin": { "color": "lavender", "hat": "tiny_hat", "glasses": "sunglasses", "hair": "sprout", "outfit": "dark" },
		"ai_type": "WILDCARD", # Unpredictable, check-raise attempts or sudden folds
		"call_rate": 0.55,
		"fold_rate": 0.25,
		"raise_rate": 0.20,
		"open_rate": 0.25
	}
]

var seat_nodes: Array[Node3D] = []
var local_seat_index: int = 0
var hud_instance: CanvasLayer = null
var network_client: Node = null
var active_room_code: String = ""

# Online Multiplayer State (Stage P5)
var is_online_match: bool = false
var local_player_id: String = ""
var last_state_version: int = 0
var player_id_to_seat: Dictionary = {}
var seat_to_player_id: Dictionary = {}
var seat_to_player_name: Dictionary = {}

# Offline / Local Simulation State
var _sim_round: int = 0
var _sim_hand_decks: Dictionary = {}      # seat_index -> Array[int]
var _sim_forehead_decks: Dictionary = {}  # seat_index -> Array[int]
var _sim_hand_history: Dictionary = {}    # seat_index -> Array[int]
var _sim_forehead_history: Dictionary = {}# seat_index -> Array[int]

# Betting Simulation State
var _sim_balances: Dictionary = {}            # seat_index -> int
var _sim_round_bets: Dictionary = {}          # seat_index -> int
var _sim_total_contributions: Dictionary = {} # seat_index -> int
var _sim_folded: Dictionary = {}              # seat_index -> bool
var _sim_all_in: Dictionary = {}              # seat_index -> bool
var _sim_has_acted: Dictionary = {}           # seat_index -> bool
var _sim_current_highest_bet: int = 0
var _sim_min_raise_inc: int = 2
var _sim_current_turn_seat: int = 0
var _sim_betting_active: bool = false
var _sim_total_pot: int = 0
var _sim_main_pot: int = 0
var _sim_side_pots: Array = []
var _sim_last_action_player: String = ""
var _sim_last_action_type: String = ""
var _sim_last_action_amount: int = 0

# Asynchronous Sequential Turn Pacing
var _turn_sequence_token: int = 0

@onready var camera: Camera3D = $Camera3D as Camera3D


func _ready() -> void:
	_setup_seats()
	_setup_poker_hud()
	_init_network_or_simulation()


func _setup_seats() -> void:
	var seats_container := get_node_or_null("SeatsContainer") as Node3D
	if seats_container == null:
		seats_container = Node3D.new()
		seats_container.name = "SeatsContainer"
		add_child(seats_container)
	
	seat_nodes.clear()
	
	for i in range(6):
		var angle_rad: float = deg_to_rad(SEAT_ANGLES_DEG[i])
		var pos_x: float = TABLE_RADIUS * sin(angle_rad)
		var pos_z: float = TABLE_RADIUS * cos(angle_rad)
		var seat_pos := Vector3(pos_x, 0.0, pos_z)
		
		var seat: Node3D = PokerSeatClass.new()
		seat.name = "PokerSeat_%d" % i
		seat.position = seat_pos
		seat.set("seat_index", i)
		seats_container.add_child(seat)
		seat_nodes.append(seat)


func _setup_offline_characters() -> void:
	local_seat_index = 0
	for i in range(6):
		var preset: Dictionary = PRESETS[i]
		var is_local: bool = (i == local_seat_index)
		seat_nodes[i].call(
			"setup_character",
			preset["name"],
			preset["coins"],
			preset["skin"],
			is_local
		)


func _setup_online_roster() -> void:
	var rm := _get_room_manager()
	var roster: Array = []
	if rm != null and rm.has_method("get_active_room_record"):
		var rec: Dictionary = rm.call("get_active_room_record")
		roster = rec.get("started_match_roster", [])
		if roster.is_empty():
			roster = rec.get("players", [])
	if roster.is_empty() and network_client != null and network_client.get("started_match_roster") != null:
		roster = network_client.get("started_match_roster")

	for seat in seat_nodes:
		seat.call("clear_character")

	player_id_to_seat.clear()
	seat_to_player_id.clear()
	seat_to_player_name.clear()

	# Guarantee valid seat assignment for all players in roster (even if server omitted seat_index)
	var occupied_seats: Dictionary = {}
	# Pass 1: preserve valid pre-assigned seats
	for p in roster:
		var s := int(p.get("seat_index", -1))
		if s >= 0 and s < seat_nodes.size() and not occupied_seats.has(s):
			occupied_seats[s] = str(p.get("player_id", ""))

	# Pass 2: assign any player without a valid seat index
	for i in range(roster.size()):
		var p: Dictionary = roster[i]
		var s := int(p.get("seat_index", -1))
		if s < 0 or s >= seat_nodes.size() or (occupied_seats.has(s) and occupied_seats[s] != str(p.get("player_id", ""))):
			# For 2-player heads-up, place 2nd player at Seat 3 (North, directly opposite) if free
			var preferred_seat := 3 if (roster.size() == 2 and i == 1 and not occupied_seats.has(3)) else -1
			if preferred_seat >= 0:
				s = preferred_seat
			else:
				for candidate in range(seat_nodes.size()):
					if not occupied_seats.has(candidate):
						s = candidate
						break
			p["seat_index"] = s
			occupied_seats[s] = str(p.get("player_id", ""))

	# Find local player's assigned seat index
	local_seat_index = 0
	for p in roster:
		var pid := str(p.get("player_id", ""))
		if pid == local_player_id and p.has("seat_index"):
			local_seat_index = int(p.get("seat_index", 0))
			break

	# Reposition first-person camera to local seat eye position
	_setup_first_person_camera()

	# Spawn each player at their assigned seat
	for p in roster:
		var pid := str(p.get("player_id", ""))
		var s_idx := int(p.get("seat_index", -1))
		if s_idx < 0 or s_idx >= seat_nodes.size():
			continue
		var raw_name := str(p.get("display_name", pid))
		var clean_name := Wardrobe.clean_name(raw_name)
		var decoded := Wardrobe.decode_from_display_name(raw_name)
		var skin: Dictionary = decoded.get("skin", {})
		if skin.is_empty():
			var char_id := str(p.get("character_id", "mint"))
			skin = {"color": char_id, "hat": "none", "glasses": "none", "hair": "none", "outfit": "none"}
		var is_local := (s_idx == local_seat_index)

		seat_nodes[s_idx].call("setup_character", clean_name, 100, skin, is_local)
		player_id_to_seat[pid] = s_idx
		seat_to_player_id[s_idx] = pid
		seat_to_player_name[s_idx] = clean_name
		print("[ForeheadPokerRoom] Spawned player: %s at seat %d (is_local=%s)" % [clean_name, s_idx, is_local])


func _setup_first_person_camera() -> void:
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return
	
	if seat_nodes.size() > local_seat_index:
		var local_seat: Node3D = seat_nodes[local_seat_index]
		var eye_pos: Vector3 = local_seat.call("get_first_person_eye_position")
		var look_target := Vector3(0.0, 1.05, 0.0)
		if camera.has_method("setup_first_person_view"):
			camera.call("setup_first_person_view", eye_pos, look_target)
		elif camera.has_method("set_initial_seat_view"):
			camera.call("set_initial_seat_view", local_seat.position)


func _setup_poker_hud() -> void:
	hud_instance = PokerHUDClass.new()
	hud_instance.name = "PokerHUD"
	add_child(hud_instance)

	hud_instance.request_draw_round.connect(_on_hud_request_draw_round)
	hud_instance.request_reset_match.connect(_on_hud_request_reset_match)
	hud_instance.betting_action_requested.connect(_on_hud_betting_action_requested)

	# Seamless Mouse Hover Interaction: automatically release mouse when pointer enters HUD
	hud_instance.hud_hover_changed.connect(func(is_hovered: bool):
		if camera != null and camera.has_method("set_pointer_over_hud"):
			camera.call("set_pointer_over_hud", is_hovered)
	)


func _get_room_manager() -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	var root_node := get_tree().root
	var main_node := root_node.get_node_or_null("Main")
	if main_node != null:
		var persistent_manager := main_node.get_node_or_null("RoomManager")
		if persistent_manager != null:
			return persistent_manager
	if root_node.has_node("RoomManager"):
		return root_node.get_node("RoomManager")
	return root_node.get_node_or_null("OfflineRoomManager")


func _init_network_or_simulation() -> void:
	var rm: Node = _get_room_manager()
	if rm != null and rm.has_method("is_online") and rm.call("is_online"):
		network_client = rm.get("network_client")
		active_room_code = str(rm.get("active_room_code"))
		local_player_id = str(rm.get("active_player_id"))
	else:
		network_client = get_node_or_null("/root/NetworkClient")
		if network_client != null and bool(network_client.get("is_connected_to_server")):
			local_player_id = str(network_client.get("client_player_id"))

	if network_client != null and bool(network_client.get("is_connected_to_server")) and not active_room_code.is_empty():
		is_online_match = true
		_bind_network_signals()
		_setup_online_roster()
		_replay_cached_network_state()
	else:
		is_online_match = false
		_setup_offline_characters()
		_setup_first_person_camera()
		_init_offline_simulation()
		_draw_simulated_round()


func _replay_cached_network_state() -> void:
	if network_client == null:
		return
	var rnd_status: Dictionary = network_client.get("last_poker_round_status") if network_client.get("last_poker_round_status") != null else {}
	if not rnd_status.is_empty():
		_on_poker_round_status(
			int(rnd_status.get("round", 1)),
			int(rnd_status.get("total_rounds", 10)),
			bool(rnd_status.get("is_exhausted", false))
		)
	var priv_hand: Dictionary = network_client.get("last_poker_private_hand") if network_client.get("last_poker_private_hand") != null else {}
	if not priv_hand.is_empty():
		_on_poker_private_hand(
			int(priv_hand.get("round", 1)),
			int(priv_hand.get("card", 0)),
			priv_hand.get("history", [])
		)
	var opp_foreheads: Dictionary = network_client.get("last_poker_opponent_foreheads") if network_client.get("last_poker_opponent_foreheads") != null else {}
	if not opp_foreheads.is_empty():
		_on_poker_opponent_foreheads(
			int(opp_foreheads.get("round", 1)),
			opp_foreheads.get("cards", [])
		)
	var bet_state: Dictionary = network_client.get("last_poker_betting_state") if network_client.get("last_poker_betting_state") != null else {}
	if not bet_state.is_empty():
		_on_poker_betting_state(bet_state)


func _bind_network_signals() -> void:
	if network_client == null:
		return
	if network_client.has_signal("poker_private_hand_received") and not network_client.is_connected("poker_private_hand_received", _on_poker_private_hand):
		network_client.connect("poker_private_hand_received", _on_poker_private_hand)
	if network_client.has_signal("poker_opponent_foreheads_received") and not network_client.is_connected("poker_opponent_foreheads_received", _on_poker_opponent_foreheads):
		network_client.connect("poker_opponent_foreheads_received", _on_poker_opponent_foreheads)
	if network_client.has_signal("poker_round_status_received") and not network_client.is_connected("poker_round_status_received", _on_poker_round_status):
		network_client.connect("poker_round_status_received", _on_poker_round_status)
	if network_client.has_signal("poker_match_reset_received") and not network_client.is_connected("poker_match_reset_received", _on_poker_match_reset):
		network_client.connect("poker_match_reset_received", _on_poker_match_reset)
	if network_client.has_signal("poker_betting_state_received") and not network_client.is_connected("poker_betting_state_received", _on_poker_betting_state):
		network_client.connect("poker_betting_state_received", _on_poker_betting_state)
	if network_client.has_signal("poker_action_result_received") and not network_client.is_connected("poker_action_result_received", _on_poker_action_result):
		network_client.connect("poker_action_result_received", _on_poker_action_result)
	if network_client.has_signal("poker_betting_completed_received") and not network_client.is_connected("poker_betting_completed_received", _on_poker_betting_completed):
		network_client.connect("poker_betting_completed_received", _on_poker_betting_completed)
	if network_client.has_signal("poker_reconnect_response_received") and not network_client.is_connected("poker_reconnect_response_received", _on_poker_reconnect_response):
		network_client.connect("poker_reconnect_response_received", _on_poker_reconnect_response)
	if network_client.has_signal("connection_closed") and not network_client.is_connected("connection_closed", _on_connection_closed):
		network_client.connect("connection_closed", _on_connection_closed)
	if network_client.has_signal("connected_to_server") and not network_client.is_connected("connected_to_server", _on_connected_to_server):
		network_client.connect("connected_to_server", _on_connected_to_server)
	if network_client.has_signal("room_state_received") and not network_client.is_connected("room_state_received", _on_room_state_received):
		network_client.connect("room_state_received", _on_room_state_received)


# ── HUD CONTROLS & LOCAL PLAYER BETTING ──────────────────────────────────────

func _on_hud_request_draw_round() -> void:
	if is_online_match and network_client != null and network_client.get("is_connected_to_server") == true:
		network_client.call("send_poker_draw_round", active_room_code)
	elif not is_online_match:
		_draw_simulated_round()


func _on_hud_request_reset_match() -> void:
	if is_online_match and network_client != null and network_client.get("is_connected_to_server") == true:
		network_client.call("send_poker_reset_match", active_room_code)
	elif not is_online_match:
		_reset_simulated_match()


func _on_hud_betting_action_requested(action: String, target_bet: int) -> void:
	if is_online_match and network_client != null and network_client.get("is_connected_to_server") == true:
		network_client.call("send_poker_betting_action", active_room_code, action, target_bet)
	elif not is_online_match:
		# Process local player's action
		var p_name: String = PRESETS[local_seat_index]["name"]
		var desc: String = _format_action_text(action, target_bet, local_seat_index)
		var col: String = _get_action_color_hex(action)
		
		# Clear local turn highlight ring
		if local_seat_index < seat_nodes.size():
			seat_nodes[local_seat_index].call("set_turn_active", false)

		_process_simulated_action(local_seat_index, action, target_bet)

		if hud_instance != null:
			hud_instance.add_action_history_entry(p_name, desc, col)

		# Advance turn to next player asynchronously
		_advance_simulated_turn()


# ── OFFLINE SIMULATION: DECKS, SEQUENTIAL TURNS & DIVERSE NPC AI ─────────────

func _init_offline_simulation() -> void:
	_sim_round = 0
	_turn_sequence_token += 1
	_sim_hand_decks.clear()
	_sim_forehead_decks.clear()
	_sim_hand_history.clear()
	_sim_forehead_history.clear()

	_sim_balances.clear()
	_sim_round_bets.clear()
	_sim_total_contributions.clear()
	_sim_folded.clear()
	_sim_all_in.clear()
	_sim_has_acted.clear()

	for i in range(6):
		var hand_cards: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
		var forehead_cards: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
		hand_cards.shuffle()
		forehead_cards.shuffle()
		_sim_hand_decks[i] = hand_cards
		_sim_forehead_decks[i] = forehead_cards
		_sim_hand_history[i] = []
		_sim_forehead_history[i] = []

		_sim_balances[i] = 100
		_sim_round_bets[i] = 0
		_sim_total_contributions[i] = 0
		_sim_folded[i] = false
		_sim_all_in[i] = false
		_sim_has_acted[i] = false


func _draw_simulated_round() -> void:
	if _sim_round >= 10:
		if hud_instance != null:
			hud_instance.update_round_status(10, 10, true)
		return

	_turn_sequence_token += 1
	_sim_round += 1

	if hud_instance != null:
		hud_instance.reset_action_history(_sim_round)

	# Reset round bets and acted flags
	_sim_current_highest_bet = 0
	_sim_min_raise_inc = 2
	_sim_betting_active = true
	_sim_total_pot = 0
	_sim_side_pots = []

	# Draw cards & Deduct Ante (1 chip)
	var drawn_hands: Dictionary = {}
	var drawn_foreheads: Dictionary = {}

	for i in range(6):
		var h_deck: Array = _sim_hand_decks[i]
		var f_deck: Array = _sim_forehead_decks[i]
		var h_card: int = h_deck.pop_back() if h_deck.size() > 0 else 0
		var f_card: int = f_deck.pop_back() if f_deck.size() > 0 else 0

		drawn_hands[i] = h_card
		drawn_foreheads[i] = f_card
		_sim_hand_history[i].append(h_card)
		_sim_forehead_history[i].append(f_card)

		# Reset round states
		_sim_round_bets[i] = 0
		_sim_has_acted[i] = false
		_sim_folded[i] = false

		# Ante deduction
		if _sim_balances[i] >= 1:
			_sim_balances[i] -= 1
			_sim_total_contributions[i] = 1
			_sim_total_pot += 1
		else:
			_sim_total_contributions[i] = _sim_balances[i]
			_sim_total_pot += _sim_balances[i]
			_sim_balances[i] = 0
			_sim_all_in[i] = true

		if i < seat_nodes.size():
			seat_nodes[i].call("update_balance", _sim_balances[i])
			seat_nodes[i].call("set_player_status", "ACTIVE" if not _sim_all_in[i] else "ALL_IN")
			seat_nodes[i].call("set_turn_active", false)

	_sim_main_pot = _sim_total_pot

	# 1. Update Local Player's Private Hand (Seat 0)
	if hud_instance != null:
		hud_instance.set_private_hand_card(
			_sim_round,
			drawn_hands[local_seat_index],
			_sim_hand_history[local_seat_index]
		)

	# 2. Update Opponents' 3D Forehead Cards (Seats 1..5)
	for i in range(6):
		if i == local_seat_index:
			continue
		
		if i < seat_nodes.size():
			var seat: Node3D = seat_nodes[i]
			var f_val: int = drawn_foreheads[i]
			seat.call("set_forehead_card_value", f_val)
			
			if hud_instance != null:
				var opp_name: String = PRESETS[i]["name"]
				hud_instance.record_opponent_forehead(PRESETS[i]["id"], opp_name, f_val)

	# 3. Start Betting Turn at Seat 0 (Local Player)
	_sim_current_turn_seat = 0
	_sim_last_action_player = ""
	_sim_last_action_type = ""
	_sim_last_action_amount = 0

	# Highlight initial turn
	if seat_nodes.size() > 0:
		seat_nodes[0].call("set_turn_active", true)

	_sync_simulated_betting_state()


func _sync_simulated_betting_state() -> void:
	if hud_instance == null:
		return

	var players_list: Array = []
	for i in range(6):
		players_list.append({
			"player_id": PRESETS[i]["id"],
			"balance": _sim_balances[i],
			"round_bet": _sim_round_bets[i],
			"total_contribution": _sim_total_contributions[i],
			"is_folded": _sim_folded[i],
			"is_all_in": _sim_all_in[i],
			"has_acted": _sim_has_acted[i]
		})

	var turn_id: String = str(PRESETS[_sim_current_turn_seat]["id"]) if _sim_betting_active else ""
	var turn_name: String = str(PRESETS[_sim_current_turn_seat]["name"]) if _sim_betting_active else ""
	var state_dict := {
		"betting_phase_active": _sim_betting_active,
		"current_turn_player_id": turn_id,
		"current_turn_name": turn_name,
		"current_highest_bet": _sim_current_highest_bet,
		"min_raise_increment": _sim_min_raise_inc,
		"total_pot": _sim_total_pot,
		"main_pot": _sim_main_pot,
		"side_pots": _sim_side_pots,
		"players": players_list,
		"last_action_player_id": _sim_last_action_player,
		"last_action_type": _sim_last_action_type,
		"last_action_amount": _sim_last_action_amount
	}

	hud_instance.update_betting_state(state_dict, PRESETS[local_seat_index]["id"])


func _process_simulated_action(seat_idx: int, action: String, target_bet: int = 0) -> void:
	var p_name: String = PRESETS[seat_idx]["name"]
	var amt_added := 0

	match action:
		"FOLD":
			_sim_folded[seat_idx] = true
			_sim_has_acted[seat_idx] = true
			if seat_idx < seat_nodes.size():
				seat_nodes[seat_idx].call("set_player_status", "FOLDED")
				seat_nodes[seat_idx].call("set_turn_active", false)

		"CHECK":
			_sim_has_acted[seat_idx] = true
			if seat_idx < seat_nodes.size():
				seat_nodes[seat_idx].call("set_temporary_action", "CHECK", Color(0.35, 0.75, 1.0, 1.0))

		"CALL":
			var to_call: int = _sim_current_highest_bet - _sim_round_bets[seat_idx]
			if to_call > 0:
				amt_added = mini(to_call, _sim_balances[seat_idx])
				_sim_balances[seat_idx] -= amt_added
				_sim_round_bets[seat_idx] += amt_added
				_sim_total_contributions[seat_idx] += amt_added
				_sim_total_pot += amt_added
				_sim_main_pot += amt_added
				if _sim_balances[seat_idx] == 0:
					_sim_all_in[seat_idx] = true
					if seat_idx < seat_nodes.size():
						seat_nodes[seat_idx].call("set_player_status", "ALL_IN")
			_sim_has_acted[seat_idx] = true
			if seat_idx < seat_nodes.size():
				var label_txt := "CALL %d" % amt_added if amt_added > 0 else "CHECK"
				seat_nodes[seat_idx].call("set_temporary_action", label_txt, Color(0.25, 0.90, 0.45, 1.0))

		"RAISE":
			var needed: int = target_bet - _sim_round_bets[seat_idx]
			amt_added = mini(needed, _sim_balances[seat_idx])
			_sim_balances[seat_idx] -= amt_added
			_sim_round_bets[seat_idx] += amt_added
			_sim_total_contributions[seat_idx] += amt_added
			_sim_total_pot += amt_added
			_sim_main_pot += amt_added

			var raise_inc: int = target_bet - _sim_current_highest_bet
			if raise_inc >= _sim_min_raise_inc:
				_sim_min_raise_inc = raise_inc
			_sim_current_highest_bet = target_bet

			if _sim_balances[seat_idx] == 0:
				_sim_all_in[seat_idx] = true
				if seat_idx < seat_nodes.size():
					seat_nodes[seat_idx].call("set_player_status", "ALL_IN")

			# Reset has_acted for other active players
			for i in range(6):
				if i != seat_idx and not _sim_folded[i] and not _sim_all_in[i]:
					_sim_has_acted[i] = false
			_sim_has_acted[seat_idx] = true
			if seat_idx < seat_nodes.size():
				seat_nodes[seat_idx].call("set_temporary_action", "RAISE %d" % target_bet, Color(1.0, 0.65, 0.15, 1.0))

		"ALL_IN":
			amt_added = _sim_balances[seat_idx]
			_sim_balances[seat_idx] = 0
			_sim_round_bets[seat_idx] += amt_added
			_sim_total_contributions[seat_idx] += amt_added
			_sim_total_pot += amt_added
			_sim_main_pot += amt_added
			_sim_all_in[seat_idx] = true
			if seat_idx < seat_nodes.size():
				seat_nodes[seat_idx].call("set_player_status", "ALL_IN")
				seat_nodes[seat_idx].call("set_temporary_action", "ALL-IN (%d)" % _sim_round_bets[seat_idx], Color(0.85, 0.40, 1.0, 1.0))

			if _sim_round_bets[seat_idx] > _sim_current_highest_bet:
				var inc: int = _sim_round_bets[seat_idx] - _sim_current_highest_bet
				if inc >= _sim_min_raise_inc:
					_sim_min_raise_inc = inc
				_sim_current_highest_bet = _sim_round_bets[seat_idx]
				for i in range(6):
					if i != seat_idx and not _sim_folded[i] and not _sim_all_in[i]:
						_sim_has_acted[i] = false

			_sim_has_acted[seat_idx] = true

	_sim_last_action_player = p_name
	_sim_last_action_type = action
	_sim_last_action_amount = amt_added

	if seat_idx < seat_nodes.size():
		seat_nodes[seat_idx].call("update_balance", _sim_balances[seat_idx])


func _advance_simulated_turn() -> void:
	if _check_simulated_betting_complete():
		_sim_betting_active = false
		_sim_calculate_side_pots()
		for i in range(seat_nodes.size()):
			seat_nodes[i].call("set_turn_active", false)
		_sync_simulated_betting_state()
		return

	# Increment turn sequence token to invalidate any previous pending timers
	_turn_sequence_token += 1
	var current_token := _turn_sequence_token

	# Advance cyclically to next eligible player
	var next_seat := (_sim_current_turn_seat + 1) % 6
	var loops := 0
	while loops < 6:
		if not _sim_folded[next_seat] and not _sim_all_in[next_seat]:
			_sim_current_turn_seat = next_seat
			
			# Update 3D seat turn highlight rings
			for i in range(seat_nodes.size()):
				seat_nodes[i].call("set_turn_active", (i == _sim_current_turn_seat))

			_sync_simulated_betting_state()
			
			# If human turn (Seat 0): release mouse capture so player can click buttons immediately
			if _sim_current_turn_seat == local_seat_index:
				if camera != null and camera.has_method("set_mouse_captured"):
					camera.call("set_mouse_captured", false)
				return
			
			# If NPC turn: process sequentially with asynchronous thinking delay
			_execute_npc_turn_async(current_token, _sim_current_turn_seat)
			return

		next_seat = (next_seat + 1) % 6
		loops += 1

	# No more players can act
	_sim_betting_active = false
	_sim_calculate_side_pots()
	for i in range(seat_nodes.size()):
		seat_nodes[i].call("set_turn_active", false)
	_sync_simulated_betting_state()


func _execute_npc_turn_async(token: int, seat_idx: int) -> void:
	# Random thinking delay between 0.65s and 0.95s
	var think_time: float = randf_range(0.65, 0.95)
	await get_tree().create_timer(think_time).timeout

	# Guard: Ensure token matches and round is still actively running
	if token != _turn_sequence_token or not _sim_betting_active or not is_inside_tree():
		return

	# Generate independent decision based on NPC personality and board state
	var decision: Dictionary = _decide_npc_action(seat_idx)
	var action: String = str(decision.get("action", "CHECK"))
	var target_bet: int = int(decision.get("target_bet", 0))

	var p_name: String = PRESETS[seat_idx]["name"]
	var desc: String = _format_action_text(action, target_bet, seat_idx)
	var col_hex: String = _get_action_color_hex(action)

	# Process action
	_process_simulated_action(seat_idx, action, target_bet)

	# Update action history feed
	if hud_instance != null:
		hud_instance.add_action_history_entry(p_name, desc, col_hex)

	# Brief visual settle delay (0.3s) before advancing to next player
	await get_tree().create_timer(0.30).timeout
	if token != _turn_sequence_token or not _sim_betting_active or not is_inside_tree():
		return

	# Advance to next player
	_advance_simulated_turn()


func _decide_npc_action(seat_idx: int) -> Dictionary:
	var preset: Dictionary = PRESETS[seat_idx]
	var bal: int = _sim_balances[seat_idx]
	var round_bet: int = _sim_round_bets[seat_idx]
	var to_call: int = _sim_current_highest_bet - round_bet

	var call_rate: float = float(preset.get("call_rate", 0.65))
	var fold_rate: float = float(preset.get("fold_rate", 0.20))
	var raise_rate: float = float(preset.get("raise_rate", 0.15))
	var open_rate: float = float(preset.get("open_rate", 0.15))

	var roll := randf()

	# Scenario A: No bet to match (to_call <= 0)
	if to_call <= 0:
		# Check or Open Raise
		if bal >= _sim_min_raise_inc and roll < open_rate:
			var open_amt := _sim_current_highest_bet + _sim_min_raise_inc
			return { "action": "RAISE", "target_bet": open_amt }
		return { "action": "CHECK", "target_bet": 0 }

	# Scenario B: Facing a bet (to_call > 0)
	# Check if affordable
	if bal <= to_call:
		# Player doesn't have enough to fully call -> All-in or Fold
		if roll < (fold_rate * 1.25):
			return { "action": "FOLD", "target_bet": 0 }
		return { "action": "CALL", "target_bet": 0 }

	# Check fold threshold (higher to_call encourages folding)
	var adjusted_fold := fold_rate
	if to_call >= 20:
		adjusted_fold *= 1.8
	elif to_call >= 10:
		adjusted_fold *= 1.3

	if roll < adjusted_fold:
		return { "action": "FOLD", "target_bet": 0 }

	# Check raise potential (needs chips for to_call + min_raise)
	var can_raise: bool = (bal >= (to_call + _sim_min_raise_inc))
	if can_raise and roll > (1.0 - raise_rate):
		var target := _sim_current_highest_bet + _sim_min_raise_inc
		return { "action": "RAISE", "target_bet": target }

	# Default: Call the bet
	return { "action": "CALL", "target_bet": 0 }


func _format_action_text(action: String, target_bet: int, seat_idx: int) -> String:
	match action:
		"FOLD":
			return "FOLD"
		"CHECK":
			return "CHECK"
		"CALL":
			var to_call: int = _sim_current_highest_bet - _sim_round_bets[seat_idx]
			return "CALL %d" % maxi(0, to_call)
		"RAISE":
			return "RAISE %d" % target_bet
		"ALL_IN":
			return "ALL-IN (%d)" % _sim_balances[seat_idx]
		_:
			return action


func _get_action_color_hex(action: String) -> String:
	match action:
		"FOLD":
			return "#FF6B6B"
		"CHECK":
			return "#4DABF7"
		"CALL":
			return "#51CF66"
		"RAISE":
			return "#FFA94D"
		"ALL_IN":
			return "#CC5DE8"
		_:
			return "#FFFFFF"


func _get_action_color(action: String) -> Color:
	return Color(_get_action_color_hex(action))


func _check_simulated_betting_complete() -> bool:
	# 1. If only 1 or 0 non-folded players remain -> complete
	var non_folded := 0
	for i in range(6):
		if not _sim_folded[i]:
			non_folded += 1
	if non_folded <= 1:
		return true

	# 2. Check if all eligible players have acted and matched highest bet
	for i in range(6):
		if _sim_folded[i] or _sim_all_in[i]:
			continue
		if not _sim_has_acted[i]:
			return false
		if _sim_round_bets[i] != _sim_current_highest_bet:
			return false

	return true


func _sim_calculate_side_pots() -> void:
	_sim_side_pots.clear()
	var contribs: Array = []
	for i in range(6):
		if not _sim_folded[i] and _sim_total_contributions[i] > 0:
			contribs.append(_sim_total_contributions[i])
	contribs.sort()
	
	var distinct_contribs: Array = []
	for c in contribs:
		if not distinct_contribs.has(c):
			distinct_contribs.append(c)

	if distinct_contribs.size() <= 1:
		_sim_main_pot = _sim_total_pot
		return

	var prev_tier := 0
	_sim_main_pot = 0
	for tier_idx in range(distinct_contribs.size()):
		var cap: int = distinct_contribs[tier_idx]
		var slice_size: int = cap - prev_tier
		var pot_amt := 0
		var eligibles: Array = []

		for i in range(6):
			var player_c: int = _sim_total_contributions[i]
			if player_c > prev_tier:
				pot_amt += mini(player_c - prev_tier, slice_size)
			if not _sim_folded[i] and player_c >= cap:
				eligibles.append(PRESETS[i]["name"])

		if tier_idx == 0:
			_sim_main_pot = pot_amt
		else:
			_sim_side_pots.append({
				"tier": tier_idx,
				"amount": pot_amt,
				"eligible_players": eligibles
			})
		prev_tier = cap


func _reset_simulated_match() -> void:
	_init_offline_simulation()
	if hud_instance != null:
		hud_instance.reset_hud()
	for i in range(seat_nodes.size()):
		var seat: Node3D = seat_nodes[i]
		seat.call("update_balance", 100)
		seat.call("set_player_status", "ACTIVE")
		seat.call("set_turn_active", false)
		var card_node := seat.get_node_or_null("ForeheadCardAttachment") as Node3D
		if card_node != null:
			card_node.visible = false


# ── NETWORK MESSAGE HANDLERS ─────────────────────────────────────────────────

func _on_poker_private_hand(rnd: int, card_val: int, history: Array) -> void:
	if hud_instance != null:
		hud_instance.set_private_hand_card(rnd, card_val, history)


func _on_poker_opponent_foreheads(rnd: int, cards: Array) -> void:
	for entry in cards:
		if not (entry is Dictionary):
			continue
		var p_id: String = str(entry.get("player_id", ""))
		var c_val: int = int(entry.get("card", 0))

		if is_online_match:
			var s_idx: int = player_id_to_seat.get(p_id, -1)
			if s_idx >= 0 and s_idx < seat_nodes.size() and s_idx != local_seat_index:
				seat_nodes[s_idx].call("set_forehead_card_value", c_val)
				if hud_instance != null:
					hud_instance.record_opponent_forehead(p_id, seat_to_player_name.get(s_idx, p_id), c_val)
		else:
			for i in range(PRESETS.size()):
				if PRESETS[i]["id"] == p_id:
					if i < seat_nodes.size() and i != local_seat_index:
						seat_nodes[i].call("set_forehead_card_value", c_val)
						if hud_instance != null:
							hud_instance.record_opponent_forehead(p_id, PRESETS[i]["name"], c_val)
					break


func _on_poker_round_status(rnd: int, total: int, is_exhausted: bool) -> void:
	if hud_instance != null:
		hud_instance.update_round_status(rnd, total, is_exhausted)


func _on_poker_match_reset(_code: String) -> void:
	if hud_instance != null:
		hud_instance.reset_hud()
	for i in range(seat_nodes.size()):
		var seat: Node3D = seat_nodes[i]
		seat.call("update_balance", 100)
		seat.call("set_player_status", "ACTIVE")
		seat.call("set_turn_active", false)
		var card_node := seat.get_node_or_null("ForeheadCardAttachment") as Node3D
		if card_node != null:
			card_node.visible = false


func _on_poker_betting_state(data: Dictionary) -> void:
	var v: int = int(data.get("version", 0))
	if v > 0 and v < last_state_version:
		return
	if v > 0:
		last_state_version = v

	if hud_instance != null:
		var my_pid := local_player_id
		if my_pid.is_empty() and network_client != null:
			my_pid = str(network_client.get("client_player_id"))
		if my_pid.is_empty():
			my_pid = PRESETS[local_seat_index]["id"]
		hud_instance.update_betting_state(data, my_pid)

	# Update 3D seat balances and statuses
	var players_data: Array = data.get("players", [])
	for p_entry in players_data:
		if not (p_entry is Dictionary):
			continue
		var pid := str(p_entry.get("player_id", ""))
		var bal := int(p_entry.get("balance", 0))
		var is_fold := bool(p_entry.get("is_folded", false))
		var is_all := bool(p_entry.get("is_all_in", false))

		var s_idx: int = -1
		if is_online_match:
			s_idx = player_id_to_seat.get(pid, int(p_entry.get("seat_index", -1)))
		else:
			for i in range(PRESETS.size()):
				if PRESETS[i]["id"] == pid:
					s_idx = i
					break

		if s_idx >= 0 and s_idx < seat_nodes.size():
			seat_nodes[s_idx].call("update_balance", bal)
			if is_fold:
				seat_nodes[s_idx].call("set_player_status", "FOLDED")
			elif is_all:
				seat_nodes[s_idx].call("set_player_status", "ALL_IN")
			else:
				seat_nodes[s_idx].call("set_player_status", "ACTIVE")

	# Update active turn highlight rings on 3D seats
	var cur_turn_pid: String = str(data.get("current_turn_player_id", ""))
	for s_idx in range(seat_nodes.size()):
		var is_turn := false
		if is_online_match:
			var spid: String = seat_to_player_id.get(s_idx, "")
			is_turn = (spid != "" and spid == cur_turn_pid)
		else:
			is_turn = (s_idx == _sim_current_turn_seat and _sim_betting_active)
		seat_nodes[s_idx].call("set_turn_active", is_turn)

	# If human turn: release mouse capture
	var is_my_turn := false
	if is_online_match:
		is_my_turn = (cur_turn_pid != "" and cur_turn_pid == local_player_id)
	else:
		is_my_turn = (_sim_current_turn_seat == local_seat_index and _sim_betting_active)

	if is_my_turn and camera != null and camera.has_method("set_mouse_captured"):
		camera.call("set_mouse_captured", false)


func _on_poker_action_result(data: Dictionary) -> void:
	var res_info: Dictionary = data.get("action_result", data)
	var success := bool(res_info.get("success", false))
	if not success:
		var err := str(res_info.get("error", "Action failed"))
		if hud_instance != null:
			hud_instance.announcement_label.text = "Error: %s" % err
		return

	var act_pid := str(res_info.get("player_id", ""))
	var act_type := str(res_info.get("action", ""))
	var act_amt := int(res_info.get("amount_added", 0))

	var s_idx: int = -1
	var p_name := act_pid
	if is_online_match:
		s_idx = player_id_to_seat.get(act_pid, -1)
		p_name = seat_to_player_name.get(s_idx, act_pid)
	else:
		for i in range(PRESETS.size()):
			if PRESETS[i]["id"] == act_pid:
				s_idx = i
				p_name = PRESETS[i]["name"]
				break

	if s_idx >= 0 and s_idx < seat_nodes.size():
		var desc := _format_action_text(act_type, act_amt, s_idx)
		var col_hex := _get_action_color_hex(act_type)
		seat_nodes[s_idx].call("show_action_badge", desc, _get_action_color(act_type))
		if hud_instance != null:
			hud_instance.add_action_history_entry(p_name, desc, col_hex)


func _on_poker_betting_completed(data: Dictionary) -> void:
	var total_p := int(data.get("total_pot", 0))
	if hud_instance != null:
		hud_instance.pot_label.text = "💰 POT: %d CHIPS (BETTING LOCKED)" % total_p
		hud_instance.turn_label.text = "ROUND COMPLETE • ALL BETS SETTLED"
	for i in range(seat_nodes.size()):
		seat_nodes[i].call("set_turn_active", false)


func _on_poker_reconnect_response(success: bool, data: Dictionary) -> void:
	if success:
		if hud_instance != null:
			hud_instance.announcement_label.text = "Reconnected to match!"
		if data.has("seat_index"):
			local_seat_index = int(data.get("seat_index", 0))
			_setup_first_person_camera()
	else:
		if hud_instance != null:
			hud_instance.announcement_label.text = "Reconnection failed: %s" % str(data.get("message", "Error"))


func _on_connection_closed() -> void:
	if is_online_match and hud_instance != null:
		hud_instance.announcement_label.text = "⚠️ Connection to server lost. Reconnecting..."


func _on_connected_to_server() -> void:
	if is_online_match and not active_room_code.is_empty() and not local_player_id.is_empty():
		var token: String = str(network_client.get("reconnect_token")) if network_client != null else ""
		if not token.is_empty():
			network_client.call("send_poker_reconnect", active_room_code, local_player_id, token)


func _on_room_state_received(room_dict: Dictionary) -> void:
	if is_online_match and str(room_dict.get("room_code", "")) == active_room_code:
		var roster: Array = room_dict.get("started_match_roster", [])
		if roster.is_empty():
			roster = room_dict.get("players", [])
		if not roster.is_empty():
			for p in roster:
				var pid := str(p.get("player_id", ""))
				var s_idx := int(p.get("seat_index", -1))
				if s_idx >= 0 and s_idx < seat_nodes.size():
					player_id_to_seat[pid] = s_idx
					seat_to_player_id[s_idx] = pid
					seat_to_player_name[s_idx] = Wardrobe.clean_name(str(p.get("display_name", pid)))

