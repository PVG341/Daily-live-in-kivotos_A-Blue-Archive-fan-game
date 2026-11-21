# scripts/hub/SenseiController.gd
class_name SenseiController
extends CharacterBody3D

signal interactable_focused(prompt_text: String, target: Object)

const DEFAULT_INPUT_BINDINGS := {
	&"move_forward": KEY_W,
	&"move_back": KEY_S,
	&"move_left": KEY_A,
	&"move_right": KEY_D,
	&"jump": KEY_SPACE,
	&"sprint": KEY_SHIFT,
	&"interact": KEY_E,
	&"toggle_camera": KEY_V,
}

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var interact_distance: float = 2.0

var camera_state: CameraModeState
var interact_raycast: RayCast3D
var tps_camera: Camera3D
var fps_camera: Camera3D
var spring_arm: SpringArm3D
var head_pivot: Node3D
var proximity_area: Area3D

var is_sitting: bool = false
var active_chair: SittableChair = null
var _pre_sit_position: Vector3 = Vector3.ZERO
var _current_interactable: Object = null
var _current_prompt: String = ""

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _init() -> void:
	camera_state = CameraModeState.new()

func _ready() -> void:
	_ensure_input_map()
	_cache_nodes()
	_apply_settings_draw_distance()
	if interact_raycast:
		interact_raycast.target_position = Vector3(0.0, 0.0, -interact_distance)
		interact_raycast.collide_with_areas = true
		interact_raycast.collide_with_bodies = true
	_restore_camera_mode()
	_sync_cameras()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if head_pivot:
			head_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			head_pivot.rotation.x = clampf(
				head_pivot.rotation.x,
				deg_to_rad(-80.0),
				deg_to_rad(80.0)
			)
	elif event.is_action_pressed(&"toggle_camera"):
		toggle_camera_mode()
	elif event.is_action_pressed(&"interact"):
		try_interact()

func _physics_process(delta: float) -> void:
	if is_sitting:
		if active_chair == null or not is_instance_valid(active_chair):
			stand_up()
		elif Input.is_action_just_pressed(&"jump"):
			stand_up()
		else:
			if is_inside_tree():
				global_position = active_chair.get_seat_world_position()
			else:
				position = active_chair.get_seat_world_position()
			velocity = Vector3.ZERO
			_update_interactable_focus()
			return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_velocity

	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var is_sprinting := Input.is_action_pressed(&"sprint")
	var desired := compute_desired_horizontal_velocity(input_dir, transform.basis, is_sprinting)
	velocity.x = desired.x
	velocity.z = desired.z

	move_and_slide()
	_update_interactable_focus()

func toggle_camera_mode() -> int:
	_cache_nodes()
	var new_mode: int = camera_state.toggle()
	if is_inside_tree():
		var ztm := get_node_or_null("/root/ZoneTransitionManager")
		if ztm != null and &"active_camera_mode" in ztm:
			ztm.set(&"active_camera_mode", new_mode)
	_sync_cameras()
	return new_mode

func compute_desired_horizontal_velocity(
	input_dir: Vector2,
	basis_transform: Basis,
	is_sprinting: bool
) -> Vector3:
	if input_dir.is_zero_approx():
		return Vector3.ZERO
	var raw_dir := basis_transform * Vector3(input_dir.x, 0.0, input_dir.y)
	raw_dir.y = 0.0
	if raw_dir.is_zero_approx():
		return Vector3.ZERO
	var speed := sprint_speed if is_sprinting else walk_speed
	return raw_dir.normalized() * speed

func get_focused_interactable() -> Object:
	_cache_nodes()
	if interact_raycast != null:
		if interact_raycast.is_inside_tree():
			interact_raycast.force_raycast_update()
		if interact_raycast.is_colliding():
			var collider := interact_raycast.get_collider()
			if collider != null and collider.has_method(&"interact"):
				return collider

	if proximity_area != null and proximity_area.is_inside_tree():
		var origin: Vector3 = global_position if is_inside_tree() else position
		var closest_area: Area3D = null
		var closest_dist_sq: float = INF
		for area in proximity_area.get_overlapping_areas():
			if area != null and is_instance_valid(area) and area.has_method(&"interact"):
				var dist_sq: float = origin.distance_squared_to(area.global_position)
				if dist_sq < closest_dist_sq:
					closest_dist_sq = dist_sq
					closest_area = area
		if closest_area != null:
			return closest_area

	return null

func sit_on_chair(chair: SittableChair) -> void:
	if chair == null or not is_instance_valid(chair):
		return
	_pre_sit_position = global_position if is_inside_tree() else position
	if not chair.is_occupied:
		chair.interact()
	active_chair = chair
	is_sitting = true
	velocity = Vector3.ZERO
	var seat_pos: Vector3 = chair.get_seat_world_position()
	if is_inside_tree():
		global_position = seat_pos
	else:
		position = seat_pos

func stand_up() -> void:
	if not is_sitting:
		return
	if active_chair != null and is_instance_valid(active_chair) and active_chair.is_occupied:
		active_chair.interact()
	if is_inside_tree():
		global_position = _pre_sit_position
	else:
		position = _pre_sit_position
	is_sitting = false
	active_chair = null
	velocity = Vector3.ZERO

func try_interact() -> Object:
	if is_sitting:
		var chair := active_chair
		stand_up()
		_update_interactable_focus()
		return chair
	var target := get_focused_interactable()
	if target == null:
		return null
	if target is SittableChair:
		sit_on_chair(target as SittableChair)
		_update_interactable_focus()
		return target
	target.interact()
	_update_interactable_focus()
	return target

func _update_interactable_focus() -> void:
	var target: Object = null
	var prompt: String = ""
	if is_sitting:
		target = active_chair
		prompt = "[E] Stand up"
	else:
		target = get_focused_interactable()
		if target != null and is_instance_valid(target):
			var raw_prompt: Variant = target.get(&"interaction_prompt")
			prompt = str(raw_prompt) if raw_prompt != null and not str(raw_prompt).is_empty() else "[E] Interact"

	if target != _current_interactable or prompt != _current_prompt:
		_current_interactable = target
		_current_prompt = prompt
		interactable_focused.emit(prompt, target)

func _ensure_input_map() -> void:
	for action: StringName in DEFAULT_INPUT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = DEFAULT_INPUT_BINDINGS[action]
			InputMap.action_add_event(action, event)

func _cache_nodes() -> void:
	if head_pivot == null:
		head_pivot = get_node_or_null("HeadPivot") as Node3D
	if fps_camera == null:
		fps_camera = get_node_or_null("HeadPivot/FPSCamera") as Camera3D
	if spring_arm == null:
		spring_arm = get_node_or_null("HeadPivot/SpringArm3D") as SpringArm3D
	if tps_camera == null:
		tps_camera = get_node_or_null("HeadPivot/SpringArm3D/TPSCamera") as Camera3D
	if interact_raycast == null:
		interact_raycast = get_node_or_null("HeadPivot/InteractRayCast") as RayCast3D
	if proximity_area == null:
		proximity_area = get_node_or_null("ProximityArea") as Area3D

func _sync_cameras() -> void:
	var fps_active := camera_state.is_fps()
	if fps_camera:
		fps_camera.current = fps_active
	if tps_camera:
		tps_camera.current = not fps_active

func _restore_camera_mode() -> void:
	if not is_inside_tree():
		return
	var ztm := get_node_or_null("/root/ZoneTransitionManager")
	if ztm == null:
		return
	var saved_mode: Variant = ztm.get(&"active_camera_mode")
	if saved_mode == null:
		return
	var mode_int: int = int(saved_mode)
	if mode_int == CameraModeState.CameraMode.FPS or mode_int == CameraModeState.CameraMode.TPS:
		camera_state.current_mode = mode_int

func _exit_tree() -> void:
	is_sitting = false
	active_chair = null
	_current_interactable = null
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed") and sm.settings_changed.is_connected(_apply_settings_draw_distance):
		sm.settings_changed.disconnect(_apply_settings_draw_distance)

func _apply_settings_draw_distance() -> void:
	if not is_inside_tree():
		return
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	var draw_dist_val: Variant = sm.get(&"current_draw_distance")
	if draw_dist_val == null:
		return
	var draw_dist: float = float(draw_dist_val)
	if fps_camera != null:
		fps_camera.far = draw_dist
	if tps_camera != null:
		tps_camera.far = draw_dist
	if sm.has_signal("settings_changed") and not sm.settings_changed.is_connected(_apply_settings_draw_distance):
		sm.settings_changed.connect(_apply_settings_draw_distance)
