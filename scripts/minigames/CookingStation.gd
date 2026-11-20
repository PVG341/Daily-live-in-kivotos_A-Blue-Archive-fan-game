# scripts/minigames/CookingStation.gd
class_name CookingStation
extends InteractableBase

const CookingManagerScript := preload("res://scripts/minigames/CookingManager.gd")

var cooking_manager: CookingManagerScript
var is_cooking_active: bool = false

func _init() -> void:
	interaction_prompt = "[E] Cook"
	cooking_manager = CookingManagerScript.new()

func _ready() -> void:
	_sync_ui_state()

func _process(delta: float) -> void:
	if not is_cooking_active or cooking_manager == null:
		return
	var pos: float = cooking_manager.advance_indicator(delta)
	var bar := get_node_or_null("CookingUI/TimingIndicatorBar") as ProgressBar
	if bar != null:
		bar.value = pos * 100.0

func get_interaction_type() -> String:
	return "COOK"

func interact() -> void:
	is_cooking_active = not is_cooking_active
	_sync_ui_state()

func _sync_ui_state() -> void:
	var ui := get_node_or_null("CookingUI") as CanvasLayer
	if ui != null:
		ui.visible = is_cooking_active
