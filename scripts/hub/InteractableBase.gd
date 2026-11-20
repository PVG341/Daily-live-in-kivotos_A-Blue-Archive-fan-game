# scripts/hub/InteractableBase.gd
class_name InteractableBase
extends Area3D

@export var interaction_prompt: String = "[E] Interact"

func interact() -> void:
	pass

func get_interaction_type() -> String:
	return "GENERIC"
