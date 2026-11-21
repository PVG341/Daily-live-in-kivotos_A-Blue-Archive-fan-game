# scripts/hub/InteractiveElevator.gd
class_name InteractiveElevator
extends InteractableBase

signal floor_change_started(from_floor: int, to_floor: int)
signal floor_reached(floor_index: int, floor_name: String)

@export var platform_path: NodePath
@export var floor_heights: Array[float] = [0.0, 4.5]
@export var floor_names: Array[String] = ["1F - Schale Lobby", "2F - Sensei Office"]
@export var current_floor_index: int = 0
@export var travel_speed: float = 3.5

var is_moving: bool = false
var _active_tween: Tween = null

func _init() -> void:
	interaction_prompt = "[E] Use Elevator"

func _ready() -> void:
	if not floor_heights.is_empty():
		current_floor_index = clampi(current_floor_index, 0, floor_heights.size() - 1)
	else:
		current_floor_index = 0
	_refresh_prompt()

func _exit_tree() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	is_moving = false

func get_interaction_type() -> String:
	return "ELEVATOR"

func get_current_floor_name() -> String:
	if current_floor_index >= 0 and current_floor_index < floor_names.size():
		return floor_names[current_floor_index]
	return "Floor %d" % (current_floor_index + 1)

func get_floor_height(index: int) -> float:
	if floor_heights.is_empty():
		return 0.0
	var clamped_idx: int = clampi(index, 0, floor_heights.size() - 1)
	return floor_heights[clamped_idx]

func call_to_floor(target_index: int) -> bool:
	if floor_heights.is_empty() or target_index < 0 or target_index >= floor_heights.size():
		return false
	if target_index == current_floor_index:
		return false

	var from_floor: int = current_floor_index
	current_floor_index = target_index
	floor_change_started.emit(from_floor, target_index)

	var platform := get_node_or_null(platform_path) as Node3D
	var target_y: float = floor_heights[target_index]

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null

	if platform != null and is_inside_tree() and travel_speed > 0.0:
		var dist: float = absf(target_y - platform.position.y)
		var dur: float = maxf(0.15, dist / travel_speed)
		is_moving = true
		_refresh_prompt()
		_active_tween = create_tween()
		_active_tween.tween_property(platform, "position:y", target_y, dur) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
		_active_tween.finished.connect(func() -> void: _on_travel_finished(target_index))
	else:
		if platform != null:
			platform.position.y = target_y
		_on_travel_finished(target_index)

	return true

func cycle_next_floor() -> int:
	if floor_heights.size() < 2:
		return current_floor_index
	var next_idx: int = (current_floor_index + 1) % floor_heights.size()
	call_to_floor(next_idx)
	return current_floor_index

func interact() -> void:
	cycle_next_floor()

func _on_travel_finished(target_index: int) -> void:
	is_moving = false
	_active_tween = null
	_refresh_prompt()
	floor_reached.emit(target_index, get_current_floor_name())

func _refresh_prompt() -> void:
	if floor_heights.size() >= 2:
		var next_idx: int = (current_floor_index + 1) % floor_heights.size()
		var next_name: String = floor_names[next_idx] if next_idx < floor_names.size() else "Floor %d" % (next_idx + 1)
		interaction_prompt = "[E] Elevator -> %s" % next_name
	else:
		interaction_prompt = "[E] Use Elevator"
