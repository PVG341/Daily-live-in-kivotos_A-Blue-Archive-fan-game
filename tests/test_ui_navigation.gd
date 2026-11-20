# tests/test_ui_navigation.gd
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

	print("PASS: test_ui_navigation")
	quit(0)
	return true

class MockSaveManager extends Node:
	var saved_slots: Array[int] = []
	var loaded_slots: Array[int] = []

	func save_game(slot: int) -> bool:
		saved_slots.append(slot)
		return true

	func load_game(slot: int) -> bool:
		loaded_slots.append(slot)
		return slot > 0

class MockModLoader extends Node:
	var mods: Array[Dictionary] = [
		{"id": "mod_a", "name": "Mod A", "version": "1.0.0", "enabled": true},
		{"id": "mod_b", "name": "Mod B", "version": "0.2.0", "enabled": false},
	]
	var toggled: Array = []

	func get_loaded_mods() -> Array[Dictionary]:
		return mods.duplicate(true)

	func set_mod_enabled(mod_id: String, enabled: bool) -> void:
		toggled.append([mod_id, enabled])
		for m in mods:
			if m.get("id", "") == mod_id:
				m["enabled"] = enabled

func _run_tests() -> void:
	# 1. Load all 5 UI scripts
	var hud_script: GDScript = load("res://scripts/ui/HUDManager.gd")
	if not check(hud_script != null and hud_script.can_instantiate(), "HUDManager.gd must load and compile"):
		return
	var phone_script: GDScript = load("res://scripts/ui/PhoneOSManager.gd")
	if not check(phone_script != null and phone_script.can_instantiate(), "PhoneOSManager.gd must load and compile"):
		return
	var pause_script: GDScript = load("res://scripts/ui/PauseMenuManager.gd")
	if not check(pause_script != null and pause_script.can_instantiate(), "PauseMenuManager.gd must load and compile"):
		return
	var mod_ui_script: GDScript = load("res://scripts/ui/ModManagerUI.gd")
	if not check(mod_ui_script != null and mod_ui_script.can_instantiate(), "ModManagerUI.gd must load and compile"):
		return
	var combat_hud_script: GDScript = load("res://scripts/ui/CombatHUD.gd")
	if not check(combat_hud_script != null and combat_hud_script.can_instantiate(), "CombatHUD.gd must load and compile"):
		return

	# 2. PhoneOSManager unit tests
	var phone = phone_script.new()
	check(phone is Control, "PhoneOSManager must extend Control")
	check(phone.is_open == false, "PhoneOSManager must start closed (is_open == false)")
	check(phone.active_tab == "CONTACTS", "PhoneOSManager default active_tab must be CONTACTS")
	check(phone.current_bgm_track == "Constant Moderato", "Default BGM track must be 'Constant Moderato'")

	var toggled_events: Array[bool] = []
	phone.phone_toggled.connect(func(opened: bool): toggled_events.append(opened))
	var tab_events: Array[String] = []
	phone.tab_switched.connect(func(tab_name: String): tab_events.append(tab_name))
	var skin_events: Array = []
	phone.skin_changed.connect(func(sid: String, skin_id: String): skin_events.append([sid, skin_id]))
	var bgm_events: Array[String] = []
	phone.bgm_track_selected.connect(func(track_id: String): bgm_events.append(track_id))

	check(phone.toggle() == true, "First toggle() must open phone and return true")
	check(phone.is_open == true and phone.visible == true, "Phone must be open and visible after toggle()")
	check(phone.toggle() == false, "Second toggle() must close phone and return false")
	check(phone.is_open == false and phone.visible == false, "Phone must be closed and hidden after second toggle()")
	check(toggled_events == [true, false], "phone_toggled must emit [true, false]")

	for valid_tab in ["INVENTORY", "MAP", "CONTACTS", "MISSIONS", "BGM"]:
		check(phone.switch_tab(valid_tab) == true, "switch_tab('%s') must return true" % valid_tab)
		check(phone.active_tab == valid_tab, "active_tab must become '%s'" % valid_tab)
	check(tab_events.size() == 5, "tab_switched must emit for each valid tab switch")

	check(phone.switch_tab("INVALID") == false, "switch_tab('INVALID') must return false")
	check(phone.active_tab == "BGM", "Invalid switch_tab must preserve previous active_tab")
	check(tab_events.size() == 5, "Invalid switch_tab must not emit tab_switched")

	check(phone.get_student_skin("shiroko") == "default", "Unset student skin must default to 'default'")
	phone.set_student_skin("shiroko", "cycling")
	check(phone.get_student_skin("shiroko") == "cycling", "get_student_skin must return updated skin")
	check(skin_events.size() == 1 and skin_events[0] == ["shiroko", "cycling"], "set_student_skin must emit skin_changed")

	phone.select_bgm_track("Unwelcome School")
	check(phone.current_bgm_track == "Unwelcome School", "select_bgm_track must update current_bgm_track")
	check(bgm_events == ["Unwelcome School"], "select_bgm_track must emit bgm_track_selected")
	phone.free()

	# 3. PauseMenuManager unit tests
	var pause_menu = pause_script.new()
	check(pause_menu is Control, "PauseMenuManager must extend Control")
	check(pause_menu.is_paused == false, "PauseMenuManager must start unpaused")

	var pause_events: Array[bool] = []
	pause_menu.pause_toggled.connect(func(p: bool): pause_events.append(p))

	var mock_save := MockSaveManager.new()
	pause_menu.save_manager = mock_save
	check(pause_menu.request_save(2) == true, "request_save(2) must delegate to save_manager and return true")
	check(mock_save.saved_slots == [2], "save_manager.save_game must receive slot 2")
	check(pause_menu.request_load(2) == true, "request_load(2) must delegate to save_manager and return true")
	check(mock_save.loaded_slots == [2], "save_manager.load_game must receive slot 2")

	root.add_child(pause_menu)
	check(pause_menu.toggle_pause() == true, "First toggle_pause() must pause and return true")
	check(pause_menu.is_paused == true and pause_menu.visible == true, "PauseMenu must be paused and visible")
	check(paused == true, "SceneTree.paused must become true when PauseMenuManager pauses in tree")
	check(pause_menu.toggle_pause() == false, "Second toggle_pause() must unpause and return false")
	check(pause_menu.is_paused == false and pause_menu.visible == false, "PauseMenu must be unpaused and hidden")
	check(paused == false, "SceneTree.paused must return to false when unpaused")
	check(pause_events == [true, false], "pause_toggled must emit [true, false]")
	pause_menu.free()
	mock_save.free()

	# 4. HUDManager, CombatHUD, ModManagerUI unit tests
	var hud = hud_script.new()
	check(hud is CanvasLayer, "HUDManager must extend CanvasLayer")
	hud.update_ap(75, 120)
	check(hud.displayed_ap == 75 and hud.displayed_max_ap == 120, "HUDManager.update_ap must update displayed_ap and displayed_max_ap")
	hud.update_day(4, true)
	check(hud.displayed_day == 4, "HUDManager.update_day must update displayed_day")
	hud.update_credits(12500)
	check(hud.displayed_credits == 12500, "HUDManager.update_credits must update displayed_credits")
	hud.free()

	var combat_hud = combat_hud_script.new()
	check(combat_hud is CanvasLayer, "CombatHUD must extend CanvasLayer")
	combat_hud.update_cost(6.5, 10.0)
	check(is_equal_approx(combat_hud.displayed_cost, 6.5) and is_equal_approx(combat_hud.displayed_max_cost, 10.0), "CombatHUD.update_cost must update displayed_cost and displayed_max_cost")
	combat_hud.update_striker_hp("hoshino", 1800, 2400)
	check(combat_hud.striker_hp.get("hoshino", Vector2i.ZERO) == Vector2i(1800, 2400), "CombatHUD.update_striker_hp must store Vector2i(current_hp, max_hp)")
	combat_hud.update_wave(3)
	check(combat_hud.displayed_wave == 3, "CombatHUD.update_wave must update displayed_wave")
	var buffs: Array[String] = ["fire_rounds", "cost_regen"]
	combat_hud.set_active_buff_ids(buffs)
	check(combat_hud.active_buff_ids == ["fire_rounds", "cost_regen"], "CombatHUD.set_active_buff_ids must update active_buff_ids")
	combat_hud.free()

	var mod_ui = mod_ui_script.new()
	check(mod_ui is Control, "ModManagerUI must extend Control")
	check(mod_ui.refresh_mod_list().is_empty(), "refresh_mod_list without mod_loader must return empty array")
	var mock_loader := MockModLoader.new()
	mod_ui.mod_loader = mock_loader
	var mods: Array[Dictionary] = mod_ui.refresh_mod_list()
	check(mods.size() == 2 and mods[0].get("id", "") == "mod_a", "refresh_mod_list must return mods from mod_loader")
	mod_ui.toggle_mod("mod_b", true)
	check(mock_loader.toggled.size() == 1 and mock_loader.toggled[0] == ["mod_b", true], "toggle_mod must call mod_loader.set_mod_enabled")
	mod_ui.free()
	mock_loader.free()

	# 5. Scene loading, instantiation, hierarchy, and cleanup tests
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	if not check(hud_scene != null, "scenes/ui/hud.tscn must load"):
		return
	var hud_inst: Node = hud_scene.instantiate()
	check(hud_inst != null and hud_inst is CanvasLayer and hud_inst.get_script() == hud_script, "hud.tscn root must be CanvasLayer with HUDManager.gd")
	check(hud_inst.find_child("APBar", true, false) is ProgressBar, "hud.tscn must contain APBar ProgressBar")
	check(hud_inst.find_child("DayLabel", true, false) is Label, "hud.tscn must contain DayLabel Label")
	check(hud_inst.find_child("CreditsLabel", true, false) is Label, "hud.tscn must contain CreditsLabel Label")
	check(hud_inst.find_child("MiniMapContainer", true, false) is Control, "hud.tscn must contain MiniMapContainer Control")
	hud_inst.update_ap(50, 100)
	hud_inst.update_day(2, false)
	hud_inst.update_credits(999)
	root.add_child(hud_inst)
	check(hud_inst.find_child("DayLabel", true, false).text.contains("Day"), "hud.tscn DayLabel must display day text after _ready()")
	var root_sm := root.get_node_or_null("SaveManager")
	var root_dcm := root.get_node_or_null("DayCycleManager")
	if root_sm != null and root_dcm != null:
		var orig_credits: int = root_sm.credits
		var orig_day: int = root_dcm.current_day
		var orig_ap: int = root_dcm.current_ap
		root_sm.credits = 42000
		root_dcm.current_day = 9
		root_dcm.current_ap = 65
		root_sm.game_loaded.emit(1)
		check(hud_inst.displayed_credits == 42000 and hud_inst.displayed_day == 9 and hud_inst.displayed_ap == 65, "HUDManager must resync state on SaveManager.game_loaded")
		check(hud_inst.find_child("DayLabel", true, false).text == "Day 9", "HUDManager must refresh DayLabel on SaveManager.game_loaded")
		root_sm.credits = orig_credits
		root_dcm.current_day = orig_day
		root_dcm.current_ap = orig_ap
	root.remove_child(hud_inst)
	hud_inst.free()

	var phone_scene: PackedScene = load("res://scenes/ui/phone_os.tscn")
	if not check(phone_scene != null, "scenes/ui/phone_os.tscn must load"):
		return
	var phone_inst: Node = phone_scene.instantiate()
	check(phone_inst != null and phone_inst is Control and phone_inst.get_script() == phone_script, "phone_os.tscn root must be Control with PhoneOSManager.gd")
	check(phone_inst.find_child("TabBar", true, false) != null, "phone_os.tscn must contain TabBar")
	for panel_name in ["InventoryPanel", "MapPanel", "ContactsPanel", "MissionsPanel", "BGMPanel"]:
		check(phone_inst.find_child(panel_name, true, false) is Control, "phone_os.tscn must contain %s" % panel_name)
	root.add_child(phone_inst)
	phone_inst.switch_tab("MAP")
	check(phone_inst.find_child("MapPanel", true, false).visible == true, "MapPanel must be visible when switched to MAP")
	check(phone_inst.find_child("ContactsPanel", true, false).visible == false, "ContactsPanel must be hidden when switched to MAP")
	root.remove_child(phone_inst)
	phone_inst.free()

	var pause_scene: PackedScene = load("res://scenes/ui/pause_menu.tscn")
	if not check(pause_scene != null, "scenes/ui/pause_menu.tscn must load"):
		return
	var pause_inst: Node = pause_scene.instantiate()
	check(pause_inst != null and pause_inst is Control and pause_inst.get_script() == pause_script, "pause_menu.tscn root must be Control with PauseMenuManager.gd")
	for btn_name in ["ResumeButton", "SaveButton", "LoadButton", "SettingsButton", "QuitButton"]:
		check(pause_inst.find_child(btn_name, true, false) is Button, "pause_menu.tscn must contain %s Button" % btn_name)
	root.add_child(pause_inst)
	check(pause_inst.process_mode == Node.PROCESS_MODE_ALWAYS, "pause_menu.tscn must run with PROCESS_MODE_ALWAYS")
	var settings_req_count := [0]
	pause_inst.settings_requested.connect(func(): settings_req_count[0] += 1)
	pause_inst.find_child("SettingsButton", true, false).pressed.emit()
	check(settings_req_count[0] == 1, "Pressing SettingsButton must emit settings_requested signal")
	root.remove_child(pause_inst)
	pause_inst.free()

	var mod_scene: PackedScene = load("res://scenes/ui/mod_manager_menu.tscn")
	if not check(mod_scene != null, "scenes/ui/mod_manager_menu.tscn must load"):
		return
	var mod_inst: Node = mod_scene.instantiate()
	check(mod_inst != null and mod_inst is Control and mod_inst.get_script() == mod_ui_script, "mod_manager_menu.tscn root must be Control with ModManagerUI.gd")
	check(mod_inst.find_child("ModListContainer", true, false) is Container, "mod_manager_menu.tscn must contain ModListContainer")
	check(mod_inst.find_child("RefreshButton", true, false) is Button, "mod_manager_menu.tscn must contain RefreshButton")
	var mock_loader_scene := MockModLoader.new()
	mod_inst.mod_loader = mock_loader_scene
	root.add_child(mod_inst)
	check(mod_inst.find_child("ModListContainer", true, false).get_child_count() == 2, "ModListContainer must populate 2 mod entries after _ready()")
	root.remove_child(mod_inst)
	mod_inst.free()
	mock_loader_scene.free()

	var combat_scene: PackedScene = load("res://scenes/ui/combat_hud.tscn")
	if not check(combat_scene != null, "scenes/ui/combat_hud.tscn must load"):
		return
	var combat_inst: Node = combat_scene.instantiate()
	check(combat_inst != null and combat_inst is CanvasLayer and combat_inst.get_script() == combat_hud_script, "combat_hud.tscn root must be CanvasLayer with CombatHUD.gd")
	check(combat_inst.find_child("StrikerPortraits", true, false) is Control, "combat_hud.tscn must contain StrikerPortraits")
	check(combat_inst.find_child("SpecialSkillButtons", true, false) is Control, "combat_hud.tscn must contain SpecialSkillButtons")
	check(combat_inst.find_child("CostProgressBar", true, false) is ProgressBar, "combat_hud.tscn must contain CostProgressBar ProgressBar")
	check(combat_inst.find_child("WaveLabel", true, false) is Label, "combat_hud.tscn must contain WaveLabel Label")
	check(combat_inst.find_child("BuffRow", true, false) is Control, "combat_hud.tscn must contain BuffRow")
	root.add_child(combat_inst)
	combat_inst.update_cost(4.0, 10.0)
	combat_inst.update_wave(2)
	combat_inst.update_striker_hp("shiroko", 700, 850)
	var scene_buffs: Array[String] = ["fire_rounds"]
	combat_inst.set_active_buff_ids(scene_buffs)
	check(is_equal_approx(combat_inst.find_child("CostProgressBar", true, false).value, 4.0), "CostProgressBar value must update")
	check(combat_inst.find_child("WaveLabel", true, false).text == "Wave 2", "WaveLabel text must update")
	check(combat_inst.find_child("StrikerPortraits", true, false).get_child_count() == 1, "StrikerPortraits must display updated striker")
	check(combat_inst.find_child("BuffRow", true, false).get_child_count() == 1, "BuffRow must display active buffs")
	root.remove_child(combat_inst)
	combat_inst.free()

	_completed = true
