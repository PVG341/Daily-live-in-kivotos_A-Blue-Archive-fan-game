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
@export var drag_pan_sensitivity: float = 0.0022
@export var shake_decay: float = 1.8
@export var max_shake_offset: Vector2 = Vector2(0.45, 0.34)
@export var max_shake_roll: float = 0.025
@export var bounds_min: Vector2 = Vector2(-50.0, -50.0)
@export var bounds_max: Vector2 = Vector2(50.0, 50.0)

var current_zoom: float = 12.0
var yaw_degrees: float = 35.264
var pitch_degrees: float = -45.0
var is_drag_panning: bool = false
var shake_strength: float = 1.0
var trauma: float = 0.0
var _shake_time: float = 0.0
var _last_drag_pos: Vector2 = Vector2.ZERO

var pitch_pivot: Node3D = null
var isometric_camera: Camera3D = null

func _ready() -> void:
	_ensure_input_map()
	_cache_nodes()
	_sync_transforms()

func _process(delta: float) -> void:
	var pan_input: Vector2 = get_keyboard_pan_vector()
	if not pan_input.is_zero_approx():
		pan_planar(pan_input, delta)

	var rot_axis: float = Input.get_axis(&"cam_rotate_right", &"cam_rotate_left")
	if is_zero_approx(rot_axis):
		if Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q):
			rot_axis += 1.0
		if Input.is_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_E):
			rot_axis -= 1.0
	if not is_zero_approx(rot_axis):
		rotate_yaw(rot_axis * rad_to_deg(rotate_speed) * delta)
	tick_shake(delta)

## Adds trauma in [0.0, 1.0] for quadratic decaying camera shake.
func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)

## Advances real-time camera shake decay and applies visual-only offsets on IsometricCamera.
func tick_shake(delta: float) -> void:
	_cache_nodes()
	if isometric_camera == null:
		trauma = maxf(0.0, trauma - shake_decay * maxf(0.0, delta))
		return
	if trauma <= 0.0:
		if not is_zero_approx(isometric_camera.h_offset) or not is_zero_approx(isometric_camera.v_offset) or not is_zero_approx(isometric_camera.rotation.z):
			isometric_camera.h_offset = 0.0
			isometric_camera.v_offset = 0.0
			isometric_camera.rotation.z = 0.0
		return
	var real_dt: float = maxf(0.0, delta) / maxf(Engine.time_scale, 0.0001)
	trauma = maxf(0.0, trauma - shake_decay * real_dt)
	if trauma <= 0.0:
		isometric_camera.h_offset = 0.0
		isometric_camera.v_offset = 0.0
		isometric_camera.rotation.z = 0.0
		return
	var shake: float = trauma * trauma * clampf(shake_strength, 0.0, 1.0)
	_shake_time += real_dt * 30.0
	isometric_camera.h_offset = max_shake_offset.x * shake * sin(_shake_time * 1.7)
	isometric_camera.v_offset = max_shake_offset.y * shake * sin(_shake_time * 2.3)
	isometric_camera.rotation.z = max_shake_roll * shake * sin(_shake_time * 1.1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE)):
			is_drag_panning = mb.pressed
			_last_drag_pos = mb.position
			get_viewport().set_input_as_handled()
			return
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				adjust_zoom(-zoom_speed)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				adjust_zoom(zoom_speed)
	elif event is InputEventMouseMotion and is_drag_panning:
		var mm := event as InputEventMouseMotion
		var delta_px: Vector2 = mm.relative if not mm.relative.is_zero_approx() else (mm.position - _last_drag_pos)
		_last_drag_pos = mm.position
		if not delta_px.is_zero_approx():
			pan_by_screen_delta(delta_px)
		get_viewport().set_input_as_handled()

## Returns combined WASD + Arrow Key planar movement vector regardless of UI focus.
func get_keyboard_pan_vector() -> Vector2:
	var pan_input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if not pan_input.is_zero_approx():
		return pan_input
	var raw := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		raw.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		raw.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		raw.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		raw.y += 1.0
	return raw.normalized() if not raw.is_zero_approx() else Vector2.ZERO

## Pans camera rig from screen-space drag pixels scaled by zoom level and clamped to bounds.
func pan_by_screen_delta(screen_delta: Vector2) -> Vector3:
	var pos: Vector3 = global_position if is_inside_tree() else position
	if not screen_delta.is_zero_approx():
		var yaw_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
		var offset_local := Vector3(-screen_delta.x, 0.0, -screen_delta.y) * (current_zoom * drag_pan_sensitivity)
		var world_offset: Vector3 = yaw_basis * offset_local
		world_offset.y = 0.0
		pos += world_offset
	return _apply_clamped_position(pos)

## Recenters the camera rig XZ position on a world target clamped to bounds.
func center_on_position(target_pos: Vector3) -> Vector3:
	var cur_y: float = global_position.y if is_inside_tree() else position.y
	return _apply_clamped_position(Vector3(target_pos.x, cur_y, target_pos.z))

## Moves camera rig on the XZ plane relative to current yaw and clamps to [bounds_min, bounds_max].
func pan_planar(input_dir: Vector2, delta: float) -> Vector3:
	var pos: Vector3 = global_position if is_inside_tree() else position
	if not input_dir.is_zero_approx() and delta > 0.0:
		var dir2: Vector2 = input_dir.normalized()
		var yaw_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
		var world_dir: Vector3 = yaw_basis * Vector3(dir2.x, 0.0, dir2.y)
		world_dir.y = 0.0
		pos += world_dir * pan_speed * delta
	return _apply_clamped_position(pos)

func _apply_clamped_position(pos: Vector3) -> Vector3:
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
		var keycode: Key = DEFAULT_INPUT_BINDINGS[action]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		_bind_key_if_missing(action, keycode)
	_bind_key_if_missing(&"move_forward", KEY_UP)
	_bind_key_if_missing(&"move_back", KEY_DOWN)
	_bind_key_if_missing(&"move_left", KEY_LEFT)
	_bind_key_if_missing(&"move_right", KEY_RIGHT)

func _bind_key_if_missing(action: StringName, keycode: Key) -> void:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey:
			var k := existing as InputEventKey
			if k.keycode == keycode or k.physical_keycode == keycode:
				return
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
