# scripts/hub/MissionTerminal.gd
class_name MissionTerminal
extends InteractableBase

signal terminal_activated(terminal: Node)

func _init() -> void:
	interaction_prompt = "[E] Bảng Nhiệm vụ Xuất kích"

func get_interaction_type() -> String:
	return "MISSION_TERMINAL"

func interact() -> void:
	terminal_activated.emit(self)
