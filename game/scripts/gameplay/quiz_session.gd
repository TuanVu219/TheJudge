extends Node

## Quiz state and answer validation, independent from the presentation layer.

signal player_state_updated(player_id: String, player_state: Dictionary)
signal session_time_updated(seconds_remaining: float)
signal session_completed(summary: Dictionary)

enum PlayerStatus {
	ANSWERING,
	COOLDOWN,
	QUALIFIED,
	ELIMINATED,
}

const DEFAULT_SESSION_SECONDS := 60.0
const COOLDOWN_SECONDS := 10.0
const QUESTION_BANK_SCRIPT = preload("res://scripts/gameplay/quiz_question_bank.gd")

var session_active := false
var seconds_remaining := DEFAULT_SESSION_SECONDS
var players: Dictionary = {}

var _question_bank: RefCounted
var _answer_by_player: Dictionary = {}
var _explanation_by_player: Dictionary = {}
var _last_timer_second := -1


func _ready() -> void:
	set_process(false)


func start_session(player_configs: Array[Dictionary], duration_seconds: float = DEFAULT_SESSION_SECONDS) -> bool:
	_question_bank = QUESTION_BANK_SCRIPT.new()
	if not _question_bank.load_question_data():
		return false

	_question_bank.start_session()
	players.clear()
	_answer_by_player.clear()
	_explanation_by_player.clear()
	seconds_remaining = maxf(0.1, duration_seconds)
	_last_timer_second = -1
	session_active = true
	set_process(true)

	for config in player_configs:
		var player_id := str(config.get("player_id", ""))
		var team_id := int(config.get("team_id", 0))
		if not register_player(player_id, team_id):
			push_warning("Could not register quiz player '%s'." % player_id)

	if players.is_empty():
		session_active = false
		set_process(false)
		return false

	session_time_updated.emit(seconds_remaining)
	return true


func register_player(player_id: String, team_id: int) -> bool:
	if not session_active or player_id.is_empty() or players.has(player_id):
		return false

	var player_state := {
		"player_id": player_id,
		"team_id": team_id,
		"current_question": {},
		"status": PlayerStatus.ANSWERING,
		"cooldown_remaining": 0.0,
		"correct_count": 0,
		"wrong_count": 0,
		"qualified": false,
	}
	players[player_id] = player_state
	_assign_question(player_id)
	player_state_updated.emit(player_id, get_player_state(player_id))
	return true


func submit_answer(player_id: String, selected_index: int) -> Dictionary:
	if not session_active:
		return _rejected_answer("The quiz session has ended.")
	if not players.has(player_id):
		return _rejected_answer("Unknown player.")

	var player_state: Dictionary = players[player_id]
	if player_state["status"] != PlayerStatus.ANSWERING:
		return _rejected_answer("This player cannot answer right now.")
	if selected_index < 0 or selected_index > 3:
		return _rejected_answer("Choose one of the four answers.")

	var is_correct := selected_index == int(_answer_by_player.get(player_id, -1))
	var explanation := str(_explanation_by_player.get(player_id, ""))
	_answer_by_player.erase(player_id)
	_explanation_by_player.erase(player_id)

	if is_correct:
		player_state["correct_count"] = int(player_state["correct_count"]) + 1
		player_state["qualified"] = true
		player_state["status"] = PlayerStatus.QUALIFIED
		player_state["cooldown_remaining"] = 0.0
	else:
		player_state["wrong_count"] = int(player_state["wrong_count"]) + 1
		player_state["status"] = PlayerStatus.COOLDOWN
		player_state["cooldown_remaining"] = COOLDOWN_SECONDS

	players[player_id] = player_state
	player_state_updated.emit(player_id, get_player_state(player_id))
	return {
		"accepted": true,
		"is_correct": is_correct,
		"explanation": explanation,
		"player_state": get_player_state(player_id),
	}


func submit_bot_answer(player_id: String, accuracy: float = 0.75) -> Dictionary:
	## Offline-only bot simulation. The answer key stays inside this session,
	## and the result still passes through the same answer-validation method.
	if not session_active or not players.has(player_id):
		return _rejected_answer("The bot cannot answer right now.")

	var player_state: Dictionary = players[player_id]
	if player_state["status"] != PlayerStatus.ANSWERING:
		return _rejected_answer("The bot cannot answer right now.")

	var correct_index := int(_answer_by_player.get(player_id, -1))
	if correct_index < 0 or correct_index > 3:
		return _rejected_answer("No answer key is available for this bot.")

	var selected_index := correct_index
	if randf() > clampf(accuracy, 0.0, 1.0):
		var wrong_options: Array[int] = []
		for option_index in range(4):
			if option_index != correct_index:
				wrong_options.append(option_index)
		selected_index = wrong_options.pick_random()

	return submit_answer(player_id, selected_index)


func get_player_state(player_id: String) -> Dictionary:
	if not players.has(player_id):
		return {}
	return (players[player_id] as Dictionary).duplicate(true)


func get_status_name(status: int) -> String:
	match status:
		PlayerStatus.ANSWERING:
			return "ANSWERING"
		PlayerStatus.COOLDOWN:
			return "COOLDOWN"
		PlayerStatus.QUALIFIED:
			return "QUALIFIED"
		PlayerStatus.ELIMINATED:
			return "ELIMINATED"
		_:
			return "UNKNOWN"


func _process(delta: float) -> void:
	if not session_active:
		return

	seconds_remaining = maxf(0.0, seconds_remaining - delta)
	var current_second := int(ceil(seconds_remaining))
	if current_second != _last_timer_second:
		_last_timer_second = current_second
		session_time_updated.emit(seconds_remaining)

	if seconds_remaining <= 0.0:
		_finish_session()
		return

	for player_id in players.keys():
		var player_state: Dictionary = players[player_id]
		if player_state["status"] != PlayerStatus.COOLDOWN:
			continue

		player_state["cooldown_remaining"] = maxf(0.0, float(player_state["cooldown_remaining"]) - delta)
		if player_state["cooldown_remaining"] <= 0.0:
			player_state["status"] = PlayerStatus.ANSWERING
			_assign_question(player_id)

		players[player_id] = player_state
		player_state_updated.emit(player_id, get_player_state(player_id))


func _assign_question(player_id: String) -> void:
	var question: Dictionary = _question_bank.draw_next_question()
	if question.is_empty():
		players[player_id]["status"] = PlayerStatus.ELIMINATED
		players[player_id]["current_question"] = {}
		return

	var public_question := question.duplicate(true)
	var correct_index := int(public_question["correct_index"])
	var explanation := str(public_question["explanation"])
	public_question.erase("correct_index")
	public_question.erase("explanation")
	_answer_by_player[player_id] = correct_index
	_explanation_by_player[player_id] = explanation
	players[player_id]["current_question"] = public_question


func _finish_session() -> void:
	session_active = false
	set_process(false)
	var qualified_count := 0
	var correct_total := 0
	var wrong_total := 0
	var player_summaries: Dictionary = {}

	for player_id in players.keys():
		var player_state: Dictionary = players[player_id]
		if bool(player_state["qualified"]):
			qualified_count += 1
		else:
			player_state["status"] = PlayerStatus.ELIMINATED
		player_state["cooldown_remaining"] = 0.0
		correct_total += int(player_state["correct_count"])
		wrong_total += int(player_state["wrong_count"])
		players[player_id] = player_state
		player_summaries[player_id] = get_player_state(player_id)
		player_state_updated.emit(player_id, get_player_state(player_id))

	var summary := {
		"qualified_count": qualified_count,
		"not_qualified_count": players.size() - qualified_count,
		"correct_count": correct_total,
		"wrong_count": wrong_total,
		"players": player_summaries,
	}
	session_completed.emit(summary)


func _rejected_answer(message: String) -> Dictionary:
	return {"accepted": false, "is_correct": false, "message": message}
