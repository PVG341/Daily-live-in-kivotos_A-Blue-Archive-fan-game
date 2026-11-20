# tests/test_interactables.gd
extends SceneTree

var _failed: bool = false
var _completed: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _init() -> void:
	_run_tests()

	if _failed or not _completed:
		quit(1)
		return

	print("PASS: test_interactables")
	quit(0)

func _run_tests() -> void:
	var base_script: GDScript = load("res://scripts/hub/InteractableBase.gd")
	if not check(base_script != null and base_script.can_instantiate(), "InteractableBase.gd must load and compile"):
		return
	var pickup_script: GDScript = load("res://scripts/hub/PickableItem.gd")
	if not check(pickup_script != null and pickup_script.can_instantiate(), "PickableItem.gd must load and compile"):
		return
	var door_script: GDScript = load("res://scripts/hub/DoorPortal.gd")
	if not check(door_script != null and door_script.can_instantiate(), "DoorPortal.gd must load and compile"):
		return
	var chair_script: GDScript = load("res://scripts/hub/SittableChair.gd")
	if not check(chair_script != null and chair_script.can_instantiate(), "SittableChair.gd must load and compile"):
		return
	var light_script: GDScript = load("res://scripts/hub/ToggleLight.gd")
	if not check(light_script != null and light_script.can_instantiate(), "ToggleLight.gd must load and compile"):
		return
	var ztm_script: GDScript = load("res://scripts/hub/ZoneTransitionManager.gd")
	if not check(ztm_script != null and ztm_script.can_instantiate(), "ZoneTransitionManager.gd must load and compile"):
		return
	var event_bus_script: GDScript = load("res://scripts/core/EventBus.gd")
	if not check(event_bus_script != null and event_bus_script.can_instantiate(), "EventBus.gd must load and compile"):
		return

	# 0. InteractableBase defaults
	var base_obj = base_script.new()
	check(base_obj is Area3D, "InteractableBase must extend Area3D")
	check(base_obj.interaction_prompt == "[E] Interact", "InteractableBase default prompt must be '[E] Interact'")
	check(base_obj.get_interaction_type() == "GENERIC", "InteractableBase interaction type must be 'GENERIC'")
	base_obj.free()

	# 1. PickableItem
	var event_bus = event_bus_script.new()
	var picked_events: Array = []
	event_bus.item_picked_up.connect(func(item_id: String, qty: int): picked_events.append([item_id, qty]))

	var item_res := ItemData.new()
	item_res.id = "energy_drink"
	item_res.name = "Energy Drink"

	var pickup = pickup_script.new()
	pickup.event_bus = event_bus
	pickup.item_data = item_res
	pickup.quantity = 3
	check(pickup.get_interaction_type() == "PICKUP", "PickableItem type must be 'PICKUP'")
	check(pickup.interaction_prompt == "[E] Pick up", "PickableItem prompt must be '[E] Pick up'")
	pickup.interact()
	check(picked_events.size() == 1, "PickableItem.interact() must emit item_picked_up once")
	if picked_events.size() == 1:
		check(picked_events[0] == ["energy_drink", 3], "item_picked_up payload must be ['energy_drink', 3]")
	check(pickup.is_queued_for_deletion(), "PickableItem.interact() must queue_free() the pickup")
	pickup.free()

	# Guard: null item_data should not emit
	var pickup_empty = pickup_script.new()
	pickup_empty.event_bus = event_bus
	pickup_empty.item_data = null
	pickup_empty.quantity = 1
	pickup_empty.interact()
	check(picked_events.size() == 1, "PickableItem with null item_data must not emit item_picked_up")
	pickup_empty.free()
	event_bus.free()

	# 2. DoorPortal & ZoneTransitionManager
	var ztm = ztm_script.new()
	var started_events: Array = []
	var completed_events: Array = []
	ztm.transition_started.connect(func(path: String, spawn_id: String): started_events.append([path, spawn_id]))
	ztm.transition_completed.connect(func(path: String, spawn_id: String): completed_events.append([path, spawn_id]))

	var door = door_script.new()
	door.zone_transition_manager = ztm
	door.target_scene_path = "res://scenes/hub/zones/abydos_academy.tscn"
	door.spawn_point_id = "entrance_a"
	check(door.get_interaction_type() == "DOOR", "DoorPortal type must be 'DOOR'")
	check(door.interaction_prompt == "[E] Enter", "DoorPortal prompt must be '[E] Enter'")
	door.interact()
	check(started_events.size() == 1, "DoorPortal.interact() must trigger transition_started")
	check(completed_events.size() == 1, "DoorPortal.interact() must trigger transition_completed")
	if started_events.size() == 1:
		check(started_events[0] == ["res://scenes/hub/zones/abydos_academy.tscn", "entrance_a"], "transition_started args mismatch")
	check(ztm.current_scene_path == "res://scenes/hub/zones/abydos_academy.tscn", "ZoneTransitionManager.current_scene_path must update")
	check(ztm.pending_spawn_point_id == "entrance_a", "ZoneTransitionManager.pending_spawn_point_id must update")

	# Guard: empty target_scene_path should not transition
	door.target_scene_path = ""
	door.interact()
	check(started_events.size() == 1, "DoorPortal with empty target_scene_path must not trigger transition")
	door.free()

	# 3. SittableChair
	var chair = chair_script.new()
	check(chair.get_interaction_type() == "SIT", "SittableChair type must be 'SIT'")
	check(chair.interaction_prompt == "[E] Sit", "SittableChair prompt must be '[E] Sit'")
	check(chair.seat_offset.is_equal_approx(Vector3(0.0, 0.5, 0.0)), "SittableChair default seat_offset must be (0, 0.5, 0)")
	check(chair.is_occupied == false, "SittableChair must start unoccupied")
	chair.interact()
	check(chair.is_occupied == true, "First SittableChair.interact() must set is_occupied = true")
	chair.interact()
	check(chair.is_occupied == false, "Second SittableChair.interact() must set is_occupied = false")
	chair.free()

	# 4. ToggleLight
	var toggle_light = light_script.new()
	var omni := OmniLight3D.new()
	omni.name = "OmniLight3D"
	omni.visible = true
	toggle_light.add_child(omni)
	toggle_light.target_light_path = NodePath("OmniLight3D")
	check(toggle_light.get_interaction_type() == "TOGGLE", "ToggleLight type must be 'TOGGLE'")
	check(toggle_light.interaction_prompt == "[E] Toggle Light", "ToggleLight prompt must be '[E] Toggle Light'")
	check(toggle_light.is_on == true, "ToggleLight must start with is_on = true")
	toggle_light.interact()
	check(toggle_light.is_on == false, "First ToggleLight.interact() must flip is_on to false")
	check(omni.visible == false, "First ToggleLight.interact() must set OmniLight3D.visible to false")
	toggle_light.interact()
	check(toggle_light.is_on == true, "Second ToggleLight.interact() must flip is_on to true")
	check(omni.visible == true, "Second ToggleLight.interact() must set OmniLight3D.visible to true")
	toggle_light.free()

	# 5. ZoneTransitionManager spawn points, tips, and loading_screen.tscn
	check(ztm.transition_to("") == false, "transition_to('') must return false")
	ztm.register_spawn_point("entrance_a", Vector3(4.0, 0.0, -2.0))
	check(ztm.get_spawn_position("entrance_a").is_equal_approx(Vector3(4.0, 0.0, -2.0)), "Registered spawn point must return exact position")
	check(ztm.get_spawn_position("nonexistent").is_equal_approx(Vector3.ZERO), "Unknown spawn point must return Vector3.ZERO")
	ztm.clear_spawn_points()
	check(ztm.get_spawn_position("entrance_a").is_equal_approx(Vector3.ZERO), "clear_spawn_points() must clear registered spawn points")

	check(ztm.loading_tips.size() >= 3, "ZoneTransitionManager must have at least 3 default loading tips")
	check(ztm.get_random_tip().length() > 0, "get_random_tip() must return a non-empty string")
	ztm.free()

	var loading_scene = load("res://scenes/hub/loading_screen.tscn")
	if not check(loading_scene != null and loading_scene is PackedScene, "scenes/hub/loading_screen.tscn must load as PackedScene"):
		return
	var loading_inst: Node = loading_scene.instantiate()
	if not check(loading_inst != null, "loading_screen.tscn must instantiate cleanly"):
		return
	check(loading_inst is CanvasLayer, "LoadingScreen root must be CanvasLayer")
	check(loading_inst.name == "LoadingScreen", "LoadingScreen root node must be named 'LoadingScreen'")

	var bg: Node = loading_inst.find_child("Background", true, false)
	if bg == null:
		for child in loading_inst.get_children():
			if child is ColorRect:
				bg = child
				break
	check(bg != null and bg is ColorRect, "LoadingScreen must contain a ColorRect background")

	var tip_label: Node = loading_inst.find_child("TipLabel", true, false)
	check(tip_label != null and tip_label is Label, "LoadingScreen must contain a Label named 'TipLabel'")

	var loading_bar: Node = loading_inst.find_child("LoadingBar", true, false)
	check(loading_bar != null and loading_bar is ProgressBar, "LoadingScreen must contain a ProgressBar named 'LoadingBar'")

	loading_inst.free()
	_completed = true
