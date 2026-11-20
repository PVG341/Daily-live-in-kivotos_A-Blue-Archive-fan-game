# tests/test_memory_leaks.gd
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

	print("PASS: test_memory_leaks")
	quit(0)
	return true

class MockModLoader extends Node:
	var mods: Array[Dictionary] = [
		{"id": "mod_a", "name": "Mod A", "version": "1.0.0", "enabled": true},
		{"id": "mod_b", "name": "Mod B", "version": "0.2.0", "enabled": false},
	]

	func get_loaded_mods() -> Array[Dictionary]:
		return mods.duplicate(true)

	func set_mod_enabled(mod_id: String, enabled: bool) -> void:
		for m in mods:
			if m.get("id", "") == mod_id:
				m["enabled"] = enabled

func _get_orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _run_tests() -> void:
	# 1. Baseline Orphan Check
	if not check(_get_orphan_count() == 0, "Baseline OBJECT_ORPHAN_NODE_COUNT must be 0, got %d" % _get_orphan_count()):
		return

	# 2. ShittimChestSpaceManager Stress & Predelete Guard
	var shittim_script: GDScript = load("res://scripts/hub/ShittimChestSpaceManager.gd")
	if not check(shittim_script != null and shittim_script.can_instantiate(), "ShittimChestSpaceManager.gd must load"):
		return

	var shittim_mgr = shittim_script.new()
	for _i in range(25):
		if not check(shittim_mgr.enter_space() == true, "enter_space() must succeed in stress cycle"):
			shittim_mgr.free()
			return
		shittim_mgr.exit_space()
	shittim_mgr.free()
	if not check(_get_orphan_count() == 0, "After 25 ShittimChest enter/exit cycles, orphan count must be 0, got %d" % _get_orphan_count()):
		return

	var shittim_leak_guard = shittim_script.new()
	check(shittim_leak_guard.enter_space() == true, "Second ShittimChest manager enter_space() must succeed")
	var space_inst_ref: Node = shittim_leak_guard.loaded_space_instance
	check(space_inst_ref != null and is_instance_valid(space_inst_ref), "loaded_space_instance must be valid before free()")
	# Directly free without calling exit_space()
	shittim_leak_guard.free()
	check(not is_instance_valid(space_inst_ref), "NOTIFICATION_PREDELETE on ShittimChestSpaceManager must free loaded_space_instance")
	if not check(_get_orphan_count() == 0, "Orphan count after ShittimChest direct free() must be 0, got %d" % _get_orphan_count()):
		return

	# 3. ProjectileManager Zero-Speed, Lifetime & Cleanup
	var proj_script: GDScript = load("res://scripts/combat/ProjectileManager.gd")
	if not check(proj_script != null and proj_script.can_instantiate(), "ProjectileManager.gd must load"):
		return
	var proj_mgr = proj_script.new()
	var dummy_unit := Node3D.new()

	for _i in range(50):
		proj_mgr.spawn_projectile(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 10.0, 10, dummy_unit, dummy_unit)
		proj_mgr.spawn_projectile(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 0.0, 10, dummy_unit, dummy_unit)
		proj_mgr.spawn_projectile(Vector3.ZERO, Vector3(1000.0, 0.0, 0.0), 0.01, 10, dummy_unit, dummy_unit)

	check(proj_mgr.active_projectiles.size() == 150, "Expected 150 spawned projectiles")
	proj_mgr.tick_projectiles(0.5)
	# Normal 50 hit immediately (dist 1.0 <= 10.0 * 0.5), zero-speed 50 purged immediately; only 50 slow remain
	check(proj_mgr.active_projectiles.size() == 50, "Expected 50 slow projectiles remaining after 0.5s tick, got %d" % proj_mgr.active_projectiles.size())
	proj_mgr.tick_projectiles(16.0)
	check(proj_mgr.active_projectiles.is_empty(), "Slow projectiles exceeding MAX_PROJECTILE_LIFETIME must be purged")

	for _i in range(20):
		proj_mgr.spawn_projectile(Vector3.ZERO, Vector3(50.0, 0.0, 0.0), 5.0, 10, dummy_unit, dummy_unit)
	check(proj_mgr.active_projectiles.size() == 20, "Expected 20 projectiles before clear_projectiles()")
	proj_mgr.clear_projectiles()
	check(proj_mgr.active_projectiles.is_empty(), "clear_projectiles() must empty active_projectiles")

	dummy_unit.free()
	proj_mgr.free()
	if not check(_get_orphan_count() == 0, "Orphan count after ProjectileManager tests must be 0, got %d" % _get_orphan_count()):
		return

	# 4. DungeonRoomManager Re-start & Predelete Guard
	var room_mgr_script: GDScript = load("res://scripts/combat/DungeonRoomManager.gd")
	var layout_gen_script: GDScript = load("res://scripts/combat/DungeonLayoutGenerator.gd")
	var room_mgr = room_mgr_script.new()
	var layout_gen = layout_gen_script.new()
	var sample_layout: Array[Dictionary] = layout_gen.generate_layout(3, 1)

	var old_room := Node3D.new()
	room_mgr.current_room_node = old_room
	room_mgr.start_dungeon(sample_layout)
	check(not is_instance_valid(old_room), "start_dungeon() must free leftover unparented current_room_node")
	check(room_mgr.current_room_node == null, "current_room_node must be reset to null on start_dungeon()")

	var leaked_room := Node3D.new()
	room_mgr.current_room_node = leaked_room
	room_mgr.free()
	check(not is_instance_valid(leaked_room), "DungeonRoomManager NOTIFICATION_PREDELETE must free unparented current_room_node")
	if not check(_get_orphan_count() == 0, "Orphan count after DungeonRoomManager tests must be 0, got %d" % _get_orphan_count()):
		return

	# 5. CombatUnit Death + CoverPoint3D Auto-Sanitize + UnitSelectionManager Prune
	var cover_script: GDScript = load("res://scripts/combat/CoverPoint3D.gd")
	var unit_script: GDScript = load("res://scripts/combat/CombatUnit.gd")
	var sel_script: GDScript = load("res://scripts/combat/UnitSelectionManager.gd")

	var cover = cover_script.new()
	var unit_a = unit_script.new()
	var unit_b = unit_script.new()
	var dummy_target := Node3D.new()
	var sel_mgr = sel_script.new()

	var student_a := StudentData.new()
	student_a.id = "student_a"
	student_a.base_hp = 500
	var student_b := StudentData.new()
	student_b.id = "student_b"
	student_b.base_hp = 500
	unit_a.setup(student_a)
	unit_b.setup(student_b)

	check(cover.claim(unit_a) == true, "unit_a must claim CoverPoint3D")
	sel_mgr.select_unit(unit_a, false)
	unit_a.receive_focus_fire(dummy_target)
	check(unit_a.order_target_node == dummy_target, "order_target_node must reference dummy_target before die()")

	unit_a.die()
	check(unit_a.order_target_node == null and unit_a.current_order_type == "", "CombatUnit.die() must clear order_target_node and current_order_type")
	check(cover.claim(unit_b) == true, "Living unit_b must claim CoverPoint3D after unit_a died via _sanitize_occupant()")

	unit_a.free()
	sel_mgr.prune_invalid_units()
	check(sel_mgr.selected_units.is_empty(), "prune_invalid_units() must remove freed unit_a from selected_units")

	# Also verify CoverPoint3D sanitizes freed occupant
	unit_b.free()
	cover.release()
	check(cover.is_occupied == false and cover.occupant == null, "CoverPoint3D must sanitize freed occupant cleanly")

	cover.free()
	dummy_target.free()
	sel_mgr.free()
	if not check(_get_orphan_count() == 0, "Orphan count after CombatUnit/Cover/Selection tests must be 0, got %d" % _get_orphan_count()):
		return

	# 6. CombatHUD & ModManagerUI Dynamic Rebuild Stress
	var combat_hud_scene: PackedScene = load("res://scenes/ui/combat_hud.tscn")
	var combat_hud = combat_hud_scene.instantiate()
	var portraits := combat_hud.find_child("StrikerPortraits", true, false) as Container
	var buff_row := combat_hud.find_child("BuffRow", true, false) as Container
	check(portraits != null and buff_row != null, "combat_hud must contain StrikerPortraits and BuffRow")

	for i in range(30):
		var sid_new: String = "striker_%d" % i
		var sid_old: String = "striker_%d" % (i - 1)
		if i > 0:
			combat_hud.striker_hp.erase(sid_old)
		combat_hud.update_striker_hp(sid_new, 100 + i, 1000)
		var cycle_buffs: Array[String] = ["buff_a_%d" % i, "buff_b_%d" % i]
		combat_hud.set_active_buff_ids(cycle_buffs)
		check(portraits.get_child_count() == 1, "StrikerPortraits must remove stale portraits and retain only active ones (got %d)" % portraits.get_child_count())
		check(buff_row.get_child_count() == 2, "BuffRow must contain 2 labels per cycle")

	combat_hud.clear_hud()
	check(portraits.get_child_count() == 0, "clear_hud() must leave 0 children in StrikerPortraits")
	check(buff_row.get_child_count() == 0, "clear_hud() must leave 0 children in BuffRow")
	combat_hud.free()

	var mod_ui_scene: PackedScene = load("res://scenes/ui/mod_manager_menu.tscn")
	var mod_ui = mod_ui_scene.instantiate()
	var mock_loader := MockModLoader.new()
	mod_ui.mod_loader = mock_loader
	for _i in range(15):
		mod_ui.refresh_mod_list()
	var mod_list := mod_ui.find_child("ModListContainer", true, false) as Container
	check(mod_list != null and mod_list.get_child_count() == 2, "ModListContainer must cleanly rebuild without accumulating children")
	mod_ui.free()
	mock_loader.free()
	if not check(_get_orphan_count() == 0, "Orphan count after UI stress tests must be 0, got %d" % _get_orphan_count()):
		return

	# 7. SaveManager EventBus Swap
	var sm_script: GDScript = load("res://scripts/core/SaveManager.gd")
	var bus_script: GDScript = load("res://scripts/core/EventBus.gd")
	var test_sm = sm_script.new()
	var bus1 = bus_script.new()
	var bus2 = bus_script.new()

	test_sm.set_event_bus(bus1)
	check(bus1.item_picked_up.is_connected(test_sm._on_item_picked_up), "SaveManager must connect to bus1")
	test_sm.set_event_bus(bus2)
	check(not bus1.item_picked_up.is_connected(test_sm._on_item_picked_up), "SaveManager must disconnect from previous bus1 on set_event_bus(bus2)")
	check(bus2.item_picked_up.is_connected(test_sm._on_item_picked_up), "SaveManager must connect to bus2")
	test_sm.set_event_bus(null)
	check(not bus2.item_picked_up.is_connected(test_sm._on_item_picked_up), "SaveManager must disconnect from bus2 when set_event_bus(null) is called")

	test_sm.free()
	bus1.free()
	bus2.free()

	# Also test autoload SaveManager if present
	var root_sm := root.get_node_or_null("SaveManager")
	if root_sm != null:
		var orig_bus = root_sm.event_bus
		var ab1 = bus_script.new()
		var ab2 = bus_script.new()
		root_sm.set_event_bus(ab1)
		check(ab1.item_picked_up.is_connected(root_sm._on_item_picked_up), "Autoload SaveManager must connect to ab1")
		root_sm.set_event_bus(ab2)
		check(not ab1.item_picked_up.is_connected(root_sm._on_item_picked_up), "Autoload SaveManager must disconnect from ab1 when swapped to ab2")
		root_sm.set_event_bus(orig_bus)
		check(not ab2.item_picked_up.is_connected(root_sm._on_item_picked_up), "Autoload SaveManager must disconnect from ab2 when restored")
		ab1.free()
		ab2.free()

	# 8. Final Orphan Node Count Assertion
	var final_orphans: int = _get_orphan_count()
	check(final_orphans == 0, "Final OBJECT_ORPHAN_NODE_COUNT must be 0, got %d" % final_orphans)

	_completed = true
