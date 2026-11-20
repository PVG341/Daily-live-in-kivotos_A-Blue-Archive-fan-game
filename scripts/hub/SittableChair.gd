# scripts/hub/SittableChair.gd
class_name SittableChair
extends InteractableBase

@export var seat_offset: Vector3 = Vector3(0.0, 0.5, 0.0)

var is_occupied: bool = false

func _init() -> void:
	interaction_prompt = "[E] Sit"

func get_interaction_type() -> String:
	return "SIT"

func interact() -> void:
	is_occupied = not is_occupied
