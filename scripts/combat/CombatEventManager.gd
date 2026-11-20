# scripts/combat/CombatEventManager.gd
class_name CombatEventManager
extends Node

const MIN_ELAPSED_SECONDS: float = 15.0
const EVENT_TYPES: Array[String] = ["ALLY_ARTILLERY", "HIDDEN_BOSS", "THIRD_PARTY"]

var event_bus: Node = null
var last_triggered_event: Dictionary = {}

## Evaluates whether a random battlefield event triggers; blocked before 15s, during card draft, or on non-positive room indices.
func check_for_random_event(elapsed_time: float, room_index: int, is_draft_open: bool = false, force_roll: float = -1.0) -> Variant:
	if elapsed_time < MIN_ELAPSED_SECONDS or is_draft_open or room_index <= 0:
		return null

	var chance: float = clampf(0.05 * float(room_index), 0.05, 0.50)
	var roll: float = force_roll if force_roll >= 0.0 else randf()
	if roll > chance:
		return null

	var event_type: String = EVENT_TYPES[randi() % EVENT_TYPES.size()]
	return {
		"type": event_type,
		"room_index": room_index,
		"elapsed_time": elapsed_time,
	}

## Records the event and emits EventBus.combat_event_triggered.
func trigger_event(event: Dictionary) -> bool:
	if event.is_empty() or not event.has("type"):
		return false
	last_triggered_event = event.duplicate(true)
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_signal(&"combat_event_triggered"):
		bus.combat_event_triggered.emit(str(event["type"]))
	return true

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		return loop.root.get_node_or_null("EventBus")
	return null
