extends Node3D
class_name TerritoryGrid

## Maps world positions to tiles and keeps authoritative local score counts.

signal scores_changed(red_score: int, blue_score: int)

const TEAM_NONE := 0
const TEAM_RED := 1
const TEAM_BLUE := 2
const TILE_SCENE = preload("res://scenes/arena/TerritoryTile.tscn")

@export_range(1, 32, 1) var columns := 8
@export_range(1, 32, 1) var rows := 8
@export var tile_spacing := 1.05

var red_score := 0
var blue_score := 0
var capture_enabled := true
var _tiles: Array[Node3D] = []


func _ready() -> void:
	if _tiles.is_empty():
		for child in get_children():
			if child is Node3D and child.has_method("set_owner_team"):
				_tiles.append(child as Node3D)

	var expected_count := columns * rows
	if _tiles.size() != expected_count:
		push_error("Territory grid expects %d tiles, but found %d." % [expected_count, _tiles.size()])
		return

	_reset_scores()


func build_grid(grid_cols: int, grid_rows: int) -> void:
	columns = grid_cols
	rows = grid_rows
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_tiles.clear()

	var half_width := float(columns) * tile_spacing * 0.5
	var half_depth := float(rows) * tile_spacing * 0.5
	for r in range(rows):
		for c in range(columns):
			var tile: Node3D = TILE_SCENE.instantiate() as Node3D
			tile.name = "Tile_%d_%d" % [r, c]
			var x := -half_width + (float(c) + 0.5) * tile_spacing
			var z := -half_depth + (float(r) + 0.5) * tile_spacing
			tile.position = Vector3(x, 0.0, z)
			add_child(tile)
			_tiles.append(tile)

	_reset_scores()


func get_tile_count() -> int:
	return _tiles.size()


func get_grid_dimensions() -> Vector2i:
	return Vector2i(columns, rows)


func get_tile_coordinates(world_position: Vector3) -> Vector2i:
	var local_position := to_local(world_position)
	var half_width := float(columns) * tile_spacing * 0.5
	var half_depth := float(rows) * tile_spacing * 0.5
	var column := int(floor((local_position.x + half_width) / tile_spacing))
	var row := int(floor((local_position.z + half_depth) / tile_spacing))
	if column < 0 or column >= columns or row < 0 or row >= rows:
		return Vector2i(-1, -1)
	return Vector2i(column, row)


func claim_tile_from_network(col: int, row: int, team_id: int, r_score: int, b_score: int) -> void:
	if col < 0 or col >= columns or row < 0 or row >= rows:
		return
	var tile_index := row * columns + col
	if tile_index < _tiles.size():
		_tiles[tile_index].call("set_owner_team", team_id)
	red_score = r_score
	blue_score = b_score
	scores_changed.emit(red_score, blue_score)


func claim_at_global_position(world_position: Vector3, team_id: int) -> bool:
	if not capture_enabled or (team_id != TEAM_RED and team_id != TEAM_BLUE):
		return false

	var local_position := to_local(world_position)
	var half_width := float(columns) * tile_spacing * 0.5
	var half_depth := float(rows) * tile_spacing * 0.5
	var column := int(floor((local_position.x + half_width) / tile_spacing))
	var row := int(floor((local_position.z + half_depth) / tile_spacing))

	if column < 0 or column >= columns or row < 0 or row >= rows:
		return false

	var tile_index := row * columns + column
	if tile_index >= _tiles.size():
		return false

	var tile: Node3D = _tiles[tile_index]
	var previous_owner := int(tile.get("owner_team"))
	if not bool(tile.call("set_owner_team", team_id)):
		return false

	# Only adjust counts after a real ownership change, so repeated samples
	# while standing on the same tile can never award duplicate points.
	if previous_owner == TEAM_RED:
		red_score -= 1
	elif previous_owner == TEAM_BLUE:
		blue_score -= 1

	if team_id == TEAM_RED:
		red_score += 1
	else:
		blue_score += 1

	scores_changed.emit(red_score, blue_score)
	return true


func reset_grid() -> void:
	for tile in _tiles:
		tile.call("reset_owner")
	_reset_scores()


func _reset_scores() -> void:
	red_score = 0
	blue_score = 0
	scores_changed.emit(red_score, blue_score)
