# tests/test_mission_system.gd
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

	print("PASS: test_mission_system")
	quit(0)

func _make_quest(
	quest_script: GDScript,
	id: String,
	title: String,
	student_id: String,
	req_level: int,
	obj_type: String,
	target_id: String,
	target_count: int = 1,
	rewards: Dictionary = {},
	card_id: String = ""
) -> Resource:
	var q: Resource = quest_script.new()
	q.id = id
	q.title = title
	q.description = "Bond quest for " + student_id
	q.student_id = student_id
	q.required_bond_level = req_level
	q.objective_type = obj_type
	q.target_id = target_id
	q.target_count = target_count
	q.reward_items = rewards
	q.unlocks_roguelike_card_id = card_id
	return q

func _run_tests() -> void:
	var quest_script: GDScript = load("res://scripts/data/QuestData.gd")
	if not check(quest_script != null and quest_script.can_instantiate(), "QuestData.gd must load and compile"):
		return
	var mission_script: GDScript = load("res://scripts/core/MissionManager.gd")
	if not check(mission_script != null and mission_script.can_instantiate(), "MissionManager.gd must load and compile"):
		return
	var tracker_script: GDScript = load("res://scripts/intimacy/BondProgressTracker.gd")
	if not check(tracker_script != null and tracker_script.can_instantiate(), "BondProgressTracker.gd must load and compile"):
		return
	var bus_script: GDScript = load("res://scripts/core/EventBus.gd")
	if not check(bus_script != null and bus_script.can_instantiate(), "EventBus.gd must load and compile"):
		return

	# 1. QuestData defaults and MissionManager registration
	var default_q: Resource = quest_script.new()
	check(default_q is Resource, "QuestData must extend Resource")
	check(default_q.id == "", "QuestData default id must be empty")
	check(default_q.title == "", "QuestData default title must be empty")
	check(default_q.description == "", "QuestData default description must be empty")
	check(default_q.student_id == "", "QuestData default student_id must be empty")
	check(default_q.required_bond_level == 5, "QuestData default required_bond_level must be 5")
	check(default_q.objective_type == "CLEAR_DUNGEON", "QuestData default objective_type must be 'CLEAR_DUNGEON'")
	check(default_q.target_id == "", "QuestData default target_id must be empty")
	check(default_q.target_count == 1, "QuestData default target_count must be 1")
	check(default_q.reward_items is Dictionary and default_q.reward_items.is_empty(), "QuestData default reward_items must be empty Dictionary")
	check(default_q.unlocks_roguelike_card_id == "", "QuestData default unlocks_roguelike_card_id must be empty")

	var mm: Node = mission_script.new()
	check(mm is Node, "MissionManager must extend Node")
	check(mm.has_signal("quest_completed"), "MissionManager must define quest_completed signal")

	var completed_events: Array = []
	mm.quest_completed.connect(func(qid: String, sid: String): completed_events.append([qid, sid]))

	var q5 := _make_quest(
		quest_script,
		"shiroko_bond_5",
		"Bank Heist Rehearsal",
		"shiroko",
		5,
		"CLEAR_DUNGEON",
		"abydos_bank_robbery",
		1,
		{"credits": 5000},
		"card_shiroko_drone"
	)
	var q10 := _make_quest(
		quest_script,
		"shiroko_bond_10",
		"Cycling Lunch",
		"shiroko",
		10,
		"COOK_DISH",
		"matcha_parfait",
		2
	)
	var q15 := _make_quest(
		quest_script,
		"shiroko_bond_15",
		"Mask Maintenance",
		"shiroko",
		15,
		"GIFT_ITEM",
		"ski_mask",
		1
	)
	var q20 := _make_quest(
		quest_script,
		"shiroko_bond_20",
		"Desert Patrol",
		"shiroko",
		20,
		"INTERACT",
		"abydos_rooftop_bench",
		1
	)

	mm.register_quest(q5)
	mm.register_quest(q10)
	mm.register_quest(q15)
	mm.register_quest(q20)

	check(mm.quests.has("shiroko_bond_5"), "register_quest must store quest in quests dictionary")
	check(int(mm.quest_progress.get("shiroko_bond_5", -1)) == 0, "register_quest must initialize quest_progress to 0")
	check(mm.is_quest_completed("shiroko_bond_5") == false, "New quest must not be completed")
	check(mm.is_quest_ready_to_complete("shiroko_bond_5") == false, "New quest must not be ready before progress")
	check(mm.get_available_quests("shiroko", 4).is_empty(), "No quests available for shiroko at bond level 4")
	var avail_at_5: Array = mm.get_available_quests("shiroko", 5)
	check(avail_at_5.size() == 1 and avail_at_5[0].id == "shiroko_bond_5", "Only level 5 quest available at bond level 5")
	check(mm.get_available_quests("hoshino", 20).is_empty(), "Quests must filter by student_id")

	# 2. Milestone gating at level 5
	var bus: Node = bus_script.new()
	var tracker = tracker_script.new()
	tracker.event_bus = bus

	tracker.add_bond_exp("shiroko", 50000)
	check(tracker.get_bond_level("shiroko") == 5, "add_bond_exp(50000) must stop at bond gate level 5")
	check(tracker.is_bond_gate_locked("shiroko") == true, "is_bond_gate_locked('shiroko') must be true at level 5")

	# 3. complete_quest fails before objective progress, succeeds after progress, unlocks level 5 gate
	check(mm.complete_quest("shiroko_bond_5", tracker) == false, "complete_quest must fail before objective progress is recorded")
	check(mm.is_quest_completed("shiroko_bond_5") == false, "Failed complete_quest must not mark quest completed")
	check(tracker.is_bond_gate_locked("shiroko") == true, "Failed complete_quest must not unlock bond gate")

	# Unrelated and non-positive progress must not advance shiroko_bond_5
	mm.record_objective_progress("CLEAR_DUNGEON", "other_dungeon", 5)
	mm.record_objective_progress("CLEAR_DUNGEON", "abydos_bank_robbery", -2)
	check(mm.is_quest_ready_to_complete("shiroko_bond_5") == false, "Unrelated or negative progress must not make quest ready")

	mm.record_objective_progress("CLEAR_DUNGEON", "abydos_bank_robbery", 1)
	check(mm.is_quest_ready_to_complete("shiroko_bond_5") == true, "Quest must be ready after recording matching objective progress")
	check(mm.complete_quest("shiroko_bond_5", tracker) == true, "complete_quest must succeed once objective is met")
	check(mm.is_quest_completed("shiroko_bond_5") == true, "Quest must be marked completed")
	check(mm.is_quest_ready_to_complete("shiroko_bond_5") == false, "Completed quest must no longer be ready to complete")
	check(mm.complete_quest("shiroko_bond_5", tracker) == false, "Completing an already completed quest must return false")
	check(completed_events.size() == 1 and completed_events[0] == ["shiroko_bond_5", "shiroko"], "quest_completed signal must emit with quest_id and student_id")
	check(tracker.get_bond_level("shiroko") == 10, "Unlocking level 5 gate with 50000 overflow EXP must advance shiroko to level 10 gate")

	# Also verify single-gate unlock leaves is_bond_gate_locked == false when overflow stops before next gate
	var q5_hoshino := _make_quest(quest_script, "hoshino_bond_5", "Nap Patrol", "hoshino", 5, "INTERACT", "couch", 1)
	mm.register_quest(q5_hoshino)
	tracker.add_bond_exp("hoshino", 1850) # 1300 (0->5) + 550 (5->6)
	check(tracker.get_bond_level("hoshino") == 5, "Hoshino must pause at level 5 gate")
	check(tracker.is_bond_gate_locked("hoshino") == true, "Hoshino level 5 gate must be locked")
	mm.record_objective_progress("INTERACT", "couch", 1)
	check(mm.complete_quest("hoshino_bond_5", tracker) == true, "Completing hoshino_bond_5 must succeed")
	check(tracker.get_bond_level("hoshino") == 6, "Unlocking hoshino level 5 gate must advance to level 6")
	check(tracker.is_bond_gate_locked("hoshino") == false, "After unlocking level 5 gate without hitting level 10, is_bond_gate_locked must be false")

	# 4. Complete gates 10, 15, 20; verify free leveling 20 -> 100 by default, and dynamic gating at 50 via register_quest
	var q50 := _make_quest(
		quest_script,
		"shiroko_bond_50",
		"Abydos Future",
		"shiroko",
		50,
		"CLEAR_DUNGEON",
		"abydos_final_vault",
		1
	)
	mm.register_quest(q50, tracker)

	# Complete shiroko gates 10, 15, 20
	mm.record_objective_progress("COOK_DISH", "matcha_parfait", 1)
	check(mm.is_quest_ready_to_complete("shiroko_bond_10") == false, "target_count 2 must require 2 progress updates")
	mm.record_objective_progress("COOK_DISH", "matcha_parfait", 1)
	check(mm.complete_quest("shiroko_bond_10", tracker) == true, "Completing shiroko_bond_10 must succeed")
	check(tracker.get_bond_level("shiroko") == 15, "Completing gate 10 must advance shiroko to gate 15")

	mm.record_objective_progress("GIFT_ITEM", "ski_mask", 1)
	check(mm.complete_quest("shiroko_bond_15", tracker) == true, "Completing shiroko_bond_15 must succeed")
	check(tracker.get_bond_level("shiroko") == 20, "Completing gate 15 must advance shiroko to gate 20")

	tracker.add_bond_exp("shiroko", 1000000)
	mm.record_objective_progress("INTERACT", "abydos_rooftop_bench", 1)
	check(mm.complete_quest("shiroko_bond_20", tracker) == true, "Completing shiroko_bond_20 must succeed")
	check(tracker.get_bond_level("shiroko") == 50, "Future quest registered at level 50 must gate shiroko at level 50")
	check(tracker.is_bond_gate_locked("shiroko") == true, "is_bond_gate_locked must be true at custom gate 50")

	mm.record_objective_progress("CLEAR_DUNGEON", "abydos_final_vault", 1)
	check(mm.complete_quest("shiroko_bond_50", tracker) == true, "Completing shiroko_bond_50 must succeed")
	check(tracker.get_bond_level("shiroko") == tracker.MAX_BOND_LEVEL, "After unlocking level 50 gate, shiroko must reach MAX_BOND_LEVEL (100)")
	check(tracker.is_bond_gate_locked("shiroko") == false, "At MAX_BOND_LEVEL 100, is_bond_gate_locked must be false")

	# Verify a student without >20 quests advances freely from 20 -> 100 after [5, 10, 15, 20]
	var arisu_quests := [
		_make_quest(quest_script, "arisu_5", "Quest 5", "arisu", 5, "CLEAR_DUNGEON", "millennium_1", 1),
		_make_quest(quest_script, "arisu_10", "Quest 10", "arisu", 10, "CLEAR_DUNGEON", "millennium_2", 1),
		_make_quest(quest_script, "arisu_15", "Quest 15", "arisu", 15, "CLEAR_DUNGEON", "millennium_3", 1),
		_make_quest(quest_script, "arisu_20", "Quest 20", "arisu", 20, "CLEAR_DUNGEON", "millennium_4", 1),
	]
	for aq in arisu_quests:
		mm.register_quest(aq, tracker)
	tracker.add_bond_exp("arisu", 1000000)
	check(tracker.get_bond_level("arisu") == 5, "Arisu must pause at level 5")
	mm.record_objective_progress("CLEAR_DUNGEON", "millennium_1", 1)
	check(mm.complete_quest("arisu_5", tracker) == true, "arisu_5 must complete")
	mm.record_objective_progress("CLEAR_DUNGEON", "millennium_2", 1)
	check(mm.complete_quest("arisu_10", tracker) == true, "arisu_10 must complete")
	mm.record_objective_progress("CLEAR_DUNGEON", "millennium_3", 1)
	check(mm.complete_quest("arisu_15", tracker) == true, "arisu_15 must complete")
	mm.record_objective_progress("CLEAR_DUNGEON", "millennium_4", 1)
	check(mm.complete_quest("arisu_20", tracker) == true, "arisu_20 must complete")
	check(tracker.get_bond_level("arisu") == 100, "After gates [5, 10, 15, 20], arisu must advance freely to MAX_BOND_LEVEL 100")

	mm.free()
	bus.free()
	_completed = true
