# scripts/hub/ElevatorCallButton.gd
class_name ElevatorCallButton
extends InteractableBase

@export var elevator_path: NodePath
@export var target_floor_index: int = 0

func _init() -> void:
	interaction_prompt = "[E] Call Elevator"

func get_interaction_type() -> String:
	return "ELEVATOR_CALL"

func interact() -> void:
	var elevator := get_node_or_null(elevator_path)
	if elevator != null and elevator.has_method(&"call_to_floor"):
		elevator.call_to_floor(target_floor_index)
