# tests/test_save_load.gd
extends SceneTree

const TEST_TMP_ROOT := "res://.test_tmp"
const TEST_SAVE_DIR := "res://.test_tmp/saves"

var _failed: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path := path.path_join(file_name)
				if dir.current_is_dir():
					_remove_dir_recursive(full_path)
				else:
					dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		dir = null
	DirAccess.remove_absolute(path)

func _init():
	var save_mgr = preload("res://scripts/core/SaveManager.gd").new()
	var day_mgr = preload("res://scripts/core/DayCycleManager.gd").new()
	var fresh_mgr = preload("res://scripts/core/SaveManager.gd").new()

	_run_tests(save_mgr, day_mgr, fresh_mgr)

	# Clean up temp test directory and resources
	_remove_dir_recursive(TEST_TMP_ROOT)
	fresh_mgr.free()
	day_mgr.free()
	save_mgr.free()

	if _failed:
		quit(1)
		return

	print("PASS: test_save_load")
	quit(0)

func _run_tests(save_mgr: Node, day_mgr: Node, fresh_mgr: Node) -> void:
	# 0. Test get_save_root_dir() and configure isolated test save_dir
	var root_dir: String = save_mgr.get_save_root_dir()
	check(root_dir.ends_with("saves"), "get_save_root_dir() should end with 'saves', got: " + root_dir)

	_remove_dir_recursive(TEST_TMP_ROOT)
	save_mgr.save_dir = TEST_SAVE_DIR

	# Build mock state
	var state = {
		"day": 5,
		"hour": 14.5,
		"ap": 60,
		"max_ap": 100,
		"credits": 25000,
		"bonds": {"shiroko": 3, "hoshino": 5},
		"inventory": [{"id": "yakisoba_bread", "qty": 2}],
		"current_zone": "schale_office",
		"playtime": 123.45
	}

	# 1. Test state_to_json & json_to_state
	var json_str = save_mgr.state_to_json(state)
	check(json_str.length() > 0, "Serialized JSON must not be empty")

	var restored = save_mgr.json_to_state(json_str)
	if not check(not restored.is_empty(), "Restored JSON dictionary must not be empty"):
		return
	check(restored.day == 5, "Day must round-trip")
	check(restored.hour == 14.5, "Hour must round-trip")
	check(restored.ap == 60, "AP must round-trip")
	check(restored.max_ap == 100, "Max AP must round-trip")
	check(restored.credits == 25000, "Credits must round-trip")
	check(restored.bonds.shiroko == 3, "Bond data must round-trip")
	check(restored.inventory[0].id == "yakisoba_bread", "Inventory must round-trip")
	check(restored.current_zone == "schale_office", "Current zone must round-trip")

	# Test invalid json_to_state
	check(save_mgr.json_to_state("invalid json string").is_empty(), "Invalid JSON should parse to empty dict")

	# 2. Test serialize_game_state & deserialize_game_state
	day_mgr.current_day = 8
	day_mgr.current_hour = 16.0
	day_mgr.current_ap = 45
	day_mgr.max_ap = 120
	save_mgr.day_cycle_manager = day_mgr
	save_mgr.credits = 9999
	save_mgr.bonds = {"hoshino": 10}
	save_mgr.inventory = [{"id": "sports_drink", "qty": 5}]
	save_mgr.current_zone = "abydos_desert"
	save_mgr.playtime = 3600.0

	var serialized = save_mgr.serialize_game_state()
	check(serialized["day"] == 8, "Serialized day should match DayCycleManager")
	check(serialized["hour"] == 16.0, "Serialized hour should match DayCycleManager")
	check(serialized["ap"] == 45, "Serialized AP should match DayCycleManager")
	check(serialized["max_ap"] == 120, "Serialized max_ap should match DayCycleManager")
	check(serialized["credits"] == 9999, "Serialized credits should match")
	check(serialized["bonds"]["hoshino"] == 10, "Serialized bonds should match")
	check(serialized["inventory"][0]["id"] == "sports_drink", "Serialized inventory should match")
	check(serialized["current_zone"] == "abydos_desert", "Serialized current_zone should match")

	# Test deserialize_game_state
	var new_state = {
		"day": 12,
		"hour": 9.5,
		"ap": 80,
		"max_ap": 100,
		"credits": 50000,
		"bonds": {"nonomi": 4},
		"inventory": [{"id": "donut", "qty": 1}],
		"current_zone": "millennium_plaza",
		"playtime": 7200.0
	}
	check(save_mgr.deserialize_game_state(new_state) == true, "Deserialization should succeed")
	check(day_mgr.current_day == 12, "DayCycleManager day should update")
	check(day_mgr.current_hour == 9.5, "DayCycleManager hour should update")
	check(day_mgr.current_ap == 80, "DayCycleManager AP should update")
	check(day_mgr.max_ap == 100, "DayCycleManager max_ap should update")
	check(save_mgr.credits == 50000, "Credits should update")
	check(save_mgr.bonds["nonomi"] == 4, "Bonds should update")
	check(save_mgr.inventory[0]["id"] == "donut", "Inventory should update")
	check(save_mgr.current_zone == "millennium_plaza", "Zone should update")

	check(save_mgr.deserialize_game_state({}) == false, "Empty dict should return false")

	# Test deserialize_game_state WITHOUT a day_cycle_manager attached (pins max_ap vs current_ap bug)
	var standalone_state = {
		"day": 3,
		"hour": 11.0,
		"ap": 42,
		"max_ap": 150,
		"credits": 1000,
		"bonds": {"shiroko": 2},
		"inventory": [],
		"current_zone": "schale_office",
		"playtime": 60.0
	}
	check(fresh_mgr.deserialize_game_state(standalone_state) == true, "Standalone deserialization should succeed")
	check(fresh_mgr.max_ap == 150, "SaveManager.max_ap should match input max_ap without day_cycle_manager")
	check(fresh_mgr.current_ap == 42, "SaveManager.current_ap should match input ap without day_cycle_manager")

	# 3. Test save_game, load_game, get_save_slots, delete_save
	var test_slot = 99
	save_mgr.delete_save(test_slot)

	check(save_mgr.load_game(test_slot) == false, "Loading non-existent slot should return false")

	var save_success = save_mgr.save_game(test_slot)
	check(save_success == true, "Saving game to slot 99 should succeed")

	var slots = save_mgr.get_save_slots()
	var found_slot = false
	for slot_info in slots:
		if slot_info.get("slot") == test_slot:
			found_slot = true
			check(slot_info.get("day") == 12, "Slot metadata day should match saved state")
			check(slot_info.has("playtime"), "Slot metadata should contain playtime")
			check(slot_info.has("timestamp"), "Slot metadata should contain timestamp")
			break
	check(found_slot == true, "Saved slot 99 must be present in get_save_slots()")

	# Mutate state before loading
	day_mgr.current_day = 1
	save_mgr.credits = 0

	var load_success = save_mgr.load_game(test_slot)
	check(load_success == true, "Loading game from slot 99 should succeed")
	check(day_mgr.current_day == 12, "Loaded day should be restored")
	check(save_mgr.credits == 50000, "Loaded credits should be restored")

	# Test delete_save
	var delete_success = save_mgr.delete_save(test_slot)
	check(delete_success == true, "Deleting existing slot 99 should succeed")
	check(save_mgr.delete_save(test_slot) == false, "Deleting already deleted slot should return false")

	var slots_after_delete = save_mgr.get_save_slots()
	for slot_info in slots_after_delete:
		check(slot_info.get("slot") != test_slot, "Slot 99 should no longer exist after deletion")
