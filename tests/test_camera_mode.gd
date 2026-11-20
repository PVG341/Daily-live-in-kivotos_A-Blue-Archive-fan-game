# tests/test_camera_mode.gd
extends SceneTree

var _failed: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _init() -> void:
	_run_tests()

	if _failed:
		quit(1)
		return

	print("PASS: test_camera_mode")
	quit(0)

func _run_tests() -> void:
	# 1. Test CameraModeState
	var cam_script = load("res://scripts/hub/CameraModeState.gd")
	if not check(cam_script != null, "CameraModeState.gd must load"):
		return
	var cam_state = cam_script.new()
	check(cam_state.current_mode == cam_script.CameraMode.TPS, "Default camera mode must be TPS")
	check(cam_state.is_tps() == true, "is_tps() must be true by default")
	check(cam_state.is_fps() == false, "is_fps() must be false by default")

	var next_mode = cam_state.toggle()
	check(next_mode == cam_script.CameraMode.FPS, "First toggle() must return FPS")
	check(cam_state.current_mode == cam_script.CameraMode.FPS, "current_mode must be FPS after first toggle")
	check(cam_state.is_fps() == true, "is_fps() must be true in FPS mode")
	check(cam_state.is_tps() == false, "is_tps() must be false in FPS mode")

	var back_mode = cam_state.toggle()
	check(back_mode == cam_script.CameraMode.TPS, "Second toggle() must return TPS")
	check(cam_state.current_mode == cam_script.CameraMode.TPS, "current_mode must be TPS after second toggle")
	check(cam_state.is_tps() == true, "is_tps() must be true after toggling back")
	check(cam_state.is_fps() == false, "is_fps() must be false after toggling back")

	# 2. Test SenseiController logic
	var sensei_script = load("res://scripts/hub/SenseiController.gd")
	if not check(sensei_script != null, "SenseiController.gd must load"):
		return
	var controller = sensei_script.new()
	if not check(controller != null, "SenseiController must instantiate"):
		return

	check(controller.camera_state != null, "camera_state must be initialized in _init()")
	check(controller.camera_state.current_mode == cam_script.CameraMode.TPS, "Controller camera_state must start in TPS")

	# Zero input
	var zero_vel: Vector3 = controller.compute_desired_horizontal_velocity(Vector2.ZERO, Basis.IDENTITY, false)
	check(zero_vel.is_equal_approx(Vector3.ZERO), "Zero input must produce zero horizontal velocity")

	# Walk forward (input_dir.y = -1 in Godot forward convention or normalized direction)
	var walk_vel: Vector3 = controller.compute_desired_horizontal_velocity(Vector2(0.0, -1.0), Basis.IDENTITY, false)
	check(is_equal_approx(walk_vel.length(), controller.walk_speed), "Walk velocity magnitude must equal walk_speed (5.0), got: %f" % walk_vel.length())
	check(is_equal_approx(walk_vel.y, 0.0), "Horizontal velocity must have y == 0")

	# Sprint forward
	var sprint_vel: Vector3 = controller.compute_desired_horizontal_velocity(Vector2(0.0, -1.0), Basis.IDENTITY, true)
	check(is_equal_approx(sprint_vel.length(), controller.sprint_speed), "Sprint velocity magnitude must equal sprint_speed (8.5), got: %f" % sprint_vel.length())
	check(is_equal_approx(sprint_vel.y, 0.0), "Sprint horizontal velocity must have y == 0")

	# Diagonal input must be normalized so speed doesn't exceed walk_speed
	var diag_vel: Vector3 = controller.compute_desired_horizontal_velocity(Vector2(1.0, -1.0), Basis.IDENTITY, false)
	check(is_equal_approx(diag_vel.length(), controller.walk_speed), "Diagonal walk velocity magnitude must normalize to walk_speed, got: %f" % diag_vel.length())

	# Rotated basis transforms forward input along rotated -Z
	var yaw_90 := Basis(Vector3.UP, PI * 0.5)
	var rotated_vel: Vector3 = controller.compute_desired_horizontal_velocity(Vector2(0.0, -1.0), yaw_90, false)
	check(rotated_vel.is_equal_approx(Vector3(-controller.walk_speed, 0.0, 0.0)), "90-degree yaw basis must rotate forward velocity to -X, got: %s" % str(rotated_vel))

	# Fallback input map registration
	controller._ensure_input_map()
	for action_name in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact", "toggle_camera"]:
		check(InputMap.has_action(action_name), "InputMap must contain fallback action '%s'" % action_name)

	# Toggle camera mode via controller
	var toggled_to: int = controller.toggle_camera_mode()
	check(toggled_to == cam_script.CameraMode.FPS, "toggle_camera_mode() must return FPS")
	check(controller.camera_state.current_mode == cam_script.CameraMode.FPS, "controller.camera_state.current_mode must update to FPS")
	var toggled_back: int = controller.toggle_camera_mode()
	check(toggled_back == cam_script.CameraMode.TPS, "Second toggle_camera_mode() must return TPS")
	check(controller.camera_state.current_mode == cam_script.CameraMode.TPS, "controller.camera_state.current_mode must update back to TPS")

	# try_interact() without raycast/collision returns null cleanly
	check(controller.try_interact() == null, "try_interact() without colliding raycast must return null")

	controller.free()

	# 3. Test player_sensei.tscn scene instantiation and hierarchy
	var scene_res = load("res://scenes/hub/player_sensei.tscn")
	if not check(scene_res != null and scene_res is PackedScene, "scenes/hub/player_sensei.tscn must load as PackedScene"):
		return

	var instance = scene_res.instantiate()
	if not check(instance != null, "player_sensei.tscn must instantiate"):
		return
	check(instance is CharacterBody3D, "Root node must be CharacterBody3D")
	check(instance.name == "Sensei", "Root node must be named 'Sensei'")

	var col_shape := instance.get_node_or_null("CollisionShape3D") as CollisionShape3D
	check(col_shape != null, "Must contain CollisionShape3D")
	check(col_shape.shape is CapsuleShape3D, "CollisionShape3D must use CapsuleShape3D")
	if col_shape and col_shape.shape is CapsuleShape3D:
		var cap := col_shape.shape as CapsuleShape3D
		check(is_equal_approx(cap.radius, 0.35), "CapsuleShape3D radius must be 0.35")
		check(is_equal_approx(cap.height, 1.75), "CapsuleShape3D height must be 1.75")

	var head_pivot := instance.get_node_or_null("HeadPivot") as Node3D
	check(head_pivot != null, "Must contain HeadPivot")
	if head_pivot:
		check(head_pivot.position.is_equal_approx(Vector3(0.0, 1.5, 0.0)), "HeadPivot position must be (0, 1.5, 0)")

	var fps_cam := instance.get_node_or_null("HeadPivot/FPSCamera") as Camera3D
	check(fps_cam != null, "Must contain HeadPivot/FPSCamera")
	if fps_cam:
		check(fps_cam.current == false, "FPSCamera must default to current = false")

	var spring_arm := instance.get_node_or_null("HeadPivot/SpringArm3D") as SpringArm3D
	check(spring_arm != null, "Must contain HeadPivot/SpringArm3D")
	if spring_arm:
		check(is_equal_approx(spring_arm.spring_length, 3.0), "SpringArm3D spring_length must be 3.0")

	var tps_cam := instance.get_node_or_null("HeadPivot/SpringArm3D/TPSCamera") as Camera3D
	check(tps_cam != null, "Must contain HeadPivot/SpringArm3D/TPSCamera")
	if tps_cam:
		check(tps_cam.current == true, "TPSCamera must default to current = true")

	var raycast := instance.get_node_or_null("HeadPivot/InteractRayCast") as RayCast3D
	check(raycast != null, "Must contain HeadPivot/InteractRayCast")
	if raycast:
		check(raycast.collide_with_areas == true, "InteractRayCast must have collide_with_areas == true")
		check(raycast.collide_with_bodies == true, "InteractRayCast must have collide_with_bodies == true")
		check(is_equal_approx(raycast.target_position.length(), 2.0), "InteractRayCast length must be 2.0")
		check(raycast.target_position.is_equal_approx(Vector3(0.0, 0.0, -2.0)), "InteractRayCast target_position must be Vector3(0, 0, -2.0)")

	var prox_area := instance.get_node_or_null("ProximityArea") as Area3D
	check(prox_area != null, "Must contain ProximityArea")
	if prox_area:
		var prox_col := prox_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		check(prox_col != null and prox_col.shape is SphereShape3D, "ProximityArea must contain CollisionShape3D with SphereShape3D")
		if prox_col and prox_col.shape is SphereShape3D:
			check(is_equal_approx((prox_col.shape as SphereShape3D).radius, 2.2), "ProximityArea SphereShape3D radius must be 2.2")

	# Test toggle_camera_mode updates camera current flags on instantiated scene
	var mode_after_toggle: int = instance.toggle_camera_mode()
	check(mode_after_toggle == cam_script.CameraMode.FPS, "Instance toggle_camera_mode() must switch to FPS")
	check(fps_cam.current == true and tps_cam.current == false, "FPS toggle must set fps_cam.current=true and tps_cam.current=false")
	instance.toggle_camera_mode()
	check(fps_cam.current == false and tps_cam.current == true, "Second toggle must restore fps_cam.current=false and tps_cam.current=true")

	instance.free()
