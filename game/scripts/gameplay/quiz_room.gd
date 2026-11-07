extends Control

## Quiz presentation layer for one local player. QuizSession owns all rules.

const OPTION_LETTERS := ["A", "B", "C", "D"]

@export var local_player_id := "player_1"
@export var session_duration_seconds := 60.0
@export var player_configs: Array[Dictionary] = []

@onready var quiz_session: Node = $QuizSession
@onready var timer_label: Label = $Overlay/TimerPanel/TimerLabel
@onready var player_status_label: Label = $Overlay/PlayerStatus
@onready var category_label: Label = $Overlay/QuizCard/CategoryLabel
@onready var question_label: Label = $Overlay/QuizCard/QuestionLabel
@onready var feedback_label: Label = $Overlay/QuizCard/FeedbackLabel
@onready var cooldown_label: Label = $Overlay/QuizCard/CooldownLabel
@onready var answer_buttons: Array[Button] = [
	$Overlay/QuizCard/AnswerGrid/AnswerA,
	$Overlay/QuizCard/AnswerGrid/AnswerB,
	$Overlay/QuizCard/AnswerGrid/AnswerC,
	$Overlay/QuizCard/AnswerGrid/AnswerD,
]
@onready var quiz_card: Panel = $Overlay/QuizCard
@onready var result_panel: Panel = $Overlay/ResultPanel
@onready var result_summary: Label = $Overlay/ResultPanel/ResultSummary
@onready var player_results: Label = $Overlay/ResultPanel/PlayerResults
@onready var restart_button: Button = $Overlay/ResultPanel/RestartButton

var _previous_status := -1


func _ready() -> void:
	quiz_session.connect("player_state_updated", _on_player_state_updated)
	quiz_session.connect("session_time_updated", _on_session_time_updated)
	quiz_session.connect("session_completed", _on_session_completed)
	restart_button.pressed.connect(_on_restart_pressed)

	for index in range(answer_buttons.size()):
		answer_buttons[index].pressed.connect(_on_answer_pressed.bind(index))

	_start_new_quiz()


func _start_new_quiz() -> void:
	result_panel.hide()
	quiz_card.show()
	feedback_label.text = "Pick the right answer to qualify!"
	feedback_label.add_theme_color_override("font_color", Color(0.15, 0.35, 0.38))
	cooldown_label.text = ""
	_previous_status = -1

	var session_players := player_configs.duplicate(true)
	if session_players.is_empty():
		session_players.append({"player_id": local_player_id, "team_id": 1})
	var started: bool = quiz_session.call("start_session", session_players, session_duration_seconds)
	if not started:
		question_label.text = "Quiz questions could not be loaded."
		return

	_update_timer(session_duration_seconds)
	_update_player_view(quiz_session.call("get_player_state", local_player_id))


func _on_answer_pressed(answer_index: int) -> void:
	var result: Dictionary = quiz_session.call("submit_answer", local_player_id, answer_index)
	if not bool(result.get("accepted", false)):
		return

	if bool(result.get("is_correct", false)):
		feedback_label.text = "QUALIFIED! You can enter the arena."
		feedback_label.add_theme_color_override("font_color", Color(0.08, 0.55, 0.29))
	else:
		feedback_label.text = "Not quite! %s" % str(result.get("explanation", "Try again after the cooldown."))
		feedback_label.add_theme_color_override("font_color", Color(0.78, 0.19, 0.23))


func _on_player_state_updated(player_id: String, player_state: Dictionary) -> void:
	if player_id != local_player_id:
		return
	_update_player_view(player_state)


func _update_player_view(player_state: Dictionary) -> void:
	if player_state.is_empty():
		return

	var status_id := int(player_state["status"])
	var status_name: String = quiz_session.call("get_status_name", status_id)
	player_status_label.text = "PLAYER 1     %s     •     RIGHT %d     •     WRONG %d" % [
		status_name,
		int(player_state["correct_count"]),
		int(player_state["wrong_count"]),
	]

	var question: Dictionary = player_state["current_question"]
	if not question.is_empty():
		category_label.text = "%s   •   %s" % [str(question["category"]).to_upper(), str(question["difficulty"]).to_upper()]
		question_label.text = str(question["prompt"])
		var options: Array = question["options"]
		for index in range(answer_buttons.size()):
			answer_buttons[index].text = "%s     %s" % [OPTION_LETTERS[index], str(options[index])]
	else:
		category_label.text = ""
		question_label.text = "No question is available."

	var can_answer := status_id == 0 and bool(quiz_session.get("session_active"))
	for button in answer_buttons:
		button.disabled = not can_answer

	if status_id == 1:
		cooldown_label.text = "NEXT QUESTION IN  %0.1f s" % float(player_state["cooldown_remaining"])
	elif status_id == 2:
		cooldown_label.text = "YOU ARE QUALIFIED!"
	else:
		cooldown_label.text = ""

	if _previous_status == 1 and status_id == 0:
		feedback_label.text = "New question ready!"
		feedback_label.add_theme_color_override("font_color", Color(0.15, 0.35, 0.38))
	_previous_status = status_id


func _on_session_time_updated(seconds_remaining: float) -> void:
	_update_timer(seconds_remaining)


func _update_timer(seconds_remaining: float) -> void:
	var total_seconds := int(ceil(seconds_remaining))
	timer_label.text = "%02d:%02d" % [int(total_seconds / 60), total_seconds % 60]


func _on_session_completed(summary: Dictionary) -> void:
	quiz_card.hide()
	result_panel.show()
	result_summary.text = "QUALIFIED: %d\nNOT QUALIFIED: %d\nCORRECT: %d     WRONG: %d" % [
		int(summary["qualified_count"]),
		int(summary["not_qualified_count"]),
		int(summary["correct_count"]),
		int(summary["wrong_count"]),
	]

	var result_lines: PackedStringArray = []
	var player_summaries: Dictionary = summary["players"]
	for player_id in player_summaries.keys():
		var player_state: Dictionary = player_summaries[player_id]
		var status_name: String = quiz_session.call("get_status_name", int(player_state["status"]))
		result_lines.append("%s  —  %s  •  %d right / %d wrong" % [
			str(player_id),
			status_name,
			int(player_state["correct_count"]),
			int(player_state["wrong_count"]),
		])
	player_results.text = "\n".join(result_lines)


func _on_restart_pressed() -> void:
	_start_new_quiz()
