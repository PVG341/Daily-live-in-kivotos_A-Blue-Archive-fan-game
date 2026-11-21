# tests/test_hub_scene_flow.gd
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

	print("PASS: test_hub_scene_flow")
	quit(0)
	return true

func _find_first_by_class(node: Node, target_type: Variant) -> Node:
	if is_instance_of(node, target_type):
		return node
	for child in node.get_children():
		var found := _find_first_by_class(child, target_type)
		if found != null:
			return found
	return null

func _run_tests() -> void:
	# 1. Verify both schale_office.tscn and crafting_chamber.tscn instantiate with full camera/light/UI/controller setup
	for scene_path in ["res://scenes/hub/zones/schale_office.tscn", "res://scenes/hub/zones/crafting_chamber.tscn"]:
		var packed := load(scene_path) as PackedScene
		if not check(packed != null, "Scene must load cleanly: %s" % scene_path):
			return
		var inst := packed.instantiate()
		if not check(inst != null, "Scene must instantiate cleanly: %s" % scene_path):
			return

		check(inst is HubSceneController, "%s root must use HubSceneController" % scene_path)
		var sensei := _find_first_by_class(inst, SenseiController) as SenseiController
		var dir_light := _find_first_by_class(inst, DirectionalLight3D) as DirectionalLight3D
		var world_env := _find_first_by_class(inst, WorldEnvironment) as WorldEnvironment
		var portal := _find_first_by_class(inst, DoorPortal) as DoorPortal
		var hud := _find_first_by_class(inst, HUDManager) as HUDManager
		check(sensei != null, "%s must contain SenseiController" % scene_path)
		check(_find_first_by_class(sensei, Camera3D) != null, "%s Sensei must contain Camera3D" % scene_path)
		check(dir_light != null, "%s must contain DirectionalLight3D" % scene_path)
		check(world_env != null, "%s must contain WorldEnvironment" % scene_path)
		check(portal != null, "%s must contain DoorPortal" % scene_path)
		check(hud != null, "%s must contain HUDManager" % scene_path)

		inst.free()

	# 2. Verify PauseMenu -> SettingsMenu no-overlap flow in-tree
	var office_packed := load("res://scenes/hub/zones/schale_office.tscn") as PackedScene
	var office := office_packed.instantiate() as HubSceneController
	root.add_child(office)

	var pause_menu := office.pause_menu
	var settings_menu := office.settings_menu
	var hud_mgr := office.hud
	var sensei_ctrl := office.sensei
	check(pause_menu != null and settings_menu != null and hud_mgr != null and sensei_ctrl != null, "HubSceneController must resolve pause, settings, hud, and sensei")

	check(settings_menu.visible == false, "SettingsMenu must start hidden")
	check(pause_menu.visible == false, "PauseMenu must start hidden")

	pause_menu.toggle_pause()
	check(pause_menu.is_paused == true and pause_menu.visible == true, "toggle_pause() must pause and show PauseMenu")
	check(settings_menu.visible == false, "SettingsMenu must remain hidden when PauseMenu opens")

	pause_menu.settings_requested.emit()
	check(settings_menu.visible == true, "settings_requested must show SettingsMenu")
	check(pause_menu.visible == false and pause_menu.is_paused == true, "Opening SettingsMenu must hide PauseMenu without unpausing (no overlap)")

	settings_menu.emit_signal(&"back_requested")
	check(settings_menu.visible == false, "back_requested must hide SettingsMenu")
	check(pause_menu.visible == true and pause_menu.is_paused == true, "Closing SettingsMenu must restore visible PauseMenu")

	pause_menu.toggle_pause()
	check(pause_menu.is_paused == false and pause_menu.visible == false, "Second toggle_pause() must unpause and hide PauseMenu")

	# 3. Verify SenseiController sit_on_chair() / stand_up()
	var chair := _find_first_by_class(office, SittableChair) as SittableChair
	if not check(chair != null, "schale_office.tscn must contain a SittableChair"):
		root.remove_child(office)
		office.free()
		return

	var initial_pos: Vector3 = sensei_ctrl.global_position
	sensei_ctrl.sit_on_chair(chair)
	check(sensei_ctrl.is_sitting == true, "sit_on_chair() must set is_sitting == true")
	check(chair.is_occupied == true, "sit_on_chair() must mark chair occupied")
	check(chair.interaction_prompt == "[E] Stand up", "Occupied chair prompt must update to '[E] Stand up'")
	check(sensei_ctrl.global_position.is_equal_approx(chair.get_seat_world_position()), "Sensei global_position must move to chair seat world position")

	sensei_ctrl.stand_up()
	check(sensei_ctrl.is_sitting == false, "stand_up() must set is_sitting == false")
	check(chair.is_occupied == false, "stand_up() must mark chair unoccupied")
	check(chair.interaction_prompt == "[E] Sit", "Unoccupied chair prompt must restore to '[E] Sit'")
	check(sensei_ctrl.global_position.is_equal_approx(initial_pos), "stand_up() must restore Sensei position")

	# 4. Verify HUDManager interaction prompt show / hide
	var prompt_container := hud_mgr.find_child("InteractionPromptContainer", true, false) as Control
	var prompt_label := hud_mgr.find_child("InteractionPromptLabel", true, false) as Label
	check(prompt_container != null and prompt_label != null, "HUD must contain InteractionPromptContainer and InteractionPromptLabel")
	check(prompt_container.visible == false, "InteractionPromptContainer must start hidden")

	hud_mgr.update_interaction_prompt("[E] Sit")
	check(prompt_container.visible == true and prompt_label.text == "[E] Sit", "update_interaction_prompt('[E] Sit') must show container and update text")

	hud_mgr.update_interaction_prompt("")
	check(prompt_container.visible == false and prompt_label.text == "", "update_interaction_prompt('') must hide container and clear text")

	# 5. Cleanup & Orphan Check
	root.remove_child(office)
	office.free()
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphans == 0, "OBJECT_ORPHAN_NODE_COUNT after freeing Hub scene must be 0, got %d" % orphans)

	_completed = true
