# tests/test_gesture_logic.gd
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

	print("PASS: test_gesture_logic")
	quit(0)

func _run_tests() -> void:
	var receiver_script: GDScript = load("res://scripts/intimacy/GestureReceiver.gd")
	if not check(receiver_script != null and receiver_script.can_instantiate(), "GestureReceiver.gd must load and compile"):
		return
	var tracker_script: GDScript = load("res://scripts/intimacy/BondProgressTracker.gd")
	if not check(tracker_script != null and tracker_script.can_instantiate(), "BondProgressTracker.gd must load and compile"):
		return
	var manager_script: GDScript = load("res://scripts/intimacy/IntimacyManager.gd")
	if not check(manager_script != null and manager_script.can_instantiate(), "IntimacyManager.gd must load and compile"):
		return
	var event_bus_script: GDScript = load("res://scripts/core/EventBus.gd")
	if not check(event_bus_script != null and event_bus_script.can_instantiate(), "EventBus.gd must load and compile"):
		return

	# 1. GestureReceiver headpat, cheek pinch, and reset
	var receiver = receiver_script.new()
	var headpat_events: Array = []
	var cheek_events: Array = []
	var food_events: Array = []
	receiver.headpat_completed.connect(func(sat: float): headpat_events.append(sat))
	receiver.cheek_pinched.connect(func(offset: float): cheek_events.append(offset))
	receiver.food_fed.connect(func(item_id: String, reaction: String): food_events.append([item_id, reaction]))

	check(is_equal_approx(receiver.get_headpat_satisfaction(), 0.0), "Initial headpat satisfaction must be 0.0")
	check(is_equal_approx(receiver.get_cheek_pinch_offset(), 0.0), "Initial cheek pinch offset must be 0.0")

	# Back-and-forth horizontal strokes build headpat satisfaction and reach 1.0
	for _i in range(6):
		receiver.register_stroke(Vector2(60.0, 0.0))
		receiver.register_stroke(Vector2(-60.0, 0.0))

	check(receiver.get_headpat_satisfaction() > 0.0, "Back-and-forth strokes must build headpat satisfaction > 0.0")
	check(is_equal_approx(receiver.get_headpat_satisfaction(), 1.0), "Repeated strokes must reach max satisfaction 1.0")
	check(headpat_events.size() == 1 and is_equal_approx(headpat_events[0], 1.0), "headpat_completed(1.0) must emit once when reaching 1.0")

	receiver.reset()
	check(is_equal_approx(receiver.get_headpat_satisfaction(), 0.0), "reset() must reset headpat satisfaction to 0.0")
	check(is_equal_approx(receiver.get_cheek_pinch_offset(), 0.0), "reset() must reset cheek pinch offset to 0.0")

	# Cheek pinch pull generates offset > 0.0 and emits cheek_pinched
	receiver.register_stroke(Vector2(35.0, 15.0))
	check(receiver.get_cheek_pinch_offset() > 0.0, "Cheek pinch pull must generate offset > 0.0")
	check(cheek_events.size() >= 1 and cheek_events[cheek_events.size() - 1] > 0.0, "cheek_pinched signal must emit with positive offset")

	receiver.reset()
	check(is_equal_approx(receiver.get_cheek_pinch_offset(), 0.0), "reset() must reset cheek pinch offset to 0.0 after pinch")

	# Vertical back-and-forth strokes also build headpat satisfaction
	receiver.register_stroke(Vector2(0.0, 50.0))
	receiver.register_stroke(Vector2(0.0, -50.0))
	check(receiver.get_headpat_satisfaction() > 0.0, "Vertical back-and-forth strokes must build headpat satisfaction > 0.0")
	receiver.reset()

	# 2. GestureReceiver.register_feed()
	var student := StudentData.new()
	student.id = "shiroko"
	student.student_name = "Sunaookami Shiroko"
	student.favorite_food = "matcha_parfait"

	var fav_food := ItemData.new()
	fav_food.id = "matcha_parfait"
	fav_food.name = "Matcha Parfait"
	fav_food.type = ItemData.ItemType.FOOD
	fav_food.bond_bonus = 20
	fav_food.quality = "NORMAL"

	var fav_res: Dictionary = receiver.register_feed(fav_food, student)
	check(fav_res.get("accepted", false) == true, "FOOD item must be accepted")
	check(fav_res.get("bond_bonus", 0) == 30, "Favorite food must apply 1.5x bonus (20 -> 30)")
	check(fav_res.get("reaction", "") == "FAVORITE", "Favorite food reaction must be 'FAVORITE'")
	check(food_events.size() == 1 and food_events[0] == ["matcha_parfait", "FAVORITE"], "food_fed must emit for favorite food")

	var perfect_food := ItemData.new()
	perfect_food.id = "strawberry_cake"
	perfect_food.name = "Strawberry Cake"
	perfect_food.type = ItemData.ItemType.FOOD
	perfect_food.bond_bonus = 20
	perfect_food.quality = "PERFECT"

	var perf_res: Dictionary = receiver.register_feed(perfect_food, student)
	check(perf_res.get("accepted", false) == true, "PERFECT food item must be accepted")
	check(perf_res.get("bond_bonus", 0) == 20, "Non-favorite food bond_bonus must remain 20")
	check(perf_res.get("reaction", "") == "DELICIOUS", "PERFECT quality food reaction must be 'DELICIOUS'")

	var normal_food := ItemData.new()
	normal_food.id = "onigiri"
	normal_food.name = "Onigiri"
	normal_food.type = ItemData.ItemType.FOOD
	normal_food.bond_bonus = 10
	normal_food.quality = "NORMAL"

	var norm_res: Dictionary = receiver.register_feed(normal_food, student)
	check(norm_res.get("accepted", false) == true, "NORMAL food item must be accepted")
	check(norm_res.get("reaction", "") == "HAPPY", "Normal non-favorite food reaction must be 'HAPPY'")

	var non_food := ItemData.new()
	non_food.id = "iron_ore"
	non_food.name = "Iron Ore"
	non_food.type = ItemData.ItemType.MATERIAL
	non_food.bond_bonus = 50

	var rej_res: Dictionary = receiver.register_feed(non_food, student)
	check(rej_res.get("accepted", true) == false, "Non-FOOD item must be rejected")
	check(rej_res.get("bond_bonus", -1) == 0, "Rejected item bond_bonus must be 0")
	check(rej_res.get("reaction", "") == "REJECTED", "Rejected item reaction must be 'REJECTED'")

	var null_res: Dictionary = receiver.register_feed(null, student)
	check(null_res.get("accepted", true) == false and null_res.get("reaction", "") == "REJECTED", "null item must be rejected")

	# 3. BondProgressTracker: level thresholds, quest gates [5, 10, 15, 20], custom gates, cap 100
	var bus = event_bus_script.new()
	var bonded_events: Array = []
	bus.student_bonded.connect(func(sid: String, lvl: int): bonded_events.append([sid, lvl]))

	var tracker = tracker_script.new()
	tracker.event_bus = bus
	check(tracker.MAX_BOND_LEVEL == 100, "MAX_BOND_LEVEL must be 100")
	check(tracker.DEFAULT_QUEST_GATE_LEVELS == [5, 10, 15, 20], "DEFAULT_QUEST_GATE_LEVELS must be [5, 10, 15, 20]")
	check(tracker.get_bond_level("shiroko") == 0, "Untracked student bond level must default to 0")
	check(tracker.get_bond_exp("shiroko") == 0, "Untracked student bond exp must default to 0")
	check(tracker.get_level_up_threshold(0) == 100, "Level 0->1 threshold must be 100")
	check(tracker.get_level_up_threshold(1) == 150, "Level 1->2 threshold must be 150")

	tracker.add_bond_exp("shiroko", 0)
	tracker.add_bond_exp("shiroko", -50)
	check(tracker.get_bond_level("shiroko") == 0, "Non-positive EXP must not change bond level")

	tracker.add_bond_exp("shiroko", 100)
	check(tracker.get_bond_level("shiroko") == 1, "100 EXP must level student from 0 -> 1")
	check(tracker.get_bond_exp("shiroko") == 0, "Exact 100 EXP leaves 0 overflow EXP")
	check(bonded_events.size() == 1 and bonded_events[0] == ["shiroko", 1], "student_bonded must emit on 0 -> 1")

	# Large EXP must pause at gate level 5 and preserve overflow EXP
	tracker.add_bond_exp("shiroko", 1000000)
	check(tracker.get_bond_level("shiroko") == 5, "Leveling must pause at quest gate level 5")
	check(tracker.is_bond_gate_locked("shiroko") == true, "is_bond_gate_locked('shiroko') must be true at gate 5 with excess EXP")

	tracker.complete_bond_quest_gate("shiroko", 5)
	check(tracker.get_bond_level("shiroko") == 10, "Completing gate 5 must resume leveling up to gate 10")
	check(tracker.is_bond_gate_locked("shiroko") == true, "is_bond_gate_locked('shiroko') must be true at gate 10")

	tracker.complete_bond_quest_gate("shiroko", 10)
	check(tracker.get_bond_level("shiroko") == 15, "Completing gate 10 must resume leveling up to gate 15")
	tracker.complete_bond_quest_gate("shiroko", 15)
	check(tracker.get_bond_level("shiroko") == 20, "Completing gate 15 must resume leveling up to gate 20")

	# Register custom gate > 20 before completing 20 to verify extensibility, then clear it
	tracker.register_quest_gate("shiroko", 50)
	tracker.complete_bond_quest_gate("shiroko", 20)
	check(tracker.get_bond_level("shiroko") == 50, "Custom quest gate at level 50 must pause leveling")
	check(tracker.is_bond_gate_locked("shiroko") == true, "is_bond_gate_locked('shiroko') must be true at custom gate 50")

	tracker.complete_bond_quest_gate("shiroko", 50)
	check(tracker.get_bond_level("shiroko") == 100, "After all gates completed, massive EXP must reach MAX_BOND_LEVEL 100")
	check(tracker.is_bond_gate_locked("shiroko") == false, "At cap 100 with no gate, is_bond_gate_locked must be false")

	tracker.add_bond_exp("shiroko", 500000)
	check(tracker.get_bond_level("shiroko") == 100, "Bond level must never exceed MAX_BOND_LEVEL 100")

	# Verify free leveling from 21 to 100 without custom gates
	tracker.add_bond_exp("hoshino", 1000000)
	for gate in [5, 10, 15, 20]:
		tracker.complete_bond_quest_gate("hoshino", gate)
	check(tracker.get_bond_level("hoshino") == 100, "Without custom gates >20, completing 5/10/15/20 must allow free leveling to 100")

	# 4. IntimacyManager & scenes/intimacy/intimacy_viewport.tscn
	var scene_res = load("res://scenes/intimacy/intimacy_viewport.tscn")
	if not check(scene_res != null and scene_res is PackedScene, "scenes/intimacy/intimacy_viewport.tscn must load as PackedScene"):
		bus.free()
		return
	var viewport_node = scene_res.instantiate()
	if not check(viewport_node != null, "intimacy_viewport.tscn must instantiate"):
		bus.free()
		return

	check(viewport_node.name == "IntimacyViewport", "Root node must be named IntimacyViewport")
	check(viewport_node is Node and viewport_node is Node3D, "IntimacyViewport must be Node3D (inheriting Node)")
	check(viewport_node.get_script() == manager_script, "Root node must use IntimacyManager.gd")
	check(viewport_node.get_node_or_null("CloseUpCamera") is Camera3D, "CloseUpCamera must be Camera3D")
	check(viewport_node.get_node_or_null("StudentAnchor") is Marker3D, "StudentAnchor must be Marker3D")
	var hitboxes = viewport_node.get_node_or_null("Hitboxes")
	check(hitboxes is Node3D, "Hitboxes must be Node3D")
	for area_name in ["HeadArea", "LeftCheekArea", "RightCheekArea", "MouthArea"]:
		check(hitboxes != null and hitboxes.get_node_or_null(area_name) is Area3D, "Hitboxes/%s must be Area3D" % area_name)

	viewport_node.bond_tracker.event_bus = bus
	viewport_node.start_session(student)
	check(viewport_node.current_student == student, "start_session must set current_student")
	for key in ["eye_smile", "cheek_puff", "mouth_open", "blush"]:
		check(viewport_node.blendshape_weights.has(key), "blendshape_weights must contain key '%s'" % key)

	# Headpat input updates blendshape weights
	viewport_node.apply_headpat_Input(Vector2(50.0, 0.0))
	var sat_after_pat: float = viewport_node.apply_headpat_Input(Vector2(-50.0, 0.0))
	check(sat_after_pat > 0.0, "apply_headpat_Input reversals must increase satisfaction")
	check(viewport_node.blendshape_weights["eye_smile"] > 0.0, "Headpat must increase eye_smile blendshape weight")
	check(viewport_node.blendshape_weights["blush"] > 0.0, "Headpat must increase blush blendshape weight")

	# Cheek pinch input updates cheek_puff weight
	var pinch_offset: float = viewport_node.apply_cheek_pinch_input(Vector2(30.0, 0.0))
	check(pinch_offset > 0.0, "apply_cheek_pinch_input must return positive offset")
	check(viewport_node.blendshape_weights["cheek_puff"] > 0.0, "Cheek pinch must increase cheek_puff blendshape weight")

	# Feed student updates mouth_open and adds bond EXP without clobbering existing bond_level
	var feed_result: Dictionary = viewport_node.feed_student(fav_food)
	check(feed_result.get("accepted", false) == true, "feed_student must accept FOOD ItemData")
	check(viewport_node.blendshape_weights["mouth_open"] > 0.0, "Feeding must increase mouth_open blendshape weight")
	check(viewport_node.bond_tracker.get_bond_exp("shiroko") > 0, "Feeding must add bond EXP to bond_tracker")
	check(student.bond_level == 1, "Feeding must preserve existing StudentData.bond_level (1), not reset to 0")

	# Pre-existing saved StudentData bond_level and bond_exp are preserved and incremented
	var saved_student := StudentData.new()
	saved_student.id = "arisu"
	saved_student.student_name = "Tendou Arisu"
	saved_student.favorite_food = "matcha_parfait"
	saved_student.bond_level = 3
	saved_student.bond_exp = 340
	viewport_node.start_session(saved_student)
	check(viewport_node.bond_tracker.get_bond_level("arisu") == 3, "start_session must seed bond_tracker level from StudentData")
	check(viewport_node.bond_tracker.get_bond_exp("arisu") == 340, "start_session must seed bond_tracker exp from StudentData")
	viewport_node.feed_student(fav_food)
	check(saved_student.bond_level == 4, "Pre-existing bond_level (3) must increment to 4 after reaching threshold (350)")
	check(saved_student.bond_exp == 20, "Overflow bond_exp (340 + 30 - 350 = 20) must be preserved on StudentData")

	# Register custom modded action
	viewport_node.register_custom_action("boop_nose", {"label": "Boop Nose", "bond_bonus": 15})
	check(viewport_node.custom_actions.has("boop_nose"), "register_custom_action must store custom modded action")

	viewport_node.end_session()
	check(viewport_node.current_student == null, "end_session must clear current_student")
	check(is_equal_approx(viewport_node.blendshape_weights["eye_smile"], 0.0), "end_session must reset blendshape weights")

	viewport_node.free()
	bus.free()

	_completed = true
