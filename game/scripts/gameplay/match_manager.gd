extends Node

## Owns the offline match phases and passes qualified roster data to the Arena.

signal phase_changed(phase_name: String)

enum Phase {
	QUIZ,
	QUALIFICATION,
	ARENA,
	RESULTS,
}

const QUIZ_SCENE = preload("res://scenes/quiz/QuizRoom.tscn")
const ARENA_SCENE = preload("res://scenes/arena/TerritoryArena.tscn")
const TEAM_RED := 1
const TEAM_BLUE := 2

@export_range(0.1, 180.0, 0.1) var quiz_duration_seconds := 60.0
@export_range(0.1, 300.0, 0.1) var arena_duration_seconds := 75.0
@export_range(0.05, 10.0, 0.05) var bot_answer_interval_seconds := 1.1
@export_range(0.0, 1.0, 0.01) var default_bot_accuracy := 0.72
@export var registrations: Array[Dictionary] = []

@onready var phase_container: Node = $PhaseContainer
@onready var phase_label: Label = $HUD/Overlay/PhaseLabel
@onready var transition_panel: Panel = $HUD/Overlay/TransitionPanel
@onready var transition_label: Label = $HUD/Overlay/TransitionPanel/TransitionLabel
@onready var result_panel: Panel = $HUD/Overlay/ResultPanel
@onready var result_title: Label = $HUD/Overlay/ResultPanel/ResultTitle
@onready var result_details: Label = $HUD/Overlay/ResultPanel/ResultDetails
@onready var play_again_button: Button = $HUD/Overlay/ResultPanel/PlayAgainButton

var phase := Phase.QUIZ
var player_registry: Dictionary = {}
var last_result: Dictionary = {}

var _qualified_roster: Array[Dictionary] = []
var _quiz_room: Control
var _quiz_session: Node
var _arena: Node3D
var _bot_answer_timers: Dictionary = {}
var _local_player_id := ""


func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again_pressed)
	if registrations.is_empty():
		registrations = _build_default_registrations()

	if not _set_player_registry(registrations):
		phase = Phase.RESULTS
		_set_phase_label("RESULTS")
		_show_result("INVALID PLAYER SETUP", "Register 1–10 unique players, with no more than 5 per team.", {})
		return

	_start_new_match()


func _process(delta: float) -> void:
	if phase != Phase.QUIZ or _quiz_session == null:
		return

	for player_id in player_registry.keys():
		var player: Dictionary = player_registry[player_id]
		if bool(player["is_human"]) or not bool(player["is_test_bot"]):
			continue

		var state: Dictionary = _quiz_session.call("get_player_state", str(player_id))
		if state.is_empty():
			continue

		var status_name: String = _quiz_session.call("get_status_name", int(state["status"]))
		if status_name != "ANSWERING":
			_bot_answer_timers[player_id] = bot_answer_interval_seconds
			continue

		var delay := float(_bot_answer_timers.get(player_id, bot_answer_interval_seconds)) - delta
		if delay <= 0.0:
			_quiz_session.call("submit_bot_answer", str(player_id), float(player["quiz_accuracy"]))
			_bot_answer_timers[player_id] = bot_answer_interval_seconds
		else:
			_bot_answer_timers[player_id] = delay


func configure_registrations(new_registrations: Array[Dictionary]) -> bool:
	## Allows a future room/server adapter to provide player records before play.
	if is_inside_tree() and phase != Phase.RESULTS:
		return false
	if not _is_valid_registration_list(new_registrations):
		return false
	registrations = new_registrations.duplicate(true)
	return true


func get_phase_name() -> String:
	match phase:
		Phase.QUIZ:
			return "QUIZ"
		Phase.QUALIFICATION:
			return "QUALIFICATION"
		Phase.ARENA:
			return "ARENA"
		Phase.RESULTS:
			return "RESULTS"
		_:
			return "UNKNOWN"


func get_player_registry() -> Dictionary:
	return player_registry.duplicate(true)


func get_qualified_roster() -> Array[Dictionary]:
	return _qualified_roster.duplicate(true)


func _start_new_match() -> void:
	_clear_phase_container()
	qualified_roster_reset()
	last_result.clear()
	_bot_answer_timers.clear()
	_set_phase(Phase.QUIZ)
	_set_phase_label("QUIZ PHASE")
	transition_panel.hide()
	result_panel.hide()

	var quiz_configs: Array[Dictionary] = []
	_local_player_id = ""
	for player_id in player_registry.keys():
		var player: Dictionary = player_registry[player_id]
		quiz_configs.append({
			"player_id": str(player_id),
			"team_id": int(player["team_id"]),
			"character_id": str(player.get("character_id", "mint")),
		})
		if bool(player["is_human"]):
			_local_player_id = str(player_id)
		_bot_answer_timers[player_id] = bot_answer_interval_seconds

	_quiz_room = QUIZ_SCENE.instantiate() as Control
	_quiz_room.set("local_player_id", _local_player_id)
	_quiz_room.set("session_duration_seconds", quiz_duration_seconds)
	_quiz_room.set("player_configs", quiz_configs)
	_quiz_session = _quiz_room.get_node("QuizSession")
	_quiz_session.connect("session_completed", _on_quiz_completed)
	_quiz_session.connect("player_state_updated", _on_quiz_player_state_updated)
	phase_container.add_child(_quiz_room)


func _on_quiz_player_state_updated(player_id: String, player_state: Dictionary) -> void:
	if phase != Phase.QUIZ or player_id != _local_player_id:
		return

	var status_name: String = _quiz_session.call("get_status_name", int(player_state.get("status", -1)))
	if status_name != "QUALIFIED":
		return

	var current_states: Dictionary = {}
	for registered_id in player_registry.keys():
		current_states[registered_id] = _quiz_session.call("get_player_state", str(registered_id))
	_enter_arena_from_quiz_states(current_states)


func _on_quiz_completed(summary: Dictionary) -> void:
	if phase != Phase.QUIZ:
		return
	_enter_arena_from_quiz_states(summary.get("players", {}))


func _enter_arena_from_quiz_states(states: Dictionary) -> void:
	if phase != Phase.QUIZ:
		return

	_set_phase(Phase.QUALIFICATION)
	_set_phase_label("QUALIFICATION")
	_qualified_roster.clear()
	for player_id in player_registry.keys():
		var player: Dictionary = player_registry[player_id]
		var state: Dictionary = states.get(player_id, {})
		var status_name := "UNKNOWN"
		if not state.is_empty():
			status_name = _quiz_session.call("get_status_name", int(state.get("status", -1)))
		var is_qualified := status_name == "QUALIFIED"
		player["qualification_status"] = "QUALIFIED" if is_qualified else "ELIMINATED"
		player["arena_participation"] = is_qualified
		player_registry[player_id] = player
		if is_qualified:
			_qualified_roster.append(player.duplicate(true))

	if _qualified_roster.is_empty():
		_clear_phase_container()
		var no_qualifiers := {
			"winner_team_id": 0,
			"red_score": 0,
			"blue_score": 0,
			"qualified_red_count": 0,
			"qualified_blue_count": 0,
			"quiz_duration_seconds": quiz_duration_seconds,
			"arena_duration_seconds": 0.0,
			"arena_skipped": true,
		}
		_show_result("NO QUALIFIED PLAYERS", "No player qualified, so the empty Arena was skipped.", no_qualifiers)
		return

	_clear_phase_container()
	transition_panel.hide()
	_start_arena()


func _start_arena() -> void:
	if _qualified_roster.is_empty():
		return

	_set_phase(Phase.ARENA)
	_set_phase_label("TERRITORY ARENA")
	transition_panel.hide()
	_arena = ARENA_SCENE.instantiate() as Node3D
	_arena.set("player_roster", _qualified_roster.duplicate(true))
	_arena.set("round_duration_seconds", arena_duration_seconds)
	_arena.connect("arena_completed", _on_arena_completed)
	phase_container.add_child(_arena)


func _on_arena_completed(arena_result: Dictionary) -> void:
	if phase != Phase.ARENA:
		return

	var result := arena_result.duplicate(true)
	result["qualified_red_count"] = _count_qualified_for_team(TEAM_RED)
	result["qualified_blue_count"] = _count_qualified_for_team(TEAM_BLUE)
	result["quiz_duration_seconds"] = quiz_duration_seconds
	result["arena_skipped"] = false
	last_result = result
	_set_phase(Phase.RESULTS)
	_set_phase_label("RESULTS")
	transition_panel.hide()
	_clear_phase_container()
	_show_arena_result(result)


func _show_arena_result(result: Dictionary) -> void:
	var winner_id := int(result.get("winner_team_id", 0))
	var title := "IT'S A TIE!"
	if winner_id == TEAM_RED:
		title = "RED TEAM WINS!"
	elif winner_id == TEAM_BLUE:
		title = "BLUE TEAM WINS!"

	var details := "RED TILES: %d     •     BLUE TILES: %d\nQUALIFIED: RED %d     •     BLUE %d\nQUIZ: %.0f sec     •     ARENA: %.1f sec" % [
		int(result["red_score"]),
		int(result["blue_score"]),
		int(result["qualified_red_count"]),
		int(result["qualified_blue_count"]),
		float(result["quiz_duration_seconds"]),
		float(result["arena_elapsed_seconds"]),
	]
	_show_result(title, details, result)


func _show_result(title: String, details: String, result: Dictionary) -> void:
	last_result = result.duplicate(true)
	result_title.text = title
	result_details.text = details
	result_panel.show()
	_set_phase(Phase.RESULTS)
	_set_phase_label("RESULTS")


func _on_play_again_pressed() -> void:
	if phase != Phase.RESULTS:
		return
	_start_new_match()


func _set_player_registry(new_registrations: Array[Dictionary]) -> bool:
	if not _is_valid_registration_list(new_registrations):
		return false

	player_registry.clear()
	for source_record in new_registrations:
		var player_id := str(source_record["player_id"])
		var is_human := bool(source_record.get("is_human", source_record.get("human_controlled", false)))
		player_registry[player_id] = {
			"player_id": player_id,
			"display_name": str(source_record.get("display_name", player_id)),
			"team_id": int(source_record["team_id"]),
			"character_id": str(source_record.get("character_id", "mint")),
			"is_human": is_human,
			"is_test_bot": bool(source_record.get("is_test_bot", false)),
			"quiz_accuracy": clampf(float(source_record.get("quiz_accuracy", default_bot_accuracy)), 0.0, 1.0),
			"qualification_status": "PENDING",
			"arena_participation": false,
		}
	return true


func _is_valid_registration_list(candidate: Array[Dictionary]) -> bool:
	if candidate.is_empty() or candidate.size() > 10:
		return false

	var team_counts := {TEAM_RED: 0, TEAM_BLUE: 0}
	var seen_ids: Dictionary = {}
	var human_count := 0
	for player in candidate:
		var player_id := str(player.get("player_id", ""))
		var team_id := int(player.get("team_id", 0))
		if player_id.is_empty() or seen_ids.has(player_id):
			return false
		if team_id != TEAM_RED and team_id != TEAM_BLUE:
			return false
		seen_ids[player_id] = true
		team_counts[team_id] += 1
		if bool(player.get("is_human", player.get("human_controlled", false))):
			human_count += 1
		if human_count > 1:
			return false

	return team_counts[TEAM_RED] <= 5 and team_counts[TEAM_BLUE] <= 5


func _build_default_registrations() -> Array[Dictionary]:
	# Offline default represents the actual local player. Bots are added only
	# when explicitly configured as test fixtures with is_test_bot=true.
	return [{
		"player_id": "player_1",
		"display_name": "You",
		"team_id": TEAM_RED,
		"is_human": true,
	}]


func _count_qualified_for_team(team_id: int) -> int:
	var count := 0
	for player in _qualified_roster:
		if int(player["team_id"]) == team_id:
			count += 1
	return count


func _clear_phase_container() -> void:
	for child in phase_container.get_children():
		phase_container.remove_child(child)
		child.queue_free()
	_quiz_room = null
	_quiz_session = null
	_arena = null


func qualified_roster_reset() -> void:
	_qualified_roster.clear()
	for player_id in player_registry.keys():
		var player: Dictionary = player_registry[player_id]
		player["qualification_status"] = "PENDING"
		player["arena_participation"] = false
		player_registry[player_id] = player


func _set_phase(new_phase: int) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(get_phase_name())


func _set_phase_label(text: String) -> void:
	phase_label.text = text
