# tests/test_cooking_system.gd
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

	print("PASS: test_cooking_system")
	quit(0)

func _run_tests() -> void:
	var prep_script: GDScript = load("res://scripts/minigames/IngredientPrepStep.gd")
	if not check(prep_script != null and prep_script.can_instantiate(), "IngredientPrepStep.gd must load and compile"):
		return
	var manager_script: GDScript = load("res://scripts/minigames/CookingManager.gd")
	if not check(manager_script != null and manager_script.can_instantiate(), "CookingManager.gd must load and compile"):
		return
	var station_script: GDScript = load("res://scripts/minigames/CookingStation.gd")
	if not check(station_script != null and station_script.can_instantiate(), "CookingStation.gd must load and compile"):
		return

	# 1. IngredientPrepStep: relaxed action counting without timer
	var step = prep_script.new()
	check(step.prep_type == "CHOP", "IngredientPrepStep default prep_type must be 'CHOP'")
	check(step.target_count == 5, "IngredientPrepStep default target_count must be 5")
	check(step.current_count == 0, "IngredientPrepStep initial current_count must be 0")
	check(is_equal_approx(step.get_average_quality(), 0.0), "Empty action_scores average quality must be 0.0")
	check(step.is_complete() == false, "is_complete() must be false before 5 actions")

	var s1: float = step.perform_action(1.5) # clamped to 1.0
	var s2: float = step.perform_action(0.8)
	var s3: float = step.perform_action(-0.2) # clamped to 0.0
	var s4: float = step.perform_action(0.9)
	check(is_equal_approx(s1, 1.0), "perform_action must clamp precision > 1.0 to 1.0")
	check(is_equal_approx(s3, 0.0), "perform_action must clamp precision < 0.0 to 0.0")
	check(step.current_count == 4, "current_count must be 4 after 4 actions")
	check(step.is_complete() == false, "is_complete() must be false at 4/5 actions")

	var s5: float = step.perform_action(0.8)
	check(is_equal_approx(s5, 0.8), "perform_action must return clamped score 0.8")
	check(step.current_count == 5, "current_count must reach 5 after 5th action")
	check(step.is_complete() == true, "is_complete() must be true at 5/5 actions")
	check(step.action_scores.size() == 5, "action_scores must have 5 entries")

	# Extra call does not exceed target_count
	step.perform_action(0.5)
	check(step.current_count == 5, "current_count must not exceed target_count")

	# Average of [1.0, 0.8, 0.0, 0.9, 0.8] = 3.5 / 5 = 0.7
	check(is_equal_approx(step.get_average_quality(), 0.7), "get_average_quality() must be 0.7")

	step.reset()
	check(step.current_count == 0, "reset() must reset current_count to 0")
	check(step.action_scores.is_empty(), "reset() must clear action_scores")
	check(step.is_complete() == false, "is_complete() must be false after reset()")
	check(is_equal_approx(step.get_average_quality(), 0.0), "get_average_quality() must be 0.0 after reset()")

	# 2. CookingManager: recipe check, deduction, indicator, sweet spot, quality, finalize
	var cm = manager_script.new()
	check(is_equal_approx(cm.SWEET_SPOT_CENTER, 0.5), "SWEET_SPOT_CENTER must be 0.5")
	check(is_equal_approx(cm.indicator_speed, 2.0), "Default indicator_speed must be 2.0")

	var recipe := RecipeData.new()
	recipe.id = "parfait"
	recipe.name = "Matcha Parfait"
	recipe.ingredients = {"matcha": 1, "cream": 2}

	var insufficient_inv: Dictionary = {"matcha": 1, "cream": 1}
	check(cm.can_cook(null, insufficient_inv) == false, "can_cook(null, ...) must return false")
	check(cm.can_cook(recipe, insufficient_inv) == false, "can_cook must return false when ingredient quantity is insufficient")
	check(cm.start_recipe(recipe, insufficient_inv) == false, "start_recipe must return false when can_cook is false")
	check(insufficient_inv["cream"] == 1, "Failed start_recipe must not deduct ingredients")

	var inv: Dictionary = {"matcha": 2, "cream": 3}
	check(cm.can_cook(recipe, inv) == true, "can_cook must return true when inventory satisfies recipe")
	cm.complete_prep_step(0, 0.5)
	cm.advance_indicator(0.5)
	check(cm.start_recipe(recipe, inv) == true, "start_recipe must return true when ingredients suffice")
	check(cm.active_recipe == recipe, "start_recipe must set active_recipe")
	check(inv["matcha"] == 1 and inv["cream"] == 1, "start_recipe must deduct required ingredients from inventory")
	check(cm.prep_scores.is_empty(), "start_recipe must reset prep_scores")
	check(is_equal_approx(cm.indicator_time, 0.0), "start_recipe must reset indicator_time to 0.0")

	# Check prep_steps array compatibility and reset
	var step_for_list = prep_script.new()
	cm.prep_steps.append(step_for_list)
	check(cm.prep_steps.size() == 1, "CookingManager.prep_steps must accept IngredientPrepStep instances")
	cm.prep_steps.clear()

	# Oscillating indicator in [0.0, 1.0] and sweet spot scoring
	check(is_equal_approx(cm.get_cooking_indicator_position(), 0.5), "At indicator_time 0.0, position must be 0.5")
	check(is_equal_approx(cm.get_sweet_spot_score(0.5), 1.0), "Sweet spot score at 0.5 must be 1.0")
	check(is_equal_approx(cm.get_sweet_spot_score(0.0), 0.0), "Sweet spot score at 0.0 must be 0.0")
	check(is_equal_approx(cm.get_sweet_spot_score(1.0), 0.0), "Sweet spot score at 1.0 must be 0.0")
	check(is_equal_approx(cm.get_sweet_spot_score(), 1.0), "Default get_sweet_spot_score() must evaluate current indicator at 0.5 -> 1.0")

	for _i in range(20):
		var pos: float = cm.advance_indicator(0.15)
		check(pos >= 0.0 and pos <= 1.0, "Oscillating indicator must stay within [0.0, 1.0]")
	check(not is_equal_approx(cm.get_cooking_indicator_position(), 0.5), "advance_indicator must move indicator position")

	# Dish quality calculations
	check(cm.calculate_dish_quality([0.9, 0.85, 0.95], 0.92) == "PERFECT", "Weighted score >= 0.85 must return 'PERFECT'")
	check(cm.calculate_dish_quality([0.7, 0.65], 0.65) == "GOOD", "Weighted score in [0.60, 0.85) must return 'GOOD'")
	check(cm.calculate_dish_quality([0.4, 0.5, 0.3], 0.2) == "NORMAL", "Weighted score < 0.60 must return 'NORMAL'")
	check(cm.calculate_dish_quality([], 0.9) == "PERFECT", "Empty prep scores must use cook_timing directly")

	# create_dish_item
	var perfect_dish: ItemData = cm.create_dish_item("parfait", "PERFECT", "Matcha Parfait")
	check(perfect_dish != null, "create_dish_item must return ItemData")
	check(perfect_dish.id == "parfait", "Dish item id must be 'parfait'")
	check(perfect_dish.type == ItemData.ItemType.FOOD, "Dish item type must be ItemData.ItemType.FOOD")
	check(perfect_dish.quality == "PERFECT", "Dish item quality must be 'PERFECT'")
	check(perfect_dish.bond_bonus >= 50, "PERFECT dish bond_bonus must be >= 50")

	var good_dish: ItemData = cm.create_dish_item("parfait", "GOOD")
	check(good_dish.bond_bonus == 30, "GOOD dish bond_bonus must be 30")
	var normal_dish: ItemData = cm.create_dish_item("parfait", "NORMAL")
	check(normal_dish.bond_bonus == 15, "NORMAL dish bond_bonus must be 15")

	# finalize_cook end-to-end
	cm.start_recipe(recipe, {})
	# Empty inventory passed with recipe having ingredients -> returns false; test with no-ingredient recipe or fresh manager with inventory
	var free_recipe := RecipeData.new()
	free_recipe.id = "tea"
	free_recipe.name = "Green Tea"
	check(cm.start_recipe(free_recipe) == true, "start_recipe with empty recipe ingredients must succeed")
	cm.complete_prep_step(0, 0.9)
	cm.complete_prep_step(1, 0.95)
	var final_dish: ItemData = cm.finalize_cook(0.95)
	check(final_dish != null, "finalize_cook must return an ItemData")
	check(final_dish.id == "tea", "finalize_cook dish id must match active_recipe.id")
	check(final_dish.type == ItemData.ItemType.FOOD, "finalize_cook dish must be FOOD")
	check(final_dish.quality == "PERFECT", "finalize_cook with high prep & timing must produce PERFECT dish")
	check(final_dish.bond_bonus == 50, "finalize_cook PERFECT dish must have bond_bonus 50")

	# finalize_cook without override uses current indicator sweet spot (at time 0.0 -> pos 0.5 -> score 1.0)
	cm.start_recipe(free_recipe)
	cm.complete_prep_step(0, 0.9)
	var auto_timing_dish: ItemData = cm.finalize_cook()
	check(auto_timing_dish.quality == "PERFECT", "finalize_cook() at indicator_time 0.0 must hit sweet spot and yield PERFECT")

	# 3. CookingStation & scenes/minigames/cooking_station.tscn
	var station = station_script.new()
	check(station is InteractableBase, "CookingStation must extend InteractableBase")
	check(station.cooking_manager != null, "CookingStation must initialize cooking_manager in _init()")
	check(station.interaction_prompt == "[E] Cook", "CookingStation interaction_prompt must be '[E] Cook'")
	check(station.get_interaction_type() == "COOK", "CookingStation get_interaction_type() must return 'COOK'")
	check(station.is_cooking_active == false, "CookingStation is_cooking_active must start false")
	station.interact()
	check(station.is_cooking_active == true, "First interact() must toggle is_cooking_active to true")
	station.interact()
	check(station.is_cooking_active == false, "Second interact() must toggle is_cooking_active to false")
	station.free()

	var station_scene = load("res://scenes/minigames/cooking_station.tscn")
	if not check(station_scene != null and station_scene is PackedScene, "scenes/minigames/cooking_station.tscn must load as PackedScene"):
		return
	var station_node: Node = station_scene.instantiate()
	if not check(station_node != null, "cooking_station.tscn must instantiate cleanly"):
		return
	check(station_node.name == "CookingStation", "Root node must be named 'CookingStation'")
	check(station_node is Area3D, "CookingStation root must be Area3D")
	check(station_node.get_script() == station_script, "CookingStation root must use CookingStation.gd")
	check(station_node.get_interaction_type() == "COOK", "Instantiated CookingStation must return 'COOK'")
	check(station_node.get_node_or_null("CollisionShape3D") is CollisionShape3D, "CookingStation must contain CollisionShape3D")
	check(station_node.get_node_or_null("CounterMesh") is MeshInstance3D, "CookingStation must contain CounterMesh (MeshInstance3D)")
	check(station_node.get_node_or_null("CookingCamera") is Camera3D, "CookingStation must contain CookingCamera (Camera3D)")
	var ui_layer: Node = station_node.get_node_or_null("CookingUI")
	check(ui_layer is CanvasLayer, "CookingStation must contain CookingUI (CanvasLayer)")
	check(ui_layer != null and ui_layer.get_node_or_null("PrepContainer") is Control, "CookingUI must contain PrepContainer (Control)")
	check(ui_layer != null and ui_layer.get_node_or_null("TimingIndicatorBar") is ProgressBar, "CookingUI must contain TimingIndicatorBar (ProgressBar)")

	station_node.interact()
	check(station_node.is_cooking_active == true, "Scene CookingStation.interact() must toggle is_cooking_active to true")
	check(ui_layer.visible == true, "CookingUI must become visible when cooking is active")
	station_node._process(0.25)
	var bar: ProgressBar = ui_layer.get_node("TimingIndicatorBar") as ProgressBar
	check(bar != null and not is_equal_approx(bar.value, 50.0), "CookingStation._process must update TimingIndicatorBar value when active")
	station_node.interact()
	check(station_node.is_cooking_active == false, "Second Scene CookingStation.interact() must toggle is_cooking_active to false")
	check(ui_layer.visible == false, "CookingUI must hide when cooking becomes inactive")
	station_node.free()

	_completed = true
