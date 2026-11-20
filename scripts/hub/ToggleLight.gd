# scripts/hub/ToggleLight.gd
class_name ToggleLight
extends InteractableBase

@export var is_on: bool = true
@export var target_light_path: NodePath

func _init() -> void:
	interaction_prompt = "[E] Toggle Light"

func _ready() -> void:
	_sync_light_visibility()

func get_interaction_type() -> String:
	return "TOGGLE"

func interact() -> void:
	is_on = not is_on
	_sync_light_visibility()

func _sync_light_visibility() -> void:
	if target_light_path.is_empty():
		return
	var target_light := get_node_or_null(target_light_path) as Light3D
	if target_light != null:
		target_light.visible = is_on
