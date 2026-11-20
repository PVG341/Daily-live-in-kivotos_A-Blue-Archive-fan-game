# tests/test_rts_selection.gd
extends SceneTree

var _failed: bool = false
var _completed: bool = false

class MockOrderUnit extends Node3D:
	var has_player_order: bool = false
	var order_type: String = ""
	var target_position: Vector3 = Vector3.ZERO
	var target_cover: Node3D = null
	var target_enemy: Node3D = null
	var move_order_calls: int = 0

	func receive_move_order(target: Vector3) -> void:
		move_order_calls += 1
		target_position = target

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

var _ran: bool = false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_tests()

	if _failed or not _completed:
		quit(1)
		return true

	print("PASS: test_rts_selection")
	quit(0)
	return true

func _run_tests() -> void:
	# 1. SelectionMath tests
	var math_script: GDScript = load("res://scripts/combat/SelectionMath.gd")
	if not check(math_script != null and math_script.can_instantiate(), "SelectionMath.gd must load and compile"):
		return
	var sel_math = math_script.new()

	var norm_rev: Rect2 = sel_math.normalize_selection_rect(Vector2(150.0, 150.0), Vector2(50.0, 50.0))
	check(norm_rev.position.is_equal_approx(Vector2(50.0, 50.0)), "Reversed drag origin must normalize to (50, 50)")
	check(norm_rev.size.is_equal_approx(Vector2(100.0, 100.0)), "Reversed drag size must normalize to (100, 100)")

	var norm_bl_tr: Rect2 = sel_math.normalize_selection_rect(Vector2(50.0, 150.0), Vector2(150.0, 50.0))
	check(norm_bl_tr.is_equal_approx(Rect2(50.0, 50.0, 100.0, 100.0)), "Bottom-left to top-right drag must normalize to Rect2(50, 50, 100, 100)")

	check(sel_math.is_point_in_rect(Vector2(100.0, 100.0), norm_rev) == true, "Point (100, 100) must be inside Rect2(50, 50, 100, 100)")
	check(sel_math.is_point_in_rect(Vector2(50.0, 50.0), norm_rev) == true, "Top-left boundary (50, 50) must be inside rect")
	check(sel_math.is_point_in_rect(Vector2(150.0, 150.0), norm_rev) == true, "Bottom-right boundary (150, 150) must be inside rect")
	check(sel_math.is_point_in_rect(Vector2(200.0, 200.0), norm_rev) == false, "Point (200, 200) must be outside Rect2(50, 50, 100, 100)")
	check(sel_math.is_point_in_rect(Vector2(49.5, 100.0), norm_rev) == false, "Point (49.5, 100) must be outside Rect2(50, 50, 100, 100)")

	# 2. UnitSelectionManager tests
	var mgr_script: GDScript = load("res://scripts/combat/UnitSelectionManager.gd")
	if not check(mgr_script != null and mgr_script.can_instantiate(), "UnitSelectionManager.gd must load and compile"):
		return
	var mgr = mgr_script.new()
	check(mgr.selection_math != null, "selection_math must be initialized in _init()")
	check(mgr.selected_units.is_empty(), "selected_units must start empty")

	var u1 := Node3D.new()
	var u2 := Node3D.new()
	var u3 := MockOrderUnit.new()
	var unselected := Node3D.new()

	mgr.select_unit(u1, true)
	check(mgr.selected_units.size() == 1 and mgr.selected_units[0] == u1, "select_unit(u1, true) must add u1")
	mgr.select_unit(u1, true)
	check(mgr.selected_units.size() == 1, "select_unit must not duplicate already-selected unit")

	mgr.select_unit(u2, true)
	check(mgr.selected_units.size() == 2 and mgr.selected_units.has(u2), "select_unit(u2, true) must append u2")

	mgr.select_unit(null, false)
	check(mgr.selected_units.size() == 2, "select_unit(null, false) must ignore null and keep selection")

	mgr.select_unit(u3, false)
	check(mgr.selected_units.size() == 1 and mgr.selected_units[0] == u3, "select_unit(u3, false) must replace selection with u3")

	mgr.deselect_unit(u3)
	check(mgr.selected_units.is_empty(), "deselect_unit(u3) must remove u3")

	mgr.select_unit(u1, true)
	mgr.select_unit(u2, true)
	mgr.deselect_all()
	check(mgr.selected_units.is_empty(), "deselect_all() must clear all selected units")

	# box_select_screen_points with unnormalized Rect2
	var screen_map: Dictionary = {
		u1: Vector2(100.0, 100.0),
		u2: Vector2(150.0, 50.0),
		u3: Vector2(75.0, 125.0),
		unselected: Vector2(200.0, 200.0),
	}
	var boxed: Array[Node3D] = mgr.box_select_screen_points(Rect2(Vector2(150.0, 150.0), Vector2(-100.0, -100.0)), screen_map)
	check(boxed.size() == 3, "box_select_screen_points must select 3 units inside rect, got %d" % boxed.size())
	check(boxed.has(u1) and boxed.has(u2) and boxed.has(u3), "box_select_screen_points must include u1, u2, u3")
	check(not boxed.has(unselected), "box_select_screen_points must exclude unit outside rect")

	# box_select with null camera returns empty cleanly
	var null_cam_boxed: Array[Node3D] = mgr.box_select(Rect2(0.0, 0.0, 100.0, 100.0), null, [u1, u2])
	check(null_cam_boxed.is_empty(), "box_select with null camera must return empty array")

	# box_select with live Camera3D inside SubViewport (front vs behind camera)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	root.add_child(vp)
	var cam3d := Camera3D.new()
	vp.add_child(cam3d)
	cam3d.global_position = Vector3.ZERO
	var front_unit := Node3D.new()
	var side_unit := Node3D.new()
	var behind_unit := Node3D.new()
	vp.add_child(front_unit)
	vp.add_child(side_unit)
	vp.add_child(behind_unit)
	front_unit.global_position = Vector3(0.0, 0.0, -10.0)
	side_unit.global_position = Vector3(20.0, 0.0, -10.0)
	behind_unit.global_position = Vector3(0.0, 0.0, 10.0)
	var cam_boxed: Array[Node3D] = mgr.box_select(Rect2(Vector2(540.0, 260.0), Vector2(200.0, 200.0)), cam3d, [front_unit, side_unit, behind_unit])
	check(cam_boxed.size() == 1 and cam_boxed[0] == front_unit, "box_select must select only unit projected inside rect and skip behind-camera unit")
	vp.free()

	# Order dispatch tests on [u1, u3]
	mgr.select_unit(u1, false)
	mgr.select_unit(u3, true)

	var move_target := Vector3(12.0, 0.0, -8.0)
	mgr.issue_move_order(move_target)
	check(u1.get_meta(&"has_player_order", false) == true, "issue_move_order must set has_player_order meta on plain Node3D")
	check(u1.get_meta(&"order_type", "") == "MOVE", "issue_move_order must set order_type='MOVE' meta")
	check(u1.get_meta(&"order_target_position", Vector3.ZERO).is_equal_approx(move_target), "issue_move_order must store target position meta")
	check(u3.has_player_order == true, "issue_move_order must set has_player_order property on unit script")
	check(u3.order_type == "MOVE", "issue_move_order must set order_type='MOVE' property")
	check(u3.target_position.is_equal_approx(move_target), "issue_move_order must set target_position property")
	check(u3.move_order_calls == 1, "issue_move_order must invoke receive_move_order if present")
	check(not unselected.has_meta(&"has_player_order"), "Unselected unit must not receive move order")

	var cover_node := Node3D.new()
	mgr.issue_cover_order(cover_node)
	check(u1.get_meta(&"has_player_order", false) == true, "issue_cover_order must set has_player_order")
	check(u1.get_meta(&"order_type", "") == "COVER", "issue_cover_order must set order_type='COVER'")
	check(u1.get_meta(&"order_target_cover", null) == cover_node, "issue_cover_order must store cover_point")
	check(u3.order_type == "COVER" and u3.target_cover == cover_node, "issue_cover_order must set properties on scripted unit")

	var enemy_node := Node3D.new()
	mgr.issue_focus_fire(enemy_node)
	check(u1.get_meta(&"has_player_order", false) == true, "issue_focus_fire must set has_player_order")
	check(u1.get_meta(&"order_type", "") == "FOCUS_FIRE", "issue_focus_fire must set order_type='FOCUS_FIRE'")
	check(u1.get_meta(&"order_target_enemy", null) == enemy_node, "issue_focus_fire must store enemy target")
	check(u3.order_type == "FOCUS_FIRE" and u3.target_enemy == enemy_node, "issue_focus_fire must set properties on scripted unit")

	mgr.issue_hold_position()
	check(u1.get_meta(&"has_player_order", false) == true, "issue_hold_position must set has_player_order")
	check(u1.get_meta(&"order_type", "") == "HOLD_POSITION", "issue_hold_position must set order_type='HOLD_POSITION'")
	check(u3.order_type == "HOLD_POSITION", "issue_hold_position must set order_type property")

	mgr.issue_hold_fire()
	check(u1.get_meta(&"has_player_order", false) == true, "issue_hold_fire must set has_player_order")
	check(u1.get_meta(&"order_type", "") == "HOLD_FIRE", "issue_hold_fire must set order_type='HOLD_FIRE'")
	check(u3.order_type == "HOLD_FIRE", "issue_hold_fire must set order_type property")

	u1.free()
	u2.free()
	u3.free()
	unselected.free()
	cover_node.free()
	enemy_node.free()
	mgr.free()

	# 3. RTSCamera3D & combat_camera.tscn tests
	var cam_script: GDScript = load("res://scripts/combat/RTSCamera3D.gd")
	if not check(cam_script != null and cam_script.can_instantiate(), "RTSCamera3D.gd must load and compile"):
		return

	var cam_scene = load("res://scenes/combat/combat_camera.tscn")
	if not check(cam_scene != null and cam_scene is PackedScene, "scenes/combat/combat_camera.tscn must load as PackedScene"):
		return

	var rig = cam_scene.instantiate()
	if not check(rig != null, "combat_camera.tscn must instantiate cleanly"):
		return

	check(rig is Node3D, "CombatCameraRig root must be Node3D")
	check(rig.name == "CombatCameraRig", "Root node must be named CombatCameraRig")
	check(rig.get_script() == cam_script, "Root node must use RTSCamera3D.gd")

	var pitch_pivot := rig.get_node_or_null("PitchPivot") as Node3D
	check(pitch_pivot != null, "Must contain PitchPivot Node3D")
	var iso_cam := rig.get_node_or_null("PitchPivot/IsometricCamera") as Camera3D
	check(iso_cam != null, "Must contain PitchPivot/IsometricCamera Camera3D")
	var sel_overlay := rig.get_node_or_null("SelectionOverlay") as CanvasLayer
	check(sel_overlay != null, "Must contain SelectionOverlay CanvasLayer")
	var sel_box := rig.get_node_or_null("SelectionOverlay/SelectionBoxControl") as Control
	check(sel_box != null, "Must contain SelectionOverlay/SelectionBoxControl Control")

	# Default properties
	check(is_equal_approx(rig.pan_speed, 15.0), "Default pan_speed must be 15.0")
	check(is_equal_approx(rig.rotate_speed, 1.8), "Default rotate_speed must be 1.8")
	check(is_equal_approx(rig.zoom_speed, 2.0), "Default zoom_speed must be 2.0")
	check(is_equal_approx(rig.min_zoom, 5.0), "Default min_zoom must be 5.0")
	check(is_equal_approx(rig.max_zoom, 25.0), "Default max_zoom must be 25.0")
	check(rig.bounds_min.is_equal_approx(Vector2(-50.0, -50.0)), "Default bounds_min must be (-50, -50)")
	check(rig.bounds_max.is_equal_approx(Vector2(50.0, 50.0)), "Default bounds_max must be (50, 50)")
	check(is_equal_approx(rig.current_zoom, 12.0), "Default current_zoom must be 12.0")
	check(is_equal_approx(rig.yaw_degrees, 35.264), "Default yaw_degrees must be 35.264")
	check(is_equal_approx(rig.pitch_degrees, -45.0), "Default pitch_degrees must be -45.0")

	# adjust_zoom clamping [5.0, 25.0]
	check(is_equal_approx(rig.adjust_zoom(-100.0), 5.0), "adjust_zoom(-100) must clamp to min_zoom 5.0")
	check(is_equal_approx(rig.current_zoom, 5.0), "current_zoom must update to 5.0")
	check(is_equal_approx(rig.adjust_zoom(100.0), 25.0), "adjust_zoom(100) must clamp to max_zoom 25.0")
	check(is_equal_approx(rig.current_zoom, 25.0), "current_zoom must update to 25.0")
	check(is_equal_approx(rig.adjust_zoom(-5.0), 20.0), "adjust_zoom(-5) from 25 must return 20.0")

	# rotate_yaw updates yaw_degrees and rig rotation
	var new_yaw: float = rig.rotate_yaw(9.736)
	check(is_equal_approx(new_yaw, 45.0), "rotate_yaw(9.736) from 35.264 must return 45.0")
	check(is_equal_approx(rig.yaw_degrees, 45.0), "yaw_degrees must update to 45.0")
	check(is_equal_approx(rad_to_deg(rig.rotation.y), 45.0), "rig rotation.y must reflect yaw_degrees")

	# pan_planar moves on XZ plane and clamps to [bounds_min, bounds_max]
	var pos_after_pan: Vector3 = rig.pan_planar(Vector2(1.0, 0.0), 1.0)
	check(pos_after_pan.length() > 0.0, "pan_planar must move rig on XZ plane")
	check(is_equal_approx(pos_after_pan.y, 0.0), "pan_planar must keep y == 0")

	var clamped_max: Vector3 = rig.pan_planar(Vector2(1.0, 1.0), 100.0)
	check(clamped_max.x <= 50.0 and clamped_max.x >= -50.0, "pan_planar x must clamp within [-50, 50]")
	check(clamped_max.z <= 50.0 and clamped_max.z >= -50.0, "pan_planar z must clamp within [-50, 50]")

	# Verify exact clamping against bounds_max/bounds_min when yaw is 0
	rig.rotate_yaw(-45.0)
	var pos_pos_edge: Vector3 = rig.pan_planar(Vector2(1.0, 1.0), 100.0)
	check(is_equal_approx(pos_pos_edge.x, 50.0) and is_equal_approx(pos_pos_edge.z, 50.0), "At yaw 0, large +X/+Z pan must clamp to (50, 0, 50)")
	var pos_neg_edge: Vector3 = rig.pan_planar(Vector2(-1.0, -1.0), 100.0)
	check(is_equal_approx(pos_neg_edge.x, -50.0) and is_equal_approx(pos_neg_edge.z, -50.0), "At yaw 0, large -X/-Z pan must clamp to (-50, 0, -50)")

	# Verify camera distance updates on zoom and rig works inside SceneTree
	root.add_child(rig)
	rig.adjust_zoom(-6.0)
	check(is_equal_approx(rig.current_zoom, 14.0), "adjust_zoom(-6) from 20 must update current_zoom to 14.0")
	check(is_equal_approx(iso_cam.position.z, 14.0), "IsometricCamera.position.z must match current_zoom")
	var tree_pos: Vector3 = rig.pan_planar(Vector2(1.0, 1.0), 100.0)
	check(rig.global_position.is_equal_approx(Vector3(50.0, 0.0, 50.0)) and tree_pos.is_equal_approx(Vector3(50.0, 0.0, 50.0)), "In-tree pan_planar must update and clamp global_position")

	rig.free()
	_completed = true
