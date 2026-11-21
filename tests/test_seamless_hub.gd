# tests/test_seamless_hub.gd
extends SceneTree

var _failed: bool = false
var _completed: bool = false
var _ran: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_tests()

	if _failed or not _completed:
		quit(1)
		return true

	print("PASS: test_seamless_hub")
	quit(0)
	return true

func _collect_by_class(node: Node, target_type: Variant, out: Array) -> void:
	if is_instance_of(node, target_type):
		out.append(node)
	for child in node.get_children():
		_collect_by_class(child, target_type, out)

func _run_tests() -> void:
	# 1. Load scripts
	var door_script: GDScript = load("res://scripts/hub/InteractiveDoor.gd")
	var elev_script: GDScript = load("res://scripts/hub/InteractiveElevator.gd")
	var btn_script: GDScript = load("res://scripts/hub/ElevatorCallButton.gd")
	var vis_script: GDScript = load("res://scripts/hub/FloorVisibilityZone.gd")
	if not check(door_script != null and elev_script != null and btn_script != null and vis_script != null, "All seamless hub scripts must load and compile"):
		return

	# 2. InteractiveDoor tests (SLIDE & SWING)
	var slide_holder := Node3D.new()
	var slide_leaf := Node3D.new()
	slide_leaf.name = "SlideLeaf"
	slide_leaf.position = Vector3(1.0, 2.0, 3.0)
	var slide_door = door_script.new()
	slide_door.door_style = door_script.DoorStyle.SLIDE
	slide_door.slide_offset = Vector3(0.0, 0.0, -2.5)
	slide_holder.add_child(slide_leaf)
	slide_holder.add_child(slide_door)
	slide_door.target_door_path = NodePath("../SlideLeaf")

	check(slide_door.get_interaction_type() == "SEAMLESS_DOOR", "InteractiveDoor type must be 'SEAMLESS_DOOR'")
	check(slide_door.interaction_prompt == "[E] Open Door", "Initial prompt must be '[E] Open Door'")
	check(slide_door.is_open == false, "Door must start closed")

	var slide_events: Array[bool] = []
	slide_door.door_toggled.connect(func(open_st: bool): slide_events.append(open_st))

	slide_door.interact()
	check(slide_door.is_open == true, "interact() must open door")
	check(slide_door.interaction_prompt == "[E] Close Door", "Open door prompt must be '[E] Close Door'")
	check(slide_leaf.position.is_equal_approx(Vector3(1.0, 2.0, 0.5)), "Sliding door must offset leaf position by slide_offset")
	check(slide_events == [true], "door_toggled(true) must emit")

	slide_door.interact()
	check(slide_door.is_open == false, "Second interact() must close door")
	check(slide_door.interaction_prompt == "[E] Open Door", "Closed door prompt must restore to '[E] Open Door'")
	check(slide_leaf.position.is_equal_approx(Vector3(1.0, 2.0, 3.0)), "Sliding door must return to closed position")
	check(slide_events == [true, false], "door_toggled(false) must emit")
	slide_holder.free()

	var swing_holder := Node3D.new()
	var swing_hinge := Node3D.new()
	swing_hinge.name = "DoorHinge"
	var swing_door = door_script.new()
	swing_door.door_style = door_script.DoorStyle.SWING
	swing_door.swing_angle_degrees = -90.0
	swing_holder.add_child(swing_hinge)
	swing_holder.add_child(swing_door)
	swing_door.target_door_path = NodePath("../DoorHinge")

	swing_door.interact()
	check(swing_door.is_open == true, "Swing door must open")
	check(is_equal_approx(swing_hinge.rotation.y, deg_to_rad(-90.0)), "Swing door must rotate hinge by -90 deg")
	swing_door.interact()
	check(is_equal_approx(swing_hinge.rotation.y, 0.0), "Swing door must rotate hinge back to 0")
	swing_holder.free()

	# 3. InteractiveElevator & ElevatorCallButton tests
	var elev_plat := Node3D.new()
	var elev_ctrl = elev_script.new()
	elev_ctrl.name = "ElevatorControl"
	elev_plat.add_child(elev_ctrl)
	elev_ctrl.platform_path = NodePath("..")
	var heights: Array[float] = [0.0, 4.5]
	var names: Array[String] = ["1F - Schale Lobby", "2F - Sensei Office"]
	elev_ctrl.floor_heights = heights
	elev_ctrl.floor_names = names
	elev_ctrl._ready()

	check(elev_ctrl.get_interaction_type() == "ELEVATOR", "InteractiveElevator type must be 'ELEVATOR'")
	check(elev_ctrl.current_floor_index == 0, "Elevator must start at floor 0")
	check(elev_ctrl.get_current_floor_name() == "1F - Schale Lobby", "Floor 0 name mismatch")
	check(is_equal_approx(elev_ctrl.get_floor_height(1), 4.5), "Floor 1 height must be 4.5")

	var start_log: Array = []
	var reach_log: Array = []
	elev_ctrl.floor_change_started.connect(func(f_from: int, f_to: int): start_log.append([f_from, f_to]))
	elev_ctrl.floor_reached.connect(func(idx: int, fname: String): reach_log.append([idx, fname]))

	check(elev_ctrl.call_to_floor(-1) == false, "Out-of-bounds floor index -1 must return false")
	check(elev_ctrl.call_to_floor(5) == false, "Out-of-bounds floor index 5 must return false")
	check(elev_ctrl.call_to_floor(0) == false, "Calling current floor 0 must return false")

	check(elev_ctrl.call_to_floor(1) == true, "call_to_floor(1) must succeed")
	check(elev_ctrl.current_floor_index == 1, "current_floor_index must update to 1")
	check(is_equal_approx(elev_plat.position.y, 4.5), "Elevator platform position.y must reach 4.5")
	check(start_log == [[0, 1]], "floor_change_started must emit [0, 1]")
	check(reach_log == [[1, "2F - Sensei Office"]], "floor_reached must emit floor 1")

	var next_floor: int = elev_ctrl.cycle_next_floor()
	check(next_floor == 0 and is_equal_approx(elev_plat.position.y, 0.0), "cycle_next_floor() must wrap back to floor 0")

	var elev_btn = btn_script.new()
	elev_plat.add_child(elev_btn)
	elev_btn.elevator_path = NodePath("../ElevatorControl")
	elev_btn.target_floor_index = 1
	check(elev_btn.get_interaction_type() == "ELEVATOR_CALL", "ElevatorCallButton type must be 'ELEVATOR_CALL'")
	elev_btn.interact()
	check(elev_ctrl.current_floor_index == 1 and is_equal_approx(elev_plat.position.y, 4.5), "ElevatorCallButton.interact() must summon elevator to target_floor_index 1")
	elev_plat.free()

	# 4. FloorVisibilityZone tests
	var vis_parent := Node3D.new()
	var vis_target := Node3D.new()
	vis_target.name = "TargetRoom"
	var vis_zone = vis_script.new()
	vis_parent.add_child(vis_target)
	vis_parent.add_child(vis_zone)
	var vis_paths: Array[NodePath] = [NodePath("../TargetRoom")]
	vis_zone.target_node_paths = vis_paths

	vis_zone.set_zone_active(false)
	check(vis_zone.is_zone_active == false and vis_target.visible == false, "set_zone_active(false) must hide target nodes")
	vis_zone.set_zone_active(true)
	check(vis_zone.is_zone_active == true and vis_target.visible == true, "set_zone_active(true) must show target nodes")
	vis_parent.free()

	# 5. SchaleBuilding Scene Verification
	var building_packed := load("res://scenes/hub/zones/schale_building.tscn") as PackedScene
	if not check(building_packed != null, "scenes/hub/zones/schale_building.tscn must load cleanly"):
		return
	var building := building_packed.instantiate()
	if not check(building != null, "schale_building.tscn must instantiate"):
		return
	root.add_child(building)

	check(building is HubSceneController, "SchaleBuilding root must use HubSceneController")
	check(building.sensei != null and building.hud != null, "HubSceneController must resolve Sensei and HUD")

	var doors: Array = []
	_collect_by_class(building, door_script, doors)
	check(doors.size() >= 2, "SchaleBuilding must contain at least 2 InteractiveDoors (got %d)" % doors.size())

	var elevators: Array = []
	_collect_by_class(building, elev_script, elevators)
	check(elevators.size() >= 1, "SchaleBuilding must contain InteractiveElevator")

	var elev_btns: Array = []
	_collect_by_class(building, btn_script, elev_btns)
	check(elev_btns.size() >= 2, "SchaleBuilding must contain at least 2 ElevatorCallButtons (got %d)" % elev_btns.size())

	var chairs: Array = []
	_collect_by_class(building, SittableChair, chairs)
	check(chairs.size() >= 1, "SchaleBuilding must contain SittableChair")

	var cooks: Array = []
	_collect_by_class(building, CookingStation, cooks)
	check(cooks.size() >= 1, "SchaleBuilding must contain CookingStation")

	var pickups: Array = []
	_collect_by_class(building, PickableItem, pickups)
	check(pickups.size() >= 1, "SchaleBuilding must contain PickableItem")

	var lights: Array = []
	_collect_by_class(building, ToggleLight, lights)
	check(lights.size() >= 1, "SchaleBuilding must contain ToggleLight")

	var vis_zones: Array = []
	_collect_by_class(building, vis_script, vis_zones)
	check(vis_zones.size() >= 1, "SchaleBuilding must contain FloorVisibilityZone")

	# 6. Cleanup & Orphan Check
	root.remove_child(building)
	building.free()
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphans == 0, "OBJECT_ORPHAN_NODE_COUNT must be 0 after freeing SchaleBuilding, got %d" % orphans)

	_completed = true
