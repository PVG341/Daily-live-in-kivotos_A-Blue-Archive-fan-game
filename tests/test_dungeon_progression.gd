# tests/test_dungeon_progression.gd
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

	print("PASS: test_dungeon_progression")
	quit(0)
	return true

func _run_tests() -> void:
	# 1. Load scripts and scene
	var layout_gen_script: GDScript = load("res://scripts/combat/DungeonLayoutGenerator.gd")
	if not check(layout_gen_script != null and layout_gen_script.can_instantiate(), "DungeonLayoutGenerator.gd must load and compile"):
		return
	var card_mgr_script: GDScript = load("res://scripts/combat/RoguelikeCardManager.gd")
	if not check(card_mgr_script != null and card_mgr_script.can_instantiate(), "RoguelikeCardManager.gd must load and compile"):
		return
	var room_mgr_script: GDScript = load("res://scripts/combat/DungeonRoomManager.gd")
	if not check(room_mgr_script != null and room_mgr_script.can_instantiate(), "DungeonRoomManager.gd must load and compile"):
		return
	var draft_scene: PackedScene = load("res://scenes/combat/roguelike_card_draft.tscn")
	if not check(draft_scene != null, "roguelike_card_draft.tscn must load"):
		return

	# 2. DungeonLayoutGenerator tests
	var gen = layout_gen_script.new()
	check(gen is RefCounted, "DungeonLayoutGenerator must extend RefCounted")
	check(gen.ROOM_TYPES == ["COMBAT", "ELITE", "REST", "BOSS"], "ROOM_TYPES must match contract")

	var layout_5: Array[Dictionary] = gen.generate_layout(5, 1)
	check(layout_5.size() == 5, "generate_layout(5, 1) must return 5 rooms")
	check(layout_5[0].get("room_type", "") == "COMBAT", "First room (index 0) must always be COMBAT")
	check(layout_5[4].get("room_type", "") == "BOSS", "Last room (index 4) must always be BOSS")
	for i in range(layout_5.size()):
		var r: Dictionary = layout_5[i]
		check(r.get("room_index", -1) == i, "Room must have matching room_index")
		check(gen.ROOM_TYPES.has(r.get("room_type", "")), "Room type must be valid")
		check(r.get("room_scene_path", "") is String and not str(r.get("room_scene_path", "")).is_empty(), "Room must have non-empty room_scene_path")
		check(r.get("enemy_wave_def", null) is Dictionary, "Room must have enemy_wave_def Dictionary")
		check(r.get("door_positions", null) is Array, "Room must have door_positions Array")

	var layout_min: Array[Dictionary] = gen.generate_layout(1, 1)
	check(layout_min.size() == 2, "generate_layout(1, 1) must clamp to minimum 2 rooms")
	check(layout_min[0].get("room_type", "") == "COMBAT", "2-room layout first room must be COMBAT")
	check(layout_min[1].get("room_type", "") == "BOSS", "2-room layout last room must be BOSS")

	var allowed_middle: Array[String] = ["COMBAT", "ELITE", "REST"]
	for trial in range(25):
		var layout_7: Array[Dictionary] = gen.generate_layout(7, 1)
		check(layout_7.size() == 7, "generate_layout(7, 1) must return 7 rooms")
		check(layout_7[0].get("room_type", "") == "COMBAT", "Trial first room must be COMBAT")
		check(layout_7[6].get("room_type", "") == "BOSS", "Trial last room must be BOSS")
		for idx in range(1, 6):
			check(allowed_middle.has(layout_7[idx].get("room_type", "")), "Middle room must be COMBAT, ELITE, or REST")
		for idx in range(layout_7.size() - 1):
			var adjacent_rest: bool = (layout_7[idx].get("room_type", "") == "REST" and layout_7[idx + 1].get("room_type", "") == "REST")
			check(not adjacent_rest, "Two REST rooms must never be adjacent")

	var layout_d1: Array[Dictionary] = gen.generate_layout(5, 1)
	var layout_d3: Array[Dictionary] = gen.generate_layout(5, 3)
	var d1_combat_enemies: int = int(layout_d1[0]["enemy_wave_def"].get("enemy_count", 0))
	var d3_combat_enemies: int = int(layout_d3[0]["enemy_wave_def"].get("enemy_count", 0))
	var d1_boss_enemies: int = int(layout_d1[4]["enemy_wave_def"].get("enemy_count", 0))
	var d3_boss_enemies: int = int(layout_d3[4]["enemy_wave_def"].get("enemy_count", 0))
	check(d3_combat_enemies > d1_combat_enemies, "Higher difficulty must increase enemy count in COMBAT room")
	check(d3_boss_enemies > d1_boss_enemies, "Higher difficulty must increase enemy count in BOSS room")

	# 3. RoguelikeCardManager tests
	var card_mgr = card_mgr_script.new()
	check(card_mgr is RefCounted, "RoguelikeCardManager must extend RefCounted")
	check(card_mgr.card_pool.size() >= 6, "card_pool must initialize with at least 6 default cards")

	var rolled: Array[Dictionary] = card_mgr.roll_cards(3)
	check(rolled.size() == 3, "roll_cards(3) must return 3 cards")
	var seen_ids: Dictionary = {}
	for c in rolled:
		var cid: String = str(c.get("id", ""))
		check(not cid.is_empty(), "Rolled card must have non-empty id")
		check(not seen_ids.has(cid), "roll_cards must not return duplicate card ids in a single draft")
		seen_ids[cid] = true

	check(card_mgr.roll_cards(0).is_empty(), "roll_cards(0) must return empty array")
	check(card_mgr.roll_cards(999).size() == card_mgr.card_pool.size(), "roll_cards(999) must cap at card_pool size")

	check(card_mgr.apply_buff("unknown_card_id") == false, "apply_buff with unknown id must return false")
	check(card_mgr.get_active_buffs().is_empty(), "Unknown buff must not be added")

	check(card_mgr.apply_buff("fire_rounds") == true, "apply_buff('fire_rounds') must return true")
	check(card_mgr.apply_buff("cost_regen") == true, "apply_buff('cost_regen') must return true")
	check(card_mgr.apply_buff("fire_rounds") == true, "Applying same buff again must stack and return true")
	var active_buffs: Array[Dictionary] = card_mgr.get_active_buffs()
	check(active_buffs.size() == 3, "get_active_buffs must contain all 3 applied buffs including stacked ones")
	active_buffs.clear()
	check(card_mgr.get_active_buffs().size() == 3, "get_active_buffs must return a copy")

	var custom_card := {"id": "custom_overclock", "name": "Overclock", "type": "ATK_UP", "value": 0.25, "effect": "ATK+25%"}
	var pool_before: int = card_mgr.card_pool.size()
	card_mgr.register_card(custom_card)
	check(card_mgr.card_pool.size() == pool_before + 1, "register_card must add new valid card")
	card_mgr.register_card(custom_card)
	check(card_mgr.card_pool.size() == pool_before + 1, "register_card must ignore duplicate id")
	card_mgr.register_card({"name": "No ID"})
	check(card_mgr.card_pool.size() == pool_before + 1, "register_card must ignore card without id")
	check(card_mgr.apply_buff("custom_overclock") == true, "Registered custom card must be applicable via apply_buff")

	card_mgr.clear_session_buffs()
	check(card_mgr.get_active_buffs().is_empty(), "clear_session_buffs must clear all active buffs")

	# Sync unlocked cards from ProgressionManager & load_cards_from_json
	var prog_script: GDScript = load("res://scripts/core/ProgressionManager.gd")
	var prog_mgr = prog_script.new()
	prog_mgr.unlock_horizontal_option("shiroko", "ROGUELIKE_CARD", "card_shiroko_drone")
	var synced_count: int = card_mgr.sync_unlocked_cards(prog_mgr)
	check(synced_count == 1, "sync_unlocked_cards must register 1 new card")
	check(card_mgr.sync_unlocked_cards(prog_mgr) == 0, "sync_unlocked_cards must not duplicate already-registered cards")
	check(card_mgr.apply_buff("card_shiroko_drone") == true, "Synced unlocked card must be applicable via apply_buff")
	prog_mgr.free()

	var json_cards := '[{"id":"mod_card_1","name":"Mod Card 1","type":"ATK_UP","value":0.25,"effect":"ATK+25%"},{"id":"fire_rounds","name":"Dup","type":"ATK_UP","value":0.1}]'
	var loaded_cards: int = card_mgr.load_cards_from_json(json_cards)
	check(loaded_cards == 1, "load_cards_from_json must register 1 new non-duplicate card")
	check(card_mgr.apply_buff("mod_card_1") == true, "JSON-loaded mod card must be applicable via apply_buff")
	check(card_mgr.load_cards_from_json("invalid json") == 0, "load_cards_from_json must return 0 on invalid JSON")

	# 4. DungeonRoomManager tests
	var room_mgr = room_mgr_script.new()
	check(room_mgr is Node, "DungeonRoomManager must extend Node")
	root.add_child(room_mgr)

	var bus_script: GDScript = load("res://scripts/core/EventBus.gd")
	var mock_bus = bus_script.new()
	room_mgr.event_bus = mock_bus

	var cleared_rooms: Array[int] = []
	mock_bus.combat_room_cleared.connect(func(idx: int): cleared_rooms.append(idx))

	var loaded_events: Array = []
	var completed_count := [0]
	room_mgr.room_loaded.connect(func(idx: int, data: Dictionary): loaded_events.append({"idx": idx, "data": data}))
	room_mgr.dungeon_completed.connect(func(): completed_count[0] += 1)

	var initial_hp := {"shiroko": 850, "hoshino": 2400}
	room_mgr.set_squad_hp(initial_hp)
	initial_hp["shiroko"] = 1
	var persisted_hp: Dictionary = room_mgr.get_squad_persistent_state()
	check(persisted_hp.get("shiroko", 0) == 850 and persisted_hp.get("hoshino", 0) == 2400, "set_squad_hp must store deep copy")
	persisted_hp["hoshino"] = 1
	check(room_mgr.get_squad_persistent_state().get("hoshino", 0) == 2400, "get_squad_persistent_state must return deep copy")

	var test_layout: Array[Dictionary] = gen.generate_layout(3, 2)
	room_mgr.start_dungeon(test_layout)
	check(room_mgr.get_current_room_index() == 0, "start_dungeon must reset current_room_index to 0")
	check(room_mgr.is_draft_open == false, "start_dungeon must set is_draft_open to false")
	check(room_mgr.is_dungeon_complete() == false, "Dungeon must not be complete at start")
	check(loaded_events.size() == 1 and loaded_events[0]["idx"] == 0, "start_dungeon must emit room_loaded for room 0")

	var dummy_room := Node3D.new()
	root.add_child(dummy_room)
	room_mgr.current_room_node = dummy_room

	room_mgr.mark_current_room_cleared()
	check(room_mgr.is_draft_open == true, "mark_current_room_cleared must open draft")
	check(cleared_rooms.size() == 1 and cleared_rooms[0] == 0, "mark_current_room_cleared must emit EventBus.combat_room_cleared(0)")
	check(room_mgr.get_squad_persistent_state().get("shiroko", 0) == 850, "Squad HP must persist across room clear")

	check(room_mgr.advance_to_next_room() == true, "advance_to_next_room from room 0 of 3 must return true")
	check(dummy_room.is_queued_for_deletion(), "advance_to_next_room must queue_free current_room_node")
	check(room_mgr.current_room_node == null, "advance_to_next_room must clear current_room_node reference")
	check(room_mgr.is_draft_open == false, "advance_to_next_room must close draft")
	check(room_mgr.get_current_room_index() == 1, "current_room_index must now be 1")
	check(loaded_events.size() == 2 and loaded_events[1]["idx"] == 1, "room_loaded must emit for room 1")

	room_mgr.mark_current_room_cleared()
	check(cleared_rooms.size() == 2 and cleared_rooms[1] == 1, "mark_current_room_cleared must emit combat_room_cleared(1)")
	check(room_mgr.advance_to_next_room() == true, "advance_to_next_room from room 1 of 3 must return true")
	check(room_mgr.get_current_room_index() == 2, "current_room_index must now be 2")
	check(loaded_events.size() == 3 and loaded_events[2]["idx"] == 2, "room_loaded must emit for room 2")
	check(room_mgr.is_dungeon_complete() == false, "Dungeon must not be complete while in final room")

	room_mgr.mark_current_room_cleared()
	check(room_mgr.advance_to_next_room() == false, "advance_to_next_room after final room must return false")
	check(room_mgr.is_dungeon_complete() == true, "is_dungeon_complete must be true after advancing past final room")
	check(completed_count[0] == 1, "dungeon_completed must emit once when finishing last room")
	check(room_mgr.get_squad_persistent_state().get("shiroko", 0) == 850, "Squad HP must remain intact after dungeon completion")

	# 5. roguelike_card_draft.tscn tests
	var draft_ui: Node = draft_scene.instantiate()
	check(draft_ui != null, "roguelike_card_draft.tscn must instantiate")
	check(draft_ui is PanelContainer and draft_ui.name == "RoguelikeCardDraft", "Root must be PanelContainer named RoguelikeCardDraft")
	var vbox: Node = draft_ui.get_node_or_null("VBoxContainer")
	check(vbox is VBoxContainer, "Must contain VBoxContainer")
	var title_lbl: Node = draft_ui.get_node_or_null("VBoxContainer/TitleLabel")
	check(title_lbl is Label, "Must contain VBoxContainer/TitleLabel (Label)")
	var cards_hbox: Node = draft_ui.get_node_or_null("VBoxContainer/CardsHBox")
	check(cards_hbox is HBoxContainer, "Must contain VBoxContainer/CardsHBox (HBoxContainer)")
	var btn1: Node = draft_ui.get_node_or_null("VBoxContainer/CardsHBox/CardOption1")
	var btn2: Node = draft_ui.get_node_or_null("VBoxContainer/CardsHBox/CardOption2")
	var btn3: Node = draft_ui.get_node_or_null("VBoxContainer/CardsHBox/CardOption3")
	check(btn1 is Button and btn2 is Button and btn3 is Button, "CardsHBox must contain CardOption1, CardOption2, CardOption3 Buttons")

	# Cleanup
	draft_ui.free()
	room_mgr.queue_free()
	mock_bus.free()

	_completed = true
