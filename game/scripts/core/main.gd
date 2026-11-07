extends Node

@onready var scene_container: Node = $SceneContainer


func change_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("Scene resource does not exist: %s" % scene_path)
		return

	var scene_resource: Resource = load(scene_path)
	if not scene_resource is PackedScene:
		push_error("Resource is not a PackedScene: %s" % scene_path)
		return

	var new_scene: Node = scene_resource.instantiate()
	if new_scene == null:
		push_error("Could not instantiate scene: %s" % scene_path)
		return

	for previous_scene in scene_container.get_children():
		scene_container.remove_child(previous_scene)
		previous_scene.queue_free()

	scene_container.add_child(new_scene)
