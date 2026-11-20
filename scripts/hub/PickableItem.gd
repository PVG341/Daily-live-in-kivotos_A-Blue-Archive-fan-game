# scripts/hub/PickableItem.gd
class_name PickableItem
extends InteractableBase

@export var item_data: ItemData
@export var quantity: int = 1

var event_bus: Node = null

func _init() -> void:
	interaction_prompt = "[E] Pick up"

func get_interaction_type() -> String:
	return "PICKUP"

func interact() -> void:
	if item_data != null and quantity > 0:
		var bus := _get_event_bus()
		if bus != null and bus.has_signal(&"item_picked_up"):
			bus.item_picked_up.emit(item_data.id, quantity)
	queue_free()

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("EventBus")
	return null
