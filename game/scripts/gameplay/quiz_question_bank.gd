extends RefCounted

## Loads quiz content from JSON and deals from a shuffled, non-repeating deck.

const QUESTION_DATA_PATH := "res://resources/quiz_questions.json"

var _all_questions: Array[Dictionary] = []
var _deck: Array[Dictionary] = []


func load_question_data() -> bool:
	if not _all_questions.is_empty():
		return true

	if not FileAccess.file_exists(QUESTION_DATA_PATH):
		push_error("Quiz question data was not found: %s" % QUESTION_DATA_PATH)
		return false

	var json_text := FileAccess.get_file_as_string(QUESTION_DATA_PATH)
	var parsed_data: Variant = JSON.parse_string(json_text)
	if not parsed_data is Array:
		push_error("Quiz question data must be a JSON array.")
		return false

	var seen_ids: Dictionary = {}
	for item in parsed_data:
		if not item is Dictionary or not _is_valid_question(item):
			push_error("Quiz question data contains an invalid question entry.")
			_all_questions.clear()
			return false

		var question_id := str(item["id"])
		if seen_ids.has(question_id):
			push_error("Duplicate quiz question id: %s" % question_id)
			_all_questions.clear()
			return false
		seen_ids[question_id] = true
		_all_questions.append(item.duplicate(true))

	return not _all_questions.is_empty()


func start_session() -> void:
	if not load_question_data():
		return

	_deck = _all_questions.duplicate(true)
	_deck.shuffle()


func draw_next_question() -> Dictionary:
	if _all_questions.is_empty() and not load_question_data():
		return {}

	# Only reshuffle after every question has been used once this session.
	if _deck.is_empty():
		_deck = _all_questions.duplicate(true)
		_deck.shuffle()

	return _deck.pop_back().duplicate(true)


func get_question_count() -> int:
	if _all_questions.is_empty():
		load_question_data()
	return _all_questions.size()


func get_all_questions() -> Array[Dictionary]:
	if _all_questions.is_empty():
		load_question_data()
	return _all_questions.duplicate(true)


func _is_valid_question(question: Dictionary) -> bool:
	var required_keys := ["id", "category", "difficulty", "prompt", "options", "correct_index", "explanation"]
	for key in required_keys:
		if not question.has(key):
			return false

	var options: Variant = question["options"]
	if not options is Array or options.size() != 4:
		return false

	var answer_index := int(question["correct_index"])
	if answer_index < 0 or answer_index > 3:
		return false

	return not str(question["id"]).is_empty() and not str(question["prompt"]).is_empty()
