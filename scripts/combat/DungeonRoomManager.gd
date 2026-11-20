# scripts/combat/DungeonRoomManager.gd
class_name DungeonRoomManager
extends Node

signal room_loaded(room_index: int, room_data: Dictionary)
signal dungeon_completed()

var layout: Array[Dictionary] = []
var current_room_index: int = 0
var squad_hp: Dictionary = {}
var is_draft_open: bool = false
var event_bus: Node = null
var current_room_node: Node = null

## Initializes a dungeon run with the given layout and emits room_loaded for room 0 if non-empty.
func start_dungeon(p_layout: Array[Dictionary]) -> void:
	if current_room_node != null and is_instance_valid(current_room_node):
		if current_room_node.is_inside_tree():
			current_room_node.queue_free()
		else:
			current_room_node.free()
	current_room_node = null
	layout = p_layout.duplicate(true)
	current_room_index = 0
	is_draft_open = false
	if not layout.is_empty():
		room_loaded.emit(0, layout[0])

## Returns the current room index.
func get_current_room_index() -> int:
	return current_room_index

## Stores a deep copy of persistent squad HP keyed by student_id.
func set_squad_hp(hp_map: Dictionary) -> void:
	squad_hp = hp_map.duplicate(true)

## Returns a deep copy of persistent squad HP state.
func get_squad_persistent_state() -> Dictionary:
	return squad_hp.duplicate(true)

## Marks the current room cleared, opens the card draft, and emits EventBus.combat_room_cleared.
func mark_current_room_cleared() -> void:
	is_draft_open = true
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_signal(&"combat_room_cleared"):
		bus.combat_room_cleared.emit(current_room_index)

## Frees the active room node, closes the draft, and advances to the next room or completes the dungeon.
func advance_to_next_room() -> bool:
	if is_instance_valid(current_room_node):
		current_room_node.queue_free()
	current_room_node = null
	is_draft_open = false

	if layout.is_empty():
		return false

	if current_room_index + 1 < layout.size():
		current_room_index += 1
		room_loaded.emit(current_room_index, layout[current_room_index])
		return true

	current_room_index = layout.size()
	dungeon_completed.emit()
	return false

## Returns true once all rooms in a non-empty layout have been cleared and advanced past.
func is_dungeon_complete() -> bool:
	return not layout.is_empty() and current_room_index >= layout.size()

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		return loop.root.get_node_or_null("EventBus")
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if current_room_node != null and is_instance_valid(current_room_node):
			if not current_room_node.is_inside_tree() and not current_room_node.is_queued_for_deletion():
				current_room_node.free()
			current_room_node = null
