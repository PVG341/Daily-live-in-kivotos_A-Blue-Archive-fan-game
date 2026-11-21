# scripts/hub/InteractiveDoor.gd
class_name InteractiveDoor
extends InteractableBase

enum DoorStyle {
	SLIDE,
	SWING,
}

signal door_toggled(is_open: bool)

@export var door_style: DoorStyle = DoorStyle.SLIDE
@export var target_door_path: NodePath
@export var slide_offset: Vector3 = Vector3(1.6, 0.0, 0.0)
@export var swing_angle_degrees: float = 90.0
@export var animation_duration: float = 0.4

var is_open: bool = false
var _closed_position: Vector3 = Vector3.ZERO
var _closed_rotation_y: float = 0.0
var _initialized_base: bool = false
var _active_tween: Tween = null

func _init() -> void:
	interaction_prompt = "[E] Open Door"

func _ready() -> void:
	_cache_closed_transform()

func _exit_tree() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null

func get_interaction_type() -> String:
	return "SEAMLESS_DOOR"

func interact() -> void:
	set_open(not is_open)

func set_open(open_state: bool) -> void:
	_cache_closed_transform()
	is_open = open_state
	interaction_prompt = "[E] Close Door" if is_open else "[E] Open Door"

	var target := get_node_or_null(target_door_path) as Node3D
	if target != null:
		if _active_tween != null and _active_tween.is_valid():
			_active_tween.kill()
		_active_tween = null

		if door_style == DoorStyle.SLIDE:
			var target_pos: Vector3 = _closed_position + (slide_offset if is_open else Vector3.ZERO)
			if is_inside_tree() and animation_duration > 0.0:
				_active_tween = create_tween()
				_active_tween.tween_property(target, "position", target_pos, animation_duration) \
					.set_trans(Tween.TRANS_SINE) \
					.set_ease(Tween.EASE_IN_OUT)
			else:
				target.position = target_pos
		else:
			var target_rot_y: float = _closed_rotation_y + (deg_to_rad(swing_angle_degrees) if is_open else 0.0)
			if is_inside_tree() and animation_duration > 0.0:
				_active_tween = create_tween()
				_active_tween.tween_property(target, "rotation:y", target_rot_y, animation_duration) \
					.set_trans(Tween.TRANS_SINE) \
					.set_ease(Tween.EASE_IN_OUT)
			else:
				target.rotation.y = target_rot_y

	door_toggled.emit(is_open)

func _cache_closed_transform() -> void:
	if _initialized_base:
		return
	var target := get_node_or_null(target_door_path) as Node3D
	if target != null:
		_closed_position = target.position
		_closed_rotation_y = target.rotation.y
		_initialized_base = true
