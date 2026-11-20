# scripts/combat/RTSCamera3D.gd
class_name RTSCamera3D
extends Node3D

const DEFAULT_INPUT_BINDINGS := {
	&"move_forward": KEY_W,
	&"move_back": KEY_S,
	&"move_left": KEY_A,
	&"move_right": KEY_D,
	&"cam_rotate_left": KEY_Q,
	&"cam_rotate_right": KEY_E,
}

@export var pan_speed: float = 15.0
@export var rotate_speed: float = 1.8
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 25.0
@export var bounds_min: Vector2 = Vector2(-50.0, -50.0)
@export var bounds_max: Vector2 = Vector2(50.0, 50.0)

var current_zoom: float = 12.0
var yaw_degrees: float = 35.264
var pitch_degrees: float = -45.0

var pitch_pivot: Node3D = null
var isometric_camera: Camera3D = null

func _ready() -> void:
	_ensure_input_map()
	_cache_nodes()
	_sync_transforms()

func _process(delta: float) -> void:
	var pan_input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if not pan_input.is_zero_approx():
		pan_planar(pan_input, delta)

	var rot_axis: float = Input.get_axis(&"cam_rotate_right", &"cam_rotate_left")
	if not is_zero_approx(rot_axis):
		rotate_yaw(rot_axis * rad_to_deg(rotate_speed) * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			adjust_zoom(-zoom_speed)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			adjust_zoom(zoom_speed)

## Moves camera rig on the XZ plane relative to current yaw and clamps to [bounds_min, bounds_max].
func pan_planar(input_dir: Vector2, delta: float) -> Vector3:
	var pos: Vector3 = global_position if is_inside_tree() else position
	if not input_dir.is_zero_approx() and delta > 0.0:
		var dir2: Vector2 = input_dir.normalized()
		var yaw_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
		var world_dir: Vector3 = yaw_basis * Vector3(dir2.x, 0.0, dir2.y)
		world_dir.y = 0.0
		pos += world_dir * pan_speed * delta

	var min_x: float = minf(bounds_min.x, bounds_max.x)
	var max_x: float = maxf(bounds_min.x, bounds_max.x)
	var min_z: float = minf(bounds_min.y, bounds_max.y)
	var max_z: float = maxf(bounds_min.y, bounds_max.y)
	pos.x = clampf(pos.x, min_x, max_x)
	pos.z = clampf(pos.z, min_z, max_z)

	if is_inside_tree():
		global_position = pos
	else:
		position = pos
	return pos

## Rotates camera rig yaw in degrees and applies the updated Y rotation.
func rotate_yaw(delta_degrees: float) -> float:
	yaw_degrees += delta_degrees
	rotation.y = deg_to_rad(yaw_degrees)
	return yaw_degrees

## Adjusts camera zoom distance and clamps it within [min_zoom, max_zoom].
func adjust_zoom(delta_zoom: float) -> float:
	var low: float = minf(min_zoom, max_zoom)
	var high: float = maxf(min_zoom, max_zoom)
	current_zoom = clampf(current_zoom + delta_zoom, low, high)
	_cache_nodes()
	if isometric_camera != null:
		isometric_camera.position = Vector3(0.0, 0.0, current_zoom)
	return current_zoom

func _cache_nodes() -> void:
	if pitch_pivot == null:
		pitch_pivot = get_node_or_null("PitchPivot") as Node3D
	if isometric_camera == null:
		isometric_camera = get_node_or_null("PitchPivot/IsometricCamera") as Camera3D

func _sync_transforms() -> void:
	rotation.y = deg_to_rad(yaw_degrees)
	if pitch_pivot != null:
		pitch_pivot.rotation.x = deg_to_rad(pitch_degrees)
	if isometric_camera != null:
		isometric_camera.position = Vector3(0.0, 0.0, current_zoom)

func _ensure_input_map() -> void:
	for action: StringName in DEFAULT_INPUT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = DEFAULT_INPUT_BINDINGS[action]
			InputMap.action_add_event(action, ev)
