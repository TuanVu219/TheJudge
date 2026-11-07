extends Node3D
class_name TerritoryTile

## A single editable tile in the territory grid.

const TEAM_NONE := 0
const TEAM_RED := 1
const TEAM_BLUE := 2

@export var neutral_color := Color(0.84, 0.85, 0.78)
@export var red_color := Color(0.94, 0.22, 0.30)
@export var blue_color := Color(0.12, 0.43, 0.96)

@onready var tile_surface: MeshInstance3D = $TileSurface

var owner_team := TEAM_NONE
var _surface_material: StandardMaterial3D


func _ready() -> void:
	# Every tile gets its own material so a color change affects only this tile.
	var shared_material := tile_surface.material_override as StandardMaterial3D
	if shared_material != null:
		_surface_material = shared_material.duplicate() as StandardMaterial3D
		tile_surface.material_override = _surface_material
	_apply_owner_color()


func set_owner_team(team_id: int) -> bool:
	if team_id < TEAM_NONE or team_id > TEAM_BLUE:
		push_warning("Unknown team id %d; tile ownership was not changed." % team_id)
		return false

	if owner_team == team_id:
		return false

	owner_team = team_id
	_apply_owner_color()
	return true


func reset_owner() -> void:
	owner_team = TEAM_NONE
	_apply_owner_color()


func _apply_owner_color() -> void:
	if _surface_material == null:
		return

	match owner_team:
		TEAM_RED:
			_surface_material.albedo_color = red_color
		TEAM_BLUE:
			_surface_material.albedo_color = blue_color
		_:
			_surface_material.albedo_color = neutral_color
