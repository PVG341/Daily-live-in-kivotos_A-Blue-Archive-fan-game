# scripts/hub/DoorPortal.gd
class_name DoorPortal
extends InteractableBase

@export var target_scene_path: String = ""
@export var spawn_point_id: String = "default"

var zone_transition_manager: Node = null

func _init() -> void:
	interaction_prompt = "[E] Enter"

func get_interaction_type() -> String:
	return "DOOR"

func interact() -> void:
	if target_scene_path.is_empty():
		return
	var ztm := _get_zone_transition_manager()
	if ztm != null and ztm.has_method(&"transition_to"):
		ztm.transition_to(target_scene_path, spawn_point_id)

func _get_zone_transition_manager() -> Node:
	if zone_transition_manager != null:
		return zone_transition_manager
	if is_inside_tree():
		return get_node_or_null("/root/ZoneTransitionManager")
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("ZoneTransitionManager")
	return null
