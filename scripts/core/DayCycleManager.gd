# scripts/core/DayCycleManager.gd
extends Node

const WAKE_UP_HOUR: float = 7.0
const LATE_WAKE_UP_HOUR: float = 10.5
const FORCED_SLEEP_HOUR: float = 3.0
const FATIGUE_PENALTY_RATIO: float = 0.7

var current_day: int = 1
var current_hour: float = WAKE_UP_HOUR
var current_ap: int = 100
var max_ap: int = 100

var event_bus: Node = null

func consume_ap(amount: int) -> bool:
	if amount < 0:
		return false
	if current_ap < amount:
		return false
	current_ap -= amount
	_emit_ap_changed()
	return true

func restore_ap(amount: int) -> void:
	if amount <= 0:
		return
	current_ap = clampi(current_ap + amount, 0, max_ap)
	_emit_ap_changed()

func advance_day() -> void:
	current_day += 1
	current_hour = WAKE_UP_HOUR
	current_ap = max_ap
	_emit_ap_changed()
	_emit_day_advanced(false)

func advance_time(hours: float) -> void:
	if hours <= 0.0:
		return

	if is_forced_sleep_hour():
		_force_sleep()
		return

	var elapsed = _time_since_morning(current_hour) + hours
	var forced_sleep_threshold = _time_since_morning(FORCED_SLEEP_HOUR)

	if elapsed >= forced_sleep_threshold:
		_force_sleep()
	else:
		current_hour = fmod(current_hour + hours, 24.0)

func _force_sleep() -> void:
	current_day += 1
	current_hour = LATE_WAKE_UP_HOUR
	current_ap = int(max_ap * FATIGUE_PENALTY_RATIO)
	_emit_ap_changed()
	_emit_day_advanced(true)

func _time_since_morning(h: float) -> float:
	if h >= WAKE_UP_HOUR:
		return h - WAKE_UP_HOUR
	else:
		return h + 24.0 - WAKE_UP_HOUR

func get_time_of_day() -> String:
	if current_hour >= 22.0 or current_hour < 7.0:
		return "NIGHT"
	elif current_hour < 12.0:
		return "MORNING"
	elif current_hour < 18.0:
		return "AFTERNOON"
	else:
		return "EVENING"

func is_forced_sleep_hour() -> bool:
	return current_hour >= FORCED_SLEEP_HOUR and current_hour < WAKE_UP_HOUR

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop = Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("EventBus")
	return null

func _emit_ap_changed() -> void:
	var bus = _get_event_bus()
	if bus and bus.has_signal("ap_changed"):
		bus.ap_changed.emit(current_ap, max_ap)

func _emit_day_advanced(fatigue_penalty: bool) -> void:
	var bus = _get_event_bus()
	if bus and bus.has_signal("day_advanced"):
		bus.day_advanced.emit(current_day, fatigue_penalty)
