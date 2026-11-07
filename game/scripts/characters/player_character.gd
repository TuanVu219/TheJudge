extends CharacterBody3D
class_name PlayerCharacter

## A lightweight, reusable cartoon player character.
## Movement and networking are intentionally left for a later step.

@onready var display_name_label: Label3D = $DisplayName
@onready var body_mesh: MeshInstance3D = $VisualRoot/Body/Bean
@onready var shirt_mesh: MeshInstance3D = $VisualRoot/Body/Shirt
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var accessories: Node3D = $VisualRoot/Accessories


func _ready() -> void:
	# Give each character its own body material so player colors do not leak
	# between instances of this scene.
	var shared_body_material := body_mesh.material_override as ShaderMaterial
	if shared_body_material != null:
		body_mesh.material_override = shared_body_material.duplicate()

	var shared_shirt_material := shirt_mesh.material_override as ShaderMaterial
	if shared_shirt_material != null:
		shirt_mesh.material_override = shared_shirt_material.duplicate()

	animation_player.play("idle")


func set_display_name(value: String) -> void:
	display_name_label.text = value


func set_display_name_visible(value: bool) -> void:
	display_name_label.visible = value


func set_body_color(color: Color) -> void:
	var body_material := body_mesh.material_override as ShaderMaterial
	if body_material != null:
		body_material.set_shader_parameter("albedo_color", color)


func set_accessory_visible(accessory_name: String, value: bool) -> void:
	var accessory := accessories.get_node_or_null(accessory_name)
	if accessory != null:
		accessory.visible = value
	else:
		push_warning("Accessory '%s' was not found." % accessory_name)


func play_emote(emote_name: String) -> void:
	# These are placeholders until the character gets emote animations.
	match emote_name:
		"wave":
			print("%s waves hello!" % display_name_label.text)
		"laugh":
			print("%s laughs." % display_name_label.text)
		"shrug":
			print("%s gives a goofy shrug." % display_name_label.text)
		"facepalm":
			print("%s facepalms." % display_name_label.text)
		_:
			print("No emote named '%s' is ready yet." % emote_name)
